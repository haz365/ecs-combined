variable "project"                    { type = string }
variable "environment"                { type = string }
variable "vpc_id"                     { type = string }
variable "private_subnet_ids"         { type = list(string) }
variable "allowed_security_group_ids" { type = list(string) }
variable "kms_key_arn"                { type = string }
variable "secrets_kms_key_arn"        { type = string }

variable "node_type" {
  type    = string
  default = "cache.t3.micro"
}

variable "num_cache_nodes" {
  type    = number
  default = 1
}