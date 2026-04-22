variable "project"     { type = string }
variable "environment" { type = string }

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC e.g. 10.0.0.0/16"
}

variable "cloudwatch_kms_key_arn" {
  type        = string
  description = "KMS key ARN for CloudWatch log group encryption"
}