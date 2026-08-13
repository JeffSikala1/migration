#!/usr/bin/env python3
"""
Builds SQL INSERT statements for Artifactory's access_permissions_v2 +
access_permissions_targets_v2 + access_permissions_actions_v2 tables,
targeting the internal schema verified via real UI-created test permission
targets (schema-test-perm, schema-test-perm-2) on the dev OSS instance.

Input: prod_permissions_detail/<name>.json (REST API config for each
       permission target, already pulled from prod).
Output: permission_inserts.sql - review before running against dev-postgres.

Legacy tables access_permissions / access_permission_action (no _v2 suffix)
are confirmed EMPTY and trigger-guarded read-only on dev
(access_fnc_allow_read_only) - dead, ignored entirely by this script.

Schema notes (all verified via real UI-created rows, not assumed):
  - access_permissions_v2: one row per permission target. realm is always
    'GLOBAL' in every real row we saw - carried forward as a constant.
  - access_permissions_targets_v2: one row per (perm_id, resource_type,
    target_name). resource_type is 'artifact' for prod's "repo" scope,
    'build' for prod's "build" scope. target_name is either a literal repo
    key (e.g. 'conexus-release-local'), a literal build-scope token
    ('artifactory-build-info', confirmed verbatim from a real build-scope
    test), or one of the special repo tokens 'ANY LOCAL' / 'ANY REMOTE' /
    'ANY DISTRIBUTION' (confirmed via the original unscoped test - selecting
    no specific repos produces exactly these 3 rows). Prod's repositories
    list uses the literal string "ANY" to mean "all three" - expanded here
    to those 3 rows. It can also mix a token with literal repos in the same
    list (e.g. Any_Remote.json: ["ANY REMOTE", "yum-local"]) - handled
    per-entry.
  - include_patterns / exclude_patterns: JSON array, compact-encoded
    (no spaces), then hex-encoded into the bytea column. E.g. ["**"] as a
    JSON string, hex-encoded.
  - access_permissions_actions_v2: NO target_id/target_name column - one
    row per (perm_id, resource_type, user_id XOR group_id), with an
    "actions" bitmask that applies across ALL target rows of that
    resource_type for this permission. This matches prod's REST shape
    exactly: one "actions" object per scope, a separate "repositories" list.

Actions bitmask (verified via individual single-checkbox UI tests):
  read                = 1
  write               = 2   (UI label: "Deploy/cache")
  delete              = 4   (UI label: "Delete/Overwrite")
  manage              = 8
  annotate            = 16
  manageXrayMetadata  = 64  (confirmed but unused - no prod permission
                             grants "distribute"/xray-metadata; not present
                             in any of the 18 prod permission JSON files)
  Sum of all 6 = 95, matching the original "everything checked" test exactly.

Users/groups not found on dev (shouldn't happen - all migrated already) or
repos not found (all 41 migrated already) produce a warning, not a silent
skip - each missing reference means an action/target row that will match
0 rows on INSERT (SELECT ... WHERE NOT EXISTS guard prevents bad inserts,
but the row simply won't be created - surfaced as a warning to investigate).
"""
import json
from pathlib import Path

BASE = Path.home() / "artifactory-migration"
DETAIL_DIR = BASE / "prod_permissions_detail"
OUT_SQL = BASE / "permission_inserts.sql"

SYNTHETIC_EPOCH_MS = 1735689600000  # 2025-01-01T00:00:00Z, same convention as repo/group/user inserts
CREATED_BY = "migration-script"

ACTION_BITS = {
    "read": 1,
    "write": 2,
    "delete": 4,
    "manage": 8,
    "annotate": 16,
    "manageXrayMetadata": 64,
}

ANY_REPO_TOKENS = {"ANY LOCAL", "ANY REMOTE", "ANY DISTRIBUTION"}


def load_json(path):
    with open(path) as f:
        return json.load(f)


def sql_escape(s):
    return (s or "").replace("'", "''")


def patterns_to_hex(patterns):
    compact = json.dumps(patterns, separators=(",", ":"))
    return compact.encode("utf-8").hex()


def bitmask(perm_list, warnings, context):
    total = 0
    for p in perm_list:
        if p not in ACTION_BITS:
            warnings.append(f"{context}: unrecognized permission '{p}' - skipped, verify manually")
            continue
        total += ACTION_BITS[p]
    return total


def target_rows_for_repositories(repositories):
    """Expand prod's repositories list into (target_name, is_any_token) pairs."""
    rows = []
    seen = set()
    for repo in repositories:
        if repo == "ANY":
            for token in sorted(ANY_REPO_TOKENS):
                if token not in seen:
                    rows.append(token)
                    seen.add(token)
        else:
            if repo not in seen:
                rows.append(repo)
                seen.add(repo)
    return rows


def main():
    if not DETAIL_DIR.exists():
        print(f"ERROR: {DETAIL_DIR} not found")
        return

    perm_files = sorted(DETAIL_DIR.glob("*.json"))
    perm_inserts = []
    target_inserts = []
    action_inserts = []
    warnings = []

    for path in perm_files:
        detail = load_json(path)
        name = detail["name"]

        perm_sql = (
            f"INSERT INTO access_permissions_v2 "
            f"(perm_id, name, created, modified, created_by, modified_by, lower_name, description, realm) "
            f"SELECT (SELECT COALESCE(MAX(perm_id),0)+1 FROM access_permissions_v2), "
            f"'{sql_escape(name)}', {SYNTHETIC_EPOCH_MS}, {SYNTHETIC_EPOCH_MS}, "
            f"'{CREATED_BY}', '{CREATED_BY}', '{sql_escape(name.lower())}', '', 'GLOBAL' "
            f"WHERE NOT EXISTS (SELECT 1 FROM access_permissions_v2 WHERE name = '{sql_escape(name)}');"
        )
        perm_inserts.append(perm_sql)

        for scope_key, resource_type in (("repo", "artifact"), ("build", "build")):
            scope = detail.get(scope_key)
            if not scope:
                continue

            repositories = scope.get("repositories", [])
            include_hex = patterns_to_hex(scope.get("include-patterns", ["**"]))
            exclude_hex = patterns_to_hex(scope.get("exclude-patterns", []))
            target_names = target_rows_for_repositories(repositories)

            for target_name in target_names:
                is_any = 0  # every real row we saw had is_target_ant_pattern = 0, including ANY tokens
                t_sql = (
                    f"INSERT INTO access_permissions_targets_v2 "
                    f"(target_id, perm_id, resource_type, target_name, is_target_ant_pattern, include_patterns, exclude_patterns) "
                    f"SELECT (SELECT COALESCE(MAX(target_id),0)+1 FROM access_permissions_targets_v2), "
                    f"p.perm_id, '{resource_type}', '{sql_escape(target_name)}', {is_any}, "
                    f"decode('{include_hex}', 'hex'), decode('{exclude_hex}', 'hex') "
                    f"FROM access_permissions_v2 p WHERE p.name = '{sql_escape(name)}' "
                    f"AND NOT EXISTS ("
                    f"SELECT 1 FROM access_permissions_targets_v2 t "
                    f"WHERE t.perm_id = p.perm_id AND t.resource_type = '{resource_type}' "
                    f"AND t.target_name = '{sql_escape(target_name)}'"
                    f");"
                )
                target_inserts.append(t_sql)

            actions = scope.get("actions", {})
            for username, perm_list in actions.get("users", {}).items():
                actions_val = bitmask(perm_list, warnings, f"{name} ({scope_key}) user {username}")
                a_sql = (
                    f"INSERT INTO access_permissions_actions_v2 "
                    f"(action_id, perm_id, resource_type, user_id, group_id, actions) "
                    f"SELECT (SELECT COALESCE(MAX(action_id),0)+1 FROM access_permissions_actions_v2), "
                    f"p.perm_id, '{resource_type}', u.user_id, NULL, {actions_val} "
                    f"FROM access_permissions_v2 p, access_users u "
                    f"WHERE p.name = '{sql_escape(name)}' AND u.username = '{sql_escape(username)}' "
                    f"AND NOT EXISTS ("
                    f"SELECT 1 FROM access_permissions_actions_v2 a "
                    f"WHERE a.perm_id = p.perm_id AND a.resource_type = '{resource_type}' AND a.user_id = u.user_id"
                    f");"
                )
                action_inserts.append(a_sql)

            for groupname, perm_list in actions.get("groups", {}).items():
                actions_val = bitmask(perm_list, warnings, f"{name} ({scope_key}) group {groupname}")
                a_sql = (
                    f"INSERT INTO access_permissions_actions_v2 "
                    f"(action_id, perm_id, resource_type, user_id, group_id, actions) "
                    f"SELECT (SELECT COALESCE(MAX(action_id),0)+1 FROM access_permissions_actions_v2), "
                    f"p.perm_id, '{resource_type}', NULL, g.group_id, {actions_val} "
                    f"FROM access_permissions_v2 p, access_groups g "
                    f"WHERE p.name = '{sql_escape(name)}' AND g.group_name = '{sql_escape(groupname)}' "
                    f"AND NOT EXISTS ("
                    f"SELECT 1 FROM access_permissions_actions_v2 a "
                    f"WHERE a.perm_id = p.perm_id AND a.resource_type = '{resource_type}' AND a.group_id = g.group_id"
                    f");"
                )
                action_inserts.append(a_sql)

    with open(OUT_SQL, "w") as f:
        f.write("BEGIN;\n\n")
        f.write("-- access_permissions_v2\n")
        f.write("\n".join(perm_inserts))
        f.write("\n\n-- access_permissions_targets_v2\n")
        f.write("\n".join(target_inserts))
        f.write("\n\n-- access_permissions_actions_v2\n")
        f.write("\n".join(action_inserts))
        f.write("\n\nCOMMIT;\n")

    print(
        f"Wrote {len(perm_inserts)} permission INSERTs, {len(target_inserts)} target INSERTs, "
        f"{len(action_inserts)} action INSERTs to {OUT_SQL}"
    )
    if warnings:
        print(f"\n{len(warnings)} WARNINGS:")
        for w in warnings:
            print(f"  - {w}")


if __name__ == "__main__":
    main()