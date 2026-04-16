# CLAUDE.md — Deployment

Authoritative deployment reference for all ~/Git apps.
Per-app scripts live in each repo; the coordinator is `mcp/scripts/deploy-all.sh`.

---

## Targets

| Label | Server | Stack | Connection | URL scheme |
|---|---|---|---|---|
| **DEV** | localhost | Apache + MariaDB | — | `localhost/%appname%.test` |
| **TEST** | akadbrain.local (10.10.10.18) | nginx + PHP-FPM + MariaDB | SSH (passwordless, `~/.ssh/id_rsa`) | `%appname%.eriks.cloud` |
| **PROD** | world4you | Apache + MySQL | FTP (`ftp.world4you.com`) | `%appname%.jardyx.com` |

SSH command: `ssh -i ~/.ssh/id_rsa -o IdentitiesOnly=yes erik@akadbrain.local`

---

## App Inventory

| App | Repo | Prefix | DEV URL | TEST URL | PROD URL |
|---|---|---|---|---|---|
| chat | `simplechat-2.1` | cht | `localhost/chat.test` | `chat.eriks.cloud` | `chat.jardyx.com` |
| wlmonitor | `wlmonitor` | wl | `localhost/wlmonitor.test` | `wlmonitor.eriks.cloud` | `wlmonitor.jardyx.com` |
| zeit | `zeiterfassung` | wd | `localhost/werda.test` | `werda.eriks.cloud` | `werda.jardyx.com` |
| energie | `Energie` | en | `localhost/energie.test` | `energie.eriks.cloud` | `energie.jardyx.com` |
| suche | `suche` | — | `localhost` | `www.eriks.cloud` | `www.jardyx.com` |

Document roots on akadbrain: `/Library/WebServer/Documents/<appname>/`
(zeit deploys to `werda/`, suche deploys to the document root directly)

> **PROD deploy status:** currently only implemented for **wlmonitor**.
> The other apps run on akadbrain (TEST) as their effective live target for now.

---

## Deploy Commands

### mcp — the deploy system

All deploys go through `mcp/deploy.py`. It runs `mcp/generate.py` to write the per-app `config.yaml`, then rsyncs (or FTPs) the files.

```bash
# TUI (interactive, arrow-key menus)
python3 mcp/deploy.py

# CLI (non-interactive)
python3 mcp/deploy.py <mcp-app-name> <target>
```

`mcp/config.yaml` is the single source of truth for all credentials and targets.
`mcp/generate.py` writes a per-app `config.yaml` at the app root (gitignored, overwritten on every deploy).

### Coordinator — deploy multiple apps at once

```bash
# Run from ~/Git
bash mcp/scripts/deploy-all.sh <target> [app ...]

# Examples
bash mcp/scripts/deploy-all.sh akadbrain
bash mcp/scripts/deploy-all.sh akadbrain chat energie
bash mcp/scripts/deploy-all.sh world4you wlmonitor
```

### App name mapping (friendly → mcp)

| Friendly | mcp name | Targets |
|---|---|---|
| chat | `simplechat-2.1` | local · akadbrain |
| wlmonitor | `wlmonitor` | local · akadbrain · world4you |
| zeit | `zeiterfassung` | local · akadbrain |
| energie | `energie` | local · akadbrain |
| suche | `suche` | local · akadbrain |

> Per-app deploy scripts in individual repos (`scripts/deploy.sh`, `deploy/deploy.sh`) are **legacy**.
> They have not been removed but should not be used — mcp supersedes them.

### DB grants

`mcp/scripts/grant-db-users.sql` — run as root on localhost and akadbrain to provision all app users:

```bash
mysql -uroot < mcp/scripts/grant-db-users.sql
```

---

## Databases

### DEV (localhost)

phpmyadmin: `http://localhost/phpmyadmin/` — user: `root` (no password)

| App | App DB | Auth DB | DB user |
|---|---|---|---|
| chat | *(none — file-backed)* | `jardyx_auth` | `simplechat` |
| wlmonitor | `wlmonitor` | `jardyx_auth` | `wlmonitor` |
| zeit | `zeiterfassung` | `jardyx_auth` | `zeiterfassung` |
| energie | `energie` | `jardyx_auth` | `energie` |

### TEST — akadbrain

phpmyadmin: `myphpadmin.eriks.cloud`
MariaDB via socket `/tmp/mysql.sock` — user: `root` (no password)

Same DB names and users as DEV:

| App | App DB | Auth DB | DB user |
|---|---|---|---|
| chat | *(none — file-backed)* | `jardyx_auth` | `simplechat` |
| wlmonitor | `wlmonitor` | `jardyx_auth` | `wlmonitor` |
| zeit | `zeiterfassung` | `jardyx_auth` | `zeiterfassung` |
| energie | `energie` | `jardyx_auth` | `energie` |

### PROD — world4you

phpmyadmin: `https://mysqlsvr78admin.world4you.com/index.php?route=/&db=5279249db19&server=59`
Server: `mysqlsvr78.world4you.com` (app-side alias: `localhost`)
User: `sql6675098`

**All tables live in a single database: `5279249db19`**
There is no separate `jardyx_auth` database — app tables and auth tables all share `5279249db19`.
Deploy configs must point both the app DSN and the auth DSN at `5279249db19`.

---

## Config files written by deploy scripts

Credentials are never committed to git — deploy scripts write them on the target at deploy time.

| App | Config location | Format |
|---|---|---|
| chat | `data/config.yaml` | YAML |
| wlmonitor | `config/db.json` | JSON (keys: dev / prod / world4you / smtp_*) |
| zeit | `config/config.php` | PHP array |
| energie | `/opt/homebrew/etc/energie-config.ini` | INI (sections: db, auth, smtp, app, slack) |

---

## data/ directories

Must exist and be writable (`chmod 777`) on akadbrain — excluded from rsync, not auto-created.

```bash
ssh akadbrain.local "mkdir -p /Library/WebServer/Documents/<app>/data && chmod 777 /Library/WebServer/Documents/<app>/data"
```

---

## nginx on akadbrain

Managed manually on the server — do not modify remotely without asking the user.
Each app's server block should include:

```nginx
location = /index.php { return 301 /; }
```
