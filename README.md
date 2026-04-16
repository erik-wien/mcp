# mcp

Central deployment system for the ~/Git app ecosystem (chat, wlmonitor, zeit, energie, suche). Runs per-app config generation and rsync/FTP to each target — DEV (localhost), TEST (akadbrain), PROD (world4you).

## Features

- **Single source of truth** — `config.yaml` holds all credentials and per-app deploy settings
- **Per-app config generation** — `generate.py` materialises the runtime config each app expects (INI, YAML, JSON, or PHP array)
- **Two invocation modes** — interactive TUI or CLI one-liner
- **Coordinator** — `scripts/deploy-all.sh` deploys multiple apps against a target in one pass
- **DB provisioning** — `scripts/grant-db-users.sql` creates the per-app MySQL users with scoped privileges

## Layout

```
deploy.py              Entry point (TUI + CLI)
generate.py            Per-app config renderer (reads config.yaml, writes app-native format)
config.yaml            All credentials, targets, per-app deploy settings (gitignored)
lib/
  common.sh            Shared shell helpers
  rsync.sh             SSH-based deploy (akadbrain)
  ftp.sh               FTP-based deploy (world4you)
scripts/
  deploy-all.sh        Deploy multiple apps to one target
  grant-db-users.sql   Provision MySQL users across auth + app DBs
tests/
  test_generate.py     pytest suite for the config generator
```

## Usage

```bash
# Interactive: arrow-key menus to pick app + target
python3 deploy.py

# Non-interactive
python3 deploy.py wlmonitor akadbrain

# Deploy a set of apps in one call
bash scripts/deploy-all.sh akadbrain wlmonitor energie
```

Targets: `local` · `akadbrain` · `world4you`. Not every app deploys to every target — see per-app entries in `config.yaml`.

## config.yaml

The heart of the system. Example shape:

```yaml
shared:
  smtp: { host, port, user, password, from, from_name }
  auth_db: { host, name, user, password }
  targets:
    local:      { web_root: /var/www }
    akadbrain:  { ssh_host, ssh_user, ssh_key }
    world4you:  { ftp_host, ftp_user, ftp_password }

apps:
  wlmonitor:
    legacy_config: config/db.json
    targets: [local, akadbrain, world4you]
    deploy:
      akadbrain: { dest: /Library/WebServer/Documents/wlmonitor/ }
      world4you: { dest: /wlmonitor/ }
    per_target_db:
      world4you: { host, name, user, password }
```

`config.yaml` is gitignored. Populate from `config.yaml.example` (to come) or by copying the live file from an existing workstation.

## Testing

```bash
pip install -r requirements.txt -r requirements-dev.txt
make test    # or: pytest tests/ -v
```

CI runs on every push/PR via GitHub Actions (Python 3.11).

## See also

- [CLAUDE.md](CLAUDE.md) — deploy targets, app inventory, per-app config paths, DB conventions
