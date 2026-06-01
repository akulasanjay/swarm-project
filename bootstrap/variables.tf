variable "aws_region" {
  description = "AWS region for the state bucket and lock table"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name, used to name the CI role"
  type        = string
  default     = "docker-swarm"
}

variable "state_bucket_name" {
  description = "Globally-unique name for the S3 state bucket"
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "terraform-locks"
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the CI role, as owner/repo"
  type        = string
}

variable "github_allowed_refs" {
  description = "Git refs (sub claim suffixes) allowed to assume the role"
  type        = list(string)
  default = [
    "ref:refs/heads/main",
    "ref:refs/heads/master",
    "pull_request",
  ]
}
