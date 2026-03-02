#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
BUCKET="s3://cnxs-atlassian-backups"
DATE="$(date +%F)"
TS="$(date +%Y%m%d_%H%M%S)"
HOST="$(hostname -f 2>/dev/null || hostname)"

BASE="/app/bamboobackup/atlassian-backups"
STAGE="${BASE}/staging/secrets/${DATE}/${TS}"
LOGDIR="${BASE}/logs"
LOG="${LOGDIR}/secrets-backup-${DATE}.log"

# KMS key used ONLY to encrypt the exported payload we store in S3
KMS_KEY_ARN="arn:aws:kms:${AWS_REGION}:339713019047:key/ae797822-83c9-4752-89f1-eb9d3fc53b68"

# Optional: only back up secrets with tag Backup=true
TAG_FILTER_ENABLED="${TAG_FILTER_ENABLED:-0}"
TAG_KEY="${TAG_KEY:-Backup}"
TAG_VALUE="${TAG_VALUE:-true}"

mkdir -p "$STAGE" "$LOGDIR"
exec > >(tee -a "$LOG") 2>&1

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 2; }; }
need aws; need jq; need base64; need gzip

OUT="${STAGE}/secrets_export_${HOST}_${TS}.ndjson"
: > "$OUT"

echo "==== Secrets backup start TS=${TS} host=${HOST} region=${AWS_REGION} ===="
echo "Output file: $OUT"
echo "Tag filter enabled: ${TAG_FILTER_ENABLED} (${TAG_KEY}=${TAG_VALUE})"
echo "Export KMS key: ${KMS_KEY_ARN}"

# Pagination + counters
NEXT_TOKEN=""
count=0
kept=0
skipped_tag=0
failed_read=0
failed_encrypt=0

# Helper: write a record even when something fails (no plaintext)
write_error_record() {
  local name="$1" arn="$2" versionId="$3" errType="$4" errMsg="$5" sourceKms="$6"
  jq -c -n \
    --arg name "$name" \
    --arg arn "$arn" \
    --arg versionId "$versionId" \
    --arg ts "$TS" \
    --arg host "$HOST" \
    --arg exportKms "$KMS_KEY_ARN" \
    --arg sourceKms "$sourceKms" \
    --arg errType "$errType" \
    --arg errMsg "$errMsg" \
    '{
      name:$name,
      arn:$arn,
      versionId:($versionId // ""),
      backedUpAt:$ts,
      backupHost:$host,
      exportKmsKey:$exportKms,
      sourceKmsKey:($sourceKms // ""),
      status:"error",
      errorType:$errType,
      error:$errMsg
    }' >> "$OUT"
}

while :; do
  if [[ -n "$NEXT_TOKEN" ]]; then
    RESP="$(aws secretsmanager list-secrets --region "$AWS_REGION" --max-results 100 --next-token "$NEXT_TOKEN")"
  else
    RESP="$(aws secretsmanager list-secrets --region "$AWS_REGION" --max-results 100)"
  fi

  while read -r s; do
    ((count++)) || true
    ARN="$(echo "$s" | jq -r '.ARN')"
    NAME="$(echo "$s" | jq -r '.Name')"
    SOURCE_KMS="$(echo "$s" | jq -r '.KmsKeyId // empty')"

    # Optional tag filter
    if [[ "$TAG_FILTER_ENABLED" -eq 1 ]]; then
      TAG_OK="$(aws secretsmanager describe-secret --region "$AWS_REGION" --secret-id "$ARN" \
        --query "Tags[?Key=='${TAG_KEY}' && Value=='${TAG_VALUE}'] | length(@)" --output text 2>/dev/null || echo 0)"
      if [[ "$TAG_OK" == "0" ]]; then
        echo "SKIP (tag filter) $NAME"
        ((skipped_tag++)) || true
        continue
      fi
    fi

    echo "BACKUP $NAME"

    # Read secret value (can fail if Secrets Manager cannot decrypt w/ that secret's KMS key)
    VAL_JSON=""
    if ! VAL_JSON="$(aws secretsmanager get-secret-value --region "$AWS_REGION" --secret-id "$ARN" 2>/tmp/secret_err.$$)"; then
      ERR="$(tr -d '\n' </tmp/secret_err.$$ | sed 's/"/'\''/g')"
      rm -f /tmp/secret_err.$$
      echo "  ERROR (GetSecretValue) $NAME -> $ERR"
      ((failed_read++)) || true
      write_error_record "$NAME" "$ARN" "" "GetSecretValueFailed" "$ERR" "$SOURCE_KMS"
      continue
    fi
    rm -f /tmp/secret_err.$$

    VERSION_ID="$(echo "$VAL_JSON" | jq -r '.VersionId // empty')"
    SECRET_STRING="$(echo "$VAL_JSON" | jq -r '.SecretString // empty')"
    SECRET_BINARY_B64="$(echo "$VAL_JSON" | jq -r '.SecretBinary // empty')"

    # Prepare plaintext payload to encrypt (string or binary)
    if [[ -n "$SECRET_STRING" ]]; then
      PLAINTEXT_PAYLOAD="$(jq -n --arg t "string" --arg v "$SECRET_STRING" '{type:$t,value:$v}')"
    elif [[ -n "$SECRET_BINARY_B64" ]]; then
      PLAINTEXT_PAYLOAD="$(jq -n --arg t "binary_b64" --arg v "$SECRET_BINARY_B64" '{type:$t,value:$v}')"
    else
      echo "  WARN: no SecretString/SecretBinary for $NAME (skipping)"
      ((failed_read++)) || true
      write_error_record "$NAME" "$ARN" "$VERSION_ID" "EmptySecretValue" "No SecretString/SecretBinary present" "$SOURCE_KMS"
      continue
    fi

    # Encrypt export payload with YOUR export key + encryption context
    # (context makes ciphertext harder to misuse outside this backup flow)
    CIPHERTEXT_B64=""
    if ! CIPHERTEXT_B64="$(printf '%s' "$PLAINTEXT_PAYLOAD" | \
      aws kms encrypt --region "$AWS_REGION" \
        --key-id "$KMS_KEY_ARN" \
        --plaintext fileb:///dev/stdin \
        --encryption-context "purpose=secrets-backup,secretArn=${ARN},backupDate=${DATE},backupHost=${HOST}" \
        --query CiphertextBlob --output text 2>/tmp/kms_err.$$)"; then
      ERR="$(tr -d '\n' </tmp/kms_err.$$ | sed 's/"/'\''/g')"
      rm -f /tmp/kms_err.$$
      echo "  ERROR (KMS Encrypt) $NAME -> $ERR"
      ((failed_encrypt++)) || true
      write_error_record "$NAME" "$ARN" "$VERSION_ID" "KMSEncryptFailed" "$ERR" "$SOURCE_KMS"
      continue
    fi
    rm -f /tmp/kms_err.$$

    # Write success record (no plaintext)
    jq -c -n \
      --arg name "$NAME" \
      --arg arn "$ARN" \
      --arg versionId "$VERSION_ID" \
      --arg ts "$TS" \
      --arg host "$HOST" \
      --arg bdate "$DATE" \
      --arg exportKms "$KMS_KEY_ARN" \
      --arg sourceKms "$SOURCE_KMS" \
      --arg encCtx "purpose=secrets-backup,secretArn=${ARN},backupDate=${DATE},backupHost=${HOST}" \
      --arg ciphertext "$CIPHERTEXT_B64" \
      '{
        name:$name,
        arn:$arn,
        versionId:$versionId,
        backedUpAt:$ts,
        backupDate:$bdate,
        backupHost:$host,
        exportKmsKey:$exportKms,
        sourceKmsKey:($sourceKms // ""),
        encryptionContext:$encCtx,
        status:"ok",
        ciphertextB64:$ciphertext
      }' >> "$OUT"

    ((kept++)) || true
  done < <(echo "$RESP" | jq -c '.SecretList[]')

  NEXT_TOKEN="$(echo "$RESP" | jq -r '.NextToken // empty')"
  [[ -z "$NEXT_TOKEN" ]] && break
done

echo "==== SUMMARY ===="
echo "Secrets enumerated: ${count}"
echo "Backed up (ok):     ${kept}"
echo "Skipped (tag):      ${skipped_tag}"
echo "Failed (read):      ${failed_read}"
echo "Failed (encrypt):   ${failed_encrypt}"

# Compress and upload
GZ="${OUT}.gz"
gzip -c "$OUT" > "$GZ"

DEST="${BUCKET}/secrets/daily/${DATE}/secrets_export_${HOST}_${TS}.ndjson.gz"
echo "Uploading: $GZ -> $DEST"
aws s3 cp "$GZ" "$DEST"

echo "==== Secrets backup completed OK ===="

# Cleanup local staging after successful upload
echo "Cleaning up local staging..."
rm -rf "$STAGE"