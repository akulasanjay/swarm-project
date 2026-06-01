variable "project_name"              { type = string }
variable "environment"               { type = string }
variable "vpc_id"                    { type = string }
variable "subnet_ids"                { type = list(string) }
variable "ami_id"                    { type = string }
variable "instance_type"             { type = string }
variable "manager_count"             { type = number }
variable "key_name"                  { type = string }
variable "security_group_ids"        { type = list(string) }
variable "iam_instance_profile_name" { type = string }
variable "swarm_join_token_secret"   { type = string }

variable "docker_version" {
  type    = string
  default = ""
}

variable "manager_primary_ip_placeholder" {
  description = "Placeholder string replaced at runtime with the primary manager's private IP"
  type        = string
  default     = "MANAGER_PRIMARY_IP"
}
