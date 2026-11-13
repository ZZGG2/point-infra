# CloudFront(정적 S3 + /api/* → ALB) + WAF(Managed Rules, Rate-based)
# Route 53 Failover 레코드 / ACM 은 도메인 확보 후 추가 (TODO: var.domain_name 도입)
# WAF(CLOUDFRONT scope)는 us-east-1 에만 만들 수 있어 aws.us_east_1 provider 를 받는다.

data "aws_cloudfront_cache_policy" "optimized" { name = "Managed-CachingOptimized" }
data "aws_cloudfront_cache_policy" "disabled" { name = "Managed-CachingDisabled" }
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" { name = "Managed-AllViewerExceptHostHeader" }

# ---------------------------------------------------------------- 프론트엔드 정적 버킷
resource "aws_s3_bucket" "web" {
  bucket_prefix = "${var.name}-web-"
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "web" {
  bucket                  = aws_s3_bucket.web.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "web" {
  bucket = aws_s3_bucket.web.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_cloudfront_origin_access_control" "web" {
  name                              = "${var.name}-web"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "CloudFrontRead"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.web.arn}/*"
      Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.this.arn } }
    }]
  })
}

# SPA 라우팅: 확장자 없는 경로(/admin 등)는 index.html 로. (API 응답의 404 까지 바꾸는 custom error 대신 사용)
resource "aws_cloudfront_function" "spa" {
  name    = "${var.name}-spa-rewrite"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-JS
    function handler(event) {
      var req = event.request;
      if (!req.uri.includes('.')) { req.uri = '/index.html'; }
      return req;
    }
  JS
}

# ---------------------------------------------------------------- WAF
resource "aws_wafv2_web_acl" "this" {
  provider = aws.us_east_1
  name     = "${var.name}-edge"
  scope    = "CLOUDFRONT"

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
    metric_name                = "${var.name}-edge"
    sampled_requests_enabled   = true
  }
  tags = var.tags
}

# ---------------------------------------------------------------- CloudFront
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = "${var.name} web + api"
  default_root_object = "index.html"
  price_class         = "PriceClass_200" # 한국 엣지 포함
  web_acl_id          = aws_wafv2_web_acl.this.arn
  http_version        = "http2and3"

  origin {
    origin_id                = "web"
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }

  origin {
    origin_id   = "api"
    domain_name = var.alb_dns_name
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # TODO: ACM 인증서 확보 후 https-only
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "web"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
    compress               = true
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa.arn
    }
  }

  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "api"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    compress                 = true
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true # TODO: 도메인 확보 후 ACM(us-east-1)
  }
  tags = var.tags
}
