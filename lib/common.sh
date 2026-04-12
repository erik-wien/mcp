#!/usr/bin/env bash
# lib/common.sh — shared output helpers for mcp scripts
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ok()   { printf '\033[0;32m✓ %s\033[0m\n' "$*"; }
err()  { printf '\033[0;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
info() { printf '\033[0;36m%s\033[0m\n' "$*"; }
ask()  { printf '\033[0;33m%s\033[0m ' "$*"; }
warn() { printf '\033[0;33mWARNING: %s\033[0m\n' "$*"; }
