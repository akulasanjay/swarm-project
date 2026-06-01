########################################
# Module: Route 53 DNS
########################################

resource "aws_route53_record" "swarm" {
  count   = var.hosted_zone_id != "" && var.domain_name != "" ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# Optional: www → apex redirect
resource "aws_route53_record" "swarm_www" {
  count   = var.hosted_zone_id != "" && var.domain_name != "" && var.create_www_record ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}
