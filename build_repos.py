#!/usr/bin/env python3
"""
Builds SQL INSERT statements for Artifactory's repository_config table,
targeting the internal JSON schema (verified via real UI-created test repos
on the dev OSS instance) rather than the REST API config format.

Input: prod_repos.json (summary list) + prod_repos_detail/<key>.json (REST API
       config for each repo, already pulled from prod).
Output: repo_inserts.sql - review before running against dev-postgres.

Scope: only Maven (local/remote/virtual) and Generic (local) repos, per the
       team's validated decision to drop Docker/Npm/Pypi/YUM from the dev CI
       environment (see 90-day request-log analysis).

NOTE: propertySetRefs is always forced to [] - property sets are an
      Artifactory Pro feature and cannot exist in OSS, confirmed earlier.
      This is a deliberate, documented deviation, not an oversight.
"""
import json
import sys
from pathlib import Path

BASE = Path.home() / "artifactory-migration"
REPOS_JSON = BASE / "prod_repos.json"
DETAIL_DIR = BASE / "prod_repos_detail"
OUT_SQL = BASE / "repo_inserts.sql"

# Fixed epoch millis used for created/modified on all inserted rows.
# Using a fixed, obviously-synthetic timestamp (not real "now") so these
# rows are identifiable later as migration-inserted vs UI-created.
SYNTHETIC_EPOCH_MS = 1735689600000  # 2025-01-01T00:00:00Z

def load_json(path):
    with open(path) as f:
        return json.load(f)

def b(val, default=False):
    """Bool passthrough with default."""
    return val if isinstance(val, bool) else default

def build_local(detail):
    key = detail["key"]
    return {
        "type": "local",
        "key": key,
        "packageType": "maven" if detail.get("packageType", "").lower() == "maven" else "generic",
        "baseConfig": {
            "modelVersion": 2,
            "description": detail.get("description", ""),
            "notes": detail.get("notes", ""),
            "repoLayoutRef": detail.get("repoLayoutRef", "maven-2-default"),
            "includesPattern": detail.get("includesPattern", "**/*"),
            "excludesPattern": detail.get("excludesPattern", ""),
        },
        "repoTypeConfig": {
            "archiveBrowsingEnabled": b(detail.get("archiveBrowsingEnabled")),
            "blackedOut": b(detail.get("blackedOut")),
            "propertySetRefs": [],  # Pro-only feature - deliberately dropped
            "checksumPolicyType": detail.get("checksumPolicyType", "client-checksums"),
            "priorityResolution": b(detail.get("priorityResolution")),
            "maxUniqueSnapshots": detail.get("maxUniqueSnapshots", 0),
            "handleReleases": b(detail.get("handleReleases"), True),
            "handleSnapshots": b(detail.get("handleSnapshots"), True),
            "snapshotVersionBehavior": detail.get("snapshotVersionBehavior", "unique"),
        },
        "packageTypeConfig": (
            {"suppressPomConsistencyChecks": str(b(detail.get("suppressPomConsistencyChecks"))).lower()}
            if detail.get("packageType", "").lower() == "maven" else {}
        ),
        "securityConfig": {
            "hideUnauthorizedResources": b(detail.get("hideUnauthorizedResources")),
            "signedUrlTtl": detail.get("signedUrlTtl", 90),
        },
        "repoType": "LOCAL",
    }

def build_remote(detail):
    key = detail["key"]
    url = detail.get("url", "")
    return {
        "type": "remote",
        "key": key,
        "packageType": "maven",
        "baseConfig": {
            "modelVersion": 2,
            "description": detail.get("description", ""),
            "notes": detail.get("notes", ""),
            "repoLayoutRef": detail.get("repoLayoutRef", "maven-2-default"),
            "includesPattern": detail.get("includesPattern", "**/*"),
            "excludesPattern": detail.get("excludesPattern", ""),
        },
        "repoTypeConfig": {
            "archiveBrowsingEnabled": b(detail.get("archiveBrowsingEnabled")),
            "blackedOut": b(detail.get("blackedOut")),
            "propertySetRefs": [],
            "allowAnyHostAuth": b(detail.get("allowAnyHostAuth")),
            "blockMismatchingMimeTypes": b(detail.get("blockMismatchingMimeTypes"), True),
            "mismatchingMimeTypesOverrideList": detail.get("mismatchingMimeTypesOverrideList", ""),
            "bypassHeadRequests": b(detail.get("bypassHeadRequests")),
            "disableUrlNormalization": b(detail.get("disableUrlNormalization")),
            "enableCookieManagement": b(detail.get("enableCookieManagement")),
            "enableTokenAuthentication": b(detail.get("enableTokenAuthentication")),
            "propagateQueryParams": b(detail.get("propagateQueryParams")),
            "shareConfiguration": b(detail.get("shareConfiguration")),
            "listRemoteFolderItems": b(detail.get("listRemoteFolderItems"), True),
            "synchronizeProperties": b(detail.get("synchronizeProperties")),
            "contentSynchronisation": detail.get("contentSynchronisation", {
                "enabled": False,
                "statistics": {"enabled": False},
                "properties": {"enabled": False},
                "source": {"originAbsenceDetection": False},
            }),
            "disableProxy": b(detail.get("disableProxy")),
            "storeArtifactsLocally": b(detail.get("storeArtifactsLocally"), True),
            "url": url,
            "retrievalCachePeriodSecs": detail.get("retrievalCachePeriodSecs", 7200),
            "metadataRetrievalTimeoutSecs": detail.get("metadataRetrievalTimeoutSecs", 60),
            "assumedOfflinePeriodSecs": detail.get("assumedOfflinePeriodSecs", 300),
            "missedRetrievalCachePeriodSecs": detail.get("missedRetrievalCachePeriodSecs", 1800),
            "checksumPolicyType": detail.get("checksumPolicyType", "generate-if-absent"),
            "unusedArtifactsCleanupPeriodHours": detail.get("unusedArtifactsCleanupPeriodHours", 0),
            "socketTimeoutMillis": detail.get("socketTimeoutMillis", 15000),
            "priorityResolution": b(detail.get("priorityResolution")),
            "handleReleases": b(detail.get("handleReleases"), True),
            "handleSnapshots": b(detail.get("handleSnapshots"), True),
            "sendContext": b(detail.get("sendContext")),
            "passThrough": b(detail.get("passThrough")),
            "curated": b(detail.get("curated")),
            "maxUniqueSnapshots": detail.get("maxUniqueSnapshots", 0),
            "retrieveSha256FromServer": b(detail.get("retrieveSha256FromServer")),
        },
        "packageTypeConfig": {
            "fetchSourcesEagerly": str(b(detail.get("fetchSourcesEagerly"))).lower(),
            "fetchJarsEagerly": str(b(detail.get("fetchJarsEagerly"))).lower(),
            "rejectInvalidJars": str(b(detail.get("rejectInvalidJars"))).lower(),
            "suppressPomConsistencyChecks": str(b(detail.get("suppressPomConsistencyChecks"))).lower(),
            "p2OriginalUrl": url,
        },
        "securityConfig": {
            "hideUnauthorizedResources": b(detail.get("hideUnauthorizedResources")),
            "signedUrlTtl": detail.get("signedUrlTtl", 90),
        },
        "repoType": "REMOTE",
        "hardFail": b(detail.get("hardFail")),
        "offline": b(detail.get("offline")),
        "proxyDisabled": b(detail.get("proxyDisabled")),
    }

def build_virtual(detail, members):
    key = detail["key"]
    return {
        "type": "virtual",
        "key": key,
        "packageType": "maven",
        "baseConfig": {
            "modelVersion": 2,
            "description": detail.get("description", ""),
            "notes": detail.get("notes", ""),
            "repoLayoutRef": detail.get("repoLayoutRef", "maven-2-default"),
            "includesPattern": detail.get("includesPattern", "**/*"),
            "excludesPattern": detail.get("excludesPattern", ""),
        },
        "repoTypeConfig": {
            "artifactoryRequestsCanRetrieveRemoteArtifacts": b(
                detail.get("artifactoryRequestsCanRetrieveRemoteArtifacts")
            ),
            "virtualCacheConfig": {
                "virtualRetrievalCachePeriodSecs": detail.get("virtualRetrievalCachePeriodSecs", 600)
            },
            "repositoryRefs": members,
        },
        "packageTypeConfig": {
            "forceMavenAuthentication": str(b(detail.get("forceMavenAuthentication"))).lower(),
            "pomRepositoryReferencesCleanupPolicy": detail.get(
                "pomRepositoryReferencesCleanupPolicy", "discard_active_reference"
            ),
        },
        "securityConfig": {
            "hideUnauthorizedResources": b(detail.get("hideUnauthorizedResources")),
            "signedUrlTtl": detail.get("signedUrlTtl", 90),
        },
        "repoType": "VIRTUAL",
    }

def main():
    repos = load_json(REPOS_JSON)
    target = [
        r for r in repos
        if r["packageType"] == "Maven" or (r["packageType"] == "Generic" and r["type"] == "LOCAL")
    ]

    inserts = []
    warnings = []

    for r in target:
        key = r["key"]
        rtype = r["type"]
        detail_path = DETAIL_DIR / f"{key}.json"
        if not detail_path.exists():
            warnings.append(f"MISSING DETAIL FILE: {key} - skipped")
            continue
        detail = load_json(detail_path)

        if rtype == "LOCAL":
            config = build_local(detail)
        elif rtype == "REMOTE":
            config = build_remote(detail)
        elif rtype == "VIRTUAL":
            members = detail.get("repositories", [])
            if not members:
                warnings.append(f"VIRTUAL repo {key} has NO members listed in prod detail - check manually")
            config = build_virtual(detail, members)
        else:
            warnings.append(f"UNKNOWN type {rtype} for {key} - skipped")
            continue

        config_json = json.dumps(config, separators=(",", ":"))
        hex_blob = config_json.encode("utf-8").hex()
        pkg_type = config["packageType"]

        sql = (
            f"INSERT INTO repository_config "
            f"(repository_key, type, package_type, revision, created, modified, config_blob) "
            f"VALUES ('{key}', '{rtype.lower()}', '{pkg_type}', 0, "
            f"{SYNTHETIC_EPOCH_MS}, {SYNTHETIC_EPOCH_MS}, decode('{hex_blob}', 'hex'))"
            f"ON CONFLICT (repository_key) DO NOTHING;"
        )
        inserts.append(sql)

    with open(OUT_SQL, "w") as f:
        f.write("BEGIN;\n\n")
        f.write("\n".join(inserts))
        f.write("\n\nCOMMIT;\n")

    print(f"Wrote {len(inserts)} INSERT statements to {OUT_SQL}")
    if warnings:
        print(f"\n{len(warnings)} WARNINGS:")
        for w in warnings:
            print(f"  - {w}")

if __name__ == "__main__":
    main()