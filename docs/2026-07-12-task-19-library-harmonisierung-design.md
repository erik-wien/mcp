# TASK-19 — Library-Harmonisierung (Suite-weite Chrome/css_library-Konsolidierung)

**Datum:** 2026-07-12
**Quelle:** biblio TASK-19 + In-Depth-Audit `mcp/docs/2026-07-12-suite-konsistenz-audit.md`
**Scope:** `~/Git/chrome`, `~/Git/css_library`, 6 Consumer-Apps (biblio, Energie, wlmonitor,
zeiterfassung, simplechat, suche) + last.fm.
**Entscheidungen (Erik, 2026-07-12):** voller Umfang inkl. appsMenu; **zentrale Registry** für
appsMenu; biblio-Link sofort (biblio.jardyx.com, Host reserviert); Anon-Theme-Pille wandert in
den Header.

---

## 0. Grundlagen (verifiziert)

- Chrome-Namespace ist **`Erikr\Chrome\`**, PSR-4 (`autoload.psr-4: {"Erikr\\Chrome\\":"src/"}`),
  Consumer via Composer-**path-Repository → Symlink** `vendor/erikr/chrome → ../../../chrome/`.
  **Konsequenz:** neue Klassen (`Erikr\Chrome\AppsMenu`, `Erikr\Chrome\AvatarCropModal`) und neue
  Methoden lösen sofort in allen Apps auf — **kein `composer update erikr/chrome` nötig** (anders
  als der auth-`autoload.files`-Fall).
- `css_library/js/*` und `css/*` sind per Symlink in jede App gespiegelt (`web/css/shared/`) →
  neue JS-Dateien propagieren sofort.
- Header liest bereits einen `appsMenu`-Array-Schlüssel mit Einträgen
  `{href,label}` bzw. Dropdown `{label,children:[{href,label}],adminOnly?}`. Kein Umbau der
  Render-Logik nötig — nur die **Datenquelle** wird zentralisiert.

---

## 1. WP-H — `Erikr\Chrome\AppsMenu` (Registry)

**Neu:** `chrome/src/AppsMenu.php`.

Kanonische Suite-Tabelle (einzige Quelle der Wahrheit):

| key | label | prod-Host | test-Host |
|---|---|---|---|
| energie | Energie | `https://energie.jardyx.com` | `http://energie.test` |
| wlmonitor | WL Monitor | `https://wlmonitor.jardyx.com` | `http://wlmonitor.test` |
| zeit | Zeit | `https://zeit.jardyx.com` | `http://zeit.test` |
| chat | Chat | `https://chat.jardyx.com` | `http://chat.test` |
| suche | Suche | `https://www.jardyx.com` | `http://suche.test` |
| lastfm | Last.fm | `https://lastfm.jardyx.com` | `http://lastfm.test` |
| biblio | Biblio | `https://biblio.jardyx.com` | `http://biblio.test` |

Kanonische Reihenfolge = Tabellenreihenfolge oben.

**API:**
```php
Erikr\Chrome\AppsMenu::build(string $currentKey, ?string $env = null): array
```
- Liefert exakt den `appsMenu`-Array, den `Header::render()` konsumiert.
- Enthält **alle Apps außer `$currentKey`** (Selbstlink überall ausgeschlossen — prod UND test).
- Prod-Links immer (absolute `https://…jardyx.com`).
- Wenn `$env === 'local'`: zusätzlich **eine** Dropdown-Gruppe
  `['label'=>'Test','adminOnly'=>true,'children'=>[…http://<key>.test…]]` (alle außer self).
- `$env` default: `defined('APP_ENV') ? (string) APP_ENV : ''`. (last.fm setzt `APP_ENV` aus
  `target`; Wert `'local'` gleich → funktioniert uniform.)
- Unbekannter `$currentKey` → Exception (Programmierfehler, früh sichtbar).

**Consumer-Umbau (7 Apps):** die inline-Liste ersetzen durch **eine Zeile**:
`'appsMenu' => \Erikr\Chrome\AppsMenu::build('<selfkey>', APP_ENV)`.

| App | Datei | self-key |
|---|---|---|
| biblio | `inc/layout.php` (~115–132) | `biblio` |
| Energie | `inc/layout.php` (~79–95) | `energie` |
| wlmonitor | `inc/layout.php` (~55–70) | `wlmonitor` |
| zeiterfassung | `inc/_header.php` (~34–49) | `zeit` |
| simplechat | `inc/html.php` (`standaloneTopBar`, ~119–134) | `chat` |
| suche | `inc/layout.php` (~54–69) | `suche` |
| last.fm | `inc/html_header.php` (~27–41) | `lastfm` |

**Damit behobene Drift:** biblio überall ergänzt; last.fm bekommt Suche; suches
`werda.eriks.cloud`/„Zeiterfassung" → `zeit.jardyx.com`/„Zeit"; Energie/last.fm asymmetrischer
Selbst-Test-Link raus; einheitliche Reihenfolge; Selbstlink-Position entfällt.

**AC #5 erfüllt.**

---

## 2. WP-A — `dialog.js` in css_library + confirm()-Migration

- **Promote:** `biblio/web/js/dialog.js` → `css_library/js/dialog.js` (byte-identisch; die
  internen deutschen Namen bleiben).
- **biblio:** `web/admin.php:82` src von `<?=$base?>/js/dialog.js` → `<?=$base?>/css/shared/js/dialog.js`;
  `biblio/web/js/dialog.js` löschen.
- **Migration nativer `confirm()` in genau energie/wlmonitor/zeiterfassung** (AC-benannt):
  - JS-Body-Aufrufe: `Energie/web/admin.php:183,199,207,220,233`; `wlmonitor/web/admin.php:183,199,207,220,233`
    + `wlmonitor/web/js/wl-monitor.js:250`; `zeiterfassung/web/admin.php:190,206,214,227,240`.
    → auf `await window.confirmDialog(text,{titel,okLabel,gefahr})` umstellen (Handler `async`),
    Gefahr-Stufe nach §7.1: löschen=`commit`, senden/reset/widerruf=`secondary`, reversibler
    Toggle (aktivieren/deaktivieren)=`neutral`.
  - `onsubmit="return confirm(...)"`-Form-Guards: `Energie/web/security.php:226,304,322`;
    `wlmonitor/web/security.php:200,269,287`; `zeiterfassung/web/security.php:200,274,292`.
    → in nonce-Skript-Listener mit `e.preventDefault()` + `await confirmDialog()` + bei true
    `form.submit()` umschreiben. Attribut `onsubmit` entfernen.
  - Jede App muss `css/shared/js/dialog.js` als `type="module"` laden (falls noch nicht) —
    Implementer prüft/ergänzt Include.
- **Nicht in Scope (nicht AC #1):** simplechat, suche, last.fm — als Folge-Kleinkram vermerkt.

**AC #1 erfüllt.**

---

## 3. WP-B — Log-Tab-JS in `css_library/js/admin.js`

- **Neu in `css_library/js/admin.js`:** `initLogTab(cfg)` — die Filter/Pagination/AJAX-Logik, aus
  **biblios bereits gefixter** Version (`.app-tab[data-tab="log"], .tab-btn[data-tab="log"]`,
  TASK-15) als Vorlage. `cfg` = `{endpoint, csrfToken, perPage=25, tabSelector?}`.
  Exportiert über das bestehende admin.js-Objekt/`window`-Muster; von `init()` NICHT automatisch
  aufgerufen (Apps rufen explizit mit ihrem Endpoint/CSRF).
- **Consumer, inline-Block ersetzen durch `initLogTab({...})`:**
  - biblio `web/admin.php:213–387` (Referenz — Verhalten muss identisch bleiben)
  - Energie `web/admin.php:245–416` (`.tab-btn`-Bug **weg**)
  - wlmonitor `web/admin.php:245–408` (`.tab-btn`-Bug **weg**)
  - zeiterfassung `web/admin.php:252–390`
  - simplechat `web/admin.php:~522–620` (`.tab-btn`-Bug **weg**; Variante `per_page:50` →
    `perPage:50` in cfg erhalten)
- **Out of scope:** suches abweichendes Log-Paar (`logFilterForm` + `nginxlogFilterForm`,
  `admin.php:428/599`) — kein 170-Zeilen-Block; separat als Folge vermerkt. last.fm hat keinen Log-Tab.

**AC #2 erfüllt** (`.tab-btn`-Bug ökosystemweit eliminiert, App-Kopien gelöscht).

---

## 4. WP-C — `Header::render()` `anonThemeToggle`

- **chrome `Header.php`:** neue Option `anonThemeToggle` (bool, default false). Wenn true UND
  `!$loggedIn`: die Theme-Pille (`.theme-btn`-Markup wie im User-Dropdown) im Header rendern
  (links neben dem „Anmelden"-Link) + **cookie-only** Theme-JS emittieren (setzt/entfernt
  `document.documentElement.dataset.theme`, schreibt Cookie `theme=…;path=/;max-age=31536000;samesite=Lax`).
  **Kein** `fetch`/CSRF-POST (Anon hat keine Session/Endpoint). Nonce-aware.
- Bestehendes Logged-in-Verhalten unverändert.
- **biblio:** `anonThemeToggle => true` bei `render()`; `web/js/theme-toggle.js` löschen +
  Include (`index.php:708`) entfernen; die Anon-Toolbar-Pille (`index.php:169–173`) entfernen
  (wandert in den Header). Cookie-Sync-Spiegel `einstellungen.php:56` prüfen (bleibt, falls
  eigenständig genutzt).

**AC #3 erfüllt.**

---

## 5. WP-D — `Footer::deriveStage()` konfigurierbar + akadbrain

- **chrome `Footer.php`:** `deriveStage()` bekommt `akadbrain` in die Default-`$devTargets`
  (`['local','localhost','dev','development','staging','akadbrain']`). Optionaler Render-Key
  `devTargets` (array) **überschreibt** die Defaults (nicht mergen — explizit).
- **Consumer, Eigenbau entfernen (auf Library-Default zurückfallen):**
  - biblio `inc/layout.php:194,198` — inline `$stage`/`version` raus, nur noch Standard-Footer.
  - Energie `inc/layout.php:339,343` — dito.
  - suche `inc/layout.php:134,138` — dito.
  (Alle drei definieren `APP_VERSION`/`APP_BUILD` → Footer baut die Version selbst.)

**AC #4 erfüllt.**

---

## 6. WP-E — `Erikr\Chrome\AvatarCropModal`

- **Neu:** `chrome/src/AvatarCropModal.php`, `render(array $cfg = []): void`. Emittiert das
  Crop-Modal-Markup mit den von `avatar-cropper.js` erwarteten IDs (`avatarCropModal`,
  `avatarCropImage`, `avatarCropConfirm`, `avatarCropCancel`) in **Katalog-Klassen** (Vorlage:
  biblios sauberes Markup `einstellungen.php:157–173` — `.app-modal-*`, `aria-modal`,
  `aria-labelledby`). Kein Inline-`style`.
- **Consumer, Inline-Kopie ersetzen durch `AvatarCropModal::render()`:**
  - biblio `web/einstellungen.php:157–173`
  - Energie `web/preferences.php:189–208` (Inline-Styles weg → Katalog)
  - wlmonitor `web/preferences.php:322–342` (Inline-Styles weg → Katalog)
  Die `initAvatarCropper({...})`-Verkabelung je App bleibt (IDs unverändert).

**AC #7 erfüllt.**

---

## 7. WP-F — Reset-Preview-Modal in biblio aktiv

- biblios Admin lädt bereits `css/shared/js/admin.js` (`admin.php:74`) und routet Admin-Aktionen
  über `Erikr\Chrome\Admin\Dispatch` (`api.php:314`), das `admin_user_reset_preview` +
  `admin_user_reset` bedient. `wireResetPreview()` aktiviert sich automatisch, sobald das
  Modal-Markup vorhanden ist.
- **biblio:** `UserModals::renderResetPasswordModal()` im Admin-Markup rendern **und** den eigenen
  inline `.btn-reset`-Handler (`web/admin.php:161–168`, `confirmDialog`+`admin_user_reset`)
  **löschen** (sonst Doppel-Binding). Danach: reicher Preview-Flow (Username/E-Mail/IPs/3 Effekte).
- **Audit-Korrektur:** simplechats „Doppel-Binding" ist **kein realer Bug** (der `getElementById`-
  Guard in `wireResetPreview` verhindert es, da simplechat kein Modal hat). Kein simplechat-Change.

**AC #6 erfüllt.**

---

## 8. WP-G — Doku-/Default-Drift

- chrome `Footer.php:34` default `owner` `'Erik R. Huemer'` → **`'Erik R. Accart-Huemer'`**.
- chrome `CLAUDE.md`: `impressumHref`-Default `impressum.html` → `impressum.php`; owner-Default-Zeile
  aktualisieren.
- wlmonitor `inc/functions.php:20-21` stale owner → `'Erik R. Accart-Huemer'`.
- Redundante `owner`-Overrides in biblio/Energie (die den neuen Default doppeln) entfernen —
  nur wenn wertgleich, sonst lassen.

**AC #8 erfüllt.**

---

## 9. Reihenfolge / Abhängigkeiten

**Phase 1 — Library (keine Consumer-Berührung):**
1. `css_library/js/dialog.js` (promote) + biblio-Include-Swap + `biblio/web/js/dialog.js` löschen
2. `css_library/js/admin.js` `initLogTab(cfg)`
3. `chrome AppsMenu`
4. `chrome Header anonThemeToggle`
5. `chrome Footer deriveStage + owner` + `chrome CLAUDE.md` (WP-D-lib + WP-G-lib)
6. `chrome AvatarCropModal`

**Phase 2 — Consumer (hängt an Phase 1):**
7. appsMenu-Umstellung 7 Apps (WP-H)
8. confirm()-Migration energie/wlmonitor/zeit (WP-A)
9. initLogTab-Adoption biblio/energie/wlmonitor/zeit/simplechat (WP-B)
10. anonThemeToggle-Adoption biblio (WP-C)
11. Footer-Stage-Eigenbau raus biblio/energie/suche + wlmonitor owner (WP-D/WP-G-consumer)
12. AvatarCropModal-Adoption biblio/energie/wlmonitor (WP-E)
13. Reset-Modal biblio (WP-F)

**Modellwahl (sparsam, danach streng auditieren):** mechanische Migrationen (7,8,9,11,12) auf
günstigem Modell mit strengem Task-Review; Library-Design (2,3,4,6) Standard; Header-JS (4) und
initLogTab (2) sind die heikelsten (Verhalten muss identisch bleiben).

## 10. Test/Verifikation

Kein PHPUnit im Ökosystem — Verifikation ist **funktional pro App**: `php -l` auf jede geänderte
PHP-Datei; für JS-Migrationen manuelle DOM-Prüfung nicht möglich in CI → Review liest Diff gegen
biblio-Referenz (identisches Verhalten). Pro App nach Change: `php -l` clean + kein natives
`confirm(` mehr in den migrierten Dateien (grep) + appsMenu rendert (Smoke via `php -r` Include
wo möglich). Registry: Unit-artiger `php -r` Smoke — `AppsMenu::build('biblio','local')` liefert 6
prod + Test-Gruppe ohne biblio-Selbstlink; `build('lastfm','prod')` enthält Suche.

## 11. Deploy-Hinweis

Kein `composer update` nötig (PSR-4-Symlink). Reine Datei-Änderungen; normaler mcp-Deploy je App.
Neuer Prod-Host `biblio.jardyx.com` wird in Menüs verlinkt, bevor biblio dort deployt ist → Link
kann bis zum biblio-jardyx-Deploy 404en (bewusst, Host reserviert).
