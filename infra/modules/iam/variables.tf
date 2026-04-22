variable "project"     { type = string }
variable "environment" { type = string }

variable "aws_region"  { type = string }
variable "account_id"  { type = string }

variable "ecr_repository_arns" {
  type = list(string)
}

variable "secrets_arns" {
  type        = list(string)
  description = "Secrets Manager ARNs the tasks need to read"
}

variable "sqs_queue_arn"  { type = string }
variable "s3_logs_bucket" { type = string }

variable "cloudwatch_kms_key_arn" { type = string }
variable "secrets_kms_key_arn"    { type = string }
variable "sqs_kms_key_arn"        { type = string }
variable "rds_kms_key_arn"        { type = string }