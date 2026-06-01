output "manager_role_arn"              { value = aws_iam_role.manager.arn }
output "manager_instance_profile_name" { value = aws_iam_instance_profile.manager.name }
output "worker_role_arn"               { value = aws_iam_role.worker.arn }
output "worker_instance_profile_name"  { value = aws_iam_instance_profile.worker.name }
output "swarm_token_secret_arn"        { value = aws_secretsmanager_secret.swarm_tokens.arn }
