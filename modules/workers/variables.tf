variable "project_name"              { type = string }
variable "environment"               { type = string }
variable "vpc_id"                    { type = string }
variable "subnet_ids"                { type = list(string) }
variable "ami_id"                    { type = string }
variable "instance_type"             { type = string }
variable "min_workers"               { type = number }
variable "max_workers"               { type = number }
variable "desired_workers"           { type = number }
variable "key_name"                  { type = string }
variable "security_group_ids"        { type = list(string) }
variable "iam_instance_profile_name" { type = string }
variable "manager_private_ip"        { type = string }
variable "swarm_join_token_secret"   { type = string }
variable "target_group_arn"          { type = string }

variable "docker_version" {
  type    = string
  default = ""
}
