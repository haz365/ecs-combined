variable "project"     { type = string }
variable "environment" { type = string }
variable "vpc_id"      { type = string }

variable "public_subnet_ids" {
  type = list(string)
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for HTTPS"
}

variable "s3_logs_bucket" {
  type        = string
  description = "S3 bucket name for ALB access logs"
}

variable "s3_kms_key_arn" {
  type = string
}