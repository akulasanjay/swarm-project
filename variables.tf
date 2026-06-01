########################################
# Root Variables
########################################

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for all resource names"
  type        = string
  default     = "docker-swarm"
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)"
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to use (2 or 3 recommended)"
  type        = number
  default     = 2
}

variable "allowed_cidr" {
  description = "CIDRs allowed to SSH into manager nodes (defaults to none; set to your IP/32 or VPN range)"
  type        = list(string)
  default     = []
}

# ---- Compute ----

variable "key_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
}

variable "manager_instance_type" {
  description = "EC2 instance type for Swarm managers"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "EC2 instance type for Swarm workers"
  type        = string
  default     = "t3.large"
}

variable "manager_count" {
  description = "Number of Swarm manager nodes (use 1, 3, or 5 for quorum)"
  type        = number
  default     = 3
}

variable "min_workers" {
  description = "Minimum number of Swarm worker nodes (ASG)"
  type        = number
  default     = 2
}

variable "max_workers" {
  description = "Maximum number of Swarm worker nodes (ASG)"
  type        = number
  default     = 10
}

variable "desired_workers" {
  description = "Desired number of Swarm worker nodes at launch"
  type        = number
  default     = 3
}

variable "docker_version" {
  description = "Docker CE version to install (empty = latest)"
  type        = string
  default     = ""
}

# ---- Load Balancer & DNS ----

variable "health_check_path" {
  description = "HTTP path used for ALB target-group health checks"
  type        = string
  default     = "/"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener (leave empty to use HTTP only)"
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID for DNS record"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Fully-qualified domain name to point at the ALB (e.g. swarm.example.com)"
  type        = string
  default     = ""
}

variable "secret_recovery_window_in_days" {
  description = "Recovery window for the Swarm-tokens Secrets Manager secret (0 to allow immediate re-create in dev; 7-30 recommended for prod)"
  type        = number
  default     = 7
}
