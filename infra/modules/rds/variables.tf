variable "project"     { type = string }
variable "environment" { type = string }
variable "vpc_id"      { type = string }

variable "private_subnet_ids" {
  type = list(string)
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "SG IDs allowed to connect to RDS (ECS task SGs)"
}

variable "rds_kms_key_arn" {
  type = string
}

variable "secrets_kms_key_arn" {
  type = string
}

variable "db_name" {
  type    = string
  default = "ecscombined"
}

variable "db_username" {
  type    = string
  default = "appuser"
}

variable "instance_class" {
  type    = string
  default = "db.t3.medium"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "deletion_protection" {
  type    = bool
  default = false
}