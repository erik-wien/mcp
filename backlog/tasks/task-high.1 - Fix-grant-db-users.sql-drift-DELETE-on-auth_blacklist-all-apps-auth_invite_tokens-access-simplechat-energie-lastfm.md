---
id: TASK-HIGH.1
title: >-
  Fix grant-db-users.sql drift: DELETE on auth_blacklist (all apps) +
  auth_invite_tokens access (simplechat, energie, lastfm)
status: To Do
assignee: []
created_date: '2026-04-22 17:00'
labels:
  - auth
  - bug
  - security
  - ops
dependencies: []
parent_task_id: TASK-HIGH
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

Two classes of grant drift in \`scripts/grant-db-users.sql\` that silently break the password-reset flow in every app. Both found while verifying last.fm TASK-19 (ship executeReset.php + setpassword.php).

### Drift class 1 — missing DELETE on auth_blacklist (every app)

Every app's \`executeReset.php\` calls \`auth_clear_auto_blacklist_ip($con, \$ip)\` after a successful reset, which issues \`DELETE FROM auth_blacklist WHERE ip = ? AND auto = 1\` (auth/src/auth.php:340). Current grants for every app are \`SELECT, INSERT, UPDATE\` only — no DELETE. Every reset flow fatal-errors in the library call.

Affected apps: simplechat, wlmonitor, zeiterfassung, energie, suche, lastfm.

### Drift class 2 — missing auth_invite_tokens grants (3 apps)

The file header comment claims \"simplechat + energie + lastfm: no invite flow (no auth_invite_tokens grant)\". This is wrong: even when an app doesn't self-invite, \`admin_reset_password()\` (auth/src/admin.php:196) and \`admin_create_user()\` (auth/src/admin.php:116) both use \`invite_create_token()\` → \`setpassword.php\`. An admin triggering a password reset hits invite_tokens, and the reset recipient hits it too.

Affected apps: simplechat, energie, lastfm.

## Scope

GLOBAL — scripts/grant-db-users.sql is the canonical source of truth per auth-rules §8. The live state must match on all three targets: local (mariadb -uroot), akadbrain, world4you.

## Implementation

1. **Update \`scripts/grant-db-users.sql\`**:
   - For every app (simplechat, wlmonitor, zeiterfassung, energie, suche, lastfm): change \`GRANT SELECT, INSERT, UPDATE ON jardyx.auth_blacklist\` to \`GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_blacklist\`.
   - For simplechat, energie, lastfm: add \`GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_invite_tokens\`.
   - Remove / update the stale header comment \"no invite flow\".

2. **Apply to local**: \`mariadb -uroot jardyx < scripts/grant-db-users.sql\` (script is written to be idempotent — all grants are GRANT, not REVOKE, so replaying is safe).

3. **Apply to akadbrain** via ssh + mariadb. (Verify the file mirrors the local apply; the akadbrain auth DB is \`jardyx_auth\` per pending migration — double-check the target DB name in the current file before applying.)

4. **Apply to world4you**: one-off PHP script per auth-rules §6.1. Script:
   - Reads DB creds from the deployed \`config.yaml\` for one app (any app — grants target the server-level user, not the app's DB).
   - Connects as a privileged user (need the world4you \`5279249\` root-equivalent; if unavailable, this task is blocked until we can grant from root).
   - Executes only the two new grant deltas (six apps × DELETE auth_blacklist, three apps × auth_invite_tokens).
   - Prints OK/ERROR line per grant.
   - Uploaded via \`scripts/ftp_deploy.php\` pattern, self-deletes after one call.

5. **Verify end-to-end** on each target: pick one app (e.g. lastfm) and run a full reset flow — token insert → GET executeReset → POST → 302 → confirm no fatal error in logs, \`auth_blacklist\` DELETE succeeds. Same for setpassword on an invite-affected app.

## Open questions for implementer

- world4you root credentials: does the shared hosting plan expose a privileged DB user we can GRANT from, or must we request it through world4you support? If the latter, this task splits into \"update the file + apply to local + apply to akadbrain\" (deliverable) and \"world4you apply\" (blocked on support ticket).
- akadbrain target DB name — verify current shape of the file (references \`jardyx\` or \`jardyx_auth\`?).

## References

- last.fm TASK-19 (blocked on this for world4you deploy AC)
- auth/src/auth.php:337-345 (auth_clear_auto_blacklist_ip)
- auth/src/admin.php:116-123 (admin_create_user → setpassword)
- auth/src/admin.php:175-210 (admin_reset_password → setpassword)
- auth/src/invite.php (invite_create_token uses REPLACE INTO, needs INSERT+DELETE)
- ~/.claude/rules/auth-rules.md §8 (grants hygiene rule)
- ~/.claude/rules/auth-rules.md §6.1 (world4you migration pattern)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 scripts/grant-db-users.sql updated: all six apps have DELETE on auth_blacklist; simplechat, energie, lastfm have SELECT+INSERT+UPDATE+DELETE on auth_invite_tokens; stale 'no invite flow' comment removed or corrected
- [ ] #2 Grants applied to local via 'mariadb -uroot jardyx < scripts/grant-db-users.sql' and SHOW GRANTS FOR each app user confirms the new privileges
- [ ] #3 Grants applied to akadbrain; SHOW GRANTS confirms on the akadbrain auth DB
- [ ] #4 Grants applied to world4you via a single-purpose temp PHP script (auth-rules §6.1); script self-deleted after one call; output log captured
- [ ] #5 End-to-end reset flow verified on at least one app per target: GET executeReset.php?token= → POST → 302 → login.php alert → no fatal error in PHP log → auth_blacklist entry for the reset IP cleared when auto=1
- [ ] #6 End-to-end invite/admin-reset flow verified for one of simplechat/energie/lastfm: admin triggers password reset → setpassword.php → invite completes → auth_invite_tokens row removed
- [ ] #7 TASK-19 unblocked: last.fm world4you deploy + live reset round-trip passes
<!-- AC:END -->
