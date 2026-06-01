variable "project_name" { type = string }
variable "environment"  { type = string }

variable "secret_recovery_window_in_days" {
  description = "Days Secrets Manager retains the swarm-tokens secret after deletion (0 = immediate, 7-30 typical for prod)"
  type        = number
  default     = 7
}
