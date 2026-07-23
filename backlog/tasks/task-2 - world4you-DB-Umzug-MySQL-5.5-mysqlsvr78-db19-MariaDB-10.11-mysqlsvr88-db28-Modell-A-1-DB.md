---
id: TASK-2
title: >-
  world4you DB-Umzug: MySQL 5.5 (mysqlsvr78/db19) -> MariaDB 10.11
  (mysqlsvr88/db28), Modell A (1 DB)
status: Done
assignee: []
created_date: '2026-07-16 19:20'
updated_date: '2026-07-16 19:33'
labels: []
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ZIEL: Alle world4you-Apps von der alten MySQL-5.5-DB (mysqlsvr78.world4you.com / 5279249db19) auf die neue MariaDB-10.11-DB (mysqlsvr88.world4you.com / 5279249db29 bzw. db28) umziehen. Beseitigt die MySQL-5.5-Fehlerklasse (MAX_JOIN_SIZE-Guard, fehlende ALTER..IF NOT EXISTS, Migrations-Fallstricke), die am 2026-07-16 mehrfach Zusatzarbeit verursachte (siehe auth/TASK-3).

MODELL A (vom User gewaehlt, 2026-07-16): EINE DB haelt alles - geteilte Auth-Tabellen UND alle App-Datentabellen, exakt wie heute auf db19. Grund: alle Apps teilen EIN SSO-Login -> muessen dieselben auth_accounts lesen -> gehoeren in dieselbe Auth-DB. Zieldatenbank: 5279249db28 (db29/db30 bleiben Reserve fuer optionale spaetere Pro-App-Trennung = Modell B).

BETROFFENE APPS (world4you-Targets): energie, wlmonitor, simplechat (nur Auth, datei-basierte Daten), suche, last.fm, biblio. (zeiterfassung ist KEIN world4you-Target.)

NEUE ZUGANGSDATEN: Host mysqlsvr88.world4you.com, User sql9051984, DB 5279249db28. PASSWORT NICHT HIER ABLEGEN - kommt beim Umzug direkt in die gitignorete mcp/config.yaml (per-App world4you db + auth_db Bloecke).

MECHANIK: world4you hat kein externes DB-Port, aber SSH (ssh_deploy.php nutzt den mysql-Client auf dem Deploy-Host). Dump db19 -> Load db28 via SSH-Pipe (mysqldump alt | mysql neu), falls der SSH-Host beide DB-Hosts erreicht; sonst per temporaerem PHP-Skript (auth-rules 6.1). Grants regelt world4you-Hosting (User gehoert zur DB).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Vorpruefung: db28 erreichbar (Host/User/Pass), leer bestaetigt; db19 dumpbar; pruefen ob SSH-Deploy-Host mysqlsvr88 erreicht
- [ ] #2 Vollstaendiger Dump von 5279249db19 (alle Tabellen inkl. auth_accounts + App-Daten) nach 5279249db28 geladen; Zeilenzahlen alt==neu stichprobenartig verifiziert
- [ ] #3 mcp/config.yaml: fuer JEDE world4you-App db.world4you + auth_db.world4you auf Host mysqlsvr88 / Name db28 / User sql9051984 / neues Passwort umgestellt
- [ ] #4 Alle world4you-Apps neu deployt (deploy.py schreibt neue config.yaml auf Server); je App auf jardyx.com verifiziert: Login funktioniert (Auth-DB) + Daten sichtbar
- [ ] #5 Rollback-Sicherheit: db19 bleibt bis zur Verifikation unangetastet; bei Fehler Config zurueck auf db19 + redeploy. Cutover in verkehrsarmer Zeit (Writes auf db19 waehrend des Dumps gehen sonst verloren)
- [ ] #6 Nach erfolgreichem Cutover: world4you-Sonderbehandlungen pruefen die dank MariaDB obsolet werden (Energie SQL_BIG_SELECTS in inc/db.php ist dann No-op - kann bleiben; sargable-Join-Umbau bleibt als echte Verbesserung)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ERLEDIGT + VERIFIZIERT 2026-07-16. Umzug MySQL 5.7.44 (mysqlsvr78/5279249db19/sql6675098) -> MariaDB 10.11.18 (mysqlsvr88/5279249db28/sql9051984), Modell A (1 DB, geteilte Auth + alle App-Daten).
Ablauf: (1) db28 als leer+MariaDB-10.11 bestaetigt; db19 charakterisiert (41 Basistabellen + 1 View ogd_stations, keine Routines/Trigger). (2) Kopie via 'mysqldump --single-transaction | sed DEFINER-strip | mysql' ueber SSH-Host www11 (erreicht beide DB-Hosts); PIPE_EXIT=0. (3) Verifikation: exakte COUNT(*) je Tabelle, alle 41 IDENTISCH. (4) mcp/config.yaml: 12x je Wert (host/name/user/pass) auf db28 umgestellt, Backup im scratchpad (config.yaml.bak.pre-db28). (5) Canary energie -> world4you, verifiziert (Login+Chart). (6) restliche 5 (wlmonitor, simplechat, suche, last.fm, biblio) deployt. (7) alle 6 im Browser verifiziert: Login (geteilte Auth aus db28) + App-Daten laden.
db19 (alt) BLEIBT als Rollback stehen -> nach Bewaehrungszeit droppen (offen). Energie SQL_BIG_SELECTS/sargable-Join bleiben (No-op bzw. Verbesserung). Memory project_world4you_mysql aktualisiert.
<!-- SECTION:NOTES:END -->
