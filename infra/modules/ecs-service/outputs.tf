output "service_name"      { value = aws_ecs_service.service.name }
output "service_id"        { value = aws_ecs_service.service.id }
output "task_definition"   { value = aws_ecs_task_definition.service.arn }
output "security_group_id" { value = aws_security_group.service.id }