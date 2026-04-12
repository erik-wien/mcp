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
