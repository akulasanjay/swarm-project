########################################
# Root Outputs
########################################

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "manager_instance_ids" {
  description = "EC2 instance IDs of Swarm manager nodes"
  value       = module.manager.manager_instance_ids
}

output "manager_primary_private_ip" {
  description = "Private IP of the primary Swarm manager"
  value       = module.manager.manager_primary_private_ip
}

output "worker_asg_name" {
  description = "Auto Scaling Group name for worker nodes"
  value       = module.workers.asg_name
}

output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = module.load_balancer.alb_dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.load_balancer.alb_arn
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = module.load_balancer.target_group_arn
}

output "swarm_url" {
  description = "Application URL (DNS record if configured, otherwise ALB DNS)"
  value = format(
    "%s://%s",
    var.certificate_arn != "" ? "https" : "http",
    var.domain_name != "" ? var.domain_name : module.load_balancer.alb_dns_name,
  )
}

output "swarm_token_secret_arn" {
  description = "ARN of the Secrets Manager secret holding Swarm join tokens"
  value       = module.iam.swarm_token_secret_arn
}

output "manager_iam_role_arn" {
  description = "ARN of the IAM role attached to manager nodes"
  value       = module.iam.manager_role_arn
}

output "worker_iam_role_arn" {
  description = "ARN of the IAM role attached to worker nodes"
  value       = module.iam.worker_role_arn
}
