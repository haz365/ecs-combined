variable "project"          { type = string }
variable "environment"      { type = string }
variable "kms_key_arn"      { type = string }
variable "allowed_role_arns" {
  type    = list(string)
  default = []
}