#!/usr/bin/env bash
# deploy.sh — thin wrapper around deploy.py
# Usage: bash deploy.sh [app] [target]
set -euo pipefail
python3 "$(dirname "$0")/deploy.py" "$@"
