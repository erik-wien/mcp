---
id: TASK-1
title: Akadbrain clean-slate redeploy (orchestrated, idempotent)
status: To Do
assignee: []
created_date: '2026-04-21 12:50'
updated_date: '2026-04-21 12:50'
labels: [deploy, akadbrain, infrastructure]
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Rebuild akadbrain (pre-production staging) from a clean slate — drop all DBs + app users + web roots, then redeploy all five apps (simplechat, wlmonitor, zeiterfassung, energie, suche) with fresh schemas, grants, configs, and routing.

A prior attempt in session ded77758 executed the wipe successfully and got most apps deployed, but the subsequent schema + config steps were reactive: non-idempotent SQL dumps caused repeated re-run failures, a stale `jardyx_auth.auth_accounts` FK in the wlmonitor dev dump had to be sed-patched at deploy time, `grant-db-users.sql` assumed app users already existed, and each sudo step required a fresh SSH session. This task replaces that approach with a single orchestrated run where all artifacts are validated locally before any remote touch.

Root causes to fix at source (not with sed during deploy):
- Non-idempotent schemas (no `IF NOT EXISTS` / `CREATE OR REPLACE`)
- Stale `jardyx_auth.auth_accounts` FK in wlmonitor migration history
- `grant-db-users.sql` creates only suche + lastfm, not the other four app users
- Per-app `config.yaml` files were not pre-generated before deploy
- Multiple sudo SSH reconnects instead of one orchestrator script
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All `CREATE TABLE` / `CREATE VIEW` / `ALTER TABLE ADD COLUMN` statements in every app's `db/NN_*.sql` migrations use idempotent forms (`IF NOT EXISTS`, `CREATE OR REPLACE`, `ADD COLUMN IF NOT EXISTS`)
- [ ] #2 No migration in any app contains a stale reference to `jardyx_auth` (references to the shared auth DB are `auth.*` only)
- [ ] #3 `mcp/scripts/grant-db-users.sql` contains `CREATE USER IF NOT EXISTS` for all six app users (simplechat, wlmonitor, zeiterfassung, energie, suche, lastfm) with passwords sourced from `config.yaml`
- [ ] #4 A single orchestrator script `mcp/scripts/akadbrain_clean_redeploy.sh` (or `.py`) runs the full wipe + rebuild under one `ssh -t sudo` session for DB/nginx work, with rsync + config push as separate non-sudo phases
- [ ] #5 The orchestrator is **re-runnable** — running it twice in a row produces the same end state without errors
- [ ] #6 `config.yaml` files for all five apps are pre-generated via `generate.py --target akadbrain` and bundled before upload
- [ ] #7 After a full run, all five apps respond on their akadbrain vhosts: `http://10.10.10.18/` (suche), `https://chat.eriks.cloud/`, `https://wlmonitor.eriks.cloud/`, `https://werda.eriks.cloud/`, `https://energie.eriks.cloud/` — each returning 200 or 302-to-login
- [ ] #8 `auth_accounts` contains the bootstrap admin users (Erik, Armin) after a full run
- [ ] #9 Suche seeds (migrations 004, 005) apply cleanly once admin users exist
- [ ] #10 `SHOW GRANTS` for every app user matches `grant-db-users.sql` intent (auth-rules §8 — no DELETE on `auth_accounts` for any app user)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Execution is split into four phases. Each phase must complete cleanly and be verifiable before the next starts. The orchestrator script drives Phase 1–3; Phase 0 is local prep with no remote touch.

### Phase 0 — Source-of-truth audit (local, no remote touch)

Goal: every artifact that will be uploaded is correct and idempotent before any SSH.

0.1. **Schema idempotency audit.** For each app (auth, wlmonitor, zeiterfassung, energie, suche), open every file under `db/` or `db/migrations/`:
   - `CREATE TABLE X` → `CREATE TABLE IF NOT EXISTS X`
   - `CREATE VIEW X` → `CREATE OR REPLACE VIEW X`
   - `ALTER TABLE X ADD COLUMN Y` → `ALTER TABLE X ADD COLUMN IF NOT EXISTS Y`
   - `CREATE INDEX X` / `ADD CONSTRAINT X` → use `DROP INDEX IF EXISTS X;` then `CREATE INDEX X` (MariaDB does not support `ADD INDEX IF NOT EXISTS` in all versions)
   - Fix *at source* in the migration file. Commit the fix. Do NOT sed at deploy time.

0.2. **Stale FK audit.** `grep -rn "jardyx_auth" ~/Git/{auth,wlmonitor,Energie,zeiterfassung,simplechat,suche}/db/` — every hit becomes `auth`. This specifically catches the wlmonitor `wl_preferences` FK that broke us this session.

0.3. **`grant-db-users.sql` fix.** Prepend `CREATE USER IF NOT EXISTS` for all six users with passwords from `config.yaml`. Current file only creates suche + lastfm. Verify against auth-rules §8 that no app has `DELETE ON auth.auth_accounts`.

0.4. **Config generation.** Run `python3 ~/Git/mcp/generate.py --app <each> --target akadbrain` for all five apps. Verify each `config.yaml` has correct DB user + password + host=localhost. Bundle into `/tmp/akadbrain-bundle/configs/`.

0.5. **SQL bundle.** Collect canonical SQL files (not dev-DB dumps!) into `/tmp/akadbrain-bundle/sql/`:
   - `auth/` — every migration in `~/Git/auth/db/` in numeric order
   - Per-app schemas from `~/Git/{app}/db/` in numeric order
   - `grant-db-users.sql` from `~/Git/mcp/scripts/`

0.6. **Admin bootstrap SQL.** Write `admin-bootstrap.sql` that INSERTs `Erik` and `Armin` into `auth_accounts` with known bcrypt hashes and `rights='Admin'`. Hashes generated locally via `php -r 'echo password_hash("…", PASSWORD_BCRYPT, ["cost"=>13]);'` — user supplies passwords out of band.

0.7. **Local validation.** Apply the full bundle against a local sandbox DB (fresh DROP + bootstrap) to catch ordering issues before touching akadbrain.

### Phase 1 — Remote teardown + DB bootstrap (ONE sudo SSH session)

Single `ssh -t` → `sudo bash /tmp/akadbrain-orchestrator.sh`. The script is re-entrant: re-running does not error, does not duplicate state.

1.1. Upload `/tmp/akadbrain-bundle/` to `erik@akadbrain.local:/tmp/akadbrain-bundle/` via scp.
1.2. ssh with `-t` and run orchestrator. Inside the script:
   a. `SET FOREIGN_KEY_CHECKS=0` → `DROP DATABASE IF EXISTS {auth,jardyx_auth,wlmonitor,zeiterfassung,energie,lastfm,wlmonitor_dev}` → `FOREIGN_KEY_CHECKS=1`
   b. `DROP USER IF EXISTS` for all six app users
   c. `rm -rf /Library/WebServer/Documents/{chat,wlmonitor,werda,energie,suche}`
   d. Apache residue purge: `launchctl bootout system/org.apache.httpd` (ignore errors), `rm -f /etc/apache2/other/php7.conf /etc/apache2/other/mpm.conf /etc/apache2/users/erik.conf`
   e. `mkdir -p` all five web roots + `chown erik:staff` (so Phase 2 rsync works without sudo)
   f. `CREATE DATABASE {auth,wlmonitor,zeiterfassung,energie}` utf8mb4 unicode_ci
   g. Apply `grant-db-users.sql` (creates all six users + grants in one pass)
   h. Apply auth migrations in order
   i. Apply each app's migrations in order (wlmonitor, zeiterfassung, energie, suche)
   j. Apply `admin-bootstrap.sql` (so Erik + Armin exist before any session starts)
   k. Apply suche seeds 004, 005 (now safe — admin users exist)
   l. Verify: `SHOW DATABASES`, `SELECT User,Host FROM mysql.user`, `SHOW TABLES` in each DB, `SHOW GRANTS` for each user
1.3. Script exits 0 on success. Orchestrator (outside ssh) proceeds to Phase 2. On any non-zero, abort with diagnostic.

### Phase 2 — App deploys + config push (no sudo)

Web roots are erik-owned after Phase 1, so rsync-as-erik works directly. No sudo, no nginx touch.

2.1. For each of the five apps in parallel:
   - `rsync` app contents to its web root (reuse `~/Git/mcp/lib/rsync.sh` conventions — exclude `scripts/`, `db/`, `docs/`, `.git/`, `backlog/`, tests)
   - `scp` the pre-generated `config.yaml` from the bundle into the app's root on the remote
2.2. `chmod -R g+r` where needed so PHP-FPM (running as `_www`) can read.

### Phase 3 — Routing + smoke test

3.1. Nginx eriks.cloud.conf + default_server patch (already done this session — carry forward, don't re-patch).
3.2. curl probe each vhost:
   - `http://10.10.10.18/` → 302 to `/login.php`
   - `https://chat.eriks.cloud/` → 200 or 302
   - `https://wlmonitor.eriks.cloud/` → 200 or 302
   - `https://werda.eriks.cloud/` → 200 or 302
   - `https://energie.eriks.cloud/` → 200 or 302
3.3. Manual browser smoke: log in as Erik/Armin on each app, confirm basic read-paths work.
3.4. Note: `suche.eriks.cloud` needs `sudo certbot --expand -d eriks.cloud -d www.eriks.cloud -d suche.eriks.cloud` — user runs this separately, not part of orchestrator.

### Artifacts produced by this task

- `mcp/scripts/akadbrain_clean_redeploy.sh` — the orchestrator
- `mcp/scripts/akadbrain_orchestrator_remote.sh` — the sudo-side script (uploaded + run once)
- Updates to each app's `db/` migrations for idempotency
- Updates to `mcp/scripts/grant-db-users.sql`

### Cert renewal (in scope)

Phase 3 extends the Let's Encrypt cert to cover `suche.eriks.cloud`:
- `sudo certbot --expand -d eriks.cloud -d www.eriks.cloud -d suche.eriks.cloud` (nginx plugin)
- Verify `https://suche.eriks.cloud/` returns a valid cert chain
- Renewal hook test: `sudo certbot renew --dry-run` after the expansion

### deploy.py debugging (in scope)

Two concrete bugs observed in the 2026-04-21 session that Phase 0 must fix inside `mcp/deploy.py`:

1. **Local-migrate step crashes on `Duplicate FOREIGN KEY constraint name ''`** when wlmonitor dev DB is out-of-sync with migrations. deploy.py should detect + surface this cleanly, not blow up the deploy. Either skip local-migrate when target is remote, or catch and warn.
2. **`Energie/scripts/ssh_deploy.php` is world4you-only** (requires `ftp_base_dir`) but deploy.py invokes it unconditionally for akadbrain. Either (a) teach deploy.py to skip the custom ssh_deploy.php for akadbrain, or (b) generalise Energie's ssh_deploy.php to handle both targets.

Fix both before Phase 2 (which relies on a working `deploy.py` or equivalent rsync path).

### What this explicitly does NOT do

- Does not touch world4you (auth-rules §6.1 — world4you is a separate flow via temp PHP scripts)
- Does not alter app business logic — only migrations, grants, config, deploy scripting, and cert config

### Safety

Per `~/.claude/projects/-Users-erikr-Git/memory/feedback_no_akadbrain_deploy.md`, do NOT execute the orchestrator on akadbrain without explicit user go-ahead per run. The script can be authored and dry-run locally without that permission; only step 1.2 (actually running on akadbrain) requires it.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
<!-- SECTION:NOTES:END -->
