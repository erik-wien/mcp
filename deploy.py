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

def get_deploy_method(config: dict, app: str, target: str) -> str:
    """Return 'ftp', 'rsync_ssh', or 'rsync_local'.

    If the target supports both FTP and SSH (world4you does), prefer SSH when
    the app ships a scripts/ssh_deploy.php. Otherwise fall back to FTP.
    """
    target_cfg = config['shared']['targets'].get(target, {})
    has_ssh = 'ssh_host' in target_cfg
    has_ftp = 'ftp_host' in target_cfg
    ssh_deploy_php = APPS_ROOT / app / 'scripts' / 'ssh_deploy.php'
    if has_ssh and ssh_deploy_php.exists():
        return 'rsync_ssh'
    if has_ftp:
        return 'ftp'
    if has_ssh:
        return 'rsync_ssh'
    return 'rsync_local'


def deploy_rsync_local(config: dict, app: str, target: str) -> None:
    dest = config['apps'][app]['deploy'][target]['dest']
    src = str(APPS_ROOT / app)
    subprocess.run(['bash', str(LIB / 'rsync.sh'), 'local', src, dest], check=True)


def deploy_rsync_ssh(config: dict, app: str, target: str) -> None:
    src = str(APPS_ROOT / app)
    # When the app ships scripts/ssh_deploy.php, rsync.sh delegates to it and
    # ignores dest/ssh_* args — so we don't need them here either. The per-app
    # script reads everything (including the remote path) from its own
    # config.yaml.
    ssh_deploy_php = APPS_ROOT / app / 'scripts' / 'ssh_deploy.php'
    if ssh_deploy_php.exists():
        subprocess.run(
            ['bash', str(LIB / 'rsync.sh'), 'ssh', src, '__delegated__'],
            check=True,
        )
        return
    dest = config['apps'][app]['deploy'][target]['dest']
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
    method = get_deploy_method(config, app, target)
    if method == 'ftp':
        deploy_ftp(config, app, target)
        # lib/ftp.sh delegates to scripts/ftp_deploy.php when present, which
        # runs its own remote migrations via an HTTP runner. Only call
        # run_migrations for the generic lftp-mirror path — otherwise the
        # local migrate.php would try to hit a MySQL host that isn't
        # reachable from the developer machine.
        if not (APPS_ROOT / app / 'scripts' / 'ftp_deploy.php').exists():
            run_migrations(app)
    elif method == 'rsync_ssh':
        deploy_rsync_ssh(config, app, target)
        # rsync_ssh delegates to scripts/ssh_deploy.php when present, which
        # runs its own remote migrations over SSH. Only call run_migrations
        # for the generic lib/rsync.sh path.
        if not (APPS_ROOT / app / 'scripts' / 'ssh_deploy.php').exists():
            run_migrations(app)
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
    try:
        do_deploy(config, app, target)
    finally:
        if target != 'local':
            print(f'→ Restoring local config: {app}...')
            run_generate(app, 'local')
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
