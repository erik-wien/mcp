# In-Depth-Audit: Suite-Konsistenz ~/Git (2026-07-12)

Geprüft: 7 Apps (biblio, Energie, wlmonitor, zeiterfassung, simplechat, suche, last.fm)
gegen die Suite-Konventionen (css_library, erikr/chrome, erikr/auth, UI-Design-Rules,
Auth-Rules, mcp-Deploy). 8 parallele Audit-Agenten (7 App-Audits + 1 Library-/Quervergleich).

Vorläufer: biblio TASK-19 „Library-Harmonisierung" (audit-2026-07-12) — dessen 8 Befunde
wurden verifiziert und bestätigt; dieses Audit erweitert sie um App-für-App-Konformität
und neue sicherheitsrelevante Funde.

---

## 1. Sicherheitsrelevante Funde (echte Priorität, nicht nur Regelverstoß)

| # | Fund | Ort | Bewertung |
|---|------|-----|-----------|
| S1 | SSO-Allowlist kennt **kein `lastfm.eriks.cloud`** (nur `.test`) → zentraler SSO-Rücksprung nach last.fm-Prod wird von `auth_sso_return_allowed()` abgewiesen | `suche/inc/initialize.php:37-42` | HOCH (funktionale SSO-Lücke) |
| S2 | SSO-Allowlist listet **nur `*.eriks.cloud`**, alle Prod-appsMenu-Links zeigen aber auf `*.jardyx.com` → SSO-Return auf jardyx.com-Hosts würde abgelehnt. Entweder Alias-Design (nie Return-URL) oder echte Lücke — klären | `suche/inc/initialize.php:35-43` vs. appsMenus aller Apps | HOCH (prüfenswert) |
| S3 | `setpassword.php` verarbeitet state-changing POST **ohne `csrf_verify()`** (nur Reset-Token-Schutz) | `wlmonitor/web/setpassword.php:26` | MITTEL-HOCH |
| S4 | **`$_SESSION['userPasswd']`** — Benutzerpasswort im Klartext in der Session (vermutlich Kanal-Schlüsselableitung) + weitere Keys `_dk`, `encryption_iv`, `ciphering` | simplechat (`web/security.php`, `prefs.php`, `inc/*`) | MITTEL-HOCH (Design prüfen) |
| S5 | Legacy `deploy/deploy.sh` mit **hartkodiertem DB-Passwort** | `Energie/deploy/deploy.sh:19` | MITTEL (Repo-Hygiene; Skript löschen) |
| S6 | Inline-`<script>` ohne CSP-Nonce (Datei nirgends verlinkt, legacy) | `wlmonitor/web/map.php:16` | NIEDRIG (Datei eher löschen) |
| S7 | last.fm-`.test`-Submenü ohne `adminOnly` → Nicht-Admins sehen Dev-Links | `last.fm/inc/html_header.php:34` | NIEDRIG |

## 2. appsMenu-Matrix (Kernbefund „Suite nicht konsistent")

Zeile = Ziel-App, Spalte = Quelle; „—" = Selbstlink-Position.

| Ziel ↓ / Quelle → | biblio | Energie | wlmonitor | zeit | chat | suche | last.fm |
|---|---|---|---|---|---|---|---|
| energie | **NEIN** | — | ja | ja | ja | ja | ja |
| wlmonitor | ja | ja | — | ja | ja | ja | ja |
| zeit/werda | ja | ja | ja | — | ja | ja ⚠️¹ | ja |
| chat | ja | ja | ja | ja | — | ja | ja |
| suche/www | ja | ja | ja | ja | ja | — | **NEIN** |
| last.fm | ja | ja | ja | ja | ja | ja | — |
| **biblio** | ⚠️ SELF | **NEIN** | **NEIN** | **NEIN** | **NEIN** | **NEIN** | **NEIN** |

¹ suche verlinkt als einzige App `werda.eriks.cloud` / Label „Zeiterfassung" statt `zeit.jardyx.com` / „Zeit".

Weitere Menü-Befunde:
- biblio fehlt in ALLEN 6 fremden Menüs; biblios eigenes Menü hat den Selbstlink drin und Energie vergessen.
- Domain-Split: Nav-Links = `*.jardyx.com`, SSO-Allowlist = `*.eriks.cloud` (→ S2).
- Test-Submenüs: biblio+Energie listen sich selbst (`.test`), die anderen 5 nicht; last.fm ohne `adminOnly` (→ S7).
- 7 verschieden benannte Pflege-Orte: `inc/layout.php` (biblio/Energie/wlmonitor/suche), `inc/_header.php` (zeit), `inc/html.php` (chat), `inc/html_header.php` (last.fm).

Fundstellen: biblio `inc/layout.php:115-122` · Energie `inc/layout.php:79-85` · wlmonitor `inc/layout.php:55-61` · zeit `inc/_header.php:34-40` · chat `inc/html.php:119-125` · suche `inc/layout.php:54-60` · last.fm `inc/html_header.php:27-31`.

## 3. Library-Lücken (Apps kopieren, weil css_library/chrome es nicht anbieten)

| # | Lücke | Betroffene Apps |
|---|-------|-----------------|
| L1 | Kein zentrales `dialog.js` — biblios `web/js/dialog.js` (confirm/prompt/alert, Fokus-Trap, ESC, Gefahr-Stufe) ist library-tauglich (nur deutsche interne Namen). Alle anderen nutzen natives `confirm()` | Energie (8×), wlmonitor (9×), zeiterfassung (8×), simplechat, suche (9×), last.fm (3×) |
| L2 | `css_library/js/admin.js` hat **kein Log-Tab-Modul** — ~170 Zeilen Filter/Pagination-JS in JEDER admin.php inline kopiert (Bug-Streuung, z. B. `.tab-btn`-Bug) | alle 7 Apps; suche lädt shared admin.js gar nicht, reimplementiert auch Modal/Tab-Wiring (861-Zeilen-admin.php) |
| L3 | Kein `anonThemeToggle`-Feature in `Header::render()` — biblios `theme-toggle.js` ist 1:1-Kopie der Header-Cookie-Logik | biblio (suche = nächster anonymer Use-Case) |
| L4 | Kein Avatar-Crop-Modal-**Markup** in chrome (`avatar-cropper.js` erwartet vorhandenes HTML) | Inline-Kopien in biblio, Energie, wlmonitor |
| L5 | `Footer::deriveStage()` nicht konfigurierbar, kennt akadbrain nicht (→ PROD statt DEV/DEV2) | biblio, Energie, suche bauen `$stage` selbst und umgehen deriveStage via `version`-Option |
| L6 | Kein `auth_verify_password()`-Helfer — Apps prüfen das Alt-/Aktuell-Passwort per eigenem SELECT + `password_verify()` direkt gegen `auth_accounts.password` | biblio (`einstellungen.php:75-90`, inkl. eigenem invalidLogins-UPDATE), wlmonitor (`preferences.php:81`, `security.php:45`), simplechat (`prefs.php:78`, `security.php:47`), last.fm (`security.php:43`) |
| L7 | TOTP-**Enrollment** nicht in erikr/auth gekapselt — Apps setzen eigenen Session-Key `totp_setup_secret` | Energie, simplechat, suche, last.fm (biblio: nicht gefunden) |
| L8 | `UserModals::renderResetPasswordModal()` (chrome) — **tote Funktion**, von keiner App aufgerufen; Apps rollen `.btn-reset`-Confirm selbst. simplechat bindet `.btn-reset` doppelt (eigenes JS + `admin.js::wireResetPreview`) → konkurrierende Handler | alle; Doppel-Binding: `simplechat/web/admin.php:488-495` |

## 4. Doku-/Default-Drift

- `chrome/CLAUDE.md:80`: `impressumHref`-Default „impressum.html" — Code und alle Apps nutzen `impressum.php`.
- **Doppelte owner-Drift**: `chrome/CLAUDE.md:81` UND `chrome/src/Footer.php:25,34` tragen noch „Erik R. Huemer"; biblio/Energie übergeben bereits „Erik R. Accart-Huemer" — Apps ohne eigenen `owner` rendern den alten Namen. Altlast auch in `wlmonitor/inc/functions.php:20-21`.
- `biblio/deploy/oekosystem-todo.md`: SSO-Allowlist-Punkt ist **bereits umgesetzt** (biblio steht in `suche/inc/initialize.php`) — Dokument stale.
- `biblio/update.md`: Config-Migration faktisch erledigt, Brief nie gelöscht; referenziert nicht-existentes `scripts/deploy.sh`.
- `wlmonitor/CLAUDE.md`: verweist auf Root-`deploy.sh`, real `scripts/deploy.sh`.

## 5. UI-Regelverstöße (Rule-Conformance, niedrigere Priorität)

**Emojis im UI (verboten, §11):**
- Energie `web/index.php:47,58,69` — Kachel-Icons 📅 📊 📈
- simplechat `inc/html.php:184,202`, `web/index.php:168,171` — 🔒 🗑 ➜ als Icons
- wlmonitor `web/js/wl-monitor.js:480` — ⚠️ als textContent
- suche `web/preferences.php:228 ff.` — ✅/— als Feed-Status, ▲/▼ als Move-Buttons

**Icon-System-Divergenz:**
- wlmonitor nutzt SVG-Sprite `<use>` (`inc/initialize.php:120-125`) statt `.ui-icon`-Masken; handgerollte Inline-SVGs in wlmonitor `security.php:258` und suche `security.php:289` (mit hartem `fill="#fff"`).

**CSS-Layer / Tokens:**
- `project-theme.css`-Layer fehlt in wlmonitor, zeiterfassung, simplechat, suche, last.fm (nur biblio + Energie vollständig; Dark-Mode-Blöcke liegen dann im app.css — funktioniert, weicht aber vom 6-Layer-Muster ab).
- Energie: Dark-Mode als dark-first-Variante statt kanonischem 3-Block.
- Hardcodierte Farben: zeiterfassung `zeit-app.css` ~21 Hex (u. a. `#ff0000`, `#00ff00` Legacy-Status), simplechat `app.css` 5× + `.btn-primary`-Redefinition mit `color:#fff`, wlmonitor vereinzelt, last.fm `--lfm-info-color:#0000ff` ohne Dark-Variante.
- simplechat: `user_theme`/`user_accent_color` als Session-Keys statt kanonischem `theme`.

**Login-Contract (§9): alle 7 Apps konform** — `rememberName` + `remember_me`, Lifetime aus `AUTH_REMEMBER_LIFETIME/86400` (= 8 Tage) gerendert. Kein Handlungsbedarf.

## 6. Deployment-Hygiene

- Legacy-Skripte parallel zum mcp-Pattern: Energie `deploy/deploy.sh` (+ Klartext-PW → S5), simplechat `scripts/deploy.sh` + `apache-chat.conf`, wlmonitor `scripts/deploy.sh`.
- Sauber (kein Legacy): biblio, zeiterfassung, suche, last.fm.
- Alle 7 Apps auf config.yaml/mcp-generate umgestellt und in `mcp/config.yaml` registriert.

## 7. App-Ranking (Konformität, absteigend)

1. **biblio** — sauberster Konsument (bestätigt TASK-19); Eigen-Abweichungen: Energie fehlt im eigenen appsMenu + Selbstlink, direkter Alt-PW-Check (L6), stale update.md.
2. **zeiterfassung** — strukturell voll auf chrome/auth; Log-Tab-JS-Kopie, confirm(), Legacy-Farben, dokumentierte Legacy-Session-Keys.
3. **last.fm** — überraschend gut migriert; confirm() 3×, appsMenu ohne biblio+suche, adminOnly-Lücke, TOTP-Setup-Key.
4. **wlmonitor** — gut, aber CSRF-Lücke setpassword.php (S3), Sprite- statt Mask-Icons, Nonce-Lücke map.php.
5. **suche** — Auth/CSRF sauber (zentraler SSO-Host), aber admin.php reimplementiert shared admin.js komplett (861 Z.), Footer-Stage-Eigenbau, Emoji-Glyphen.
6. **Energie** — meiste Einzelfunde: Emojis, Stage-Divergenz, 8× confirm(), Log-Tab-Kopie, Legacy-deploy.sh mit Klartext-PW, login.php dupliziert Head-Markup.
7. **simplechat** — Session-Key-Wildwuchs inkl. `userPasswd` (S4), Emoji-Icons, `.btn-reset`-Doppel-Binding, `.btn-primary`-Redefinition, Legacy-Deploy-Reste.

## 8. Empfohlene Task-Struktur

- **TASK-19 (biblio, existiert)** — Library-Harmonisierung: alle 8 Punkte bestätigt, bleibt der Träger für L1–L5, L8, appsMenu-Sync, Doku-Drift. Ergänzen um: L6 (`auth_verify_password()`-Helfer), L7 (TOTP-Enrollment in die Library), suche-admin.js-Sonderfall, simplechat-Doppel-Binding.
- **Neu (auth/suche):** SSO-Allowlist-Fix — `lastfm.eriks.cloud` ergänzen + jardyx.com-Frage klären (S1/S2).
- **Neu (wlmonitor):** `csrf_verify()` in setpassword.php + map.php entfernen/nonce (S3/S6).
- **Neu (simplechat):** Session-Krypto-Design prüfen (`userPasswd` raus, S4).
- **Neu (Energie):** Legacy deploy/ entfernen inkl. Passwort-Rotation-Check (S5).
- **Kleinkram-Sammelfix je App:** Emojis → `.ui-icon`, Farben → Tokens, stale Docs löschen (analog biblio TASK-18).
