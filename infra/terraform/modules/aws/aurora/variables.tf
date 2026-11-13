variable "name" { type = string }
variable "vpc_id" { type = string }
variable "db_subnet_group" { type = string }
variable "allowed_security_group_ids" { type = list(string) }
variable "engine_version" {
  type    = string
  default = "16.4"
}
variable "instance_class" {
  type    = string
  default = "db.t4g.medium"
}
variable "instance_count" {
  type    = number
  default = 2
}
variable "deletion_protection" {
  type    = bool
  default = false
}
variable "tags" {
  type    = map(string)
  default = {}
}
