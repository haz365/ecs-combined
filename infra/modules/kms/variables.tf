variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "key_deletion_window" {
  type    = number
  default = 30
}