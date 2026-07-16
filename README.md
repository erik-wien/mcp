# mcp — deploy system

Central configuration, generation and deployment entry point for every app in the Jardyx / eriks.cloud ecosystem (`~/Git/auth`, `~/Git/chrome`, `~/Git/css_library`, `~/Git/wlmonitor`, `~/Git/zeiterfassung`, `~/Git/Energie`, `~/Git/simplechat-2.1`, `~/Git/suche`).

One `config.yaml` is the single source of truth for all per-target secrets, database credentials, FTP credentials and URL bindings. `generate.py` expands that file into per-app `config.yaml` (or equivalent) files. `deploy.py` rsyncs (or FTP-uploads) the app to a target host.

## Layout

```
mcp/
├── config.yaml              # source of truth — GITIGNORED (secrets)
├── generate.py              # expands config.yaml → per-app config files
├── deploy.py                # deploy entry point (TUI + CLI)
├── deploy.sh                # thin shell wrapper
├── lib/                     # helper modules used by deploy.py
├── scripts/
│   ├── deploy-all.sh        # batch deploy all apps to a target
│   └── grant-db-users.sql   # DB grants for all apps' DB users
├── rules/
│   └── publishing.md        # GitHub-publishing rules (public-repo hygiene)
├── docs/                    # deep-dive docs (generated, architecture, runbooks)
├── requirements.txt         # runtime deps (pyyaml)
└── requirements-dev.txt     # dev deps
```

## Supported targets

| Target | Host | Auth | DB | Chrome / fronting |
|---|---|---|---|---|
| `local` | developer workstation | macOS Homebrew | MariaDB (localhost, socket) | local Apache 2.4 |
| `akadbrain` | akadbrain (production-1) | SSH key | MariaDB on host | nginx + PHP-FPM |
| `world4you` | world4you shared hosting | SSH key (`ssh_deploy.php`) | **MySQL 5.5** (`5279249db19`) | managed Apache |

Host operations (sudo scope, manual migrations, PHP-FPM reload/tuning, biblio
Hub↔Hamish Tailscale reachability): [`docs/akadbrain-host-runbook.md`](docs/akadbrain-host-runbook.md).

## Usage

### Generate config for one app/target

```bash
python3 generate.py --app energie --target akadbrain
```

Writes `~/Git/Energie/config.yaml` (or the file shape that app expects). Credential fields are redacted to `your_<key>` when generating a sibling `config.example.yaml` for commit.

### Deploy

```bash
python3 deploy.py                                   # TUI: pick app + target
python3 deploy.py wlmonitor akadbrain               # non-interactive
python3 deploy.py --mail-ini akadbrain              # write /opt/homebrew/etc/jardyx-mail.ini only
```

Mechanisms:

- `local` and `akadbrain` use `rsync --copy-links --delete`, which resolves Composer path symlinks (`vendor/erikr/auth`, `vendor/erikr/chrome`) into real files at the destination.
- `world4you` uses rsync + remote migrations over SSH via a per-app `scripts/ssh_deploy.php` shipped with the app (it derives the remote path from `deploy.<target>.ftp_base_dir`).

> **World4you runs an old MySQL — migrations must use portable SQL.** The host's DB
> is MySQL 5.5-era (the SSH `mysql` client reports `Distrib 5.5.62`), so
> **MariaDB-only extensions break there** — notably column-level `ALTER TABLE … ADD
> COLUMN IF NOT EXISTS` / `DROP COLUMN IF EXISTS` (`CREATE TABLE IF NOT EXISTS` is
> standard and fine). `ssh_deploy.php` runs each `migrations/*.sql` with **STRICT
> mysqli** and records applied files in a `db_migrations` table, so:
>
> - **Run-once is guaranteed by `db_migrations`** — migrations need not be
>   self-idempotent. Write plain `ALTER TABLE … ADD COLUMN …`, not `… IF NOT EXISTS`.
> - **Any SQL error aborts the whole deploy** — the runner exits 255, `rsync.sh`
>   (`set -e`) propagates it, `deploy.py` raises. SQL that is valid on local MariaDB
>   but invalid on world4you MySQL fails every deploy until fixed.
>   (Hit 2026-06-30 by `002_en_swipe_nav.sql`.)

### Batch deploy

```bash
./scripts/deploy-all.sh akadbrain
```

Deploys every registered app to the given target, failing fast on the first error.

## Shared mail config

`deploy.py --mail-ini <target>` writes the host-level `jardyx-mail.ini` consumed by `erikr/auth`'s `load_mail_config()`. On `local` and `akadbrain` this lands at `/opt/homebrew/etc/jardyx-mail.ini`. On `world4you` the file is placed manually once (see `docs/jardyx-mail-ini-prod.md`) because shared hosting has no writable `/etc` path.

## Database grants

`scripts/grant-db-users.sql` enumerates the least-privilege grants each app's DB user needs against `auth`. Update it in the same change that introduces a new auth-DB table — missing grants show up as runtime MySQL 1142 errors in production and are painful to attribute.

## Publishing rules

When publishing any `~/Git/*` repo to GitHub (first push, visibility flip, release on an already-public repo), follow [`rules/publishing.md`](rules/publishing.md):

- README + `docs/` must be current before pushing.
- Never publish `CLAUDE.md`, `.claude/`, `docs/superpowers/`, `update.md`, `config.yaml`, `jardyx-mail.ini`, `.env*`, `data/`, `backups/`, `logs/`.
- Cross-repo references in READMEs use GitHub URLs, not local `~/Git/...` paths.

## Security

`config.yaml` contains every secret for every target (DB passwords, FTP credentials, SMTP credentials, API keys). It is gitignored and must never be committed. Only the redacted `config.example.yaml` generated by `generate.py` is safe to publish.

## Requirements

- Python 3.11+
- `pyyaml` (see `requirements.txt`)
- `rsync` (for `local` + `akadbrain`)
- SSH key configured for `akadbrain`
- PHP available on `world4you` (FTP uploader is a PHP script)
