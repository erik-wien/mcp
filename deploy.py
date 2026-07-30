"""
mcp deploy — central deploy entry point.

Usage:
    python3 deploy.py                          # TUI mode (arrow-key menus)
    python3 deploy.py <app> <target>           # CLI mode (non-interactive)
    python3 deploy.py --mail-ini <target>      # write shared jardyx-mail.ini only
"""

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).parent
APPS_ROOT = REPO_ROOT.parent
LIB = REPO_ROOT / 'lib'

# Host-level SMTP config consumed by erikr/auth load_mail_config().
# Local + akadbrain are macOS + Homebrew → /opt/homebrew/etc.
MAIL_INI_PATHS = {
    'local':     '/opt/homebrew/etc/jardyx-mail.ini',
    'akadbrain': '/opt/homebrew/etc/jardyx-mail.ini',
}

# Targets that get a PER-APP mail.ini next to the app's config.yaml instead of
# one host-level file. world4you is shared hosting: neither /etc nor /opt is
# writable, AND open_basedir confines PHP to the site's web tree plus ~/tmp —
# so even a file in the home directory would be unreadable. The app directory
# is inside that tree but above the document root (…/<app>/web), so it is not
# served: …/<app>/config.yaml answers HTTP 404 (verified 2026-07-28).
#
# erikr/auth finds it via AUTH_MAIL_CONFIG_PATH, which each app defines in
# inc/initialize.php. See docs/jardyx-mail-ini-prod.md.
#
# Until 2026-07-28 this file was never placed on world4you at all, so no app
# there could send invitations or password resets. The comment here pointed at
# a documentation file that did not exist. auth TASK-6.
APP_MAIL_INI_TARGETS = {'world4you'}


# ── Config ────────────────────────────────────────────────────────────────────

def load_config() -> dict:
    path = REPO_ROOT / 'config.yaml'
    with open(path) as f:
        return yaml.safe_load(f)


# ── SSH-Vorabpruefung ─────────────────────────────────────────────────────────

def _ssh_reachable(host: str, user: str, key: str, timeout: int = 6) -> bool:
    """True, wenn eine BatchMode-SSH-Sitzung zustande kommt."""
    cmd = ['ssh', '-o', 'BatchMode=yes', '-o', f'ConnectTimeout={timeout}']
    if key:
        cmd += ['-i', str(Path(key).expanduser())]
    cmd += [f'{user}@{host}' if user else host, 'true']
    try:
        return subprocess.run(cmd, capture_output=True, timeout=timeout + 6).returncode == 0
    except (subprocess.TimeoutExpired, OSError):
        return False


def _resolve_ipv4(host: str) -> str | None:
    """IPv4 zu einem Hostnamen, per ping ermittelt (deckt auch mDNS/.local ab).

    Bewusst NICHT socket.gethostbyname(): das scheitert an genau demselben
    DNS-Problem, das wir umgehen wollen, wenn ~/.ssh/config den Namen auf einen
    anderen (nicht aufloesbaren) Hostnamen umschreibt. ping loest den ORIGINALEN
    Namen auf, unbeeinflusst von der SSH-Konfiguration.
    """
    try:
        r = subprocess.run(['ping', '-c', '1', '-t', '2', host],
                           capture_output=True, text=True, timeout=8)
    except (subprocess.TimeoutExpired, OSError):
        return None
    m = re.search(r'\((\d{1,3}(?:\.\d{1,3}){3})\)', r.stdout)
    return m.group(1) if m else None


def _has_path(host: str, user: str, key: str, path: str) -> bool:
    """True, wenn $path auf dem Host als Verzeichnis existiert."""
    cmd = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=6']
    if key:
        cmd += ['-i', str(Path(key).expanduser())]
    cmd += [f'{user}@{host}' if user else host, f'test -d {path}']
    try:
        return subprocess.run(cmd, capture_output=True, timeout=15).returncode == 0
    except (subprocess.TimeoutExpired, OSError):
        return False


def preflight_ssh(config: dict, target: str, expect_path: str | None = None) -> None:
    """Sichert, dass der Ziel-Host per SSH erreichbar ist — sonst Ausweichadresse.

    Hintergrund: ~/.ssh/config bindet 'akadbrain' UND 'akadbrain.local' an den
    Tailscale-Namen akadbrain.taild67bb4.ts.net. Ist Tailscale gestoppt, loest
    der Name nicht auf und JEDER Deploy scheitert mit exit 255 — obwohl der Host
    im LAN antwortet. Bisher musste man dafuer von Hand die config.yaml
    umbiegen; das ist fehleranfaellig (bleibt bei einem Abbruch verbogen stehen)
    und muss bei jedem Deploy wiederholt werden.

    Wir aendern die config.yaml NICHT: die Ausweichadresse gilt nur im Speicher
    und nur fuer diesen Lauf. Eine IP-Adresse umgeht zusaetzlich die
    Host-Muster in ~/.ssh/config, also genau die Ursache.
    """
    t = config.get('shared', {}).get('targets', {}).get(target)
    if not t or not t.get('ssh_host'):
        return
    host = t['ssh_host']
    user = t.get('ssh_user', '')
    key  = t.get('ssh_key', '')

    if _ssh_reachable(host, user, key):
        return

    ip = _resolve_ipv4(host)
    if ip and ip != host and _ssh_reachable(ip, user, key):
        # Identitaetsnachweis, bevor irgendetwas geschrieben wird: die
        # Ausweichadresse stammt aus einer mDNS-/Broadcast-Antwort, nicht aus
        # der Konfiguration. Ohne Pruefung koennte ein Deploy auf einer
        # fremden Maschine landen, die zufaellig denselben Namen beantwortet
        # und unseren Schluessel akzeptiert. Das erwartete Zielverzeichnis ist
        # ein billiger, aber wirksamer Beleg, dass es der richtige Host ist.
        if expect_path and not _has_path(ip, user, key, expect_path):
            print(f'  ABBRUCH: {ip} antwortet auf SSH, aber {expect_path} existiert dort '
                  f'nicht — das ist nicht {host}.', file=sys.stderr)
            sys.exit(1)
        beleg = f', {expect_path} vorhanden' if expect_path else ''
        print(f'  {host} per SSH nicht erreichbar — weiche fuer diesen Lauf auf {ip} aus{beleg}')
        print('  (config.yaml bleibt unveraendert; Ursache pruefen, z. B. "tailscale status")')
        t['ssh_host'] = ip
        return

    print(f'  WARNUNG: {host} antwortet nicht auf SSH und es gibt keine erreichbare '
          f'Ausweichadresse — der Deploy wird vermutlich scheitern.', file=sys.stderr)


# ── Shared mail ini ───────────────────────────────────────────────────────────

def _render_mail_ini(smtp: dict) -> str:
    lines = ['# Generated by mcp/deploy.py — do not edit manually', '[smtp]']
    for key in ('host', 'port', 'user', 'password'):
        if key in smtp:
            lines.append(f'{key} = {smtp[key]}')
    return '\n'.join(lines) + '\n'


def write_app_mail_ini(config: dict, app: str, target: str) -> None:
    """Write <app>/mail.ini on targets that have no host-level path (world4you).

    Pulls credentials from shared.smtp, same source as the host-level file.
    The remote path mirrors scripts/ssh_deploy.php: web/<ftp_base_dir>/mail.ini,
    i.e. right next to the app's config.yaml and above the document root.

    The file is excluded from the deploy rsync (see each app's ssh_deploy.php),
    so it is neither uploaded from the repo nor removed by --delete."""
    if target not in APP_MAIL_INI_TARGETS:
        return
    base = config['apps'][app].get('deploy', {}).get(target, {}).get('ftp_base_dir')
    if not base:
        print(f'  WARNING: no ftp_base_dir for {app}/{target}; mail.ini not written',
              file=sys.stderr)
        return
    dest = 'web' + base.rstrip('/') + '/mail.ini'
    body = _render_mail_ini(config['shared']['smtp'])
    _write_remote_mail_ini(config, target, dest, body, mode='600')


def write_jardyx_mail_ini(target: str, config: dict) -> None:
    """Write /opt/homebrew/etc/jardyx-mail.ini (or remote equivalent) for target.

    Pulls credentials from shared.smtp. Writes chmod 0640. Targets without a
    host-level path get a per-app file instead — see write_app_mail_ini()."""
    dest = MAIL_INI_PATHS.get(target)
    if dest is None:
        print(f'  (no host-level mail ini on {target} — written per app instead)')
        return

    smtp = config['shared']['smtp']
    body = _render_mail_ini(smtp)

    if target == 'local':
        _write_local_mail_ini(dest, body)
    else:
        _write_remote_mail_ini(config, target, dest, body)


def _write_local_mail_ini(dest: str, body: str) -> None:
    path = Path(dest)
    parent = path.parent
    if not parent.exists():
        print(f'  ERROR: {parent} does not exist; skipping jardyx-mail.ini', file=sys.stderr)
        return
    path.write_text(body)
    path.chmod(0o640)
    print(f'  wrote {dest}')


def _write_remote_mail_ini(config: dict, target: str, dest: str, body: str,
                           mode: str = '640') -> None:
    t = config['shared']['targets'][target]
    ssh_host = t['ssh_host']
    ssh_user = t['ssh_user']
    ssh_key = t.get('ssh_key', '')

    with tempfile.NamedTemporaryFile('w', suffix='.ini', delete=False) as tmp:
        tmp.write(body)
        tmp_path = tmp.name

    scp = ['scp']
    ssh = ['ssh']
    if ssh_key:
        scp += ['-i', str(Path(ssh_key).expanduser())]
        ssh += ['-i', str(Path(ssh_key).expanduser())]

    try:
        subprocess.run(
            scp + [tmp_path, f'{ssh_user}@{ssh_host}:{dest}'],
            check=True,
        )
        subprocess.run(
            ssh + [f'{ssh_user}@{ssh_host}', f'chmod {mode} {dest}'],
            check=True,
        )
        print(f'  wrote {ssh_user}@{ssh_host}:{dest}')
    finally:
        Path(tmp_path).unlink(missing_ok=True)


# ── Generate ──────────────────────────────────────────────────────────────────

def run_generate(app: str, target: str) -> None:
    """Call generate.py for the given app+target."""
    subprocess.run(
        [sys.executable, str(REPO_ROOT / 'generate.py'), '--app', app, '--target', target],
        check=True,
    )


# ── Deploy dispatch ───────────────────────────────────────────────────────────

def get_deploy_method(config: dict, app: str, target: str) -> str:
    """Return 'rsync_ssh' or 'rsync_local'.

    SSH is the only remote transport (FTP was retired). Targets with an
    ssh_host deploy over SSH; whether that delegates to the app's
    scripts/ssh_deploy.php is decided in deploy_rsync_ssh().
    """
    target_cfg = config['shared']['targets'].get(target, {})
    if 'ssh_host' in target_cfg:
        return 'rsync_ssh'
    return 'rsync_local'


def deploy_rsync_local(config: dict, app: str, target: str) -> None:
    dest = config['apps'][app]['deploy'][target]['dest']
    src = str(APPS_ROOT / app)
    subprocess.run(['bash', str(LIB / 'rsync.sh'), 'local', src, dest], check=True)


def deploy_rsync_ssh(config: dict, app: str, target: str) -> None:
    src = str(APPS_ROOT / app)
    # When the app ships scripts/ssh_deploy.php, rsync.sh delegates to it and
    # ignores dest/ssh_* args — the per-app script reads everything (including
    # the remote path) from its own config.yaml.
    # ssh_deploy.php is world4you-specific: it derives the remote path from the
    # per-app deploy.<target>.ftp_base_dir. Delegate only when that base dir is
    # configured (i.e. world4you); other ssh targets (akadbrain) fall through to
    # the generic rsync below with their explicit dest path.
    app_deploy = config['apps'][app].get('deploy', {}).get(target, {})
    ssh_deploy_php = APPS_ROOT / app / 'scripts' / 'ssh_deploy.php'
    if 'ftp_base_dir' in app_deploy and ssh_deploy_php.exists():
        subprocess.run(
            ['bash', str(LIB / 'rsync.sh'), 'ssh', src, '__delegated__'],
            check=True,
        )
        return
    dest = app_deploy['dest']
    t = config['shared']['targets'][target]
    subprocess.run(
        ['bash', str(LIB / 'rsync.sh'), 'ssh', src, dest,
         t['ssh_user'], t['ssh_host'], t.get('ssh_key', '')],
        check=True,
    )
    # rsync.sh excludes config.yaml; copy it separately so the app can boot.
    scp = ['scp']
    if t.get('ssh_key'):
        scp += ['-i', str(Path(t['ssh_key']).expanduser())]
    remote = f"{t['ssh_user']}@{t['ssh_host']}"
    subprocess.run(scp + [f'{src}/config.yaml', f'{remote}:{dest}/config.yaml'], check=True)


def run_migrations(app: str) -> None:
    """Run migrate.php if it exists in the app's scripts/ directory."""
    migrate = APPS_ROOT / app / 'scripts' / 'migrate.php'
    if migrate.exists():
        print(f'  Running migrations for {app}...')
        subprocess.run(['php', str(migrate)], check=True)


def do_deploy(config: dict, app: str, target: str) -> None:
    method = get_deploy_method(config, app, target)
    if method == 'rsync_ssh':
        deploy_rsync_ssh(config, app, target)
        # rsync_ssh delegates to scripts/ssh_deploy.php when present, which
        # runs its own remote migrations over SSH. Only call run_migrations
        # for the generic lib/rsync.sh path.
        if not (APPS_ROOT / app / 'scripts' / 'ssh_deploy.php').exists():
            run_migrations(app)
    else:
        deploy_rsync_local(config, app, target)
        run_migrations(app)
    # After the sync: the app directory has to exist, and the rsync excludes
    # mail.ini anyway (auth TASK-6).
    write_app_mail_ini(config, app, target)


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

    if target != 'local':
        preflight_ssh(config, target,
                      apps[app].get('deploy', {}).get(target, {}).get('dest'))
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
    parser.add_argument(
        '--mail-ini',
        metavar='TARGET',
        help='Write shared jardyx-mail.ini for TARGET and exit (no app deploy).',
    )
    args = parser.parse_args()

    if args.mail_ini:
        write_jardyx_mail_ini(args.mail_ini, load_config())
        return

    if args.app and args.target:
        cli_deploy(args.app, args.target)
    elif args.app or args.target:
        parser.error('Provide both <app> and <target>, or neither (for TUI mode).')
    else:
        tui_deploy()


if __name__ == '__main__':
    main()
