output "asg_name"              { value = aws_autoscaling_group.workers.name }
output "asg_arn"               { value = aws_autoscaling_group.workers.arn }
output "launch_template_id"   { value = aws_launch_template.worker.id }
