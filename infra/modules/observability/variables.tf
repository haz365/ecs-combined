variable "project"     { type = string }
variable "environment" { type = string }
variable "aws_region"  { type = string }

variable "vpc_id"             { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "cluster_id"         { type = string }
variable "alb_sg_id"          { type = string }
variable "https_listener_arn" { type = string }

variable "execution_role_arn"    { type = string }
variable "cloudwatch_kms_key_arn" { type = string }

variable "api_sg_id"       { type = string }
variable "worker_sg_id"    { type = string }
variable "dashboard_sg_id" { type = string }

variable "ecr_base" {
  type        = string
  description = "ECR registry base URL e.g. 123456789.dkr.ecr.eu-west-2.amazonaws.com/ecs-combined"
}