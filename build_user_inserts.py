#!/usr/bin/env python3
"""
Builds SQL INSERT statements for Artifactory's access_users +
access_users_custom_data + access_users_groups tables, targeting the
internal schema verified via a real UI-created test user
(schema-test-user, user_id 2002) on the dev OSS instance.

Input: prod_users_detail/<name>.json (REST API config for each user,
       already pulled from prod).
Output:
  - user_inserts.sql          - review before running against dev-postgres
  - service_account_passwords.txt - PLAINTEXT generated passwords for the
    7 service accounts. Move these into a proper secrets store (Bamboo
    global/secure variables, etc.) immediately, then delete this file.
    Do NOT leave it sitting on disk or commit it anywhere.

Skipped entirely (existing rows, never touched by this script):
  - admin      -> already exists on dev with a real password from the
                  earlier admin-password-recovery work in this same table
  - anonymous  -> built-in reserved system user (user_id 3 on dev)

Password policy (per team decision 2026-08-11/12):
  - Service accounts (see SERVICE_ACCOUNTS below) get a real, randomly
    generated password, hashed with Argon2id using the exact parameters
    Artifactory itself uses (m=512, t=16, p=1, v=19 - verified against a
    real UI-created password hash). disabled_password=false so they can
    actually authenticate.
  - Every other user (the ~40 human/SAML accounts) gets password=NULL and
    disabled_password=true - carried-forward-but-unusable until reset or
    SAML is wired up. This is a deliberate deviation from prod (prod shows
    internalPasswordDisabled=false even for realm=saml users), made
    because dev has no working SSO yet.

Field mapping (REST -> internal), verified via schema-test-user's real
access_users_custom_data row:
  admin             -> artifactory_admin
  policyViewer      -> policy_viewer
  policyManager     -> policy_manager
  watchManager      -> watch_manager
  reportsManager    -> reports_manager
  profileUpdatable  -> updatable_profile
  disableUIAccess   -> blockUiView
  (internalPasswordDisabled is NOT carried forward - see password policy above)

realm is carried forward verbatim (internal/saml) - unlike groups, no
prod user in this pull showed realm=crowd, so no override needed here.

IDs (user_id) are assigned dynamically at INSERT time via
(SELECT COALESCE(MAX(user_id),0)+1 FROM access_users), evaluated in
transaction order - not hardcoded - so this is rerun-safe. Each INSERT is
additionally guarded with WHERE NOT EXISTS so reruns skip users that
already exist.

Requires: pip install argon2-cffi --break-system-packages (or without the
flag depending on your environment)
"""
import json
import secrets
from pathlib import Path

try:
    from argon2 import PasswordHasher
except ImportError:
    raise SystemExit(
        "Missing dependency. Run: pip install argon2-cffi --break-system-packages"
    )

BASE = Path.home() / "artifactory-migration"
DETAIL_DIR = BASE / "prod_users_detail"
OUT_SQL = BASE / "user_inserts.sql"
OUT_SECRETS = BASE / "service_account_passwords.txt"

SYNTHETIC_EPOCH_MS = 1735689600000  # 2025-01-01T00:00:00Z, same convention as repo/group inserts

SKIP_USERS = {"admin", "anonymous"}

SERVICE_ACCOUNTS = {
    "sa_bamboo",
    "uploader",
    "sa_conexus",
    "sa_snyk",
    "avupload",
    "docker-uploader",
    "owasp_report_upload",
}

# Verified against schema-test-user's real password hash:
# argon$$argon2id$v=19$m=512,t=16,p=1$<salt>$<hash>
# i.e. "argon" prefix + standard PHC-format argon2id hash string.
ph = PasswordHasher(time_cost=16, memory_cost=512, parallelism=1, hash_len=32, salt_len=16)

CUSTOM_DATA_FLAG_MAP = {
    "admin": "artifactory_admin",
    "policyViewer": "policy_viewer",
    "policyManager": "policy_manager",
    "watchManager": "watch_manager",
    "reportsManager": "reports_manager",
    "profileUpdatable": "updatable_profile",
    "disableUIAccess": "blockUiView",
}


def load_json(path):
    with open(path) as f:
        return json.load(f)


def sql_escape(s):
    return (s or "").replace("'", "''")


def bool_sql(v):
    return "true" if v else "false"


def main():
    if not DETAIL_DIR.exists():
        print(f"ERROR: {DETAIL_DIR} not found")
        return

    user_files = sorted(DETAIL_DIR.glob("*.json"))
    user_inserts = []
    custom_data_inserts = []
    group_membership_inserts = []
    warnings = []
    generated_passwords = []

    for path in user_files:
        detail = load_json(path)
        name = detail["name"]

        if name in SKIP_USERS:
            continue

        email = sql_escape(detail.get("email", ""))
        realm = detail.get("realm", "internal")
        if realm not in ("internal", "saml"):
            warnings.append(f"{name}: unexpected realm '{realm}' - carried forward as-is, verify manually")
        status = detail.get("status", "ENABLED").lower()
        is_service = name in SERVICE_ACCOUNTS

        if is_service:
            random_password = secrets.token_urlsafe(24)
            password_hash = "argon" + ph.hash(random_password)
            password_sql = f"'{sql_escape(password_hash)}'"
            disabled_password = False
            generated_passwords.append((name, random_password))
        else:
            password_sql = "NULL"
            disabled_password = True

        user_sql = (
            f"INSERT INTO access_users "
            f"(user_id, username, password, allowed_ips, created, modified, firstname, lastname, "
            f"email, realm, status, last_login_time, last_login_ip, failed_attempts, "
            f"status_last_modified, password_last_modified) "
            f"SELECT (SELECT COALESCE(MAX(user_id),0)+1 FROM access_users), "
            f"'{sql_escape(name)}', {password_sql}, '*', {SYNTHETIC_EPOCH_MS}, {SYNTHETIC_EPOCH_MS}, "
            f"NULL, NULL, '{email}', '{realm}', '{status}', 0, NULL, 0, "
            f"{SYNTHETIC_EPOCH_MS}, {SYNTHETIC_EPOCH_MS} "
            f"WHERE NOT EXISTS (SELECT 1 FROM access_users WHERE username = '{sql_escape(name)}');"
        )
        user_inserts.append(user_sql)

        for rest_key, prop_key in CUSTOM_DATA_FLAG_MAP.items():
            value = bool_sql(detail.get(rest_key, False))
            cd_sql = (
                f"INSERT INTO access_users_custom_data (user_id, prop_key, prop_value, prop_sensitive, prop_cluster_local) "
                f"SELECT user_id, '{prop_key}', '{value}', 0, 0 FROM access_users "
                f"WHERE username = '{sql_escape(name)}' "
                f"AND NOT EXISTS ("
                f"SELECT 1 FROM access_users_custom_data "
                f"WHERE user_id = (SELECT user_id FROM access_users WHERE username = '{sql_escape(name)}') "
                f"AND prop_key = '{prop_key}'"
                f");"
            )
            custom_data_inserts.append(cd_sql)

        # disabled_password is set per our password policy, not carried from prod's internalPasswordDisabled
        dp_sql = (
            f"INSERT INTO access_users_custom_data (user_id, prop_key, prop_value, prop_sensitive, prop_cluster_local) "
            f"SELECT user_id, 'disabled_password', '{bool_sql(disabled_password)}', 0, 0 FROM access_users "
            f"WHERE username = '{sql_escape(name)}' "
            f"AND NOT EXISTS ("
            f"SELECT 1 FROM access_users_custom_data "
            f"WHERE user_id = (SELECT user_id FROM access_users WHERE username = '{sql_escape(name)}') "
            f"AND prop_key = 'disabled_password'"
            f");"
        )
        custom_data_inserts.append(dp_sql)

        for group_name in detail.get("groups", []):
            gm_sql = (
                f"INSERT INTO access_users_groups (user_id, group_id, realm) "
                f"SELECT u.user_id, g.group_id, '{realm}' "
                f"FROM access_users u, access_groups g "
                f"WHERE u.username = '{sql_escape(name)}' AND g.group_name = '{sql_escape(group_name)}' "
                f"AND NOT EXISTS ("
                f"SELECT 1 FROM access_users_groups ug "
                f"WHERE ug.user_id = u.user_id AND ug.group_id = g.group_id"
                f");"
            )
            group_membership_inserts.append(gm_sql)
            # Note: if the group doesn't exist on dev (shouldn't happen - all 14 prod groups were
            # migrated), this INSERT just silently matches 0 rows via the join - not a hard failure.
            # Worth checking the INSERT 0 vs INSERT 1 counts when running this.

    with open(OUT_SQL, "w") as f:
        f.write("BEGIN;\n\n")
        f.write("-- access_users\n")
        f.write("\n".join(user_inserts))
        f.write("\n\n-- access_users_custom_data (privilege flags + disabled_password)\n")
        f.write("\n".join(custom_data_inserts))
        f.write("\n\n-- access_users_groups (group membership)\n")
        f.write("\n".join(group_membership_inserts))
        f.write("\n\nCOMMIT;\n")

    with open(OUT_SECRETS, "w") as f:
        f.write("# GENERATED SERVICE ACCOUNT PASSWORDS - move to a secrets store then delete this file\n")
        f.write(f"# Generated by build_user_inserts.py\n\n")
        for name, pw in generated_passwords:
            f.write(f"{name}: {pw}\n")

    print(
        f"Wrote {len(user_inserts)} user INSERTs, {len(custom_data_inserts)} custom_data INSERTs, "
        f"{len(group_membership_inserts)} group-membership INSERTs to {OUT_SQL}"
    )
    print(f"Wrote {len(generated_passwords)} generated passwords to {OUT_SECRETS} - SECURE OR DELETE THIS FILE AFTER USE")
    if warnings:
        print(f"\n{len(warnings)} WARNINGS:")
        for w in warnings:
            print(f"  - {w}")


if __name__ == "__main__":
    main()