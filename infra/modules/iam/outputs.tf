output "execution_role_arn"  { value = aws_iam_role.execution.arn }
output "execution_role_name" { value = aws_iam_role.execution.name }

output "api_task_role_arn"       { value = aws_iam_role.api.arn }
output "worker_task_role_arn"    { value = aws_iam_role.worker.arn }
output "dashboard_task_role_arn" { value = aws_iam_role.dashboard.arn }

output "api_task_role_name"       { value = aws_iam_role.api.name }
output "worker_task_role_name"    { value = aws_iam_role.worker.name }
output "dashboard_task_role_name" { value = aws_iam_role.dashboard.name }

output "log_group_names" {
  value = { for k, v in aws_cloudwatch_log_group.service : k => v.name }
}