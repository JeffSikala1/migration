# Data for the deny-insecure-transport policy
data "aws_iam_policy_document" "combined_policy" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [
      aws_s3_bucket.bucket.arn,
      "${aws_s3_bucket.bucket.arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "AllowVPCeAccess"
    effect    = "Allow"
    actions   = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [
      aws_s3_bucket.bucket.arn,
      "${aws_s3_bucket.bucket.arn}/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpce"
      values   = [var.s3_vpc_endpoint_id]
    }
  }
}

resource "aws_s3_bucket" "bucket" {
  bucket        = var.bucket_name
  force_destroy = var.bucket_force_destroy
  tags          = merge(var.tags)
}

#Attach the policy to the bucket
resource "aws_s3_bucket_policy" "deny_insecure_and_vpce" {
  bucket = aws_s3_bucket.bucket.id
  policy = data.aws_iam_policy_document.combined_policy.json
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket                  = aws_s3_bucket.bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.key.id
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_acl" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  acl    = "private"

  depends_on = [aws_s3_bucket_ownership_controls.bucket-acl-ownership]
}

resource "aws_s3_bucket_ownership_controls" "bucket-acl-ownership" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_versioning" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  versioning_configuration {
    status = var.bucket_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    id     = "log"
    status = var.enable_logs_s3_sync && var.log_auto_clean ? "Enabled" : "Disabled"

    filter {
      prefix = "logs/"
    }

    transition {
      days          = var.log_standard_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.log_glacier_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.log_expiry_days
    }
  }
}

