variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name - used as a prefix for all resource names"
  type        = string
  default     = "vidstream"
}

variable "env" {
  description = "Environment name (prod / staging / dev)"
  type        = string
  default     = "prod"
}

variable "db_username" {
  description = "Master username for the RDS Postgres instance"
  type        = string
  default     = "vidstream_admin"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "container_image" {
  description = "Full ECR image URI including tag, e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/vidstream-api:abc1234"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for the HTTPS ALB listener"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}
