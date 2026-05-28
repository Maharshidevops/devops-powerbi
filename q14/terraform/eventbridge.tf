# EventBridge + Lambda — ECS/RDS cost scheduler
# Deployed once per environment (dev and staging).
# Pass env="dev" or env="staging" via terraform workspace or tfvars.
#
# Two cron rules:
#   scale-down: 8:00 PM IST = 14:30 UTC
#   scale-up:   8:00 AM IST = 02:30 UTC
#
# Why Lambda instead of a cron job on an EC2 instance:
# There's no instance to maintain, patch, or pay for when it's idle.
# Lambda costs essentially nothing for two invocations per day.
# EventBridge cron is more reliable than crontab — it retries on
# failure and has built-in dead-letter queue support.

variable "env"            { type = string }  # "dev" or "staging"
variable "aws_region"     { default = "us-east-1" }
variable "ecs_cluster"    { type = string }
variable "ecs_service"    { type = string }
variable "rds_identifier" { type = string }
variable "scale_up_count" { default = "2" }

locals {
  name = "vidstream-${var.env}-scheduler"
}

# ── Lambda IAM role ───────────────────────────────────────────────────
resource "aws_iam_role" "scheduler" {
  name = "${local.name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "${local.name}-policy"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ECS — only the specific cluster and service, not *
        Sid    = "ECSScale"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:UpdateService"
        ]
        Resource = [
          "arn:aws:ecs:${var.aws_region}:*:cluster/${var.ecs_cluster}",
          "arn:aws:ecs:${var.aws_region}:*:service/${var.ecs_cluster}/${var.ecs_service}"
        ]
      },
      {
        # RDS — only this specific instance
        Sid    = "RDSStartStop"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:StopDBInstance",
          "rds:StartDBInstance"
        ]
        Resource = "arn:aws:rds:${var.aws_region}:*:db:${var.rds_identifier}"
      },
      {
        # CloudWatch Logs — so Lambda can write its own logs
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ── Lambda function ───────────────────────────────────────────────────
# Package the Python file as a zip before applying.
# In CI this is done with: zip scheduler.zip scheduler.py
data "archive_file" "scheduler" {
  type        = "zip"
  source_file = "${path.module}/../lambda/scheduler.py"
  output_path = "${path.module}/scheduler.zip"
}

resource "aws_lambda_function" "scheduler" {
  function_name    = local.name
  filename         = data.archive_file.scheduler.output_path
  source_code_hash = data.archive_file.scheduler.output_base64sha256
  handler          = "scheduler.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.scheduler.arn
  timeout          = 60    # generous — RDS API calls can be slow

  environment {
    variables = {
      ECS_CLUSTER    = var.ecs_cluster
      ECS_SERVICE    = var.ecs_service
      RDS_IDENTIFIER = var.rds_identifier
      SCALE_UP_COUNT = var.scale_up_count
    }
  }

  tags = {
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_cloudwatch_log_group" "scheduler" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = 14
}

# ── EventBridge rules ─────────────────────────────────────────────────

# 8:00 PM IST = UTC 14:30
# IST is UTC+5:30. So 20:00 IST - 5:30 = 14:30 UTC.
resource "aws_cloudwatch_event_rule" "scale_down" {
  name                = "${local.name}-scale-down"
  description         = "Scale ECS to 0 and stop RDS at 8 PM IST"
  schedule_expression = "cron(30 14 * * ? *)"
  # cron format: minute hour day-of-month month day-of-week year
  # ?  in day-of-month = "no specific value" (required when day-of-week is set, but
  #    here we leave both flexible so it runs every day)
}

resource "aws_cloudwatch_event_target" "scale_down" {
  rule      = aws_cloudwatch_event_rule.scale_down.name
  target_id = "scale-down-lambda"
  arn       = aws_lambda_function.scheduler.arn
  # Payload tells the Lambda which direction to go
  input     = jsonencode({ action = "scale-down" })
}

resource "aws_lambda_permission" "scale_down" {
  statement_id  = "AllowEventBridgeScaleDown"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scale_down.arn
}

# 8:00 AM IST = UTC 02:30
resource "aws_cloudwatch_event_rule" "scale_up" {
  name                = "${local.name}-scale-up"
  description         = "Start RDS and scale ECS to 2 at 8 AM IST"
  schedule_expression = "cron(30 2 * * ? *)"
}

resource "aws_cloudwatch_event_target" "scale_up" {
  rule      = aws_cloudwatch_event_rule.scale_up.name
  target_id = "scale-up-lambda"
  arn       = aws_lambda_function.scheduler.arn
  input     = jsonencode({ action = "scale-up" })
}

resource "aws_lambda_permission" "scale_up" {
  statement_id  = "AllowEventBridgeScaleUp"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scale_up.arn
}

# ── Dead Letter Queue — catch Lambda failures ─────────────────────────
# If the Lambda throws an exception (e.g. API call failed, wrong action),
# EventBridge retries twice then sends the event here.
# An alarm on this queue's ApproximateNumberOfMessagesVisible means
# a failed invocation surfaces in Slack rather than disappearing silently.
resource "aws_sqs_queue" "scheduler_dlq" {
  name                      = "${local.name}-dlq"
  message_retention_seconds = 86400   # keep failed events for 1 day

  tags = {
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${local.name}-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Scheduler Lambda failed — check CloudWatch Logs"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.scheduler_dlq.name
  }
}
