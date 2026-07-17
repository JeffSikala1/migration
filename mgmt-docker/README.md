# Atlassian / Artifactory Startup Runbook

Approach: individualized per app startup scripts + systemd units. Restarting or upgrading one app never touches the others.

## Hosts involved

| Host | Apps | Data model |
|---|---|---|
| `ip-10-56-112-34` | Postgres (shared), Bamboo, Bitbucket, nginx (shared) | Named Docker volumes under `/app/docker/volumes` |
| `ip-10-56-112-243` | Postgres (dedicated), Artifactory, artifactory-nginx | Host bind mounts under `/app/jfrog/...` and `/app/postgres/data` |

These are two separate hosts with two separate Postgres instances, there is no cross host dependency.

## Why individualized scripts, and why ordering still matters

`docker inspect` showed `prod-postgres` has `RestartPolicy: "no"` while Bamboo/Bitbucket/nginx all have `unless-stopped`. On reboot, Docker starts the `unless-stopped` containers immediately and in parallel, Postgres does not come back on its own, and even where it does (`artifactory-postgres` already has the correct policy), there's no guarantee it's `ready` before the app tries to connect. That race is the likely cause of past misconfigured-startup incidents.

Each script below solves this: it explicitly starts Postgres first, waits for `pg_isready`, then starts its one app, then starts the relevant nginx. Nothing here uses `docker run`, these are `docker start` on containers that already exist, so no image versions, env vars, or mounts are being redefined. A real version upgrade (new image tag) stays a deliberate manual step, never something a boot script does automatically.

## Files

| File | Host | Purpose |
|---|---|---|
| `lib-common.sh` | both | Shared helper functions (logging, wait-for-postgres, safety checks). Sourced by all three scripts, never run directly. |
| `start-bamboo.sh` | .34 | Starts `prod-postgres` (if needed) -> waits ready -> starts `prod-bamboo` -> starts `nginx` (if needed) |
| `start-bitbucket.sh` | .34 | Starts `prod-postgres` (if needed) -> waits ready -> starts `cnxs-mgmt-bitbucket` -> starts `nginx` (if needed) |
| `start-artifactory.sh` | .243 | Starts `artifactory-postgres` -> waits ready -> starts `artifactory` -> starts `artifactory-nginx` |
| `bamboo.service` / `bitbucket.service` / `artifactory.service` | both | systemd units so the right script runs automatically at boot |

nginx is included in both `.34` scripts (each is safe to run, starting an already-running container is a no-op) since it fronts both Bamboo and Bitbucket and had its own crash loop history (`RestartCount: 7`), most likely from the same kind of startup ordering race.

## One-time setup

**Host `ip-10-56-112-34`:**
```
sudo mkdir -p /app/atlassian-startup
# copy start-bamboo.sh, start-bitbucket.sh, lib-common.sh into it
sudo cp <relevant script> /app/atlassian-startup
sudo chmod +x /app/atlassian-startup/start-bamboo.sh /app/atlassian-startup/start-bitbucket.sh
sudo cp bamboo.service bitbucket.service /etc/systemd/system/
sudo systemctl daemon-reload
```
Confirm the mount-unit name used in each service's `After=` line matches reality:
```
systemctl list-units -t mount | grep app
```

**Host `ip-10-56-112-243`:**
```
sudo mkdir -p /app/artifactory-startup
# copy start-artifactory.sh, lib-common.sh into it
sudo cp <relevant script> /app/artifactory-startup
sudo chmod +x /app/artifactory-startup/start-artifactory.sh
sudo cp artifactory.service /etc/systemd/system/
sudo systemctl daemon-reload
```
Before relying on this in production, run `df -Th` on this host and confirm `/app` (or wherever `/app/jfrog/...` and `/app/postgres/data` actually live) is a real separate mount, not just a directory on the root disk. If it's a distinct mount, add `mountpoint -q /app || fail ...` to `start-artifactory.sh` the same way the other host's scripts do, and add `app.mount` to the service's `After=` line.

## First run / verification (do this manually before enabling the systemd units)

On `.34`:
```
cd /app/atlassian-startup
sudo ./start-bamboo.sh
sudo ./start-bitbucket.sh
docker ps   # confirm prod-postgres, prod-bamboo, cnxs-mgmt-bitbucket, nginx all Up
```

On `.243`:
```
cd /app/artifactory-startup
sudo ./start-artifactory.sh
docker ps   # confirm artifactory-postgres, artifactory, artifactory-nginx all Up
```

Once confirmed working, enable for boot:
```
sudo systemctl enable bamboo.service bitbucket.service      # on .34
sudo systemctl enable artifactory.service                    # on .243
```

## Day-to-day: restarting or patching a single app

Each of these touches only the named app (and Postgres/nginx only if they aren't already up):
```
sudo systemctl restart bamboo.service        # only Bamboo
sudo systemctl restart bitbucket.service     # only Bitbucket
sudo systemctl restart artifactory.service   # only Artifactory
```
None of these restarts Postgres if it's already running (the scripts check first), and none of them touches the other apps.