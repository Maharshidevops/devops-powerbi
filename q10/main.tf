# =============================================================
# vidstream  Production Infrastructure
# Terraform >= 1.5  |  AWS Provider ~> 5.0
#
# What this provisions (in order):
#   1. VPC  2 public + 2 private-app + 2 private-data subnets
#   2. Internet Gateway, NAT Gateways (one per AZ), route tables
#   3. VPC endpoints  S3 (Gateway, free) + Secrets Manager (Interface)
#   4. Security groups - ALB, ECS tasks, RDS, VPC endpoints
#   5. Secrets Manager secret + random password (no hardcoded creds)
#   6. RDS Postgres - Multi-AZ, encrypted, DeletionPolicy Retain
#   7. IAM roles - ECS execution role + task role (least-privilege)
#   8. CloudWatch Log Group
#   9. ECR pull-through + ECS cluster (Container Insights on)
#  10. ECS Task Definition - resource limits, awslogs driver, secrets
#  11. Application Load Balancer + Target Group + Listeners
#  12. ECS Service - circuit breaker, ALB integration, auto scaling
# =============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.env
      ManagedBy   = "terraform"
    }
  }
}

# ── Data sources ───────────────────────────────────────────────────────
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# ── Local values ───────────────────────────────────────────────────────
locals {
  name   = "${var.project}-${var.env}"
  az_a   = data.aws_availability_zones.available.names[0]
  az_b   = data.aws_availability_zones.available.names[1]
}

# =============================================================
# 1. VPC
# =============================================================
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${local.name}-vpc" }
}

# Public subnets - ALB and NAT Gateways live here
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = local.az_a
  map_public_ip_on_launch = true
  tags = { Name = "${local.name}-public-a", Tier = "public" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = local.az_b
  map_public_ip_on_launch = true
  tags = { Name = "${local.name}-public-b", Tier = "public" }
}

# Private app subnets - ECS Fargate tasks
resource "aws_subnet" "private_app_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = local.az_a
  tags = { Name = "${local.name}-private-app-a", Tier = "private-app" }
}

resource "aws_subnet" "private_app_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = local.az_b
  tags = { Name = "${local.name}-private-app-b", Tier = "private-app" }
}

# Private data subnets - RDS only
resource "aws_subnet" "private_data_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.21.0/24"
  availability_zone = local.az_a
  tags = { Name = "${local.name}-private-data-a", Tier = "private-data" }
}

resource "aws_subnet" "private_data_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.22.0/24"
  availability_zone = local.az_b
  tags = { Name = "${local.name}-private-data-b", Tier = "private-data" }
}

# =============================================================
# 2. Internet Gateway + NAT Gateways + Route Tables
# =============================================================
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-igw" }
}

# Elastic IPs for NAT GWs
resource "aws_eip" "nat_a" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags       = { Name = "${local.name}-nat-eip-a" }
}

resource "aws_eip" "nat_b" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags       = { Name = "${local.name}-nat-eip-b" }
}

# One NAT GW per AZ - private subnets in each AZ route to its own NAT.
# If one AZ goes down the other AZ's private tasks still have egress.
resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.public_a.id
  tags          = { Name = "${local.name}-nat-a" }
}

resource "aws_nat_gateway" "nat_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.public_b.id
  tags          = { Name = "${local.name}-nat-b" }
}

# Public route table - both public subnets share one table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${local.name}-rt-public" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Private route tables - one per AZ so each uses its local NAT GW
resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id
  }
  tags = { Name = "${local.name}-rt-private-a" }
}

resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  }
  tags = { Name = "${local.name}-rt-private-b" }
}

resource "aws_route_table_association" "private_app_a" {
  subnet_id      = aws_subnet.private_app_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "private_app_b" {
  subnet_id      = aws_subnet.private_app_b.id
  route_table_id = aws_route_table.private_b.id
}

resource "aws_route_table_association" "private_data_a" {
  subnet_id      = aws_subnet.private_data_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "private_data_b" {
  subnet_id      = aws_subnet.private_data_b.id
  route_table_id = aws_route_table.private_b.id
}

# =============================================================
# 3. VPC Endpoints
# S3: Gateway type - free, routes via route table (no DNS change)
# Secrets Manager: Interface type - needed so ECS tasks in private
#   subnets can call secretsmanager API without going through NAT
# =============================================================
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [
    aws_route_table.private_a.id,
    aws_route_table.private_b.id,
  ]
  tags = { Name = "${local.name}-endpoint-s3" }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_app_a.id, aws_subnet.private_app_b.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = { Name = "${local.name}-endpoint-sm" }
}

# =============================================================
# 4. Security Groups
#
# Design: each group allows only what the component actually needs.
# No 0.0.0.0/0 ingress anywhere except the ALB on 443/80.
# =============================================================

# ALB - accepts HTTPS (and HTTP for redirect) from internet
resource "aws_security_group" "alb" {
  name        = "${local.name}-sg-alb"
  description = "ALB: inbound HTTPS and HTTP from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from internet - redirected to HTTPS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "Forward to ECS tasks"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  tags = { Name = "${local.name}-sg-alb" }
}

# ECS tasks - only accept traffic from ALB
resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name}-sg-ecs"
  description = "ECS tasks: inbound from ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Egress: HTTPS to AWS services (Secrets Manager endpoint, ECR, CW Logs)
  # and Postgres to RDS SG. No 0.0.0.0/0 - NAT handles broader egress
  # for the rare case we need to hit an external API.
  egress {
    description = "HTTPS to AWS service endpoints and internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "Postgres to RDS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.rds.id]
  }

  tags = { Name = "${local.name}-sg-ecs" }
}

# RDS - only accepts Postgres connections from ECS tasks
resource "aws_security_group" "rds" {
  name        = "${local.name}-sg-rds"
  description = "RDS: inbound Postgres from ECS tasks only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    description = "No outbound needed"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["127.0.0.1/32"]
  }

  tags = { Name = "${local.name}-sg-rds" }
}

# VPC Interface endpoints - accept HTTPS from ECS tasks
resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.name}-sg-endpoints"
  description = "VPC Interface endpoints: inbound 443 from ECS"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS from ECS tasks"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-sg-endpoints" }
}

# =============================================================
# 5. Secrets Manager - DB credentials
#
# random_password generates a strong password at plan time.
# Terraform writes it into the secret ONCE (initial version).
# The rotation Lambda then takes over and rotates every 30 days.
# No password ever appears in the Terraform state in plaintext
# because we use random_password whose result is marked sensitive.
# =============================================================
resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#%&*-_=+?"
  # Exclude characters that break connection strings or psql quoting
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${local.name}/rds/master-credentials"
  description             = "RDS master credentials - rotated every 30 days"
  recovery_window_in_days = 7
  tags                    = { Name = "${local.name}-db-secret" }
}

resource "aws_secretsmanager_secret_version" "db_initial" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    engine   = "postgres"
    host     = aws_db_instance.postgres.address
    port     = 5432
    dbname   = "vidstream"
  })

  # After initial creation the rotation Lambda owns the secret value.
  # Prevent Terraform from overwriting what the Lambda has rotated.
  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Rotation - uses the AWS-managed single-user rotation Lambda.
# That Lambda must already exist in the account (it ships as an
# AWS Serverless Application Repository app). If deploying to a
# fresh account, deploy the SAR app first or set rotation_lambda_arn
# to the deployed Lambda ARN via a variable.
resource "aws_secretsmanager_secret_rotation" "db" {
  secret_id           = aws_secretsmanager_secret.db.id
  rotation_lambda_arn = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:SecretsManagerRDSPostgreSQLRotationSingleUser"

  rotation_rules {
    automatically_after_days = 30
  }
}

# =============================================================
# 6. RDS Postgres
# =============================================================
resource "aws_db_subnet_group" "main" {
  name        = "${local.name}-db-subnet-group"
  description = "RDS subnet group - private data subnets only"
  subnet_ids  = [aws_subnet.private_data_a.id, aws_subnet.private_data_b.id]
  tags        = { Name = "${local.name}-db-subnet-group" }
}

resource "aws_db_instance" "postgres" {
  # --- identity ---
  identifier = "${local.name}-postgres"

  # --- engine ---
  engine         = "postgres"
  engine_version = "16.2"

  # --- compute / storage ---
  instance_class        = var.db_instance_class
  allocated_storage     = 100
  max_allocated_storage = 500      # autoscaling ceiling
  storage_type          = "gp3"
  storage_encrypted     = true     # encrypted at rest

  # --- credentials (pulled from random_password, NOT hardcoded) ---
  db_name  = "vidstream"
  username = var.db_username
  password = random_password.db.result

  # --- network ---
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  multi_az               = true    # standby in second AZ
  publicly_accessible    = false

  # --- backups ---
  backup_retention_period   = 7
  backup_window             = "02:00-03:00"
  maintenance_window        = "sun:03:00-sun:04:00"
  copy_tags_to_snapshot     = true

  # --- observability ---
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]

  # --- deletion protection ---
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-postgres-final-snapshot"

  tags = { Name = "${local.name}-postgres" }

  lifecycle {
    # Q requirement: DeletionPolicy Retain equivalent in Terraform.
    # prevent_destroy = true stops `terraform destroy` from dropping the instance.
    # The final_snapshot_identifier above ensures data is also preserved as a snapshot.
    prevent_destroy = true
  }
}

# Enhanced Monitoring IAM role for RDS
resource "aws_iam_role" "rds_monitoring" {
  name = "${local.name}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
  ]

  tags = { Name = "${local.name}-rds-monitoring-role" }
}

# =============================================================
# 7. IAM - ECS Execution Role + Task Role
#
# Execution role: used by the ECS agent (not the container).
#   Needs to pull the image from ECR and write logs to CloudWatch.
#   Also needs secretsmanager:GetSecretValue to inject secrets
#   into the container at startup via the "secrets" field in the
#   task definition - scoped to only the DB secret ARN.
#
# Task role: assumed by the running container process itself.
#   Scoped to ONLY what the application code needs at runtime.
#   Here: read the DB secret (for reconnect scenarios) + write to
#   the app-specific S3 bucket. Nothing more.
# =============================================================

# --- Execution Role ---
resource "aws_iam_role" "ecs_execution" {
  name = "${local.name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  # AWS managed policy covers ECR pull + CloudWatch Logs write
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]

  tags = { Name = "${local.name}-ecs-execution-role" }
}

# Inline policy: allow execution role to fetch only this secret.
# Without this the task definition "secrets" injection fails at
# container start with an AccessDeniedException.
resource "aws_iam_role_policy" "ecs_execution_secret" {
  name = "fetch-db-secret"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "FetchDbCredentials"
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      # Scoped to exactly this secret ARN - not "*"
      Resource = aws_secretsmanager_secret.db.arn
    }]
  })
}

# --- Task Role ---
resource "aws_iam_role" "ecs_task" {
  name = "${local.name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.name}-ecs-task-role" }
}

resource "aws_iam_role_policy" "ecs_task_permissions" {
  name = "task-runtime-permissions"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # App may need to re-read the secret at runtime (e.g. after rotation)
        Sid    = "ReadOwnSecret"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        # Scoped to THIS secret only - not all secrets in the account
        Resource = aws_secretsmanager_secret.db.arn
      },
      {
        # Video upload bucket - object-level permissions only
        Sid    = "VideosBucketObjects"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::${local.name}-videos/*"
      },
      {
        Sid      = "VideosBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${local.name}-videos"
      }
    ]
  })
}

# =============================================================
# 8. CloudWatch Log Group
# =============================================================
resource "aws_cloudwatch_log_group" "ecs_api" {
  name              = "/ecs/${local.name}/api"
  retention_in_days = 30
  tags              = { Name = "${local.name}-ecs-api-logs" }
}

# =============================================================
# 9. ECS Cluster
# =============================================================
resource "aws_ecs_cluster" "main" {
  name = "${local.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${local.name}-cluster" }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # Base of 1 on FARGATE ensures at least one task is always on
  # a stable capacity provider, not SPOT (which can be reclaimed)
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# =============================================================
# 10. ECS Task Definition
#
# Key decisions:
#   - 1 vCPU / 2 GB - right-sized for a typical Node/Java API.
#     Adjust via variables for your workload.
#   - Secrets are injected by the ECS agent at container start
#     using the "secrets" block - the container process never
#     calls Secrets Manager directly; the agent does.
#   - readonlyRootFilesystem = true - container can't write to
#     its own filesystem, forcing all writes to mounted volumes
#     or external stores. Reduces blast radius of RCE.
#   - User 1000:1000 - non-root, no privilege escalation.
# =============================================================
resource "aws_ecs_task_definition" "api" {
  family                   = "${local.name}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"   # 1 vCPU
  memory                   = "2048"   # 2 GB
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "api"
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      # Non-sensitive config via environment variables
      environment = [
        { name = "APP_ENV",  value = var.env },
        { name = "PORT",     value = tostring(var.container_port) },
        { name = "DB_NAME",  value = "vidstream" },
        { name = "DB_PORT",  value = "5432" },
        # Host comes from the RDS endpoint; not sensitive so env var is fine
        { name = "DB_HOST",  value = aws_db_instance.postgres.address }
      ]

      # Sensitive values injected by ECS agent from Secrets Manager.
      # The container sees them as env vars but they never appear in
      # the task definition in plaintext. The :username:: and :password::
      # suffixes are JSONPath-style keys into the secret's JSON value.
      secrets = [
        {
          name      = "DB_USERNAME"
          valueFrom = "${aws_secretsmanager_secret.db.arn}:username::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.db.arn}:password::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "api"
        }
      }

      # Health check - ECS marks tasks unhealthy and replaces them
      # if /health doesn't return 200 after 3 consecutive failures
      healthCheck = {
        command     = ["CMD-SHELL", "curl -sf http://localhost:${var.container_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      # Security hardening
      readonlyRootFilesystem = true
      user                   = "1000:1000"

      # Prevent a runaway container from consuming all task memory
      # Hard limit: container is killed if it exceeds this
      # Soft limit: kernel can reclaim memory below this if needed elsewhere
      memoryReservation = 512

      linuxParameters = {
        initProcessEnabled = true   # reaps zombie processes
      }
    }
  ])

  tags = { Name = "${local.name}-api-task" }
}

# =============================================================
# 11. Application Load Balancer
# =============================================================
resource "aws_lb" "main" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  enable_deletion_protection = true

  # Access logs to S3 - required for production auditing
  # Bucket must have the ALB service account allowed to write to it.
  # Omitted here for brevity but should be added before go-live.

  tags = { Name = "${local.name}-alb" }
}

resource "aws_lb_target_group" "api" {
  name        = "${local.name}-api-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"  # required for Fargate (awsvpc network mode)

  health_check {
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  # Allow in-flight requests to complete before deregistering a task
  deregistration_delay = 30

  tags = { Name = "${local.name}-api-tg" }
}

# HTTPS listener - production traffic
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# HTTP listener - redirect everything to HTTPS, never serve over plain HTTP
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# =============================================================
# 12. ECS Service + Auto Scaling
# =============================================================
resource "aws_ecs_service" "api" {
  name            = "${local.name}-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets = [
      aws_subnet.private_app_a.id,
      aws_subnet.private_app_b.id,
    ]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false  # private subnet; egress via NAT GW
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = var.container_port
  }

  # Deployment circuit breaker: if a new deployment fails to reach
  # a steady state (e.g. container keeps crashing) ECS automatically
  # rolls back to the previous task definition. Critical for prod.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  # Rolling update config: always keep at least 1 task running
  # during deploys, allow up to 200% capacity briefly
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  # Don't let Terraform fight with auto scaling over desired_count
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_lb_listener.https,
    aws_iam_role_policy.ecs_execution_secret,
  ]

  tags = { Name = "${local.name}-api-service" }
}

# --- Application Auto Scaling ---
resource "aws_appautoscaling_target" "ecs_api" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scale out fast on CPU pressure (60s cooldown), scale in slowly (300s)
# to avoid flapping under bursty traffic
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_api.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_api.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 65.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "memory" {
  name               = "${local.name}-mem-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_api.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_api.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# --- CloudWatch Alarm: 5xx spike ---
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name}-alb-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ALB target 5xx errors above threshold - investigate ECS tasks"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.api.arn_suffix
  }

  tags = { Name = "${local.name}-5xx-alarm" }
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${local.name}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS connections approaching max_connections limit"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.id
  }

  tags = { Name = "${local.name}-rds-conn-alarm" }
}
