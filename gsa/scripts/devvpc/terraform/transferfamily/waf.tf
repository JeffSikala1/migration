resource "aws_wafv2_web_acl" "webacls" {
  name  = "${var.vpc_name}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.vpc_name}-waf-metrics"
    sampled_requests_enabled   = true
  }

  # 1) All Traffic Rate Limit: 150 req/min => 750 per 5 min
  rule {
    name     = "RateLimitAllTraffic"
    priority = 1
    statement {
      rate_based_statement {
        limit              = 750
        aggregate_key_type = "IP"
      }
    }
    action {
      block {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitAllTraffic"
      sampled_requests_enabled   = true
    }
  }

  # 2) Block oversized headers (> 8KB total)
  rule {
    name     = "BlockOversizedHeaders"
    priority = 2
    statement {
      size_constraint_statement {
        field_to_match {
          headers {
            match_scope       = "ALL"
            oversize_handling = "CONTINUE"
            match_pattern {
              all {}
            }
          }
        }
        comparison_operator = "GT"
        size                = 8192
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }
    action {
      block {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockOversizedHeaders"
      sampled_requests_enabled   = true
    }
  }

  # 3) Block oversized request bodies (> 20 MB)
  rule {
    name     = "BlockOversizedBody"
    priority = 3
    statement {
      size_constraint_statement {
        field_to_match {
          body {
            oversize_handling = "CONTINUE"
          }
        }
        comparison_operator = "GT"
        size                = 20971520
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }
    action {
      block {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockOversizedBody"
      sampled_requests_enabled   = true
    }
  }

  # 4) Block requests with a user-agent header containing "BadBot"
  rule {
    name     = "BlockBadBot"
    priority = 4
    statement {
      byte_match_statement {
        field_to_match {
          single_header {
            name = "user-agent"
          }
        }
        positional_constraint = "CONTAINS"
        search_string         = "BadBot"
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }
    action {
      block {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockBadBot"
      sampled_requests_enabled   = true
    }
  }

  # 5) Block requests with oversized cookie header (> 4KB)
  rule {
    name     = "BlockHugeCookieHeader"
    priority = 5
    statement {
      size_constraint_statement {
        field_to_match {
          single_header {
            name = "cookie"
          }
        }
        comparison_operator = "GT"
        size                = 4096
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }
    action {
      block {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockHugeCookieHeader"
      sampled_requests_enabled   = true
    }
  }

  # 6) Block XSS (allow specific path prefix)
  rule {
    name     = "BlockXSS"
    priority = 6
    statement {
      and_statement {
        statement {
          xss_match_statement {
            field_to_match {
              body {
                oversize_handling = "CONTINUE"
              }
            }
            text_transformation {
              priority = 0
              type     = "HTML_ENTITY_DECODE"
            }
            text_transformation {
              priority = 1
              type     = "URL_DECODE"
            }
          }
        }
        statement {
          not_statement {
            statement {
              byte_match_statement {
                field_to_match {
                  uri_path {}
                }
                search_string         = "/eas/conexus/"
                positional_constraint = "STARTS_WITH"
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }
    action {
      block {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockXSS"
      sampled_requests_enabled   = true
    }
  }

  # 7) Block SQLi
  rule {
    name     = "BlockSQLi"
    priority = 7
    statement {
      sqli_match_statement {
        field_to_match {
          all_query_arguments {}
        }
        text_transformation {
          priority = 0
          type     = "URL_DECODE"
        }
        text_transformation {
          priority = 1
          type     = "HTML_ENTITY_DECODE"
        }
      }
    }
    action {
      block {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockSQLi"
      sampled_requests_enabled   = true
    }
  }
}

resource "aws_wafv2_web_acl_association" "alb_waf_assoc" {
  resource_arn = aws_lb.wafalb.arn
  web_acl_arn  = aws_wafv2_web_acl.webacls.arn
}
