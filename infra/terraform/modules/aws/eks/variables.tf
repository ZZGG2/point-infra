variable "cluster_name" { type = string }
variable "cluster_version" {
  type    = string
  default = "1.31"
}
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "core_instance_types" {
  type    = list(string)
  default = ["t3.large"]
}
variable "tags" {
  type    = map(string)
  default = {}
}
