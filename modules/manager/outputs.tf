output "manager_instance_ids" {
  value = concat(
    [aws_instance.manager_primary.id],
    aws_instance.manager_secondary[*].id
  )
}

output "manager_primary_private_ip" {
  value = aws_instance.manager_primary.private_ip
}

output "manager_private_ips" {
  value = concat(
    [aws_instance.manager_primary.private_ip],
    aws_instance.manager_secondary[*].private_ip
  )
}
