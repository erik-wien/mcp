-- grant-db-users.sql
-- Idempotent: safe to re-run on localhost and akadbrain.
-- Run as root: mysql -uroot < deploy/scripts/grant-db-users.sql
--
-- Each app gets its own user with minimal grants:
--   - App DB: full access (own data)
--   - auth: table-level access to only the tables the auth library uses
--
-- Per auth-rules §8, no app gets DELETE on auth.auth_accounts — deletion flows
-- through admin_delete_user(). REVOKEs below clean up over-broad grants that
-- earlier revisions of this file may have applied.

-- ── Revoke over-broad legacy grants ───────────────────────────────────────────
-- Wrapped in a stored procedure so the REVOKE is a no-op on fresh DBs where
-- the specific grant was never applied (CONTINUE HANDLER swallows the 1141 /
-- 1147 "There is no such grant defined" error). Safe on re-run.
DROP PROCEDURE IF EXISTS _auth_revoke_legacy;
DELIMITER //
CREATE PROCEDURE _auth_revoke_legacy()
BEGIN
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
  REVOKE ALL PRIVILEGES ON auth.* FROM 'wlmonitor'@'localhost';
  REVOKE DELETE ON auth.auth_accounts FROM 'suche'@'localhost';
  REVOKE DELETE ON jardyx_auth.auth_accounts FROM 'suche'@'localhost';
END //
DELIMITER ;
CALL _auth_revoke_legacy();
DROP PROCEDURE IF EXISTS _auth_revoke_legacy;

-- ── simplechat ────────────────────────────────────────────────────────────────
-- No app DB (file-backed). Only needs auth access.
-- Missing: password_resets (added for forgot-password flow)

GRANT SELECT, INSERT, UPDATE ON auth.auth_accounts      TO 'simplechat'@'localhost';
GRANT SELECT, INSERT, UPDATE ON auth.auth_blacklist      TO 'simplechat'@'localhost';
GRANT SELECT, INSERT         ON auth.auth_log            TO 'simplechat'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.password_resets TO 'simplechat'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.auth_remember_tokens TO 'simplechat'@'localhost';

-- ── wlmonitor ─────────────────────────────────────────────────────────────────
-- App DB: wlmonitor (full). Auth: table-level (no DELETE on auth_accounts — per
-- auth-rules §8, deletion flows through admin_delete_user()).

GRANT ALL PRIVILEGES ON wlmonitor.*                               TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE         ON auth.auth_accounts        TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE         ON auth.auth_blacklist       TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT                 ON auth.auth_log             TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.password_resets      TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.auth_invite_tokens   TO 'wlmonitor'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.auth_remember_tokens TO 'wlmonitor'@'localhost';

-- ── zeiterfassung ─────────────────────────────────────────────────────────────
-- App DB: zeiterfassung (full). Auth: auth (read + write for auth flows).

GRANT ALL PRIVILEGES ON zeiterfassung.*                        TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE         ON auth.auth_accounts        TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE         ON auth.auth_blacklist        TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT                 ON auth.auth_log              TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.password_resets       TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.auth_remember_tokens  TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.auth_invite_tokens    TO 'zeiterfassung'@'localhost';

-- ── energie ───────────────────────────────────────────────────────────────────
-- App DB: energie (full). Auth: auth (currently missing — adding now).

GRANT ALL PRIVILEGES ON energie.*                              TO 'energie'@'localhost';
GRANT SELECT, INSERT, UPDATE ON auth.auth_accounts      TO 'energie'@'localhost';
GRANT SELECT, INSERT, UPDATE ON auth.auth_blacklist      TO 'energie'@'localhost';
GRANT SELECT, INSERT         ON auth.auth_log            TO 'energie'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.password_resets TO 'energie'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.auth_remember_tokens TO 'energie'@'localhost';

-- ── suche ─────────────────────────────────────────────────────────────────────
-- No separate app DB. All three new tables (s_buttons, s_feeds, s_db_migrations)
-- live in auth alongside the auth tables. DDL is done by migrate.php;
-- the app user only needs DML on the s_* tables + auth read/write.
-- Stub tables must exist before per-table GRANTs (MariaDB requirement);
-- migrate.php will DROP and re-CREATE them with the real column definitions.

CREATE TABLE IF NOT EXISTS auth.s_buttons       (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS auth.s_feeds         (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS auth.s_db_migrations (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY) ENGINE=InnoDB;

CREATE USER IF NOT EXISTS 'suche'@'localhost' IDENTIFIED BY '3wvHihlGjhJGY5vsAeQS2z';

GRANT SELECT, INSERT, UPDATE, DELETE ON auth.s_buttons        TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.s_feeds          TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.s_db_migrations  TO 'suche'@'localhost';

-- auth_accounts: no DELETE — deletion flows through admin_delete_user() (auth-rules §8).
GRANT SELECT, INSERT, UPDATE         ON auth.auth_accounts        TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE         ON auth.auth_blacklist       TO 'suche'@'localhost';
GRANT SELECT, INSERT                 ON auth.auth_log             TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.password_resets      TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.auth_invite_tokens   TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.auth_remember_tokens TO 'suche'@'localhost';

-- ── lastfm ────────────────────────────────────────────────────────────────────
-- App DB: lastfm (full). Auth: auth (standard auth flows, no invite/registration).

CREATE USER IF NOT EXISTS 'lastfm'@'localhost' IDENTIFIED BY 'DaT8dXD36UxTpNyxSMMTxg';

GRANT ALL PRIVILEGES ON lastfm.* TO 'lastfm'@'localhost';

GRANT SELECT, INSERT, UPDATE         ON auth.auth_accounts       TO 'lastfm'@'localhost';
GRANT SELECT, INSERT, UPDATE         ON auth.auth_blacklist       TO 'lastfm'@'localhost';
GRANT SELECT, INSERT                 ON auth.auth_log             TO 'lastfm'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.password_resets      TO 'lastfm'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.auth_remember_tokens TO 'lastfm'@'localhost';

FLUSH PRIVILEGES;
