output "alb_sg_id"     { value = aws_security_group.alb.id }
output "manager_sg_id" { value = aws_security_group.manager.id }
output "worker_sg_id"  { value = aws_security_group.worker.id }
