variable "project"     { type = string }
variable "environment" { type = string }

variable "alert_email" {
  type    = string
  default = ""
}

variable "monthly_budget_usd" {
  type    = string
  default = "200"
}

variable "alb_arn_suffix" {
  type = string
}

variable "api_target_group_arn_suffix" {
  type = string
}

variable "sqs_queue_name" {
  type = string
}

variable "rds_instance_id" {
  type = string
}

variable "ecs_cluster_name" {
  type = string
}

variable "api_desired_count" {
  type    = number
  default = 2
}