variable "project_name" { type = string }
variable "environment"  { type = string }
variable "alb_dns_name" { type = string }
variable "alb_zone_id"  { type = string }

variable "hosted_zone_id" {
  type    = string
  default = ""
}

variable "domain_name" {
  type    = string
  default = ""
}

variable "create_www_record" {
  type    = bool
  default = false
}
