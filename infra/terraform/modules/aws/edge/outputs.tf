output "cloudfront_domain" { value = aws_cloudfront_distribution.this.domain_name }
output "cloudfront_distribution_id" { value = aws_cloudfront_distribution.this.id }
output "web_bucket" { value = aws_s3_bucket.web.bucket }
output "waf_arn" { value = aws_wafv2_web_acl.this.arn }
