variable "project" {
  type    = string
  default = "ecs-combined"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "domain" {
  type = string
}

variable "hosted_zone_id" {
  type = string
}

variable "certificate_arn" {
  type = string
}

variable "base_url" {
  type = string
}

variable "alert_email" {
  type = string
}

variable "grafana_password" {
  type      = string
  sensitive = true
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "key_deletion_window" {
  type    = number
  default = 7
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
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
  default = 0
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "redis_node_type" {
  type    = string
  default = "cache.t3.micro"
}

variable "redis_num_nodes" {
  type    = number
  default = 1
}

variable "api_desired_count" {
  type    = number
  default = 2
}

variable "dashboard_desired_count" {
  type    = number
  default = 2
}

variable "monthly_budget_usd" {
  type    = string
  default = "200"
}