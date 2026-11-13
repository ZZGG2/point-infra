variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "asia-northeast3"
}
variable "git_repo_url" {
  type    = string
  default = "https://github.com/CHANGE_ME_ORG/point-infra.git"
}
