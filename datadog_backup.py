#!/usr/bin/env python3
"""

Exports Datadog configuration objects (dashboards, monitors, SLOs,
synthetic tests, notebooks) and uploads them as timestamped JSON to
S3 for backup/recovery purposes.

Usage:
    python3 datadog_backup.py

Expects secrets at:
    /app/datadog_backup_scripts/secrets/backup-apikey.txt
    /app/datadog_backup_scripts/secrets/backup-appkey.txt
"""

import json
import sys
from datetime import datetime, timezone

import boto3
import requests

DD_SITE = "ddog-gov.com"
DD_API_BASE = f"https://api.{DD_SITE}"

S3_BUCKET = "cnxs-datadog-backups"
SECRETS_DIR = "/app/datadog_backup_scripts/secrets"

# (resource name, API path, response key holding the list of items)
RESOURCES = [
    ("dashboards", "/api/v1/dashboard", "dashboards"),
    ("monitors", "/api/v1/monitor", None),  # returns a bare list
    ("slos", "/api/v1/slo", "data"),
    ("synthetics", "/api/v1/synthetics/tests", "tests"),
    ("notebooks", "/api/v1/notebooks", "data"),
]


def load_keys():
    try:
        with open(f"{SECRETS_DIR}/backup-apikey.txt") as f:
            api_key = f.read().strip()
        with open(f"{SECRETS_DIR}/backup-appkey.txt") as f:
            app_key = f.read().strip()
    except FileNotFoundError as e:
        print(f"ERROR: missing key file - {e}", file=sys.stderr)
        sys.exit(1)
    return api_key, app_key


def dd_headers(api_key, app_key):
    return {
        "DD-API-KEY": api_key,
        "DD-APPLICATION-KEY": app_key,
        "Content-Type": "application/json",
    }


def fetch_list(path, headers):
    resp = requests.get(f"{DD_API_BASE}{path}", headers=headers, timeout=30)
    resp.raise_for_status()
    return resp.json()


def run_backup(s3_client, timestamp):
    print("starting Datadog config backup")
    api_key, app_key = load_keys()
    headers = dd_headers(api_key, app_key)

    for resource_name, path, list_key in RESOURCES:
        try:
            data = fetch_list(path, headers)
        except requests.exceptions.RequestException as e:
            print(f"WARN: failed to fetch {resource_name}: {e}", file=sys.stderr)
            continue

        items = data if list_key is None else data.get(list_key, [])
        s3_key = f"{resource_name}/{resource_name}-{timestamp}.json"

        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=json.dumps(items, indent=2).encode("utf-8"),
            ContentType="application/json",
        )
        print(f"{resource_name}: {len(items)} items -> s3://{S3_BUCKET}/{s3_key}")

    print("backup complete")


def main():
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    s3_client = boto3.client("s3")
    run_backup(s3_client, timestamp)


if __name__ == "__main__":
    main()