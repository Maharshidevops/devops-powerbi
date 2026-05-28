output "alb_dns_name" {
  description = "Point your domain's CNAME at this value"
  value       = aws_lb.main.dns_name
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "rds_endpoint" {
  description = "RDS writer endpoint - never expose this publicly"
  value       = aws_db_instance.postgres.address
  sensitive   = true
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding DB credentials"
  value       = aws_secretsmanager_secret.db.arn
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.ecs_api.name
}

output "vpc_id" {
  value = aws_vpc.main.id
}
