variable "endpoint" { type = string }
variable "username" { type = string }
variable "password" { type = string, sensitive = true }
variable "ssh_public_key" { type = string }
variable "node" { type = string }
