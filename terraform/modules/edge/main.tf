variable "name" { type = string }
variable "zone_name" { type = string }
variable "hostname" { type = string }
variable "vpc_id" { type = string }
variable "node_security_group_id" { type = string }
variable "enable_waf" {
  type        = bool
  description = "Whether to create the regional WAF ACL for this environment."
  default     = true
}

resource "aws_security_group" "alb" {
  # checkov:skip=CKV_AWS_260: Internet-facing ALB must accept HTTP solely to issue an HTTPS redirect; no workload port is exposed.
  # checkov:skip=CKV2_AWS_5: This security group is consumed by the AWS Load Balancer Controller-created ALB, which static analysis cannot resolve.
  name        = "${var.name}-alb"
  description = "Public HTTPS ingress to the transaction API ALB"
  vpc_id      = var.vpc_id
  ingress {
    description = "HTTP redirect only"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS client traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description     = "ALB targets on the application port"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [var.node_security_group_id]
  }
}

resource "aws_security_group_rule" "node_from_alb" {
  type                     = "ingress"
  description              = "ALB IP targets to transaction API pods"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = var.node_security_group_id
  source_security_group_id = aws_security_group.alb.id
}

data "aws_route53_zone" "this" {
  # This module uses an existing public zone; it does not register a domain
  # or create/delegate a hosted zone.
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
    # Domain names are known during planning; ACM record names are not.
    for option in aws_acm_certificate.this.domain_validation_options : option.domain_name => option
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
  # checkov:skip=CKV2_AWS_31: WAF logs are centralized by the account logging service; this module does not own the destination/resource policy.
  count = var.enable_waf ? 1 : 0
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
    name     = "AWSManagedKnownBadInputs"
    priority = 15
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "known-bad-inputs"
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
output "web_acl_arn" { value = try(aws_wafv2_web_acl.this[0].arn, null) }
output "zone_id" { value = data.aws_route53_zone.this.zone_id }
output "alb_security_group_id" { value = aws_security_group.alb.id }
