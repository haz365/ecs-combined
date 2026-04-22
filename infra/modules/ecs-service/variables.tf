variable "project"     { type = string }
variable "environment" { type = string }
variable "aws_region"  { type = string }
variable "cluster_id"  { type = string }
variable "vpc_id"      { type = string }

variable "private_subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "service_name"   { type = string }
variable "image_uri"      { type = string }
variable "container_port" { type = number }

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "min_count" {
  type    = number
  default = 1
}

variable "max_count" {
  type    = number
  default = 4
}

variable "execution_role_arn" { type = string }
variable "task_role_arn"      { type = string }

variable "target_group_arn" {
  type    = string
  default = ""
}

variable "log_group_name" { type = string }

variable "environment_vars" {
  type    = list(object({ name = string, value = string }))
  default = []
}

variable "secrets" {
  type    = list(object({ name = string, valueFrom = string }))
  default = []
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "enable_load_balancer" {
  type    = bool
  default = true
}