variable "name" { type = string }
variable "zone_name" { type = string }
variable "hostname" { type = string }

data "aws_route53_zone" "this" {
  name         = var.zone_name
  private_zone = false
}

resource "aws_acm_certificate" "this" {
  domain_name       = var.hostname
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}

resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for option in aws_acm_certificate.this.domain_validation_options : option.resource_record_name => option
  }
  zone_id         = data.aws_route53_zone.this.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

resource "aws_wafv2_web_acl" "this" {
  name  = "${var.name}-web"
  scope = "REGIONAL"
  default_action {
    allow {}
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-web"
    sampled_requests_enabled   = true
  }
  rule {
    name     = "AWSManagedCommonRules"
    priority = 10
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common"
      sampled_requests_enabled   = true
    }
  }
  rule {
    name     = "RateLimit"
    priority = 20
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 200
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }
  }
}

output "certificate_arn" { value = aws_acm_certificate_validation.this.certificate_arn }
output "web_acl_arn" { value = aws_wafv2_web_acl.this.arn }
output "zone_id" { value = data.aws_route53_zone.this.zone_id }
