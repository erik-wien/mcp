# Mail-Konfiguration auf world4you (PROD)

**Stand:** 2026-07-28 · auth TASK-6

Diese Datei war von `deploy.py` seit jeher referenziert, existierte aber nicht.
Der darin beschriebene manuelle Schritt wurde folglich nie ausgeführt: **auf
world4you lag überhaupt keine Mail-Konfiguration.** Einladungen,
Passwort-Resets und E-Mail-Bestätigungen konnten dort nicht zugestellt werden —
und weil nichts den Mailweg prüfte, fiel es niemandem auf. Entdeckt am
2026-07-28, unmittelbar nach dem Rollout des SMTP-Statuschecks (chrome
TASK-10).

Seither ist der Schritt **automatisiert**; dieses Dokument erklärt, warum der
Pfad so gewählt ist und wie man den Zustand prüft.

## Warum nicht die zwei Systempfade

`Erikr\Auth\Mail\load_mail_config()` suchte ursprünglich nur:

```
/opt/homebrew/etc/jardyx-mail.ini      # macOS/Homebrew: local + akadbrain
/etc/jardyx/mail.ini                   # Linux mit Root-Zugriff
```

Auf world4you ist keiner davon anlegbar — Shared Hosting ohne Root. Und selbst
ein Pfad im Home-Verzeichnis hilft nicht:

```
open_basedir = <home>/web:<home>/tmp:/usr/share/pear:/usr/bin/php_safemode
```

PHP darf dort **nur** innerhalb des Web-Verzeichnisses (und `~/tmp`) lesen.
`~/.config/…` wäre für den Webserver unerreichbar, `~/tmp` ist
gruppenschreibbar und für Zugangsdaten ungeeignet.

## Der gewählte Pfad

```
~/web/jardyx.com/<app>/mail.ini
```

Also **neben der `config.yaml` der App**, ein Verzeichnis **über** dem
Document-Root (`~/web/jardyx.com/<app>/web`).

Nachgewiesen am 2026-07-28: `https://<app>.jardyx.com/config.yaml` und
`https://www.jardyx.com/<app>/config.yaml` antworten beide mit **HTTP 404** —
das App-Verzeichnis wird von keinem Host ausgeliefert. Dieselbe Ablage trägt
dort seit jeher die DB-Zugangsdaten in `config.yaml`.

## Wie die Datei dorthin kommt

Automatisch bei **jedem** Deploy nach world4you:

- `deploy.py` → `write_app_mail_ini()` erzeugt sie aus `shared.smtp` der
  zentralen `mcp/config.yaml` und legt sie per `scp` ab, `chmod 600`.
- `mail.ini` steht in der `$rsyncExcludes`-Liste jeder
  `scripts/ssh_deploy.php`. Das ist **doppelt** wichtig: die Datei wird weder
  aus dem Repo hochgeladen (sie ist dort nicht und darf es nie sein), noch vom
  `rsync --delete` des nächsten Deploys entfernt — ausgeschlossene Dateien
  überleben `--delete`.
- Zusätzlich steht `mail.ini` in der `.gitignore` jeder App.

Gefunden wird sie über die Konstante `AUTH_MAIL_CONFIG_PATH`, die jede App in
`inc/initialize.php` setzt:

```php
define('AUTH_MAIL_CONFIG_PATH', dirname(__DIR__) . '/mail.ini');
```

`load_mail_config()` durchsucht diesen Pfad **zuerst** und fällt danach auf die
beiden Systempfade zurück. Auf local und akadbrain existiert die App-Datei
nicht, dort gilt also unverändert `/opt/homebrew/etc/jardyx-mail.ini`.

## Prüfen

Die Statusseite jeder App zeigt „SMTP (Mailversand)". Grün heißt: TCP-Connect,
220-Banner, EHLO und STARTTLS haben funktioniert. Es wird **keine Mail
verschickt und kein AUTH-Login versucht** (sieben Apps × Statusaufrufe würden
sonst regelmäßig Anmeldeversuche beim Hoster erzeugen und dessen Rate-Limit
auslösen).

Preis dieser Entscheidung: ein **falsches Passwort** in der `mail.ini` fällt
nicht auf. Die Datei wird aber generiert, nicht von Hand gepflegt.

## Wenn der Versand doch scheitert

Seit TASK-6 geht die Ursache nicht mehr verloren:

- `send_templated_mail()` schreibt sie ins PHP-Fehlerlog
  (`[erikr/auth] Mailversand fehlgeschlagen (…): …`) und hält sie in
  `mail_last_error()` bereit.
- `admin_create_user()` und `admin_reset_password()` hängen diese Ursache an
  ihren `auth_log`-Eintrag. Vorher stand dort nur „Failed to send invite
  email" — dass gar keine Konfiguration vorlag, war daraus nicht erkennbar.

**Offen (eigener Task):** Der Admin sieht in der Userverwaltung weiterhin eine
Erfolgsmeldung, wenn nur der Mailversand scheitert — angelegt wurde der Nutzer
ja. Auf `forgotPassword.php` ist die unveränderte Meldung dagegen **Absicht**
(sonst verrät die Seite, welche Adressen registriert sind).
