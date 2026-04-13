# TOTP 2FA Implementation Design

## Goal

Add opt-in TOTP two-factor authentication to `erikr/auth` and wire it into wlmonitor and simplechat-2.1. Users enable 2FA from a new "Passwort & 2FA" page in each app's user dropdown. Admins can reset (disable) a user's 2FA via a checkbox in the edit-user form.

## Architecture

Three layers: shared library, per-app login step, per-app management UI.

**Tech stack:** PHP 8.5, MySQLi, TOTP/RFC 6238 (HMAC-SHA1, 30 s window), PHPUnit 13 for tests.

---

## Layer 1 — `erikr/auth` library changes

### DB migration: `db/06_totp.sql`

```sql
ALTER TABLE auth_accounts
  ADD COLUMN totp_secret VARCHAR(64) NULL DEFAULT NULL
  COMMENT 'Base32-encoded TOTP secret. NULL = 2FA disabled.';
```

### New file: `src/totp.php`

All public functions use the `auth_totp_` prefix to avoid collision with simplechat's local `inc/totp.php`. Internal helpers are prefixed `_auth_totp_`.

```php
auth_totp_generate_secret(): string
    // Returns a new cryptographically random 32-char Base32 secret.
    // Does NOT save to DB — caller must confirm first.

auth_totp_verify(string $secret, string $code): bool
    // Verifies a 6-digit code against $secret.
    // Accepts ±1 time window (90 s clock drift tolerance).
    // Returns false immediately if $code is not exactly 6 digits.

auth_totp_uri(string $secret, string $label, string $issuer): string
    // Returns otpauth://totp/... URI for QR code generation.

auth_totp_enable(mysqli $con, int $userId): ?string
    // Generates a new secret and returns it for QR display.
    // Does NOT save to DB yet — caller must confirm with auth_totp_confirm().
    // Returns null if user not found.

auth_totp_confirm(mysqli $con, int $userId, string $secret, string $code): bool
    // Verifies $code matches $secret, then saves $secret to auth_accounts.totp_secret.
    // Returns true on success, false on wrong code or DB error.

auth_totp_disable(mysqli $con, int $userId): void
    // Sets auth_accounts.totp_secret = NULL for $userId.

// Internal helpers (not in public API):
_auth_totp_hotp(string $secret, int $counter): string
_auth_totp_base32_encode(string $input): string
_auth_totp_base32_decode(string $input): string
```

### Changes to `src/auth.php`

`auth_login()` gains a TOTP branch after password verification succeeds:

```php
// After password_verify() passes — existing code continues as normal.
// New block inserted before session_regenerate_id():

$totp = $row['totp_secret'] ?? null;
if ($totp !== null) {
    // Don't set up the real session yet.
    $_SESSION['auth_totp_pending'] = [
        'user_data' => $row,
        'until'     => time() + 300,  // 5-minute window
        'attempts'  => 0,
    ];
    return ['ok' => true, 'totp_required' => true];
}
// ... existing session setup continues for non-2FA users ...
```

New function `auth_totp_complete(mysqli $con, string $code): array`:

```php
// Returns ['ok' => true] on success (session is fully set up).
// Returns ['ok' => false, 'error' => '...'] on failure.
// Reads $_SESSION['auth_totp_pending'], checks TTL and attempt count (max 5),
// calls auth_totp_verify(), then runs the existing session-setup logic.
// On success or final failure: unsets $_SESSION['auth_totp_pending'].
```

The session-setup block (currently inline in `auth_login()`) is extracted into a private helper `_auth_setup_session(array $row): void` so both `auth_login()` and `auth_totp_complete()` call it.

### Changes to `src/admin.php`

`admin_edit_user()` gains an optional `bool $totp_reset = false` parameter:

```php
function admin_edit_user(
    mysqli $con, int $targetId, string $email,
    string $rights, int $disabled, int $debug,
    bool $totp_reset = false
): bool
```

When `$totp_reset` is true, also executes:
```sql
UPDATE auth_accounts SET totp_secret = NULL WHERE id = ?
```

---

## Layer 2 — Per-app login step

Both wlmonitor and simplechat get identical changes here.

### `web/authentication.php`

Add handling for the `totp_required` return value:

```php
$result = auth_login($con, $username, $password);
if ($result['ok'] && !empty($result['totp_required'])) {
    header('Location: ' . basePath('/totp_verify.php'));
    exit;
}
// existing ok/error handling unchanged
```

### New `web/totp_verify.php`

Public page (no `auth_require()`). Uses the same `auth-card` visual pattern as `login.php`.

**GET:** Checks `$_SESSION['auth_totp_pending']` exists and TTL not expired. If missing/expired: clears session key, adds alert "Sitzung abgelaufen", redirects to login.

**POST:** Verifies CSRF. Calls `auth_totp_complete($con, $code)`:
- On `['ok' => true]` → redirect to app home (`basePath('/index.php')`)
- On `['ok' => false]` → display error inline, re-render form

The form has a single `<input type="text" inputmode="numeric" maxlength="6">` field for the code and a link back to login (which clears the pending session).

---

## Layer 3 — Per-app management UI

### New `web/security.php`

Requires `auth_require()`. Linked from the user dropdown as "Passwort & 2FA". Uses each app's standard page wrapper (`adminPage()` in simplechat, `html_header.php` in wlmonitor).

Two sections:

**Change password:**
- Fields: current password, new password (min 8, max 1000), confirm
- POST action: verify current password with `password_verify()`, hash new with `password_hash(PASSWORD_BCRYPT, ['cost'=>13])`, update `auth_accounts.password`
- CSRF required

**2FA management (when 2FA is OFF):**
- "2FA aktivieren" button
- On click (POST): calls `auth_totp_enable()`, stores returned secret in `$_SESSION['totp_setup_secret']` (5-min TTL), shows:
  - QR code rendered server-side via `chillerlan/php-qrcode` (Composer package, added to `erikr/auth`'s `composer.json`), output as inline SVG `<img>` — no JS or external requests needed
  - The raw secret as text (for manual entry)
  - A 6-digit input + "Bestätigen" button
- On confirm POST: calls `auth_totp_confirm($con, $userId, $_SESSION['totp_setup_secret'], $code)`
  - Success: unset session key, show "2FA ist jetzt aktiv"
  - Failure: show "Code ungültig"

**2FA management (when 2FA is ON):**
- Status badge "2FA aktiv"
- "2FA deaktivieren" button (POST + CSRF + confirm dialog)
- Calls `auth_totp_disable($con, $userId)`

### User dropdown changes

Each app's header dropdown gains a link:
- **wlmonitor** (`inc/html_header.php`): add `<a href="security.php">Passwort &amp; 2FA</a>` as a `dropdown-link-btn`
- **simplechat** (header rendering code): same link

### Admin edit-user changes

**wlmonitor `web/admin.php`** — edit modal gets a new checkbox:
```html
<div class="form-check">
  <input class="form-check-input" type="checkbox" name="totp_reset" id="editTotpReset" value="1">
  <label class="form-check-label" for="editTotpReset">2FA zurücksetzen</label>
</div>
```
JS populates it as always-unchecked when opening the modal.

`web/api.php` `admin_user_edit` case: pass `(bool)($_POST['totp_reset'] ?? false)` as 7th arg to `wl_admin_edit_user()`, which passes it through to `admin_edit_user()`.

**simplechat `web/admin.php`** — Aktionen edit form gets the same checkbox. POST handler `edit_user` passes `totp_reset` to `admin_edit_user()`.

---

## Error handling

| Situation | Behaviour |
|-----------|-----------|
| Pending session expired | Clear key, redirect to login with "Sitzung abgelaufen" |
| Wrong TOTP code (< 5 attempts) | Show error inline, increment `$_SESSION['auth_totp_pending']['attempts']` |
| Wrong TOTP code (5th attempt) | Clear pending session, redirect to login with "Zu viele Fehlversuche" |
| `auth_totp_confirm()` wrong code | Show "Code ungültig", re-render QR + confirm form |
| DB error in `auth_totp_disable()` | Silently logs via `appendLog()` (void function, admin can retry) |
| Admin resets 2FA while user is mid-login | User's TOTP verify will fail (secret gone), they must re-login with password only |

---

## Testing (`erikr/auth/tests/Unit/TotpTest.php`)

- `test_generate_secret_returns_32_char_base32()` — length and charset
- `test_verify_accepts_valid_code()` — generate code from known secret+time, verify
- `test_verify_rejects_wrong_code()` — wrong 6-digit string
- `test_verify_rejects_non_numeric()` — "abcdef"
- `test_confirm_saves_secret_on_valid_code()` — stub UPDATE, assert bound params
- `test_confirm_returns_false_on_wrong_code()` — no DB call
- `test_disable_sets_null()` — stub UPDATE, assert totp_secret=NULL
- `test_auth_login_returns_totp_required_when_secret_set()` — mock SELECT returning row with totp_secret, assert return value and session state
- `test_auth_totp_complete_completes_session_on_valid_code()` — set up pending session, call complete, assert `$_SESSION['loggedin']`
- `test_auth_totp_complete_fails_after_five_attempts()` — assert pending cleared, error returned

---

## File map

| File | Action |
|------|--------|
| `erikr/auth/db/06_totp.sql` | Create |
| `erikr/auth/src/totp.php` | Create |
| `erikr/auth/src/auth.php` | Modify (totp branch + extract session setup helper) |
| `erikr/auth/src/admin.php` | Modify (totp_reset param) |
| `erikr/auth/tests/Unit/TotpTest.php` | Create |
| `wlmonitor/web/authentication.php` | Modify |
| `wlmonitor/web/totp_verify.php` | Create |
| `wlmonitor/web/security.php` | Create |
| `wlmonitor/inc/html_header.php` | Modify (dropdown link) |
| `wlmonitor/inc/admin.php` | Modify (`wl_admin_edit_user()` passes totp_reset through) |
| `wlmonitor/web/admin.php` | Modify (2FA reset checkbox + modal wiring fix) |
| `wlmonitor/web/api.php` | Modify (pass totp_reset) |
| `simplechat-2.1/web/authentication.php` | Modify |
| `simplechat-2.1/web/totp_verify.php` | Create |
| `simplechat-2.1/web/security.php` | Create |
| `simplechat-2.1/web/admin.php` | Modify (2FA reset checkbox) |
| `simplechat-2.1/inc/html.php` or header | Modify (dropdown link) |
