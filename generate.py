"""
Central config generator for mcp/.
Reads config.yaml, generates per-app config files.

Usage:
    python3 generate.py                                    # all apps, first target
    python3 generate.py --app energie                      # one app, first target
    python3 generate.py --app energie --target akadbrain   # one app, one target
"""

import argparse
import copy
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).parent
APPS_ROOT = REPO_ROOT.parent

# Values for these keys are replaced with `your_<key>` in config.example.yaml
CREDENTIAL_KEYS = frozenset({
    'password', 'pass', 'bot_token',
    'api_key', 'secret', 'token',
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
    result = {'target': target}

    # DB ──────────────────────────────────────────────────────────────────────
    db = resolve_db(app.get('db'), target)
    if db is not None:
        result['db'] = db

    # Deploy ──────────────────────────────────────────────────────────────────
    # Merge shared.targets[target] (ssh_host, ssh_user, web_root, …) with
    # per-app deploy[target] (ftp_base_dir = world4you remote path, dest, …).
    shared_target = (shared.get('targets') or {}).get(target, {}) or {}
    app_deploy = (app.get('deploy') or {}).get(target, {}) or {}
    deploy_block = {**shared_target, **app_deploy}
    if deploy_block:
        result['deploy'] = deploy_block

    # Auth DB ─────────────────────────────────────────────────────────────────
    auth_db = app.get('auth_db')
    if auth_db is not None:
        result['auth_db'] = resolve_db(auth_db, target)

    # Privileged delete connection (Spec 2026-07-25 §3.5) ─────────────────────
    # Shared across all apps — it is one narrowly-privileged user (authadmin),
    # not one per app. admin_delete_user() uses it because the app users
    # deliberately lack DELETE on auth_accounts (Auth-Rules §8).
    auth_admin_db = shared.get('auth_admin_db')
    if auth_admin_db is not None:
        result['auth_admin_db'] = resolve_db(auth_admin_db, target)

    # Slack: shared bot_token + app channel_id ────────────────────────────────
    if 'slack' in shared or 'slack' in app:
        slack = dict(shared.get('slack', {}))
        slack.update(app.get('slack', {}))
        result['slack'] = slack

    # (Replication config removed 2026-07-16, TASK-22: biblio's replication
    # targets now live in the DB table bi_repl_ziel, managed via the admin tab —
    # no longer generated from config.yaml.)

    # App section: name, support_email, base_url for target ──────────────────
    app_block = app.get('app', {}) or {}
    app_section = {}
    if 'name' in app_block:
        app_section['name'] = app_block['name']
    if 'support_email' in app_block:
        app_section['support_email'] = app_block['support_email']
    if 'color' in app_block:
        app_section['color'] = app_block['color']
    base_url = app_block.get('base_url')
    if isinstance(base_url, dict):
        app_section['base_url'] = base_url.get(target, base_url.get('local'))
    elif base_url is not None:
        app_section['base_url'] = base_url
    app_section['env'] = target
    result['app'] = app_section

    # App-specific extras (hofer, wienenergie, custom sections …) ─────────────
    skip = {'targets', 'deploy', 'db', 'smtp', 'slack', 'app', 'legacy_config', 'auth_db'}
    for key, value in app.items():
        if key not in skip:
            result[key] = value

    # Per-target values inside the resolver block: a resolver value that is a
    # dict keyed by target names collapses to this target's value (like base_url
    # above) — e.g. omlx_url set only for `local`, empty on prod. Everything else
    # stays verbatim. Deep-copy so the shared config dict is never mutated across
    # the per-target loop.
    if isinstance(result.get('resolver'), dict):
        known = set(app.get('targets') or [])
        resolver = copy.deepcopy(result['resolver'])
        for k, v in resolver.items():
            if isinstance(v, dict) and (set(v.keys()) & known):
                resolver[k] = v.get(target, v.get('local'))
        result['resolver'] = resolver

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
    if isinstance(value, str) and any(credword in key for credword in CREDENTIAL_KEYS):
        return f'your_{key}'
    return value


# ── update.md generation ──────────────────────────────────────────────────────

def generate_update_md(app_name: str, legacy_config: str | None) -> str:
    legacy_note = f'`{legacy_config}`' if legacy_config else 'an untracked config format'
    legacy_rm = (
        f'\n- [ ] Remove old config file (`{legacy_config}`) and its example from the repo'
        if legacy_config else ''
    )
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
        f.write('# Generated by mcp/generate.py — do not edit manually\n')
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

    # Per-app logo/favicon SVGs are no longer generated here: the jardyx brand
    # logos live centrally in css_library/logos/ (single source, one colour file
    # per app) and each app references them via /css/shared/logos/. See
    # mcp/docs/2026-07-12-task-19-library-harmonisierung-design.md.


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
