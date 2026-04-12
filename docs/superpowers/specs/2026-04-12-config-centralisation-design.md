# Config Centralisation & Deployment Design

**Date:** 2026-04-12
**Scope:** `mcp/` repository — central config and deployment hub for all personal apps

---

## Overview

`mcp/` is a local-only repository (never pushed to GitHub) that acts as the single source of truth for credentials, infrastructure config, and deployment logic across all apps. It generates per-app config files and drives deployment through a single entry point.

Apps on GitHub carry only sanitized example configs and a migration brief (`update.md`) for local Claude instances to perform the one-time migration away from legacy config formats.

---

## Apps in Scope

| App | Current config format | Deploy targets |
|---|---|---|
| `energie` | `config.ini` | local, akadbrain |
| `wlmonitor` | `config/db.json` | local, akadbrain, world4you |
| `zeiterfassung` | `config/config.php` | local, akadbrain |
| `simplechat-2.1` | unknown | local |

---

## Section 1: Directory Structure

```
mcp/
├── config.yaml             # central source of truth (real credentials)
├── generate.py             # reads config.yaml, writes into each app directory
├── deploy.py               # main entry point: TUI (no args) or CLI (with args)
├── deploy.sh               # thin shell wrapper: python3 deploy.py "$@"
├── docs/
│   └── superpowers/
│       └── specs/
│           └── 2026-04-12-config-centralisation-design.md
└── lib/
    ├── common.sh           # shared shell helpers (ok/err/info/ask, colours)
    ├── rsync.sh            # shared rsync logic (rsync to local or SSH target)
    └── ftp.sh              # shared FTP logic (world4you)
```

Each app repo receives three generated files:

```
../energie/
├── config.yaml             # real credentials, target-resolved — gitignored
├── config.example.yaml     # sanitized placeholders — committed to GitHub
└── update.md               # migration brief for local Claude — committed
```

---

## Section 2: `config.yaml` Schema

```yaml
# ── Shared infrastructure ──────────────────────────────────────────────────
shared:
  smtp:
    host: smtp.world4you.com
    port: 587
    user: catchall@jardyx.com
    password: secret

  slack:
    bot_token: xoxb-...     # shared across all apps; channel_id is per-app

  targets:
    local:
      web_root: /Library/WebServer/Documents
    akadbrain:
      ssh_user: erik
      ssh_host: akadbrain.local
      ssh_key: ~/.ssh/id_rsa
      web_root: /Library/WebServer/Documents
    world4you:
      ftp_host: ftp.world4you.com
      ftp_user: secret
      ftp_password: secret

  auth_db:                   # shared between energie and wlmonitor
    host: localhost
    name: jardyx_auth
    user: wlmonitor
    password: secret

# ── Per-app ────────────────────────────────────────────────────────────────
apps:
  energie:
    legacy_config: config.ini         # current format, used to generate update.md key mapping
    targets: [local, akadbrain]
    deploy:
      local:
        dest: /Library/WebServer/Documents/energie
        sync_dirs: [web, inc, vendor]
      akadbrain:
        dest: /Library/WebServer/Documents/energie
        sync_dirs: [web, inc, vendor]
    db:
      host: localhost
      name: energie
      user: energie
      password: secret
    smtp:
      from: energie@jardyx.com
      from_name: Energie
    slack:
      channel_id: C0ARC5TDWEL
    app:
      base_url:
        local: http://localhost/energie.test
        akadbrain: https://energie.eriks.cloud
    hofer:
      username: fu.armin@gmail.com
      password: secret
      meter_id: AT00100...
    wienenergie:
      meter_id: AT00100...

  wlmonitor:
    legacy_config: config/db.json
    targets: [local, akadbrain, world4you]
    deploy:
      local:
        dest: /Library/WebServer/Documents/wlmonitor
      akadbrain:
        dest: /Library/WebServer/Documents/wlmonitor
      world4you:
        ftp_base_dir: /wlmonitor/
    db:                      # per-target because world4you has different host/credentials
      local:     { host: localhost, name: wlmonitor, user: wlmonitor, password: secret }
      akadbrain: { host: localhost, name: wlmonitor, user: wlmonitor, password: secret }
      world4you: { host: mysqlsvr78.world4you.com, name: 5279249db19, user: sql6675098, password: secret }
    smtp:
      from: wlmonitor@jardyx.com
      from_name: WL Monitor
    app:
      base_url:
        local: http://localhost/wlmonitor.test
        akadbrain: http://akadbrain.local/wlmonitor
        world4you: https://www.jardyx.com/wl-monitor

  zeiterfassung:
    legacy_config: config/config.php
    targets: [local, akadbrain]
    deploy:
      local:
        dest: /Library/WebServer/Documents/zeiterfassung
      akadbrain:
        dest: /Library/WebServer/Documents/zeiterfassung
    db:
      host: localhost
      name: zeiterfassung
      user: zeiterfassung
      password: secret
    smtp:
      from: zeiterfassung@jardyx.com
      from_name: Zeiterfassung
    app:
      base_url:
        local: http://127.0.0.1:8765
        akadbrain: http://akadbrain.local/zeiterfassung

  simplechat-2.1:
    targets: [local]
    deploy:
      local:
        dest: /Library/WebServer/Documents/simplechat
    app:
      base_url:
        local: http://localhost/simplechat
```

**Key conventions:**
- `smtp` in each app holds only `from`/`from_name` overrides — server credentials come from `shared.smtp`
- `slack` in each app holds only `channel_id` — `bot_token` comes from `shared.slack`
- `db` is flat when all targets share the same host; per-target when they differ
- `auth_db` is referenced from `shared` and merged in by the generator where needed

---

## Section 3: `generate.py` Behavior

### Invocation

```bash
python3 generate.py                          # regenerate all apps, all targets
python3 generate.py --app energie            # one app, all its targets
python3 generate.py --app energie --target akadbrain  # one app, one target
```

`deploy.py` always calls `generate.py --app X --target Y` before deploying.

### Per-app output

For each app+target combination, `generate.py` writes:

**1. `../energie/config.yaml`** — real credentials, fully resolved for the target. No `shared` references, no nested targets. This is what the app reads at runtime.

```yaml
# Generated by mcp/generate.py — do not edit manually
# Target: akadbrain

db:
  host: localhost
  name: energie
  user: energie
  password: secret

smtp:
  host: smtp.world4you.com
  port: 587
  user: catchall@jardyx.com
  password: secret
  from: energie@jardyx.com
  from_name: Energie

slack:
  bot_token: xoxb-...
  channel_id: C0ARC5TDWEL

app:
  base_url: https://energie.eriks.cloud

hofer:
  username: fu.armin@gmail.com
  password: secret
  meter_id: AT00100...
```

**2. `../energie/config.example.yaml`** — identical structure, all credential values replaced with descriptive placeholders (`your_password`, `your_db_name`, etc.). Committed to GitHub.

**3. `../energie/update.md`** — migration brief for the local Claude instance (see Section 5).

---

## Section 4: Deployment Flow

### Entry points

```bash
python3 mcp/deploy.py                        # TUI mode (rich, arrow-key menus)
python3 mcp/deploy.py energie akadbrain      # CLI mode
bash mcp/deploy.sh [app] [target]            # shell wrapper → calls deploy.py
```

### Steps

```
1. Select app     → menu or CLI arg
2. Select target  → filtered to targets defined for that app in config.yaml
3. Confirm        → required for akadbrain and world4you; skipped for local
4. Generate       → python3 generate.py --app {app} --target {target}
                    writes config.yaml, config.example.yaml, update.md
5. Deploy         → rsync (local/akadbrain) via lib/rsync.sh
                    FTP (world4you) via lib/ftp.sh
6. Post-deploy    → run migrations if scripts/migrate.php (or equivalent) exists
```

### TUI (rich)

- App selection: arrow-key menu, app names from `config.yaml`
- Target selection: filtered list per app
- Confirmation panel: highlighted warning for non-local targets
- Live output: streaming rsync/FTP output with status indicators (`ok`, `err`)
- Dependency: `rich` (`pip install rich`)

### Shared lib files

| File | Purpose |
|---|---|
| `lib/common.sh` | Colour helpers: `ok()`, `err()`, `info()`, `ask()` |
| `lib/rsync.sh` | `deploy_rsync src dest [ssh_opts] [excludes]` |
| `lib/ftp.sh` | FTP upload wrapper for world4you |

### Per-app `scripts/deploy.sh` (GitHub-facing)

Remains standalone — reads from local `config.yaml`, no `mcp/` dependency. Simpler than today: no hardcoded credentials, no heredoc config writing. GitHub users clone the app, copy `config.example.yaml` → `config.yaml`, fill in values, run the script.

---

## Section 5: `update.md` Format

Committed to each app repo. Tells the local Claude instance exactly what to migrate.

```markdown
# Config Migration Brief

Generated by mcp/generate.py — delete this file when migration is complete.

## Current state

This app reads config from `config/config.php` (PHP array, gitignored).
It should be updated to read from `config.yaml` using the structure in
`config.example.yaml`.

## Checklist

- [ ] Add `symfony/yaml` to composer.json (PHP) or `pyyaml` (Python)
- [ ] Replace all references to the old config loader with a YAML loader
- [ ] Add `config.yaml` to `.gitignore`
- [ ] Remove old config file and its example from the repo
- [ ] Update `scripts/deploy.sh` to expect `config.yaml`
- [ ] Delete this file

## Key mapping

| Old | New |
|-----|-----|
| `$cfg['db']['password']` | `db.password` |
| `$cfg['app']['base_url']` | `app.base_url` |
| `$cfg['mail']['from']` | `smtp.from` |

## New config structure

See `config.example.yaml` for the full expected shape.
```

The key mapping table is generated by `generate.py` from a `legacy_mapping` block defined per app in `mcp/config.yaml`.

---

## Aspects Not to Forget

Things that would be easy to overlook:

- **`.gitignore` in each app** must include `config.yaml` — `generate.py` should verify or warn if missing
- **`simplechat-2.1` config** is currently unknown — needs investigation before its section in `mcp/config.yaml` can be filled in
- **Python dependency for `generate.py`**: `pyyaml` (`pip install pyyaml`) — document alongside `rich`
- **akadbrain `auth_db`** is shared between energie and wlmonitor — the generator must merge it correctly for both
- **world4you FTP deploy** currently uses `scripts/ftp_deploy.php` in wlmonitor — `lib/ftp.sh` can wrap this or replace it
- **Migration is per-app, not atomic** — apps will be in mixed state (old format + new format) during transition; `generate.py` should handle both gracefully until all apps are migrated
