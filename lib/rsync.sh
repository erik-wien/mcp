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
    # NO --delete-excluded: excluded dirs (data/, config/, var/, db/) hold
    # server-side state (file-backed chat store, legacy configs, caches) that
    # must survive deploys. --delete-excluded wiped them on 2026-07-01/02
    # (werda fatal: config/ gone; chat 500: data/ gone). ssh_deploy.php has
    # always done it right — plain --delete only.
    --copy-links
    # Enforce world-readable perms on everything deployed (dirs 755, files 644):
    # -a copies SOURCE perms, and 0400/0600 source files (macOS quirks, uploads)
    # made the web server (nobody/_www) 403 on prod — icons 2026-07-01, shared
    # woff2 fonts 2026-07-02. Secrets never ride this sync (config.yaml, data/,
    # config/ are excluded); ssh_deploy.php uses the same --chmod.
    --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r
    --exclude=".git/"
    --exclude=".gitignore"
    --exclude=".DS_Store"
    --exclude=".claude/"
    --exclude=".claude.json"
    # Git-Worktrees unter dem Repo (z. B. ~/Git/<app>/.worktrees/<name> aus
    # parallelen Sessions) NIE mitdeployen: ihr web/css/shared-Symlink zeigt
    # relativ ins Leere → rsync --copy-links bricht am fehlenden Ziel (exit 23,
    # biblio 2026-07-20). .claude/worktrees/ deckt schon der .claude/-Exclude ab.
    --exclude=".worktrees/"
    --exclude=".superpowers/"
    --exclude="backlog/"
    --exclude="CLAUDE.md"
    # Protect the erikr/auth mail templates (Markdown) from the blanket *.md
    # exclude below — first-match-wins, so this include MUST precede it. Without
    # it, blacklist/invite/reset/lockout mails throw TemplateException at runtime
    # (empty templates/email/ on prod, 2026-07-01..04). Verified via openrsync
    # dry-run: protects the 5 templates, still strips READMEs/docs.
    # Doku-Viewer-Inhalte mitdeployen (biblio/antrago anleitung.php): NUR das
    # Handbuch + die auto-gescannten Specs, nicht der Rest von docs/ (Pläne,
    # Entwürfe). Muss VOR dem *.md- UND dem docs/-Exclude stehen (first-match-
    # wins). /docs/-Anker = nur Top-Level-docs (kein backlog/docs o.ä.). Ersetzt
    # den früheren manuellen Nachsync-Workaround; via openrsync-Dry-Run verifiziert.
    --include="/docs/"
    --include="/docs/handbuch/"
    --include="/docs/handbuch/*.md"
    --include="/docs/superpowers/"
    --include="/docs/superpowers/specs/"
    --include="/docs/superpowers/specs/*.md"
    --exclude="/docs/**"
    --include="**/templates/email/*.md"
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
    # (docs/ wird jetzt selektiv einbezogen — siehe Include-Block oben; der
    #  frühere pauschale docs/-Exclude entfiel dafür.)
    --exclude="bin/"
    --exclude="db/"
    --exclude="config/"
    --exclude="data/"
    --exclude="var/"
    # Runtime-Upload-/Archiv-Verzeichnisse (z. B. zeiterfassung SAP-Journale):
    # enthalten Nutzer-/Personaldaten, gehören nie auf ein Prod-Ziel.
    --exclude="upload/"
    --exclude="archiv/"
    --exclude="config.yaml"
    --exclude="config.example.yaml"
    --exclude="__pycache__/"
    --exclude="*.pyc"
    --exclude="composer-setup.php"
)

case "$MODE" in
    local)
        info "Syncing to $DEST ..."
        mkdir -p "$DEST"
        rsync "${RSYNC_OPTS[@]}" "$SRC/" "$DEST/"
        ok "Synced to $DEST"
        ;;

    ssh)
        # Per-app override: delegate to <app>/scripts/ssh_deploy.php when the
        # caller passes __delegated__ as DEST. deploy.py only does this for
        # targets that have FTP configured (world4you), so ssh_deploy.php —
        # which requires ftp_base_dir — is never invoked for akadbrain.
        SSH_DEPLOY_PHP="$SRC/scripts/ssh_deploy.php"
        if [[ "$DEST" == "__delegated__" && -f "$SSH_DEPLOY_PHP" ]]; then
            info "Using $(basename "$SRC")/scripts/ssh_deploy.php ..."
            php "$SSH_DEPLOY_PHP"
            ok "SSH deploy complete via ssh_deploy.php"
            exit 0
        fi

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
