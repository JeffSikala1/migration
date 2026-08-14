#!/usr/bin/env python3
"""
Transfers artifact binaries for a set of confirmed-compatible LOCAL repos
from prod Artifactory to dev Artifactory, validated end-to-end the same
way the ansible-vault-password-files pilot was: AQL count on prod (the
baseline) -> jf rt download -> jf rt upload -> AQL count on dev, compared
against the FULL expected inventory, not just "some files landed."

Scope: Generic and Maven packageType LOCAL repos only. Docker, Npm, Pypi,
and YUM repos are explicitly excluded here - those package types are not
confirmed supported on the dev OSS Artifactory instance (see the running
OSS-vs-Enterprise delta list for this migration) and need that question
answered before a transfer is attempted.

Uses `jf rt download` / `jf rt upload` (already configured server IDs
prod-artifactory / dev-artifactory - both fixed this session to use
--artifactory-url explicitly, which resolved a URL-doubling bug present
in `jf rt curl` / `jf rt ping` under CLI 2.117.0 for the plain --url form).

AQL counts are queried directly via requests (not `jf rt curl`) since that
subcommand hits the same doubling bug even with the --artifactory-url fix,
and there's no need to fight it when a direct request works cleanly.

Completion signal per repo (mirrors promote.py's artifact-completeness
discipline - full expected inventory, not partial presence):
  - prod count == 0        -> nothing to transfer, log and skip
  - dev count == prod count (both > 0) -> already fully transferred,
    idempotent skip (rerun-safe)
  - dev count == 0, prod count > 0     -> full transfer needed
  - dev count > 0 but < prod count     -> PARTIAL - do NOT re-run blindly,
    flagged for manual investigation
  - dev count > prod count             -> unexpected - flagged, not
    treated as success

Requires: `pip install requests` (or `pip3 install requests` on AL2023 -
no --break-system-packages needed on this box's pip version), and the
artifactory_prod_admin_token / artifactory_dev_admin_token env vars
already used elsewhere in this migration.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

import requests

BASE = Path.home() / "artifactory-migration" / "pilot-transfer"
STAGE_DIR = BASE / "staged"
LOG_FILE = BASE / "transfer_log.json"

PROD_URL = "https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov/artifactory"
DEV_URL = "https://artifactory-test.dev.cnxs.vpcaas.fcs.gsa.gov/artifactory"

PROD_TOKEN = os.environ.get("artifactory_prod_admin_token")
DEV_TOKEN = os.environ.get("artifactory_dev_admin_token")

if not PROD_TOKEN or not DEV_TOKEN:
    sys.exit("ERROR: artifactory_prod_admin_token / artifactory_dev_admin_token not set in environment")

# Generic + Maven LOCAL repos only, per prod_repos.json - excludes the
# already-completed pilot (ansible-vault-password-files) and all
# Docker/Npm/Pypi/YUM repos pending the OSS package-type support question.
REPOS = [
    "conexus-maven-local",
    "conexus-plugins-backup",
    "conexus-rc-local",
    "conexus-release-local",
    "conexus-snapshot-local",
    "file-local",
    "generic-local",
    "keys",
    "libs-release-local",
    "libs-snapshot-local",
    "ll-2025-jboss-8",
    "ll-CNXS-68737-newer-versions",
    "ll-dev-cutover-test-01",
    "ll-dev-cutover-test-02",
    "ll-jboss8",
    "ll-modelchanges",
    "ll-postgres",
    "ll-tops-task-order-ahcs",
    "ll-unified-automation",
    "ll-upgrades",
    "mcafee",
]


def aql_count(base_url, token, repo):
    """Full-inventory file count for a repo via AQL - the completion signal."""
    resp = requests.post(
        f"{base_url}/api/search/aql",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "text/plain"},
        data=f'items.find({{"repo":"{repo}","type":"file"}})',
        timeout=60,
    )
    resp.raise_for_status()  # equivalent of curl --fail - hard stop on non-2xx, never guess
    return resp.json()["range"]["total"]


def run_jf(args, context):
    result = subprocess.run(["jf"] + args, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  [ERROR] jf {' '.join(args)} failed ({context})")
        print(f"    stdout: {result.stdout.strip()}")
        print(f"    stderr: {result.stderr.strip()}")
        return False, result.stdout
    return True, result.stdout


def transfer_repo(repo):
    print(f"\n=== {repo} ===")
    record = {"repo": repo, "status": None, "prod_count": None, "dev_count_before": None, "dev_count_after": None}

    try:
        prod_count = aql_count(PROD_URL, PROD_TOKEN, repo)
    except requests.RequestException as e:
        print(f"  [ERROR] AQL query against prod failed: {e}")
        record["status"] = "error-prod-aql"
        return record
    record["prod_count"] = prod_count

    if prod_count == 0:
        print("  prod has 0 artifacts - nothing to transfer, skipping")
        record["status"] = "skip-empty"
        return record

    try:
        dev_count_before = aql_count(DEV_URL, DEV_TOKEN, repo)
    except requests.RequestException as e:
        print(f"  [ERROR] AQL query against dev failed: {e}")
        record["status"] = "error-dev-aql"
        return record
    record["dev_count_before"] = dev_count_before

    if dev_count_before == prod_count:
        print(f"  dev already has full inventory ({dev_count_before}/{prod_count}) - idempotent skip")
        record["status"] = "skip-already-complete"
        record["dev_count_after"] = dev_count_before
        return record

    if dev_count_before > prod_count:
        print(f"  [WARN] dev has MORE artifacts than prod ({dev_count_before} > {prod_count}) - unexpected, flagging for manual review, not touching")
        record["status"] = "flag-dev-exceeds-prod"
        record["dev_count_after"] = dev_count_before
        return record

    if 0 < dev_count_before < prod_count:
        print(f"  [WARN] dev has a PARTIAL inventory ({dev_count_before}/{prod_count}) - not re-running automatically, flagging for manual investigation")
        record["status"] = "flag-partial-preexisting"
        record["dev_count_after"] = dev_count_before
        return record

    # dev_count_before == 0 and prod_count > 0: full transfer needed
    repo_stage = STAGE_DIR / repo
    repo_stage.mkdir(parents=True, exist_ok=True)

    print(f"  downloading {prod_count} artifacts from prod...")
    ok, out = run_jf(
        ["rt", "download", "--server-id=prod-artifactory", f"{repo}/**", f"{repo_stage}/"],
        "download",
    )
    if not ok:
        record["status"] = "error-download"
        return record
    try:
        down_result = json.loads(out)
        if down_result.get("totals", {}).get("failure", 1) != 0 or down_result.get("totals", {}).get("success", 0) != prod_count:
            print(f"  [WARN] download totals don't match expected count: {down_result.get('totals')}")
            record["status"] = "flag-download-mismatch"
            return record
    except (json.JSONDecodeError, KeyError):
        print(f"  [WARN] could not parse download output, review manually: {out}")
        record["status"] = "flag-download-unparseable"
        return record

    print(f"  uploading to dev...")
    ok, out = run_jf(
        ["rt", "upload", "--server-id=dev-artifactory", f"{repo_stage}/(*)", f"{repo}/{{1}}"],
        "upload",
    )
    if not ok:
        record["status"] = "error-upload"
        return record

    try:
        dev_count_after = aql_count(DEV_URL, DEV_TOKEN, repo)
    except requests.RequestException as e:
        print(f"  [ERROR] post-upload AQL query against dev failed: {e}")
        record["status"] = "error-dev-aql-post"
        return record
    record["dev_count_after"] = dev_count_after

    if dev_count_after == prod_count:
        print(f"  confirmed: dev now has full inventory ({dev_count_after}/{prod_count})")
        record["status"] = "success"
    else:
        print(f"  [WARN] post-upload count mismatch: dev={dev_count_after}, prod={prod_count} - flagging for investigation")
        record["status"] = "flag-post-upload-mismatch"

    return record


def main():
    STAGE_DIR.mkdir(parents=True, exist_ok=True)
    results = [transfer_repo(repo) for repo in REPOS]

    with open(LOG_FILE, "w") as f:
        json.dump(results, f, indent=2)

    print(f"\n=== SUMMARY ({LOG_FILE}) ===")
    by_status = {}
    for r in results:
        by_status.setdefault(r["status"], []).append(r["repo"])
    for status, repos in sorted(by_status.items()):
        print(f"  {status}: {len(repos)} -> {', '.join(repos)}")

    flagged = [r for r in results if r["status"] and r["status"].startswith(("flag-", "error-"))]
    if flagged:
        print(f"\n{len(flagged)} repo(s) need manual review - see {LOG_FILE}")


if __name__ == "__main__":
    main()