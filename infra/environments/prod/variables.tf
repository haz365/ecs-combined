variable "project"         { type = string; default = "ecs-combined" }
variable "environment"     { type = string; default = "prod" }
variable "aws_region"      { type = string; default = "eu-west-2" }
variable "domain"          { type = string }
variable "certificate_arn" { type = string }