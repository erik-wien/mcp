# akadbrain — Host-Runbook (Betriebsfakten)

Operative Eigenheiten des Prod-1-Hosts **akadbrain** (`erik@akadbrain`,
`*.eriks.cloud` via Cloudflare-Tunnel → nginx + PHP-FPM + MariaDB). Ergänzt die
`~/.claude/CLAUDE.md`-Zugangsnotizen um Dinge, die beim Arbeiten am Host immer
wieder gebraucht werden. Chronologisch gewachsen — neue Erkenntnisse unten anhängen.

## sudo ist NOPASSWD-*scoped* (nur bestimmte Befehle)

- `sudo -n /opt/homebrew/bin/mariadb …` **funktioniert** passwortlos (für
  root-DB-Zugriff via unix_socket).
- `sudo perl` / `sudo sed` / `sudo cp` **scheitern** nicht-interaktiv
  („a terminal is required to read the password"). Passwortloses sudo ist also
  auf einzelne Kommandos (u. a. `mariadb`) beschränkt, nicht global.
- **Homebrew-Configs unter `/opt/homebrew/etc/…` gehören `erik`** (Owner) und sind
  ohne sudo editierbar. Also: Config-Dateien direkt als `erik` bearbeiten, kein
  sudo nötig.

## MariaDB / Migrationen

- root braucht `sudo` (unix_socket-Auth): `sudo /opt/homebrew/bin/mariadb -u root jardyx`.
- `mariadb`/`mysql`-Binaries liegen unter `/opt/homebrew/bin/` (nicht im
  non-interaktiven SSH-PATH → absoluten Pfad nutzen).
- **Migrationen laufen manuell** — `deploy.py biblio akadbrain` synct das `db/`-
  Verzeichnis **nicht** mit. Lokale Migrationsdatei über SSH einspielen:
  ```
  ssh erik@akadbrain 'sudo /opt/homebrew/bin/mariadb -u root jardyx' < db/migrations/NN_foo.sql
  ```
- Table-Level-Grants: DB-User (z. B. `biblio`) haben Rechte **pro Tabelle**, nicht
  DB-weit. Neue Tabelle → explizit granten, sonst 1142 „command denied":
  ```
  sudo /opt/homebrew/bin/mariadb -u root jardyx -e \
    "GRANT SELECT,INSERT,UPDATE ON jardyx.<tabelle> TO 'biblio'@'localhost'; FLUSH PRIVILEGES;"
  ```
  (world4you-`biblio` hat dagegen DB-weite Rechte — dort legt der Deploy-Migrator
  die Tabelle als App-User selbst an.)

## PHP-FPM

- Geteilter Pool **`www`** für alle eriks.cloud-Apps:
  `/opt/homebrew/etc/php/8.5/php-fpm.d/www.conf` (Owner `erik`, kein sudo).
- **`pm.max_children` am 2026-07-16 von 5 → 10** angehoben (Backup:
  `www.conf.bak-20260716`). Vorher lief der Pool bei langsamen Requests voll
  („server reached pm.max_children setting (5)", Worker mit Code 124 gekillt).
- **Config neu laden (graceful, ohne laufende Requests hart zu killen):**
  ```
  kill -USR2 $(pgrep -f "php-fpm: master")
  ```
  Master-PID bleibt gleich; nur die Worker werden mit der neuen Config respawnt.
- `php`-CLI liegt unter `/opt/homebrew/opt/php/bin/php` (absoluter Pfad im SSH).
- **PHP-`error_log()` landet im nginx-Error-Log** (FastCGI stderr):
  `/opt/homebrew/var/log/nginx/error.log` — dort stehen App-Fehlermeldungen mit
  vollem Text. (php.ini/FPM-`error_log` sind auskommentiert.) `opcache` hat
  `validate_timestamps=On, revalidate_freq=2` → deployter Code greift nach ≤ 2 s.

## biblio-Replikation: Hub ↔ Hamish nur über Tailscale

- akadbrain ist der **Replikations-Hub**; er ruft die Knoten aktiv auf.
- **Hamish** (lokaler Dev-Rechner) ist von akadbrain aus **nur über Tailscale**
  erreichbar: `http://hamishmaceirik` (MagicDNS) bzw. `http://100.98.220.15`.
  Der frühere Wert `http://biblio.test` ist ein **Hamish-lokaler** dnsmasq-Name
  (→ 127.0.0.1) und von akadbrain aus **nicht auflösbar** (30-s-DNS-Timeout im Log).
- Hamishs nginx-vhost (`biblio.test.conf`) hört bereits auf
  `server_name biblio.test hamishmaceirik 100.98.220.15` (listen 80/443, alle
  Interfaces) — es genügt also die richtige Base-URL, keine vhost-Änderung.
- **Hamish muss WACH sein.** Ein schlafender/aufwachender Laptop liefert eine
  abgeschnittene Antwort → `json_decode` scheitert. biblio meldet das seit
  2026-07-16 gezielt als „Ziel hat geantwortet, aber unvollständig …" (nicht mehr
  als generischen Netzwerkfehler). Voraussetzung für erfolgreiche Hub→Hamish-
  Replikation: Hamish geweckt, dann „Vergleichen".
- Die Replikations-**Ziele (Base-URL/Token) liegen seit TASK-22 in der biblio-DB**
  (`bi_repl_ziel`, Admin-Tab „Replikation"), **nicht mehr in config.yaml**. Auf
  akadbrain sind sie geseedet (local=Hamish, world4you=jardyx.com). Design-Details:
  `~/Git/biblio/docs/superpowers/specs/2026-07-13-biblio-replikator-design.md`.
