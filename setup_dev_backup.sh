#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# One-time setup: dev/OSS backup S3 bucket + KMS key + IAM policy.
#
# Review before running. This is infrastructure creation in the dev AWS
# account — run it yourself with an identity that has permission to
# create S3 buckets, KMS keys, and IAM policies. Nothing here is
# executed automatically by Claude; it's handed to you for review per
# the "surface security-posture / shared-infra changes before making
# them" rule.
#
# Does NOT reuse prod's KMS key or IAM role — dev gets its own key and
# its own narrowly-scoped policy, kept separate from prod's blast radius.
# =====================================================================

REGION="${AWS_REGION:-us-east-1}"
BUCKET="${BUCKET:-cnxs-dev-atlassian-backups}"
KMS_ALIAS="${KMS_ALIAS:-alias/dev-atlassian-backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
IAM_POLICY_NAME="${IAM_POLICY_NAME:-dev-atlassian-backup-write}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
echo "Account: ${ACCOUNT_ID}   Region: ${REGION}   Bucket: ${BUCKET}"
echo

# ===== 1) Create bucket =====
echo "[1/6] Creating bucket s3://${BUCKET} ..."
if [[ "$REGION" == "us-east-1" ]]; then
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
fi
# If this fails with BucketAlreadyExists, S3 bucket names are globally
# unique across ALL AWS accounts — pick a more specific name, e.g.
# "cnxs-dev-atlassian-backups-${ACCOUNT_ID}", and re-run with
# BUCKET=that-name.

# ===== 2) Block all public access =====
echo "[2/6] Blocking public access ..."
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# ===== 3) Enable versioning (cheap insurance against accidental overwrite/delete) =====
echo "[3/6] Enabling versioning ..."
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

# ===== 4) Create dev-specific KMS key + alias =====
echo "[4/6] Creating KMS key ..."
KEY_ID="$(aws kms create-key \
  --description "Dev/OSS Atlassian nightly backup encryption (Bitbucket/Bamboo config, Postgres dumps)" \
  --region "$REGION" \
  --tags TagKey=Purpose,TagValue=dev-atlassian-backup \
  --query KeyMetadata.KeyId --output text)"
echo "  KeyId: ${KEY_ID}"

aws kms create-alias --alias-name "$KMS_ALIAS" --target-key-id "$KEY_ID" --region "$REGION"
KEY_ARN="arn:aws:kms:${REGION}:${ACCOUNT_ID}:key/${KEY_ID}"
echo "  Alias: ${KMS_ALIAS} -> ${KEY_ARN}"

# ===== 5) Bucket default encryption (SSE-KMS, bucket key on for cost) =====
echo "[5/6] Setting default encryption + lifecycle + TLS-only bucket policy ..."
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms",
        "KMSMasterKeyID": "'"${KEY_ARN}"'"
      },
      "BucketKeyEnabled": true
    }]
  }'

# Lifecycle: expire current + noncurrent versions after RETENTION_DAYS.
# (Weekly rollups live under weekly/ — same rule applies; if you want
# weekly kept longer than nightly, split this into two rules with a
# Filter Prefix and re-run just this step.)
aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "expire-after-'"${RETENTION_DAYS}"'-days",
      "Status": "Enabled",
      "Filter": {},
      "Expiration": { "Days": '"${RETENTION_DAYS}"' },
      "NoncurrentVersionExpiration": { "NoncurrentDays": '"${RETENTION_DAYS}"' },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 }
    }]
  }'

# Deny any non-TLS request to the bucket.
aws s3api put-bucket-policy --bucket "$BUCKET" --policy '{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyInsecureTransport",
    "Effect": "Deny",
    "Principal": "*",
    "Action": "s3:*",
    "Resource": ["arn:aws:s3:::'"${BUCKET}"'", "arn:aws:s3:::'"${BUCKET}"'/*"],
    "Condition": { "Bool": { "aws:SecureTransport": "false" } }
  }]
}'

# ===== 6) Scoped IAM policy for the backup host/role =====
echo "[6/6] Writing IAM policy document -> ./${IAM_POLICY_NAME}.json"
cat > "${IAM_POLICY_NAME}.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "WriteReadDevBackupBucket",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::${BUCKET}",
        "arn:aws:s3:::${BUCKET}/*"
      ]
    },
    {
      "Sid": "UseDevBackupKmsKey",
      "Effect": "Allow",
      "Action": ["kms:GenerateDataKey", "kms:Decrypt", "kms:DescribeKey"],
      "Resource": "${KEY_ARN}"
    }
  ]
}
JSON

echo
echo "Review ${IAM_POLICY_NAME}.json, then attach it to the dev-ssm-role role"
echo "(confirmed as the role ip-10-56-128-233 assumes for AWS CLI calls):"
echo
echo "  aws iam create-policy --policy-name ${IAM_POLICY_NAME} --policy-document file://${IAM_POLICY_NAME}.json"
echo "  aws iam attach-role-policy --role-name dev-ssm-role --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${IAM_POLICY_NAME}"
echo
echo "Bucket:  s3://${BUCKET}  (region ${REGION})"
echo "KMS key: ${KEY_ARN}  (alias ${KMS_ALIAS})"
echo "Retention: ${RETENTION_DAYS} days, versioning on, public access blocked, TLS-only."
echo
echo "Nothing here touches prod's bucket, key, or IAM role."