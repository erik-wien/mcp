-- grant-db-users.sql
-- Idempotent: safe to re-run on localhost and akadbrain.
-- Run as root: mysql -uroot < deploy/scripts/grant-db-users.sql
--
-- Each app gets its own user with minimal grants:
--   - App DB: full access (own data)
--   - jardyx_auth: table-level access to only the tables the auth library uses

-- ── simplechat ────────────────────────────────────────────────────────────────
-- No app DB (file-backed). Only needs jardyx_auth access.
-- Missing: password_resets (added for forgot-password flow)

GRANT SELECT, INSERT, UPDATE ON jardyx_auth.auth_accounts      TO 'simplechat'@'localhost';
GRANT SELECT, INSERT, UPDATE ON jardyx_auth.auth_blacklist      TO 'simplechat'@'localhost';
GRANT SELECT, INSERT         ON jardyx_auth.auth_log            TO 'simplechat'@'localhost';
GRANT SELECT, INSERT, UPDATE ON jardyx_auth.password_resets     TO 'simplechat'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx_auth.auth_remember_tokens TO 'simplechat'@'localhost';

-- ── wlmonitor ─────────────────────────────────────────────────────────────────
-- App DB: wlmonitor (full). Auth: jardyx_auth (full — has registration/invites).

GRANT ALL PRIVILEGES ON wlmonitor.*    TO 'wlmonitor'@'localhost';
GRANT ALL PRIVILEGES ON jardyx_auth.*  TO 'wlmonitor'@'localhost';

-- ── zeiterfassung ─────────────────────────────────────────────────────────────
-- App DB: zeiterfassung (full). Auth: jardyx_auth (read + write for auth flows).

GRANT ALL PRIVILEGES ON zeiterfassung.*                        TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE ON jardyx_auth.auth_accounts      TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE ON jardyx_auth.auth_blacklist      TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT         ON jardyx_auth.auth_log            TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE ON jardyx_auth.password_resets     TO 'zeiterfassung'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx_auth.auth_remember_tokens TO 'zeiterfassung'@'localhost';

-- ── energie ───────────────────────────────────────────────────────────────────
-- App DB: energie (full). Auth: jardyx_auth (currently missing — adding now).

GRANT ALL PRIVILEGES ON energie.*                              TO 'energie'@'localhost';
GRANT SELECT, INSERT, UPDATE ON jardyx_auth.auth_accounts      TO 'energie'@'localhost';
GRANT SELECT, INSERT, UPDATE ON jardyx_auth.auth_blacklist      TO 'energie'@'localhost';
GRANT SELECT, INSERT         ON jardyx_auth.auth_log            TO 'energie'@'localhost';
GRANT SELECT, INSERT, UPDATE ON jardyx_auth.password_resets     TO 'energie'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx_auth.auth_remember_tokens TO 'energie'@'localhost';

-- ── suche ─────────────────────────────────────────────────────────────────────
-- No separate app DB. All three new tables (s_buttons, s_feeds, s_db_migrations)
-- live in jardyx_auth alongside the auth tables. DDL is done by migrate.php;
-- the app user only needs DML on the s_* tables + auth read/write.
-- Stub tables must exist before per-table GRANTs (MariaDB requirement);
-- migrate.php will DROP and re-CREATE them with the real column definitions.

CREATE TABLE IF NOT EXISTS jardyx_auth.s_buttons       (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS jardyx_auth.s_feeds         (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS jardyx_auth.s_db_migrations (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY) ENGINE=InnoDB;

CREATE USER IF NOT EXISTS 'suche'@'localhost' IDENTIFIED BY '3wvHihlGjhJGY5vsAeQS2z';

GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx_auth.s_buttons        TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx_auth.s_feeds          TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx_auth.s_db_migrations  TO 'suche'@'localhost';

GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx_auth.auth_accounts       TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE         ON jardyx_auth.auth_blacklist       TO 'suche'@'localhost';
GRANT SELECT, INSERT                 ON jardyx_auth.auth_log             TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE         ON jardyx_auth.password_resets      TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx_auth.auth_invite_tokens   TO 'suche'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON jardyx_auth.auth_remember_tokens TO 'suche'@'localhost';

FLUSH PRIVILEGES;
