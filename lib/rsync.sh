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
        # Per-app override: delegate the whole deploy (composer dance, rsync,
        # remote migrations) to <app>/scripts/ssh_deploy.php if present. Mirrors
        # lib/ftp.sh, which delegates to <app>/scripts/ftp_deploy.php.
        SSH_DEPLOY_PHP="$SRC/scripts/ssh_deploy.php"
        if [[ -f "$SSH_DEPLOY_PHP" ]]; then
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
