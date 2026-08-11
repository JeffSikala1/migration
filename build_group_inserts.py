#!/usr/bin/env python3
"""
Builds SQL INSERT statements for Artifactory's access_groups +
access_groups_custom_data tables, targeting the internal schema verified
via a real UI-created test group (schema-test-admin-group, group_id 1001)
on the dev OSS instance.

Input: prod_groups_detail/<name>.json (REST API config for each group,
       already pulled from prod).
Output: group_inserts.sql - review before running against dev-postgres.

Realm handling (per team decision 2026-08-11): Crowd was part of the legacy
SSO structure and is being retired, not carried into this environment. SAML
is being sustained. So:
  - realm == "crowd"  -> forced to "internal" on insert
  - realm == "saml"   -> carried forward verbatim
  - realm == "internal" -> carried forward verbatim
  - anything else encountered -> warned, forced to "internal" (safe default)

Admin/privilege flags: verified via real UI test that these are NOT stored
as access_groups columns or in access_groups_custom_data by REST-facing
names - the real internal prop_key names are:
  adminPrivileges -> artifactory_admin
  policyManager   -> policy_manager
  watchManager    -> watch_manager
  reportsManager  -> reports_manager
policyViewer has no confirmed internal key (none of the 14 prod groups use
it), so if encountered it is flagged as a warning and skipped rather than
guessed.

IDs are assigned dynamically at INSERT time via
(SELECT COALESCE(MAX(group_id),0)+1 FROM access_groups) inside each
statement, evaluated in transaction order - NOT hardcoded - so this is
rerun-safe regardless of what group_ids already exist (e.g. after the
schema-test-admin-group cleanup). Each INSERT is additionally guarded with
WHERE NOT EXISTS so reruns skip groups that already exist.
"""
import json
from pathlib import Path

BASE = Path.home() / "artifactory-migration"
DETAIL_DIR = BASE / "prod_groups_detail"
OUT_SQL = BASE / "group_inserts.sql"

SYNTHETIC_EPOCH_MS = 1735689600000  # 2025-01-01T00:00:00Z, same convention as repo_inserts.sql

# Verified internal prop_key mapping (see docstring)
PRIVILEGE_KEY_MAP = {
    "adminPrivileges": "artifactory_admin",
    "policyManager": "policy_manager",
    "watchManager": "watch_manager",
    "reportsManager": "reports_manager",
}


def load_json(path):
    with open(path) as f:
        return json.load(f)


def sql_escape(s):
    return (s or "").replace("'", "''")


def main():
    if not DETAIL_DIR.exists():
        print(f"ERROR: {DETAIL_DIR} not found")
        return

    group_files = sorted(DETAIL_DIR.glob("*.json"))
    group_inserts = []
    custom_data_inserts = []
    warnings = []

    for path in group_files:
        detail = load_json(path)
        name = detail["name"]
        description = sql_escape(detail.get("description", ""))
        auto_join = 1 if detail.get("autoJoin") else 0
        realm = detail.get("realm", "internal")

        if realm == "crowd":
            realm = "internal"
        elif realm not in ("internal", "saml"):
            warnings.append(
                f"{name}: unrecognized realm '{realm}' - forced to 'internal', verify manually"
            )
            realm = "internal"

        group_sql = (
            f"INSERT INTO access_groups "
            f"(group_id, group_name, description, auto_join, realm, realm_attributes, "
            f"created, modified, lowercase_name, external_id) "
            f"SELECT (SELECT COALESCE(MAX(group_id),0)+1 FROM access_groups), "
            f"'{sql_escape(name)}', '{description}', {auto_join}, '{realm}', NULL, "
            f"{SYNTHETIC_EPOCH_MS}, {SYNTHETIC_EPOCH_MS}, '{sql_escape(name.lower())}', NULL "
            f"WHERE NOT EXISTS (SELECT 1 FROM access_groups WHERE group_name = '{sql_escape(name)}');"
        )
        group_inserts.append(group_sql)

        for rest_key, prop_key in PRIVILEGE_KEY_MAP.items():
            if detail.get(rest_key):
                cd_sql = (
                    f"INSERT INTO access_groups_custom_data (group_id, prop_key, prop_value) "
                    f"SELECT group_id, '{prop_key}', 'true' FROM access_groups "
                    f"WHERE group_name = '{sql_escape(name)}' "
                    f"AND NOT EXISTS ("
                    f"SELECT 1 FROM access_groups_custom_data "
                    f"WHERE group_id = (SELECT group_id FROM access_groups WHERE group_name = '{sql_escape(name)}') "
                    f"AND prop_key = '{prop_key}'"
                    f");"
                )
                custom_data_inserts.append(cd_sql)

        if detail.get("policyViewer"):
            warnings.append(
                f"{name}: policyViewer=true but no confirmed internal prop_key - SKIPPED, needs manual mapping"
            )

    with open(OUT_SQL, "w") as f:
        f.write("BEGIN;\n\n")
        f.write("-- access_groups\n")
        f.write("\n".join(group_inserts))
        f.write("\n\n-- access_groups_custom_data (admin/policy/watch/reports manager flags)\n")
        f.write("\n".join(custom_data_inserts))
        f.write("\n\nCOMMIT;\n")

    print(f"Wrote {len(group_inserts)} group INSERTs and {len(custom_data_inserts)} custom_data INSERTs to {OUT_SQL}")
    if warnings:
        print(f"\n{len(warnings)} WARNINGS:")
        for w in warnings:
            print(f"  - {w}")


if __name__ == "__main__":
    main()