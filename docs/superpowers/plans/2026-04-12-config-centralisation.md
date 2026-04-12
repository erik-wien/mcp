# Config Centralisation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `mcp/` as the local-only source of truth for credentials and deployment across energie, wlmonitor, zeiterfassung, and simplechat-2.1.

**Architecture:** A Python generator reads `mcp/config.yaml` and writes resolved `config.yaml`, `config.example.yaml`, and `update.md` into each app directory. A `deploy.py` entry point (TUI + CLI) runs the generator then dispatches rsync or FTP via shared shell lib scripts. Per-app `scripts/deploy.sh` files remain standalone for GitHub users.

**Tech Stack:** Python 3.10+, pyyaml, rich, questionary, bash, rsync

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `mcp/.gitignore` | Create | Ignore `config.yaml` (contains real credentials) |
| `mcp/requirements.txt` | Create | pyyaml, rich, questionary |
| `mcp/requirements-dev.txt` | Create | pytest |
| `mcp/config.yaml` | Create | Central source of truth — all real credentials |
| `mcp/generate.py` | Create | Reads config.yaml, generates per-app files |
| `mcp/tests/__init__.py` | Create | Make tests a package |
| `mcp/tests/test_generate.py` | Create | Unit tests for generate.py |
| `mcp/deploy.py` | Create | TUI + CLI deploy entry point |
| `mcp/deploy.sh` | Create | Thin shell wrapper → calls deploy.py |
| `mcp/lib/common.sh` | Create | Shared colour output helpers |
| `mcp/lib/rsync.sh` | Create | rsync dispatch (local + SSH) |
| `mcp/lib/ftp.sh` | Create | FTP upload wrapper |

**Generated into app repos (by generate.py, not hand-written):**
- `../energie/config.yaml`, `config.example.yaml`, `update.md`
- `../wlmonitor/config.yaml`, `config.example.yaml`, `update.md`
- `../zeiterfassung/config.yaml`, `config.example.yaml`, `update.md`
- `../simplechat-2.1/config.yaml`, `config.example.yaml`, `update.md`

---

### Task 1: Init repo, scaffold, and dependencies

**Files:**
- Create: `mcp/.gitignore`
- Create: `mcp/requirements.txt`
- Create: `mcp/requirements-dev.txt`
- Create: `mcp/tests/__init__.py`

- [ ] **Step 1: Init git repo**

```bash
cd /Users/erikr/Git/mcp
git init
```

- [ ] **Step 2: Create `.gitignore`**

```
config.yaml
__pycache__/
*.pyc
.pytest_cache/
```

- [ ] **Step 3: Create `requirements.txt`**

```
pyyaml>=6.0
rich>=13.0
questionary>=2.0
```

- [ ] **Step 4: Create `requirements-dev.txt`**

```
-r requirements.txt
pytest>=7.0
```

- [ ] **Step 5: Create `tests/__init__.py`**

Empty file — makes `tests/` a package so pytest finds it.

```bash
mkdir -p tests
touch tests/__init__.py
```

- [ ] **Step 6: Install dependencies**

```bash
pip install -r requirements-dev.txt
```

Expected: all packages install without error.

- [ ] **Step 7: Commit**

```bash
git add .gitignore requirements.txt requirements-dev.txt tests/__init__.py
git commit -m "chore: init mcp repo with dependencies"
```

---

### Task 2: Write `config.yaml` — central source of truth

**Files:**
- Create: `mcp/config.yaml`

This file is gitignored. It contains all real credentials.

- [ ] **Step 1: Create `config.yaml`**

```yaml
# mcp/config.yaml — central source of truth
# Local only. Never push this repo. This file is gitignored.

shared:
  smtp:
    host: smtp.world4you.com
    port: 587
    user: catchall@jardyx.com
    password: rtuk4cy5gu

  slack:
    bot_token: "xapp-1-A0AQP6HMV4K-10830163872103-10c7aad65d5f79f81bc4546652699a5f2c367d5dedfa7fa18708edc424e769c9"

  targets:
    local:
      web_root: /Library/WebServer/Documents
    akadbrain:
      ssh_user: erik
      ssh_host: akadbrain.local
      ssh_key: ~/.ssh/id_rsa
    world4you:
      ftp_host: ftp.world4you.com
      ftp_user: FILL_IN
      ftp_password: FILL_IN

  auth_db:
    host: localhost
    name: jardyx_auth
    user: wlmonitor
    password: sopdi9-nyKnyb-zyqpyh

apps:
  energie:
    legacy_config: config.ini
    targets: [local, akadbrain]
    deploy:
      local:
        dest: /Library/WebServer/Documents/Energie
        sync_dirs: [web, inc, vendor]
      akadbrain:
        dest: /Library/WebServer/Documents/energie
        sync_dirs: [web, inc, vendor]
    db:
      host: localhost
      name: energie
      user: energie
      password: joKqav-0finqu-fosqet
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
      password: futqyr-zewvun-fetPi1
      meter_id: AT0010000000000000001000012891962
    wienenergie:
      meter_id: AT0010000000000000001000012891962

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
    db:
      local:
        host: localhost
        name: wlmonitor
        user: wlmonitor
        password: sopdi9-nyKnyb-zyqpyh
      akadbrain:
        host: localhost
        name: wlmonitor
        user: wlmonitor
        password: sopdi9-nyKnyb-zyqpyh
      world4you:
        host: mysqlsvr78.world4you.com
        name: 5279249db19
        user: sql6675098
        password: dr@3ysr
    auth_db: shared
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
        dest: /Library/WebServer/Documents/werda
    db:
      socket: /tmp/mysql.sock
      name: zeiterfassung
      user: zeiterfassung
      password: CfgnWHMYiQYPU17Cg8KN80pO
    auth_db:
      socket: /tmp/mysql.sock
      name: jardyx_auth
      user: zeiterfassung
      password: CfgnWHMYiQYPU17Cg8KN80pO
    smtp:
      host: smtp.world4you.com
      port: 587
      user: catchall@2me.org
      password: rufxah-hocqo4-Xozxuh
      from: zeiterfassung@jardyx.com
      from_name: Zeiterfassung
    app:
      base_url:
        local: http://localhost/werda
        akadbrain: http://akadbrain.local/werda

  simplechat-2.1:
    targets: [local, akadbrain]
    deploy:
      local:
        dest: /Users/erikr/Git/simplechat
      akadbrain:
        dest: /Library/WebServer/Documents/chat
    smtp:
      from: chat@jardyx.com
      from_name: SimpleChat
    app:
      base_url:
        local: http://localhost/simplechat
        akadbrain: http://akadbrain.local/chat
```

- [ ] **Step 2: Verify it parses cleanly**

```bash
python3 -c "import yaml; cfg = yaml.safe_load(open('config.yaml')); print(list(cfg['apps'].keys()))"
```

Expected output: `['energie', 'wlmonitor', 'zeiterfassung', 'simplechat-2.1']`

Note: `config.yaml` is gitignored — do NOT commit it.

---

### Task 3: Write failing tests for `generate.py`

**Files:**
- Create: `mcp/tests/test_generate.py`

- [ ] **Step 1: Write `tests/test_generate.py`**

```python
"""Tests for generate.py — run with: pytest tests/ -v"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

import pytest
from generate import resolve_app_config, resolve_db, sanitize, generate_update_md

# ── Fixture config ────────────────────────────────────────────────────────────

FIXTURE = {
    'shared': {
        'smtp': {
            'host': 'smtp.example.com',
            'port': 587,
            'user': 'smtp_user',
            'password': 'smtp_pass',
        },
        'slack': {
            'bot_token': 'xoxb-test-token',
        },
        'auth_db': {
            'host': 'localhost',
            'name': 'shared_auth',
            'user': 'auth_user',
            'password': 'auth_pass',
        },
        'targets': {
            'local': {'web_root': '/var/www'},
            'akadbrain': {'ssh_host': 'akadbrain.local', 'ssh_user': 'erik', 'ssh_key': '~/.ssh/id_rsa'},
            'world4you': {'ftp_host': 'ftp.example.com', 'ftp_user': 'ftpu', 'ftp_password': 'ftpp'},
        },
    },
    'apps': {
        'flatdb': {
            'legacy_config': 'config.ini',
            'targets': ['local', 'akadbrain'],
            'deploy': {
                'local': {'dest': '/var/www/flatdb'},
                'akadbrain': {'dest': '/var/www/flatdb'},
            },
            'db': {
                'host': 'localhost',
                'name': 'flatdb',
                'user': 'flatdb_user',
                'password': 'db_secret',
            },
            'smtp': {
                'from': 'flatdb@example.com',
                'from_name': 'FlatDB',
            },
            'slack': {
                'channel_id': 'C12345',
            },
            'app': {
                'base_url': {
                    'local': 'http://localhost/flatdb',
                    'akadbrain': 'https://flatdb.example.com',
                },
            },
            'extra_section': {
                'key': 'value',
            },
        },
        'multidb': {
            'targets': ['local', 'world4you'],
            'deploy': {
                'local': {'dest': '/var/www/multidb'},
                'world4you': {'ftp_base_dir': '/multidb/'},
            },
            'db': {
                'local': {'host': 'localhost', 'name': 'mdb', 'user': 'mu', 'password': 'mp'},
                'world4you': {'host': 'remotehost', 'name': 'remdb', 'user': 'ru', 'password': 'rp'},
            },
            'auth_db': 'shared',
            'smtp': {'from': 'multidb@example.com', 'from_name': 'MultiDB'},
            'app': {
                'base_url': {
                    'local': 'http://localhost/multidb',
                    'world4you': 'https://example.com/multidb',
                },
            },
        },
        'ownsmtp': {
            'targets': ['local'],
            'deploy': {'local': {'dest': '/var/www/ownsmtp'}},
            'smtp': {
                'host': 'smtp.other.com',
                'port': 465,
                'user': 'own_user',
                'password': 'own_pass',
                'from': 'own@other.com',
                'from_name': 'OwnSMTP',
            },
            'app': {'base_url': {'local': 'http://localhost/ownsmtp'}},
        },
        'ownauth': {
            'targets': ['local'],
            'deploy': {'local': {'dest': '/var/www/ownauth'}},
            'db': {'host': 'localhost', 'name': 'ownauth', 'user': 'u', 'password': 'p'},
            'auth_db': {
                'socket': '/tmp/mysql.sock',
                'name': 'jardyx_auth',
                'user': 'ownauth_user',
                'password': 'ownauth_pass',
            },
            'smtp': {'from': 'ownauth@example.com', 'from_name': 'OwnAuth'},
            'app': {'base_url': {'local': 'http://localhost/ownauth'}},
        },
    },
}


# ── resolve_db ────────────────────────────────────────────────────────────────

def test_resolve_db_flat_returns_as_is():
    db = FIXTURE['apps']['flatdb']['db']
    assert resolve_db(db, 'local') == db

def test_resolve_db_per_target_local():
    db = FIXTURE['apps']['multidb']['db']
    result = resolve_db(db, 'local')
    assert result == {'host': 'localhost', 'name': 'mdb', 'user': 'mu', 'password': 'mp'}

def test_resolve_db_per_target_world4you():
    db = FIXTURE['apps']['multidb']['db']
    result = resolve_db(db, 'world4you')
    assert result == {'host': 'remotehost', 'name': 'remdb', 'user': 'ru', 'password': 'rp'}

def test_resolve_db_none_when_no_db():
    result = resolve_db(None, 'local')
    assert result is None


# ── resolve_app_config ────────────────────────────────────────────────────────

def test_smtp_merges_shared_credentials():
    result = resolve_app_config(FIXTURE, 'flatdb', 'local')
    assert result['smtp']['host'] == 'smtp.example.com'
    assert result['smtp']['password'] == 'smtp_pass'
    assert result['smtp']['from'] == 'flatdb@example.com'
    assert result['smtp']['from_name'] == 'FlatDB'

def test_smtp_app_overrides_shared_server():
    """If app defines host/user/password, they override shared smtp server."""
    result = resolve_app_config(FIXTURE, 'ownsmtp', 'local')
    assert result['smtp']['host'] == 'smtp.other.com'
    assert result['smtp']['user'] == 'own_user'
    assert result['smtp']['password'] == 'own_pass'

def test_slack_merges_bot_token_and_channel_id():
    result = resolve_app_config(FIXTURE, 'flatdb', 'local')
    assert result['slack']['bot_token'] == 'xoxb-test-token'
    assert result['slack']['channel_id'] == 'C12345'

def test_base_url_resolved_for_local():
    result = resolve_app_config(FIXTURE, 'flatdb', 'local')
    assert result['app']['base_url'] == 'http://localhost/flatdb'

def test_base_url_resolved_for_akadbrain():
    result = resolve_app_config(FIXTURE, 'flatdb', 'akadbrain')
    assert result['app']['base_url'] == 'https://flatdb.example.com'

def test_flat_db_in_output():
    result = resolve_app_config(FIXTURE, 'flatdb', 'local')
    assert result['db']['name'] == 'flatdb'
    assert result['db']['password'] == 'db_secret'

def test_per_target_db_local():
    result = resolve_app_config(FIXTURE, 'multidb', 'local')
    assert result['db']['host'] == 'localhost'
    assert result['db']['name'] == 'mdb'

def test_per_target_db_world4you():
    result = resolve_app_config(FIXTURE, 'multidb', 'world4you')
    assert result['db']['host'] == 'remotehost'
    assert result['db']['name'] == 'remdb'

def test_auth_db_shared():
    result = resolve_app_config(FIXTURE, 'multidb', 'local')
    assert result['auth_db']['name'] == 'shared_auth'
    assert result['auth_db']['user'] == 'auth_user'

def test_auth_db_own():
    result = resolve_app_config(FIXTURE, 'ownauth', 'local')
    assert result['auth_db']['user'] == 'ownauth_user'
    assert result['auth_db']['socket'] == '/tmp/mysql.sock'

def test_extra_sections_pass_through():
    result = resolve_app_config(FIXTURE, 'flatdb', 'local')
    assert result['extra_section'] == {'key': 'value'}

def test_internal_keys_not_in_output():
    result = resolve_app_config(FIXTURE, 'flatdb', 'local')
    assert 'targets' not in result
    assert 'deploy' not in result
    assert 'legacy_config' not in result


# ── sanitize ──────────────────────────────────────────────────────────────────

def test_sanitize_replaces_password():
    result = sanitize({'password': 'secret'})
    assert result['password'] == 'your_password'

def test_sanitize_replaces_bot_token():
    result = sanitize({'bot_token': 'xoxb-real'})
    assert result['bot_token'] == 'your_bot_token'

def test_sanitize_preserves_non_credentials():
    result = sanitize({'host': 'smtp.example.com'})
    assert result['host'] == 'smtp.example.com'

def test_sanitize_preserves_integers():
    result = sanitize({'port': 587})
    assert result['port'] == 587

def test_sanitize_nested_dict():
    resolved = resolve_app_config(FIXTURE, 'flatdb', 'local')
    example = sanitize(resolved)
    assert example['db']['password'] == 'your_password'
    assert example['smtp']['password'] == 'your_password'
    assert example['slack']['bot_token'] == 'your_bot_token'
    assert example['smtp']['host'] == 'smtp.example.com'
    assert example['app']['base_url'] == 'http://localhost/flatdb'


# ── generate_update_md ────────────────────────────────────────────────────────

def test_update_md_mentions_legacy_path():
    md = generate_update_md('flatdb', 'config.ini')
    assert 'config.ini' in md

def test_update_md_mentions_app_name():
    md = generate_update_md('flatdb', 'config.ini')
    assert 'flatdb' in md

def test_update_md_mentions_new_files():
    md = generate_update_md('flatdb', 'config.ini')
    assert 'config.yaml' in md
    assert 'config.example.yaml' in md

def test_update_md_no_legacy():
    md = generate_update_md('flatdb', None)
    assert 'config.yaml' in md
```

- [ ] **Step 2: Run tests — expect failures**

```bash
pytest tests/ -v 2>&1 | head -20
```

Expected: `ModuleNotFoundError: No module named 'generate'` — correct, file doesn't exist yet.

---

### Task 4: Implement `generate.py` — make all tests pass

**Files:**
- Create: `mcp/generate.py`

- [ ] **Step 1: Create `generate.py`**

```python
"""
Central config generator for mcp/.
Reads config.yaml, generates per-app config files.

Usage:
    python3 generate.py                                    # all apps, first target
    python3 generate.py --app energie                      # one app, first target
    python3 generate.py --app energie --target akadbrain   # one app, one target
"""

import argparse
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).parent
APPS_ROOT = REPO_ROOT.parent

# Values for these keys are replaced with `your_<key>` in config.example.yaml
CREDENTIAL_KEYS = frozenset({
    'password', 'pass', 'bot_token', 'ftp_password',
    'ftp_user', 'api_key', 'secret', 'token',
})


# ── Resolution helpers ────────────────────────────────────────────────────────

def resolve_db(db: dict | None, target: str) -> dict | None:
    """
    Return the resolved db block for `target`.
    Flat dict  → return as-is (same credentials for all targets).
    Nested dict → return db[target] (per-target credentials).
    """
    if db is None:
        return None
    if any(isinstance(v, dict) for v in db.values()):
        return db.get(target)
    return db


def resolve_app_config(config: dict, app_name: str, target: str) -> dict:
    """
    Merge shared + per-app config, resolve for a specific target.
    Returns a flat dict ready to be written as config.yaml.
    """
    shared = config['shared']
    app = config['apps'][app_name]
    result = {}

    # DB ──────────────────────────────────────────────────────────────────────
    db = resolve_db(app.get('db'), target)
    if db is not None:
        result['db'] = db

    # Auth DB ─────────────────────────────────────────────────────────────────
    auth_db = app.get('auth_db')
    if auth_db == 'shared':
        result['auth_db'] = shared['auth_db']
    elif auth_db is not None:
        result['auth_db'] = auth_db

    # SMTP: shared credentials + app overrides (from, from_name, or full server) ──
    smtp = dict(shared['smtp'])
    smtp.update(app.get('smtp', {}))
    result['smtp'] = smtp

    # Slack: shared bot_token + app channel_id ────────────────────────────────
    if 'slack' in shared or 'slack' in app:
        slack = dict(shared.get('slack', {}))
        slack.update(app.get('slack', {}))
        result['slack'] = slack

    # App section: resolve base_url for target ────────────────────────────────
    app_section = {}
    base_url = app.get('app', {}).get('base_url')
    if isinstance(base_url, dict):
        app_section['base_url'] = base_url.get(target, base_url.get('local'))
    elif base_url is not None:
        app_section['base_url'] = base_url
    if app_section:
        result['app'] = app_section

    # App-specific extras (hofer, wienenergie, custom sections …) ─────────────
    skip = {'targets', 'deploy', 'db', 'smtp', 'slack', 'app', 'legacy_config', 'auth_db'}
    for key, value in app.items():
        if key not in skip:
            result[key] = value

    return result


# ── Sanitiser ─────────────────────────────────────────────────────────────────

def sanitize(value, key: str = '') -> object:
    """
    Recursively replace credential values with `your_<key>` placeholders.
    Call as sanitize(resolved_dict) to process a whole config.
    """
    if isinstance(value, dict):
        return {k: sanitize(v, k) for k, v in value.items()}
    if isinstance(value, list):
        return [sanitize(v) for v in value]
    if isinstance(value, str) and key in CREDENTIAL_KEYS:
        return f'your_{key}'
    return value


# ── update.md generation ─────────────────────────────────────────────────────

def generate_update_md(app_name: str, legacy_config: str | None) -> str:
    legacy_note = f'`{legacy_config}`' if legacy_config else 'an untracked config format'
    legacy_rm = f'\n- [ ] Remove old config file (`{legacy_config}`) and its example from the repo' \
        if legacy_config else ''
    return f"""\
# Config Migration Brief

> Generated by mcp/generate.py — delete this file when migration is complete.

## Current state

This app currently reads config from {legacy_note}.
It should be updated to read from `config.yaml` (YAML) using the structure
defined in `config.example.yaml`.

## Checklist

- [ ] Add a YAML library if not present:
  - PHP: `composer require symfony/yaml`
  - Python: `pip install pyyaml` (usually already available)
- [ ] Add `config.yaml` to `.gitignore` (if not already)
- [ ] Replace all references to the old config loader with a YAML loader
- [ ] Update `scripts/deploy.sh` to expect `config.yaml` (remove credential heredocs){legacy_rm}
- [ ] Delete this file when migration is complete

## New config structure

See `config.example.yaml` for the full expected shape.

## Notes

- `config.yaml` is generated by `mcp/generate.py --app {app_name} --target <target>`
- Do not edit `config.yaml` manually — it is overwritten on every deploy
- `config.example.yaml` is safe to commit; it contains only placeholder values
"""


# ── File writing ──────────────────────────────────────────────────────────────

def write_app_files(config: dict, app_name: str, target: str) -> None:
    """Generate and write config.yaml, config.example.yaml, update.md for one app+target."""
    app_dir = APPS_ROOT / app_name
    if not app_dir.is_dir():
        print(f'  WARNING: {app_dir} does not exist — skipping', file=sys.stderr)
        return

    resolved = resolve_app_config(config, app_name, target)
    app_cfg = config['apps'][app_name]

    # config.yaml — real credentials
    config_path = app_dir / 'config.yaml'
    with open(config_path, 'w') as f:
        f.write(f'# Generated by mcp/generate.py — do not edit manually\n')
        f.write(f'# Target: {target}\n\n')
        yaml.dump(resolved, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    print(f'  wrote {app_name}/config.yaml')

    # config.example.yaml — sanitized placeholders
    example_path = app_dir / 'config.example.yaml'
    with open(example_path, 'w') as f:
        f.write('# Config template — copy to config.yaml and fill in your values\n\n')
        yaml.dump(sanitize(resolved), f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    print(f'  wrote {app_name}/config.example.yaml')

    # update.md — migration brief for local Claude
    update_path = app_dir / 'update.md'
    with open(update_path, 'w') as f:
        f.write(generate_update_md(app_name, app_cfg.get('legacy_config')))
    print(f'  wrote {app_name}/update.md')


# ── CLI ───────────────────────────────────────────────────────────────────────

def load_config(path: Path = None) -> dict:
    path = path or REPO_ROOT / 'config.yaml'
    with open(path) as f:
        return yaml.safe_load(f)


def main() -> None:
    parser = argparse.ArgumentParser(
        description='Generate per-app config files from mcp/config.yaml'
    )
    parser.add_argument('--app', help='App name (default: all apps)')
    parser.add_argument('--target', help='Deploy target (default: first target for each app)')
    args = parser.parse_args()

    config = load_config()
    apps = config['apps']

    if args.app and args.app not in apps:
        print(f'ERROR: unknown app "{args.app}". Known: {", ".join(apps)}', file=sys.stderr)
        sys.exit(1)

    app_names = [args.app] if args.app else list(apps.keys())

    for app_name in app_names:
        app_cfg = apps[app_name]
        targets = [args.target] if args.target else [app_cfg['targets'][0]]
        for target in targets:
            print(f'\n→ {app_name} ({target})')
            write_app_files(config, app_name, target)


if __name__ == '__main__':
    main()
```

- [ ] **Step 2: Run tests — expect all to pass**

```bash
pytest tests/ -v
```

Expected output: all tests green, `X passed` with no failures.

- [ ] **Step 3: Commit**

```bash
git add generate.py tests/test_generate.py
git commit -m "feat: add generate.py with full test coverage"
```

---

### Task 5: Run generator and verify app output

**Files:** generates into `../energie/`, `../wlmonitor/`, `../zeiterfassung/`, `../simplechat-2.1/`

- [ ] **Step 1: Run generator for all apps**

```bash
python3 generate.py
```

Expected: prints `→ energie (local)`, `→ wlmonitor (local)`, `→ zeiterfassung (local)`, `→ simplechat-2.1 (local)` with three `wrote` lines each.

- [ ] **Step 2: Spot-check energie output**

```bash
cat ../energie/config.yaml
```

Expected: contains real `password` values, `base_url: http://localhost/energie.test`, `bot_token` present, no `targets:` or `deploy:` keys.

- [ ] **Step 3: Spot-check example sanitisation**

```bash
grep password ../energie/config.example.yaml
```

Expected: `password: your_password` — no real credentials.

- [ ] **Step 4: Spot-check update.md**

```bash
head -10 ../energie/update.md
```

Expected: mentions `config.ini` and `energie`.

- [ ] **Step 5: Run for akadbrain target and verify base_url changes**

```bash
python3 generate.py --app energie --target akadbrain
grep base_url ../energie/config.yaml
```

Expected: `base_url: https://energie.eriks.cloud`

- [ ] **Step 6: Commit**

```bash
git commit -m "chore: verify generator output for all apps"
```

No files to stage — output goes into app repos, not mcp/.

---

### Task 6: Write `lib/common.sh`

**Files:**
- Create: `mcp/lib/common.sh`

- [ ] **Step 1: Create `lib/common.sh`**

```bash
mkdir -p lib
```

```bash
#!/usr/bin/env bash
# lib/common.sh — shared output helpers for mcp scripts
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ok()   { printf '\033[0;32m✓ %s\033[0m\n' "$*"; }
err()  { printf '\033[0;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
info() { printf '\033[0;36m%s\033[0m\n' "$*"; }
ask()  { printf '\033[0;33m%s\033[0m ' "$*"; }
warn() { printf '\033[0;33mWARNING: %s\033[0m\n' "$*"; }
```

- [ ] **Step 2: Verify**

```bash
bash -c 'source lib/common.sh; ok "common.sh works"'
```

Expected: green `✓ common.sh works`

- [ ] **Step 3: Commit**

```bash
git add lib/common.sh
git commit -m "feat: add lib/common.sh output helpers"
```

---

### Task 7: Write `lib/rsync.sh`

**Files:**
- Create: `mcp/lib/rsync.sh`

- [ ] **Step 1: Create `lib/rsync.sh`**

```bash
#!/usr/bin/env bash
# lib/rsync.sh — shared rsync deploy logic
#
# Usage:
#   bash lib/rsync.sh local  <src> <dest>
#   bash lib/rsync.sh ssh    <src> <dest> <ssh_user> <ssh_host> <ssh_key>

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

MODE="${1:?Usage: rsync.sh local|ssh <src> <dest> [ssh_user ssh_host ssh_key]}"
SRC="${2:?missing src}"
DEST="${3:?missing dest}"

RSYNC_OPTS=(
    --archive
    --verbose
    --delete
    --delete-excluded
    --copy-links
    --exclude=".git/"
    --exclude=".gitignore"
    --exclude=".DS_Store"
    --exclude=".claude/"
    --exclude=".claude.json"
    --exclude="CLAUDE.md"
    --exclude="*.md"
    --exclude="update.md"
    --exclude="phpunit.xml"
    --exclude="composer.json"
    --exclude="composer.lock"
    --exclude="package.json"
    --exclude="tailwind.config.js"
    --exclude="tailwindcss"
    --exclude="scripts/"
    --exclude="tests/"
    --exclude="deprecated/"
    --exclude="docs/"
    --exclude="bin/"
    --exclude="db/"
    --exclude="config/"
    --exclude="data/"
    --exclude="var/"
    --exclude="config.yaml"
    --exclude="config.example.yaml"
    --exclude="__pycache__/"
    --exclude="*.pyc"
)

case "$MODE" in
    local)
        info "Syncing to $DEST ..."
        mkdir -p "$DEST"
        rsync "${RSYNC_OPTS[@]}" "$SRC/" "$DEST/"
        ok "Synced to $DEST"
        ;;

    ssh)
        SSH_USER="${4:?missing ssh_user}"
        SSH_HOST="${5:?missing ssh_host}"
        SSH_KEY="${6:-}"
        SSH_CMD="ssh"
        [[ -n "$SSH_KEY" ]] && SSH_CMD="ssh -i ${SSH_KEY} -o IdentitiesOnly=yes"
        REMOTE="${SSH_USER}@${SSH_HOST}"

        info "Syncing to ${REMOTE}:${DEST} ..."
        rsync "${RSYNC_OPTS[@]}" \
            -e "$SSH_CMD" \
            "$SRC/" \
            "${REMOTE}:${DEST}/"
        ok "Synced to ${REMOTE}:${DEST}"
        ;;

    *)
        err "Unknown mode '$MODE'. Use 'local' or 'ssh'."
        ;;
esac
```

- [ ] **Step 2: Make executable**

```bash
chmod +x lib/rsync.sh
```

- [ ] **Step 3: Dry-run test (local mode)**

```bash
bash lib/rsync.sh local /tmp/rsync_test_src /tmp/rsync_test_dest 2>&1 || true
```

Expected: completes (src may not exist — rsync will fail gracefully with an error message but script syntax is valid).

- [ ] **Step 4: Commit**

```bash
git add lib/rsync.sh
git commit -m "feat: add lib/rsync.sh with local and SSH modes"
```

---

### Task 8: Write `lib/ftp.sh`

**Files:**
- Create: `mcp/lib/ftp.sh`

- [ ] **Step 1: Create `lib/ftp.sh`**

```bash
#!/usr/bin/env bash
# lib/ftp.sh — FTP deploy for world4you target
#
# Usage:
#   bash lib/ftp.sh <ftp_host> <ftp_user> <ftp_password> <src_dir> <ftp_base_dir> <app_name>
#
# Delegates to <app>/scripts/ftp_deploy.php if present (wlmonitor).
# Falls back to lftp mirror if not.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

FTP_HOST="${1:?missing ftp_host}"
FTP_USER="${2:?missing ftp_user}"
FTP_PASS="${3:?missing ftp_password}"
SRC="${4:?missing src_dir}"
FTP_BASE_DIR="${5:?missing ftp_base_dir}"
APP_NAME="${6:?missing app_name}"

FTP_DEPLOY_PHP="$SRC/scripts/ftp_deploy.php"

if [[ -f "$FTP_DEPLOY_PHP" ]]; then
    info "Using $APP_NAME/scripts/ftp_deploy.php ..."
    php "$FTP_DEPLOY_PHP" world4you
    ok "FTP deploy complete via ftp_deploy.php"
else
    command -v lftp >/dev/null 2>&1 || err "lftp not found. Install: brew install lftp"
    info "Uploading via lftp to ${FTP_HOST}${FTP_BASE_DIR} ..."
    lftp -u "${FTP_USER},${FTP_PASS}" "${FTP_HOST}" <<LFTP_SCRIPT
set ssl:verify-certificate false
mirror --reverse --delete --verbose \
    --exclude ".git/" \
    --exclude "config/" \
    --exclude "data/" \
    --exclude "tests/" \
    --exclude "docs/" \
    --exclude "deprecated/" \
    --exclude "*.md" \
    --exclude "config.yaml" \
    --exclude "config.example.yaml" \
    "$SRC/" "$FTP_BASE_DIR"
bye
LFTP_SCRIPT
    ok "FTP upload complete"
fi
```

- [ ] **Step 2: Make executable**

```bash
chmod +x lib/ftp.sh
```

- [ ] **Step 3: Verify syntax**

```bash
bash -n lib/ftp.sh && echo "syntax ok"
```

Expected: `syntax ok`

- [ ] **Step 4: Commit**

```bash
git add lib/ftp.sh
git commit -m "feat: add lib/ftp.sh for world4you FTP deploy"
```

---

### Task 9: Write `deploy.py` — core + CLI mode

**Files:**
- Create: `mcp/deploy.py`

- [ ] **Step 1: Create `deploy.py`**

```python
"""
mcp deploy — central deploy entry point.

Usage:
    python3 deploy.py                          # TUI mode (arrow-key menus)
    python3 deploy.py <app> <target>           # CLI mode (non-interactive)
"""

import argparse
import subprocess
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).parent
APPS_ROOT = REPO_ROOT.parent
LIB = REPO_ROOT / 'lib'


# ── Config ────────────────────────────────────────────────────────────────────

def load_config() -> dict:
    path = REPO_ROOT / 'config.yaml'
    with open(path) as f:
        return yaml.safe_load(f)


# ── Generate ──────────────────────────────────────────────────────────────────

def run_generate(app: str, target: str) -> None:
    """Call generate.py for the given app+target."""
    subprocess.run(
        [sys.executable, str(REPO_ROOT / 'generate.py'), '--app', app, '--target', target],
        check=True,
    )


# ── Deploy dispatch ───────────────────────────────────────────────────────────

def get_deploy_method(config: dict, target: str) -> str:
    """Return 'ftp', 'rsync_ssh', or 'rsync_local'."""
    target_cfg = config['shared']['targets'].get(target, {})
    if 'ftp_host' in target_cfg:
        return 'ftp'
    if 'ssh_host' in target_cfg:
        return 'rsync_ssh'
    return 'rsync_local'


def deploy_rsync_local(config: dict, app: str, target: str) -> None:
    dest = config['apps'][app]['deploy'][target]['dest']
    src = str(APPS_ROOT / app)
    subprocess.run(['bash', str(LIB / 'rsync.sh'), 'local', src, dest], check=True)


def deploy_rsync_ssh(config: dict, app: str, target: str) -> None:
    dest = config['apps'][app]['deploy'][target]['dest']
    src = str(APPS_ROOT / app)
    t = config['shared']['targets'][target]
    subprocess.run(
        ['bash', str(LIB / 'rsync.sh'), 'ssh', src, dest,
         t['ssh_user'], t['ssh_host'], t.get('ssh_key', '')],
        check=True,
    )


def deploy_ftp(config: dict, app: str, target: str) -> None:
    t = config['shared']['targets'][target]
    src = str(APPS_ROOT / app)
    ftp_base_dir = config['apps'][app]['deploy'][target].get('ftp_base_dir', '/')
    subprocess.run(
        ['bash', str(LIB / 'ftp.sh'),
         t['ftp_host'], t['ftp_user'], t['ftp_password'],
         src, ftp_base_dir, app],
        check=True,
    )


def run_migrations(app: str) -> None:
    """Run migrate.php if it exists in the app's scripts/ directory."""
    migrate = APPS_ROOT / app / 'scripts' / 'migrate.php'
    if migrate.exists():
        print(f'  Running migrations for {app}...')
        subprocess.run(['php', str(migrate)], check=True)


def do_deploy(config: dict, app: str, target: str) -> None:
    method = get_deploy_method(config, target)
    if method == 'ftp':
        deploy_ftp(config, app, target)
    elif method == 'rsync_ssh':
        deploy_rsync_ssh(config, app, target)
    else:
        deploy_rsync_local(config, app, target)
    run_migrations(app)


# ── CLI mode ──────────────────────────────────────────────────────────────────

def cli_deploy(app: str, target: str) -> None:
    config = load_config()
    apps = config['apps']

    if app not in apps:
        print(f'ERROR: unknown app "{app}". Known: {", ".join(apps)}', file=sys.stderr)
        sys.exit(1)

    valid_targets = apps[app]['targets']
    if target not in valid_targets:
        print(
            f'ERROR: "{target}" is not valid for {app}. '
            f'Valid targets: {", ".join(valid_targets)}',
            file=sys.stderr,
        )
        sys.exit(1)

    print(f'\n→ Generating config: {app} ({target})...')
    run_generate(app, target)
    print(f'→ Deploying {app} → {target}...')
    do_deploy(config, app, target)
    print(f'\n✓ Done: {app} → {target}')


# ── TUI mode ──────────────────────────────────────────────────────────────────

def tui_deploy() -> None:
    import questionary
    from rich.console import Console
    from rich.panel import Panel

    console = Console()
    config = load_config()
    apps = list(config['apps'].keys())

    console.print(Panel(
        '[bold cyan]mcp deploy[/bold cyan]\nCentral deployment tool',
        expand=False,
    ))

    app = questionary.select('Select app:', choices=apps).ask()
    if not app:
        sys.exit(0)

    targets = config['apps'][app]['targets']
    target = questionary.select('Select target:', choices=targets).ask()
    if not target:
        sys.exit(0)

    if target != 'local':
        confirmed = questionary.confirm(
            f'Deploy {app} → {target}? This affects a live system.',
            default=False,
        ).ask()
        if not confirmed:
            console.print('[yellow]Aborted.[/yellow]')
            sys.exit(0)

    console.print(f'\n[cyan]→ Generating config: {app} ({target})...[/cyan]')
    run_generate(app, target)
    console.print(f'[cyan]→ Deploying {app} → {target}...[/cyan]')
    do_deploy(config, app, target)
    console.print(f'\n[green]✓ Done: {app} → {target}[/green]')


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description='Deploy apps — no args for TUI, or: deploy.py <app> <target>'
    )
    parser.add_argument('app', nargs='?', help='App name')
    parser.add_argument('target', nargs='?', help='Deploy target')
    args = parser.parse_args()

    if args.app and args.target:
        cli_deploy(args.app, args.target)
    elif args.app or args.target:
        parser.error('Provide both <app> and <target>, or neither (for TUI mode).')
    else:
        tui_deploy()


if __name__ == '__main__':
    main()
```

- [ ] **Step 2: Verify CLI argument validation**

```bash
python3 deploy.py unknownapp local 2>&1
```

Expected: `ERROR: unknown app "unknownapp". Known: energie, wlmonitor, zeiterfassung, simplechat-2.1`

```bash
python3 deploy.py energie badtarget 2>&1
```

Expected: `ERROR: "badtarget" is not valid for energie. Valid targets: local, akadbrain`

- [ ] **Step 3: Commit**

```bash
git add deploy.py
git commit -m "feat: add deploy.py with TUI and CLI modes"
```

---

### Task 10: Write `deploy.sh`

**Files:**
- Create: `mcp/deploy.sh`

- [ ] **Step 1: Create `deploy.sh`**

```bash
#!/usr/bin/env bash
# deploy.sh — thin wrapper around deploy.py
# Usage: bash deploy.sh [app] [target]
set -euo pipefail
python3 "$(dirname "$0")/deploy.py" "$@"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x deploy.sh
```

- [ ] **Step 3: Verify**

```bash
bash deploy.sh unknownapp local 2>&1
```

Expected: same error as `python3 deploy.py unknownapp local`

- [ ] **Step 4: Commit**

```bash
git add deploy.sh
git commit -m "feat: add deploy.sh wrapper"
```

---

### Task 11: Update `.gitignore` in each app repo

Each app must ignore `config.yaml` (real credentials) and `update.md` (contains app-internal paths — optional but clean).

- [ ] **Step 1: energie**

Add to `/Users/erikr/Git/energie/.gitignore` (create if missing):

```
config.yaml
update.md
```

Check it's not already tracked:

```bash
git -C ../energie ls-files config.yaml update.md
```

Expected: no output (neither file is tracked).

- [ ] **Step 2: wlmonitor**

Add to `/Users/erikr/Git/wlmonitor/.gitignore`:

```
config.yaml
update.md
```

```bash
git -C ../wlmonitor ls-files config.yaml update.md
```

Expected: no output.

- [ ] **Step 3: zeiterfassung**

Add to `/Users/erikr/Git/zeiterfassung/.gitignore`:

```
config.yaml
update.md
```

```bash
git -C ../zeiterfassung ls-files config.yaml update.md
```

Expected: no output.

- [ ] **Step 4: simplechat-2.1**

Add to `/Users/erikr/Git/simplechat-2.1/.gitignore`:

```
config.yaml
update.md
```

```bash
git -C ../simplechat-2.1 ls-files config.yaml update.md
```

Expected: no output.

- [ ] **Step 5: Commit .gitignore changes in each app (separately)**

```bash
git -C ../energie add .gitignore && git -C ../energie commit -m "chore: ignore generated config.yaml and update.md"
git -C ../wlmonitor add .gitignore && git -C ../wlmonitor commit -m "chore: ignore generated config.yaml and update.md"
git -C ../zeiterfassung add .gitignore && git -C ../zeiterfassung commit -m "chore: ignore generated config.yaml and update.md"
git -C ../simplechat-2.1 add .gitignore && git -C ../simplechat-2.1 commit -m "chore: ignore generated config.yaml and update.md"
```

Also commit the generated `config.example.yaml` files in each app:

```bash
git -C ../energie add config.example.yaml && git -C ../energie commit -m "chore: add generated config.example.yaml"
git -C ../wlmonitor add config.example.yaml && git -C ../wlmonitor commit -m "chore: add generated config.example.yaml"
git -C ../zeiterfassung add config.example.yaml && git -C ../zeiterfassung commit -m "chore: add generated config.example.yaml"
git -C ../simplechat-2.1 add config.example.yaml && git -C ../simplechat-2.1 commit -m "chore: add generated config.example.yaml"
```

And `update.md` (the migration brief — committed so local Claude instances see it):

```bash
git -C ../energie add update.md && git -C ../energie commit -m "chore: add config migration brief"
git -C ../wlmonitor add update.md && git -C ../wlmonitor commit -m "chore: add config migration brief"
git -C ../zeiterfassung add update.md && git -C ../zeiterfassung commit -m "chore: add config migration brief"
git -C ../simplechat-2.1 add update.md && git -C ../simplechat-2.1 commit -m "chore: add config migration brief"
```

---

### Task 12: Final mcp commit and end-to-end smoke test

- [ ] **Step 1: Run full test suite one last time**

```bash
pytest tests/ -v
```

Expected: all tests pass.

- [ ] **Step 2: End-to-end smoke test — generate all apps**

```bash
python3 generate.py
```

Expected: 4 apps, each producing 3 files, no warnings.

- [ ] **Step 3: Verify config.yaml is gitignored**

```bash
git status
```

Expected: `config.yaml` does NOT appear in the output.

- [ ] **Step 4: Final mcp commit**

```bash
git add generate.py deploy.py deploy.sh lib/ tests/ requirements.txt requirements-dev.txt docs/
git commit -m "feat: complete mcp config centralisation and deploy tooling"
```

- [ ] **Step 5: Smoke test TUI (visual check)**

```bash
python3 deploy.py
```

Expected: rich panel appears, arrow-key app menu shows `energie`, `wlmonitor`, `zeiterfassung`, `simplechat-2.1`. Press Ctrl+C to exit without deploying.

---

## Notes

- **`world4you` FTP credentials** (`ftp_user`, `ftp_password` in `shared.targets.world4you`) are marked `FILL_IN` in Task 2. Fill them in from the real world4you account before deploying wlmonitor to world4you.
- **`simplechat-2.1` has no DB or auth credentials** — its `config.yaml` will only contain `smtp` and `app.base_url`. That is intentional.
- **`zeiterfassung` uses a unix socket** for DB (`socket: /tmp/mysql.sock`). The `update.md` instructs local Claude to use `PDO` with the socket DSN. The per-app `config.php` migration is the primary task of each app's local Claude session.
- **Energie is mixed PHP+Python** — its `update.md` should prompt the local Claude to update both `energie.py` (Python, reads `config.ini`) and any PHP bootstrap in `web/` or `inc/`.
