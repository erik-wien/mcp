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
    --exclude=".git/"
    --exclude=".gitignore"
    --exclude=".DS_Store"
    --exclude=".claude/"
    --exclude=".claude.json"
    --exclude=".superpowers/"
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
