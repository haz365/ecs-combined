output "prometheus_sg_id" { value = aws_security_group.prometheus.id }
output "grafana_sg_id"    { value = aws_security_group.grafana.id }
output "efs_id"           { value = aws_efs_file_system.observability.id }