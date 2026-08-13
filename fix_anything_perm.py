#!/usr/bin/env python3
"""
One-off: insert prod's real 'Anything' permission under a non-colliding name,
since dev already has a built-in default permission also named 'Anything'
(perm_id=1, unrelated to prod's). access_perm_name_unq_idx is a UNIQUE index
on name, so this must land as a separate row with a separate name.

Reuses the exact same schema/encoding logic as build_permission_inserts.py,
scoped to just prod_permissions_detail/Anything.json.
"""
import json
from pathlib import Path

BASE = Path.home() / "artifactory-migration"
DETAIL_FILE = BASE / "prod_permissions_detail" / "Anything.json"
OUT_SQL = BASE / "fix_anything_perm.sql"

SYNTHETIC_EPOCH_MS = 1735689600000
CREATED_BY = "migration-script"
NEW_NAME = "Anything (migrated)"  # distinct from dev's pre-existing 'Anything'

ACTION_BITS = {
    "read": 1, "write": 2, "delete": 4,
    "manage": 8, "annotate": 16, "manageXrayMetadata": 64,
}
ANY_REPO_TOKENS = {"ANY LOCAL", "ANY REMOTE", "ANY DISTRIBUTION"}


def sql_escape(s):
    return (s or "").replace("'", "''")


def patterns_to_hex(patterns):
    return json.dumps(patterns, separators=(",", ":")).encode("utf-8").hex()


def bitmask(perm_list, warnings, context):
    total = 0
    for p in perm_list:
        if p not in ACTION_BITS:
            warnings.append(f"{context}: unrecognized permission '{p}'")
            continue
        total += ACTION_BITS[p]
    return total


def target_rows_for_repositories(repositories):
    rows, seen = [], set()
    for repo in repositories:
        if repo == "ANY":
            for token in sorted(ANY_REPO_TOKENS):
                if token not in seen:
                    rows.append(token)
                    seen.add(token)
        elif repo not in seen:
            rows.append(repo)
            seen.add(repo)
    return rows


def main():
    with open(DETAIL_FILE) as f:
        detail = json.load(f)

    perm_inserts, target_inserts, action_inserts, warnings = [], [], [], []

    perm_inserts.append(
        f"INSERT INTO access_permissions_v2 "
        f"(perm_id, name, created, modified, created_by, modified_by, lower_name, description, realm) "
        f"SELECT (SELECT COALESCE(MAX(perm_id),0)+1 FROM access_permissions_v2), "
        f"'{sql_escape(NEW_NAME)}', {SYNTHETIC_EPOCH_MS}, {SYNTHETIC_EPOCH_MS}, "
        f"'{CREATED_BY}', '{CREATED_BY}', '{sql_escape(NEW_NAME.lower())}', "
        f"'Migrated from prod permission: Anything', 'GLOBAL' "
        f"WHERE NOT EXISTS (SELECT 1 FROM access_permissions_v2 WHERE name = '{sql_escape(NEW_NAME)}');"
    )

    for scope_key, resource_type in (("repo", "artifact"), ("build", "build")):
        scope = detail.get(scope_key)
        if not scope:
            continue
        repositories = scope.get("repositories", [])
        include_hex = patterns_to_hex(scope.get("include-patterns", ["**"]))
        exclude_hex = patterns_to_hex(scope.get("exclude-patterns", []))

        for target_name in target_rows_for_repositories(repositories):
            target_inserts.append(
                f"INSERT INTO access_permissions_targets_v2 "
                f"(target_id, perm_id, resource_type, target_name, is_target_ant_pattern, include_patterns, exclude_patterns) "
                f"SELECT (SELECT COALESCE(MAX(target_id),0)+1 FROM access_permissions_targets_v2), "
                f"p.perm_id, '{resource_type}', '{sql_escape(target_name)}', 0, "
                f"decode('{include_hex}', 'hex'), decode('{exclude_hex}', 'hex') "
                f"FROM access_permissions_v2 p WHERE p.name = '{sql_escape(NEW_NAME)}' "
                f"AND NOT EXISTS (SELECT 1 FROM access_permissions_targets_v2 t "
                f"WHERE t.perm_id = p.perm_id AND t.resource_type = '{resource_type}' "
                f"AND t.target_name = '{sql_escape(target_name)}');"
            )

        actions = scope.get("actions", {})
        for username, perm_list in actions.get("users", {}).items():
            val = bitmask(perm_list, warnings, f"Anything ({scope_key}) user {username}")
            action_inserts.append(
                f"INSERT INTO access_permissions_actions_v2 "
                f"(action_id, perm_id, resource_type, user_id, group_id, actions) "
                f"SELECT (SELECT COALESCE(MAX(action_id),0)+1 FROM access_permissions_actions_v2), "
                f"p.perm_id, '{resource_type}', u.user_id, NULL, {val} "
                f"FROM access_permissions_v2 p, access_users u "
                f"WHERE p.name = '{sql_escape(NEW_NAME)}' AND u.username = '{sql_escape(username)}' "
                f"AND NOT EXISTS (SELECT 1 FROM access_permissions_actions_v2 a "
                f"WHERE a.perm_id = p.perm_id AND a.resource_type = '{resource_type}' AND a.user_id = u.user_id);"
            )
        for groupname, perm_list in actions.get("groups", {}).items():
            val = bitmask(perm_list, warnings, f"Anything ({scope_key}) group {groupname}")
            action_inserts.append(
                f"INSERT INTO access_permissions_actions_v2 "
                f"(action_id, perm_id, resource_type, user_id, group_id, actions) "
                f"SELECT (SELECT COALESCE(MAX(action_id),0)+1 FROM access_permissions_actions_v2), "
                f"p.perm_id, '{resource_type}', NULL, g.group_id, {val} "
                f"FROM access_permissions_v2 p, access_groups g "
                f"WHERE p.name = '{sql_escape(NEW_NAME)}' AND g.group_name = '{sql_escape(groupname)}' "
                f"AND NOT EXISTS (SELECT 1 FROM access_permissions_actions_v2 a "
                f"WHERE a.perm_id = p.perm_id AND a.resource_type = '{resource_type}' AND a.group_id = g.group_id);"
            )

    with open(OUT_SQL, "w") as f:
        f.write("BEGIN;\n\n")
        f.write("\n".join(perm_inserts) + "\n\n")
        f.write("\n".join(target_inserts) + "\n\n")
        f.write("\n".join(action_inserts) + "\n\n")
        f.write("COMMIT;\n")

    print(f"Wrote {len(perm_inserts)} permission, {len(target_inserts)} target, {len(action_inserts)} action INSERTs to {OUT_SQL}")
    if warnings:
        print(f"{len(warnings)} WARNINGS:")
        for w in warnings:
            print(f"  - {w}")


if __name__ == "__main__":
    main()