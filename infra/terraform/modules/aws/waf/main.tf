# 리전 WAF (ALB 연결) — 봇·매크로 1차 방어, IP Rate Limit (security.md §1)
# Gateway API(LoadBalancerConfiguration.wafV2)는 ARN 을 요구해 공개 저장소에 둘 수 없으므로 Terraform 이 직접 연결한다.
resource "aws_wafv2_web_acl" "this" {
  name  = "${var.name}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit-per-ip"
    priority = 0
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.rate_limit_per_5min
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-per-ip"
      sampled_requests_enabled   = true
    }
  }

  dynamic "rule" {
    for_each = { 1 = "AWSManagedRulesAmazonIpReputationList", 2 = "AWSManagedRulesCommonRuleSet", 3 = "AWSManagedRulesKnownBadInputsRuleSet" }
    content {
      name     = rule.value
      priority = tonumber(rule.key)
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = rule.value
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.value
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-waf"
    sampled_requests_enabled   = true
  }
  tags = var.tags
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}
