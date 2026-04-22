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
  type        = string
  description = "Your Route53 domain e.g. example.com"
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for your domain"
}

variable "base_url" {
  type        = string
  description = "Base URL for short links e.g. https://hasanali.uk"
  default     = ""
}