variable "cluster_name" {}

variable "extra_tags" {
  default = {}
  type    = map(string)
}

variable "node_role_ids" {
  type = set(string)
}

variable "node_security_group" {}

variable "storage_class_name" {
  default = "efs-sc"
}

variable "subnet_ids" {
  type = set(string)
}
