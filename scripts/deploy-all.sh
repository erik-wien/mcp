#!/usr/bin/env bash
# mcp/scripts/deploy-all.sh
# Deploy all (or selected) apps to a target environment via mcp/deploy.py.
#
# Usage:
#   bash deploy/scripts/deploy-all.sh <target> [app ...]
#
# Targets:
#   local       — deploy to /Library/WebServer/Documents/ on this machine
#   akadbrain   — deploy to akadbrain.local (TEST · eriks.cloud)
#   world4you   — deploy to world4you via FTP (PROD · jardyx.com)
#
# Apps (friendly names → mcp app names):
#   chat        → simplechat
#   wlmonitor   → wlmonitor
#   zeit        → zeiterfassung
#   energie     → energie
#   suche/home  → suche
#
# Examples:
#   bash deploy/scripts/deploy-all.sh akadbrain
#   bash deploy/scripts/deploy-all.sh akadbrain chat energie
#   bash deploy/scripts/deploy-all.sh world4you wlmonitor

set -euo pipefail

GIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MCP="$GIT_ROOT/deploy.py"

info()  { printf '\033[0;36m==> %s\033[0m\n' "$*"; }
ok()    { printf '\033[0;32m✓  %s\033[0m\n' "$*"; }
warn()  { printf '\033[0;33m⚠  %s\033[0m\n' "$*"; }
err()   { printf '\033[0;31mERROR: %s\033[0m\n' "$*" >&2; }

TARGET="${1:-}"
shift || true

if [[ -z "$TARGET" ]]; then
    echo "Usage: bash deploy/scripts/deploy-all.sh <local|akadbrain|world4you> [app ...]"
    echo
    echo "Targets:  local · akadbrain · world4you"
    echo "Apps:     chat · wlmonitor · zeit · energie · home"
    exit 1
fi

case "$TARGET" in
    local|akadbrain|world4you) ;;
    *) err "Unknown target '$TARGET'. Use: local · akadbrain · world4you"; exit 1 ;;
esac

# Friendly name → mcp app name
mcp_name() {
    case "$1" in
        chat)       echo "simplechat" ;;
        wlmonitor)  echo "wlmonitor" ;;
        zeit)       echo "zeiterfassung" ;;
        energie)    echo "energie" ;;
        home|suche) echo "suche" ;;
        *)          echo "$1" ;;  # pass through unknown names for mcp to validate
    esac
}

if [[ "$#" -gt 0 ]]; then
    APPS=("$@")
else
    APPS=(chat wlmonitor zeit energie suche)
fi

echo
info "Target : $TARGET"
info "Apps   : ${APPS[*]}"
echo

info "── shared mail config ──────────────────────────────────────"
python3 "$MCP" --mail-ini "$TARGET" || warn "jardyx-mail.ini write failed — apps may not send mail"
echo

FAILED=()

for app in "${APPS[@]}"; do
    mcp_app="$(mcp_name "$app")"
    info "── $app ($mcp_app) ──────────────────────────────────────"
    if python3 "$MCP" "$mcp_app" "$TARGET"; then
        ok "$app deployed"
    else
        err "$app failed"
        FAILED+=("$app")
    fi
    echo
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    err "Failed: ${FAILED[*]}"
    exit 1
fi

info "All done."
