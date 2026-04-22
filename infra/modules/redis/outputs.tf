output "primary_endpoint"      { value = aws_elasticache_replication_group.main.primary_endpoint_address }
output "port"                  { value = 6379 }
output "auth_token_secret_arn" { value = aws_secretsmanager_secret.redis_token.arn }
output "security_group_id"     { value = aws_security_group.redis.id }