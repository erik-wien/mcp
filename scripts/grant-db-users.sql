-- grant-db-users.sql
-- Single-DB (`jardyx`) model. Every app user has table-level grants inside
-- jardyx, scoped to the table prefix it owns plus a read/write slice of the
-- auth_* tables used by the erikr/auth library.
--
-- Run as root:  mariadb -uroot < scripts/grant-db-users.sql
-- Idempotent: safe to re-run on local, akadbrain, and world4you (world4you
-- DB is named `5279249db19`; run the world4you-variant of this file instead).

-- CREATE PROCEDURE below needs a current database. `jardyx` is always
-- present by this point (create-db.sql runs first).
USE jardyx;

-- ── Create users (idempotent) ─────────────────────────────────────────────────
-- Passwords match mcp/config.yaml — when a password is rotated there, update
-- it here too.

CREATE USER IF NOT EXISTS 'simplechat'@'localhost'    IDENTIFIED BY 'ZRHSwxyj8LIi7RbG';
CREATE USER IF NOT EXISTS 'wlmonitor'@'localhost'     IDENTIFIED BY 'sopdi9-nyKnyb-zyqpyh';
CREATE USER IF NOT EXISTS 'zeiterfassung'@'localhost' IDENTIFIED BY 'CfgnWHMYiQYPU17Cg8KN80pO';
CREATE USER IF NOT EXISTS 'energie'@'localhost'       IDENTIFIED BY 'sopdi9-nyKnyb-zyqpyh';
CREATE USER IF NOT EXISTS 'suche'@'localhost'         IDENTIFIED BY '3wvHihlGjhJGY5vsAeQS2z';
CREATE USER IF NOT EXISTS 'lastfm'@'localhost'        IDENTIFIED BY 'DaT8dXD36UxTpNyxSMMTxg';

-- ── Revoke over-broad legacy grants ───────────────────────────────────────────
-- Wrapped in a stored procedure so the REVOKE is a no-op on fresh DBs (CONTINUE
-- HANDLER swallows 1141/1147 "no such grant defined"). Safe on re-run.
DROP PROCEDURE IF EXISTS _auth_revoke_legacy;
DELIMITER //
CREATE PROCEDURE _auth_revoke_legacy()
BEGIN
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
  -- Legacy multi-DB grants (pre-jardyx):
  REVOKE ALL PRIVILEGES ON auth.*          FROM 'simplechat'@'localhost';
  REVOKE ALL PRIVILEGES ON auth.*          FROM 'wlmonitor'@'localhost';
  REVOKE ALL PRIVILEGES ON auth.*          FROM 'zeiterfassung'@'localhost';
  REVOKE ALL PRIVILEGES ON auth.*          FROM 'energie'@'localhost';
  REVOKE ALL PRIVILEGES ON auth.*          FROM 'suche'@'localhost';
  REVOKE ALL PRIVILEGES ON auth.*          FROM 'lastfm'@'localhost';
  REVOKE ALL PRIVILEGES ON wlmonitor.*     FROM 'wlmonitor'@'localhost';
  REVOKE ALL PRIVILEGES ON wlmonitor_dev.* FROM 'wlmonitor'@'localhost';
  REVOKE ALL PRIVILEGES ON zeiterfassung.* FROM 'zeiterfassung'@'localhost';
  REVOKE ALL PRIVILEGES ON energie.*       FROM 'energie'@'localhost';
  REVOKE ALL PRIVILEGES ON lastfm.*        FROM 'lastfm'@'localhost';
  -- Old auth_accounts DELETE violations:
  REVOKE DELETE ON auth.auth_accounts        FROM 'suche'@'localhost';
  REVOKE DELETE ON jardyx_auth.auth_accounts FROM 'suche'@'localhost';
END //
DELIMITER ;
CALL _auth_revoke_legacy();
DROP PROCEDURE IF EXISTS _auth_revoke_legacy;

-- ── Shared auth_* grants (per auth-rules §8) ──────────────────────────────────
-- Every app gets the same slice of auth tables. No app gets DELETE on
-- auth_accounts — deletion flows through admin_delete_user().
-- auth_log is append-only (no UPDATE/DELETE for any app).

-- Every app gets auth_invite_tokens — admin-triggered password resets
-- (admin_reset_password / admin_create_user in erikr/auth) issue invite
-- tokens and link to setpassword.php, regardless of whether the app uses
-- the user-facing self-invite flow.
-- Every app gets DELETE on auth_blacklist — auth_clear_auto_blacklist_ip()
-- is called from every app's executeReset.php to unblock the reset IP.

-- Stub tables must exist for table-level GRANT (MariaDB requirement).
-- The schema apply in rebuild-jardyx.sh runs BEFORE this file, so by the
-- time we grant, every auth_* / s_* / wl_sessions table already exists.

-- simplechat ──────────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE         ON jardyx.auth_accounts        TO 'simplechat'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_blacklist       TO 'simplechat'@'localhost';
GRANT SELECT, INSERT                 ON jardyx.auth_log             TO 'simplechat'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.password_resets      TO 'simplechat'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_invite_tokens   TO 'simplechat'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_remember_tokens TO 'simplechat'@'localhost';

-- wlmonitor ──────────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE         ON jardyx.auth_accounts        TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_blacklist       TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT                 ON jardyx.auth_log             TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.password_resets      TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_invite_tokens   TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_remember_tokens TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.wl_sessions          TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.wl_favorites         TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.wl_log               TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.wl_preferences       TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.wl_userprefs         TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.db_migrations        TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.ogd_haltestellen     TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.ogd_linien           TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.ogd_stations         TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.ogd_steige           TO 'wlmonitor'@'localhost';

-- zeiterfassung ──────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE         ON jardyx.auth_accounts        TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_blacklist       TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT                 ON jardyx.auth_log             TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.password_resets      TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_invite_tokens   TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_remember_tokens TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.zeit_chkReasons            TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.zeit_cron                  TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.zeit_user                  TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.zeit_userprefs             TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.zeit_zeitErfassung         TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.zeit_zeitErfassung_deleted TO 'zeiterfassung'@'localhost';

-- energie ────────────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE         ON jardyx.auth_accounts        TO 'energie'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_blacklist       TO 'energie'@'localhost';
GRANT SELECT, INSERT                 ON jardyx.auth_log             TO 'energie'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.password_resets      TO 'energie'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_invite_tokens   TO 'energie'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_remember_tokens TO 'energie'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.readings             TO 'energie'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.tariff_config        TO 'energie'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.daily_summary        TO 'energie'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.en_preferences       TO 'energie'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.en_userprefs         TO 'energie'@'localhost';

-- suche ──────────────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE         ON jardyx.auth_accounts        TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_blacklist       TO 'suche'@'localhost';
GRANT SELECT, INSERT                 ON jardyx.auth_log             TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.password_resets      TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_invite_tokens   TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_remember_tokens TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.s_buttons            TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.s_feeds              TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.s_db_migrations      TO 'suche'@'localhost';

-- auth_sso_tickets — SSO one-time ticket grants ──────────────────────────────
-- Only suche (the central login host) issues tickets → INSERT.
-- All other apps only redeem (SELECT) and consume (DELETE).
GRANT SELECT, INSERT, DELETE ON auth.auth_sso_tickets TO 'suche'@'localhost';
GRANT SELECT, DELETE         ON auth.auth_sso_tickets TO 'simplechat'@'localhost';
GRANT SELECT, DELETE         ON auth.auth_sso_tickets TO 'wlmonitor'@'localhost';
GRANT SELECT, DELETE         ON auth.auth_sso_tickets TO 'energie'@'localhost';
GRANT SELECT, DELETE         ON auth.auth_sso_tickets TO 'zeiterfassung'@'localhost';

-- lastfm ─────────────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE         ON jardyx.auth_accounts         TO 'lastfm'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_blacklist        TO 'lastfm'@'localhost';
GRANT SELECT, INSERT                 ON jardyx.auth_log              TO 'lastfm'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.password_resets       TO 'lastfm'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_invite_tokens    TO 'lastfm'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.auth_remember_tokens  TO 'lastfm'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.lfm_albums            TO 'lastfm'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.lfm_artists           TO 'lastfm'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.lfm_played_tracks     TO 'lastfm'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.lfm_tracks            TO 'lastfm'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.lfm_user_credentials  TO 'lastfm'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.lfm_weekly_charts     TO 'lastfm'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx.lfm_year_imports      TO 'lastfm'@'localhost';

FLUSH PRIVILEGES;
