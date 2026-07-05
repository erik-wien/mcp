#!/usr/bin/env bash
#
# deploy-sso.sh — DB-Teil des zentralen Login-Hosts (SSO-Tickets).
#
# WO AUSFÜHREN:  auf akadbrain (SSH: erik@akadbrain), NICHT auf Hamish.
# WAS ES TUT:    legt die Tabelle jardyx.auth_sso_tickets an und setzt die
#                Grants für die 5 eriks.cloud-Apps. Idempotent (mehrfach
#                ausführbar). Fasst KEINE Benutzerdaten an.
#
# Voraussetzung: DB-Superuser. Auf akadbrain ist `erik@localhost` via
# unix_socket ALL PRIVILEGES (kein sudo, kein Passwort) — der Default-User des
# mariadb-Clients. Der Client liegt unter /opt/homebrew/bin und ist bei
# nicht-interaktivem SSH oft nicht im PATH, daher wird er hier aufgelöst.
#
set -euo pipefail

DB=jardyx
MARIADB="$(command -v mariadb || echo /opt/homebrew/bin/mariadb)"
DBROOT=("$MARIADB")        # erik@localhost = Superuser via Socket; kein -u/-p, kein sudo

echo "== [1/3] Migration: ${DB}.auth_sso_tickets anlegen =="
"${DBROOT[@]}" "$DB" <<'SQL'
CREATE TABLE IF NOT EXISTS auth_sso_tickets (
  id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  token_hash   CHAR(64)     NOT NULL,          -- SHA-256(token), hex
  user_id      INT          NOT NULL,
  return_host  VARCHAR(190) NOT NULL,          -- Host, an den das Ticket gebunden ist
  expires      DATETIME     NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_token (token_hash),
  KEY idx_expires (expires),
  CONSTRAINT fk_sso_user FOREIGN KEY (user_id)
      REFERENCES auth_accounts(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
SQL
echo "   OK"

echo "== [2/3] Grants (suche = INSERT+SELECT+DELETE; übrige = SELECT+DELETE) =="
"${DBROOT[@]}" <<'SQL'
GRANT SELECT, INSERT, DELETE ON jardyx.auth_sso_tickets TO 'suche'@'localhost';
GRANT SELECT, DELETE         ON jardyx.auth_sso_tickets TO 'simplechat'@'localhost';
GRANT SELECT, DELETE         ON jardyx.auth_sso_tickets TO 'wlmonitor'@'localhost';
GRANT SELECT, DELETE         ON jardyx.auth_sso_tickets TO 'energie'@'localhost';
GRANT SELECT, DELETE         ON jardyx.auth_sso_tickets TO 'zeiterfassung'@'localhost';
FLUSH PRIVILEGES;
SQL
echo "   OK"

echo "== [3/3] Verifikation =="
"${DBROOT[@]}" "$DB" -e "SHOW TABLES LIKE 'auth_sso_tickets';"
"${DBROOT[@]}" -e "SHOW GRANTS FOR 'suche'@'localhost';" | grep -i sso_tickets || {
  echo "!! Grant für suche nicht gefunden" >&2; exit 1; }
echo "== Fertig. auth_sso_tickets steht bereit. =="
