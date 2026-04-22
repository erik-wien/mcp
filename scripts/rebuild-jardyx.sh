#!/bin/sh
# rebuild-jardyx.sh — clean-slate rebuild of the single `jardyx` database.
#
# Drops every legacy per-app DB + the jardyx DB itself + app users, recreates
# jardyx from source schemas, applies grants, and reloads seed data either from
# an existing multi-DB dev instance (for the initial migration) or from a
# pre-built bundle (for akadbrain / world4you).
#
# Usage:
#   scripts/rebuild-jardyx.sh local              # first-time local rebuild
#   scripts/rebuild-jardyx.sh local --no-seed    # schema + grants only
#   scripts/rebuild-jardyx.sh akadbrain          # staging rebuild (SSH)
#   scripts/rebuild-jardyx.sh akadbrain --no-seed
#
# Akadbrain target runs mariadb over SSH and seeds from the local capture at
# $SCRATCH/seed/.  Run the local rebuild first (with --seed) so the capture
# exists, then akadbrain reuses it — matching the "clean-slate: local is the
# source of truth" rule from mcp/CLAUDE.md.
#
# Idempotent. Safe to re-run.
set -eu

TARGET=${1:-local}
MODE=${2:---seed}

SSH_AKADBRAIN="ssh -i $HOME/.ssh/id_rsa -o IdentitiesOnly=yes erik@akadbrain.local"

case "$TARGET" in
  local)     MARIADB="/opt/homebrew/bin/mariadb -uroot" ;;
  akadbrain)
    # Needs a sudoers drop-in on akadbrain granting erik NOPASSWD for mariadb.
    # Install source: scripts/akadbrain-sudoers-mariadb.
    MARIADB="$SSH_AKADBRAIN sudo -n /opt/homebrew/bin/mariadb -uroot"
    ;;
  *) echo "unknown target: $TARGET (use: local | akadbrain)"; exit 1 ;;
esac

GIT=/Users/erikr/Git
SCRATCH=/tmp/jardyx-rebuild
mkdir -p "$SCRATCH/seed"

# ── Phase 0: seed-data capture (local clean-slate migration only) ────────────
# Dump current multi-DB state to $SCRATCH/seed/*.sql before wiping, so we can
# reload into jardyx after the schema apply. Skip with --no-seed for a
# schema-only rebuild.
if [ "$MODE" = "--seed" ] && [ "$TARGET" = "akadbrain" ] && [ ! -f "$SCRATCH/seed/.captured" ]; then
  echo "✗ $SCRATCH/seed/.captured missing."
  echo "  akadbrain reuses the local capture — run \`scripts/rebuild-jardyx.sh local\` first."
  exit 1
fi

if [ "$MODE" = "--seed" ] && [ "$TARGET" = "local" ] && [ ! -f "$SCRATCH/seed/.captured" ]; then
  echo "── phase 0: dumping legacy DBs → $SCRATCH/seed/ ─────────────────────────────"
  DUMP="/opt/homebrew/bin/mariadb-dump -uroot --no-create-info --replace --complete-insert --single-transaction --skip-lock-tables --default-character-set=utf8mb4"
  # auth: exclude clean-slate-excluded tables (auth_log, auth_blacklist, auth_remember_tokens)
  $DUMP --ignore-table=auth.auth_log --ignore-table=auth.auth_blacklist --ignore-table=auth.auth_remember_tokens auth > "$SCRATCH/seed/auth.sql"
  echo "  ✓ auth"
  # wlmonitor: use wlmonitor (not wlmonitor_dev — that one's a stale copy)
  $DUMP wlmonitor > "$SCRATCH/seed/wlmonitor.sql"
  echo "  ✓ wlmonitor"
  # zeiterfassung: rename tbl_Zeit_* → zeit_* in the dump
  $DUMP zeiterfassung | perl -pe 's/tbl_Zeit_/zeit_/g' > "$SCRATCH/seed/zeiterfassung.sql"
  echo "  ✓ zeiterfassung (tbl_Zeit_* → zeit_*)"
  $DUMP energie > "$SCRATCH/seed/energie.sql"
  echo "  ✓ energie"
  $DUMP lastfm > "$SCRATCH/seed/lastfm.sql"
  echo "  ✓ lastfm"
  touch "$SCRATCH/seed/.captured"
elif [ -f "$SCRATCH/seed/.captured" ]; then
  echo "── phase 0: legacy dumps already captured at $SCRATCH/seed/ (reusing) ───────"
fi

# ── Phase 1: wipe ────────────────────────────────────────────────────────────
echo
echo "── phase 1: dropping legacy DBs + jardyx + app users ────────────────────────"
$MARIADB <<'SQL'
SET FOREIGN_KEY_CHECKS=0;
DROP DATABASE IF EXISTS auth;
DROP DATABASE IF EXISTS jardyx_auth;
DROP DATABASE IF EXISTS wlmonitor;
DROP DATABASE IF EXISTS wlmonitor_dev;
DROP DATABASE IF EXISTS zeiterfassung;
DROP DATABASE IF EXISTS energie;
DROP DATABASE IF EXISTS lastfm;
DROP DATABASE IF EXISTS jardyx;
DROP USER IF EXISTS 'simplechat'@'localhost';
DROP USER IF EXISTS 'wlmonitor'@'localhost';
DROP USER IF EXISTS 'zeiterfassung'@'localhost';
DROP USER IF EXISTS 'energie'@'localhost';
DROP USER IF EXISTS 'suche'@'localhost';
DROP USER IF EXISTS 'lastfm'@'localhost';
SET FOREIGN_KEY_CHECKS=1;
SQL
echo "  ✓ wiped"

# ── Phase 2: create jardyx ───────────────────────────────────────────────────
echo
echo "── phase 2: create jardyx ───────────────────────────────────────────────────"
$MARIADB <<'SQL'
CREATE DATABASE jardyx CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
SQL
echo "  ✓ jardyx"

# ── Phase 3: apply schemas in dependency order ───────────────────────────────
echo
echo "── phase 3: schemas ─────────────────────────────────────────────────────────"
apply() {
  file="$1"
  label="$2"
  # Strip any `USE <olddb>;` line so everything lands in jardyx.
  ( echo "USE jardyx;"; echo "SET FOREIGN_KEY_CHECKS=0;"; \
    perl -ne 'print unless /^\s*USE\s+\w+\s*;/i' "$file"; \
    echo "SET FOREIGN_KEY_CHECKS=1;" ) | $MARIADB
  echo "  ✓ $label"
}

# auth (shared core — must be first, other apps FK to auth_accounts)
# 00_initial_schema is the self-contained rollup (per its header comment);
# migrations 01..12 are historical artifacts that upgrade legacy systems
# from older shapes. Clean-slate installs only need 00.
apply "$GIT/auth/db/00_initial_schema.sql" "auth/00_initial_schema"

# wlmonitor — 000 is the self-contained rollup (filter_json, uuid CHAR(36),
# last_state, FK already present). Migrations 001..005 are historical no-ops
# on a clean-slate install. wl_colors was dropped by 005 (legacy table).
apply "$GIT/wlmonitor/migrations/000_initial_schema.sql" "wlmonitor/000_initial_schema"

# ogd_stations is a VIEW that joins haltestellen + steige + linien. It isn't
# in any migration source (view was hand-created and never committed). Add it
# here so the app can query it.
echo "  → ogd_stations view"
$MARIADB <<'SQL'
USE jardyx;
CREATE OR REPLACE VIEW ogd_stations AS
SELECT h.HALTESTELLEN_ID AS HALTESTELLEN_ID,
       h.NAME            AS Haltestelle,
       h.DIVA            AS diva,
       GROUP_CONCAT(DISTINCT l.BEZEICHNUNG ORDER BY l.BEZEICHNUNG SEPARATOR ',') AS Linien,
       h.WGS84_LAT       AS LAT,
       h.WGS84_LON       AS LON
FROM   ogd_steige       s
JOIN   ogd_linien       l ON s.FK_LINIEN_ID = l.LINIEN_ID
JOIN   ogd_haltestellen h ON s.FK_HALTESTELLEN_ID = h.HALTESTELLEN_ID
WHERE  h.DIVA IS NOT NULL AND h.DIVA <> ''
GROUP BY h.HALTESTELLEN_ID, h.NAME, h.DIVA, h.WGS84_LAT, h.WGS84_LON;
SQL
echo "  ✓ ogd_stations"

# zeiterfassung (monolithic schema, zeit_* names)
apply "$GIT/zeiterfassung/db/schema.sql" "zeiterfassung/schema"

# Energie
apply "$GIT/Energie/migrations/001_en_initial_schema.sql" "Energie/001_en_initial_schema"

# suche (stubs — 00[123] creates tables, 004/005 seed, 006 adds column)
for m in 001_create_s_db_migrations 002_create_s_buttons 003_create_s_feeds 006_feeds_img_url; do
  apply "$GIT/suche/db/migrations/${m}.sql" "suche/${m}"
done

# lastfm
apply "$GIT/last.fm/db/01_init.sql" "lastfm/01_init"
apply "$GIT/last.fm/db/02_spotify.sql" "lastfm/02_spotify"

# ── Phase 4: grants ──────────────────────────────────────────────────────────
echo
echo "── phase 4: grants ──────────────────────────────────────────────────────────"
$MARIADB < "$GIT/mcp/scripts/grant-db-users.sql"
echo "  ✓ grant-db-users.sql"

# ── Phase 5: seed data ───────────────────────────────────────────────────────
if [ "$MODE" = "--seed" ]; then
  echo
  echo "── phase 5: loading seed data ───────────────────────────────────────────────"
  for f in auth.sql wlmonitor.sql zeiterfassung.sql energie.sql lastfm.sql; do
    [ -f "$SCRATCH/seed/$f" ] || { echo "  ⚠ $f missing, skipping"; continue; }
    ( echo "USE jardyx;"; echo "SET FOREIGN_KEY_CHECKS=0;"; \
      perl -ne 'print unless /^\s*USE\s+\w+\s*;/i' "$SCRATCH/seed/$f"; \
      echo "SET FOREIGN_KEY_CHECKS=1;" ) | $MARIADB
    echo "  ✓ $f"
  done
fi

# ── Phase 6: verification ────────────────────────────────────────────────────
echo
echo "── phase 6: verification ────────────────────────────────────────────────────"
# Queries go in via stdin (not -e) so ssh-wrapped invocations don't mangle quoting.
echo "SELECT CONCAT(table_name, ' — ', table_rows) FROM information_schema.tables
      WHERE table_schema='jardyx' ORDER BY table_name;" | $MARIADB -N | sed 's/^/  /'

echo
echo "── app users ────────────────────────────────────────────────────────────────"
echo "SELECT User FROM mysql.user WHERE Host='localhost'
      AND User IN ('simplechat','wlmonitor','zeiterfassung','energie','suche','lastfm')
      ORDER BY User;" | $MARIADB -N | sed 's/^/  /'

echo
echo "── done ─────────────────────────────────────────────────────────────────────"
