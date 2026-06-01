output "dns_record_fqdn" {
  value = length(aws_route53_record.swarm) > 0 ? aws_route53_record.swarm[0].fqdn : null
}
