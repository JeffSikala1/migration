resource "aws_wafv2_web_acl" "uiwebacls" {
  name        = "${var.vpc_name}-uiwaf"
  scope       = "REGIONAL"
  default_action { 
    allow {}
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.vpc_name}-uiwaf-metrics"
    sampled_requests_enabled   = true
  }

# 3) Block oversized headers (> 8KB total)
  rule {
    name     = "BlockOversizedHeaders"
    priority = 3
    statement {
      size_constraint_statement {
        field_to_match {
          headers {
            match_scope       = "ALL"
            oversize_handling = "MATCH"
            match_pattern {
              all {}
            }
          }
        }
        comparison_operator = "GT"
        size                = 8192  # 8KB limit for all headers combined
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

  # 5) Block requests with a user-agent header containing "BadBot"
  rule {
    name     = "BlockBadBot"
    priority = 5
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

  # 6) Block requests with oversized cookie header (> 4KB)
  rule {
    name     = "BlockHugeCookieHeader"
    priority = 11
    statement {
      size_constraint_statement {
        field_to_match {
          single_header {
            name = "cookie"
          }
        }
        comparison_operator = "GT"
        size                = 4096  # 4KB limit for cookie header
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

 # 7) block XSS
  rule {
    name     = "BlockXSS"
    priority = 10
    statement {
      xss_match_statement {
        field_to_match {
          body {}
        }
        # The transformations help standardize input, so we can detect XSS even if it's encoded
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
    action {
      block {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockXSS"
      sampled_requests_enabled   = true
    }
  }
 # 8) block SQLi
  rule {
    name     = "BlockSQLi"
    priority = 20
    statement {
      sqli_match_statement {
        # Where to look for potential SQL injection
        field_to_match {
          all_query_arguments {}
        }
        # text_transformations help decode or normalize the input
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

resource "aws_wafv2_web_acl_association" "uialb_waf_assoc" {
  resource_arn = aws_lb.uiwafuialb.arn
  web_acl_arn  = aws_wafv2_web_acl.uiwebacls.arn
}
