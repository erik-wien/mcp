# Admin Unification Design

**Date:** 2026-04-13
**Scope:** Sub-project B — Unify user admin across wlmonitor and simplechat by moving shared functions into `erikr/auth`

---

## Overview

User accounts live in the shared `jardyx_auth.auth_accounts` table, managed by the `erikr/auth` Composer library. wlmonitor has a working user admin panel; simplechat has the UI skeleton but no implementation behind it. Both apps previously relied on self-registration — this is replaced by admin-only user creation with an email invitation flow.

All common user management logic moves into `erikr/auth`. Apps call library functions and handle only their own per-user preferences (stored in their own DB tables, keyed by `auth_accounts.id`).

---

## Section 1: Library Additions to `erikr/auth`

### New files

**`src/admin.php`** — added to `autoload.files` in `composer.json`

| Function | Signature | Description |
|---|---|---|
| `admin_require` | `(): void` | Guards admin pages: checks `$_SESSION['rights'] === 'Admin'`, redirects to `index.php` if not |
| `admin_list_users` | `(mysqli $con, int $page, int $perPage, string $filter): array` | Paginated user list. Returns `['users' => [...], 'total' => int, 'page' => int, 'per_page' => int]`. Each user row: `['id', 'username', 'email', 'rights', 'disabled', 'debug']`. Apps query app-specific preferences separately and merge by `id`. |
| `admin_create_user` | `(mysqli $con, string $username, string $email, string $rights, string $baseUrl): int` | Inserts account (`disabled=1`, placeholder hash), creates invite token, sends invitation email. Returns `user_id`. Throws on duplicate username/email. |
| `admin_edit_user` | `(mysqli $con, int $targetId, string $email, string $rights, int $disabled, int $debug): bool` | Updates common fields. Validates `rights` against `['Admin', 'User']` whitelist. Logs action. |
| `admin_reset_password` | `(mysqli $con, int $targetId, string $baseUrl): bool` | Sends a fresh invite email to the user (same flow as creation). Replaces any existing token. |
| `admin_delete_user` | `(mysqli $con, int $targetId, int $requestingUserId): bool` | Deletes account. Blocks self-deletion. Logs action. |

**`src/invite.php`** — added to `autoload.files` in `composer.json`

| Function | Signature | Description |
|---|---|---|
| `invite_create_token` | `(mysqli $con, int $userId): string` | Generates `bin2hex(random_bytes(32))` (64 hex chars, 256-bit entropy). Stores in `auth_invite_tokens` with 48h expiry (`REPLACE INTO` — replaces stale tokens). Returns token. |
| `invite_send_email` | `(string $email, string $username, string $token, string $baseUrl): bool` | Sends "Set your password" email via existing `mailer.php`. Link: `{baseUrl}/setpassword.php?token={token}` |
| `invite_verify_token` | `(mysqli $con, string $token): ?int` | Returns `user_id` if token exists and `expires_at > NOW()`. Returns `null` for unknown or expired tokens. |
| `invite_complete` | `(mysqli $con, int $userId, string $password): bool` | Hashes password (bcrypt cost 13), sets `disabled=0`, deletes token from `auth_invite_tokens`. |

### New DB table

Migration: `db/05_invite_tokens.sql` (run against `jardyx_auth`):

```sql
CREATE TABLE auth_invite_tokens (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    INT         NOT NULL,
  token      VARCHAR(64) NOT NULL UNIQUE,
  expires_at DATETIME    NOT NULL,
  FOREIGN KEY (user_id) REFERENCES auth_accounts(id) ON DELETE CASCADE
);
```

Token is stored separately from `auth_accounts.activation_code` to keep the accounts table clean and allow both invite and password-reset flows to share the same mechanism.

---

## Section 2: Invitation & Set-Password Flow

### Admin creates a user

```
Admin submits: username, email, rights (Admin|User)
  → admin_create_user()
      → INSERT auth_accounts (disabled=1, placeholder hash, activation_code='invited')
      → invite_create_token() → stores token in auth_invite_tokens (48h TTL)
      → invite_send_email() → sends link: {baseUrl}/setpassword.php?token={token}
  → Admin sees: "Invitation sent to email@example.com"
```

### User follows the link

```
GET /setpassword.php?token=abc123
  → invite_verify_token() → returns user_id (or shows "link invalid or expired")
  → Show: "Welcome {username}, please set your password" form

POST /setpassword.php
  → Validate: password ≥ 8 chars, confirmation matches
  → invite_complete() → bcrypt-13 hash, disabled=0, token deleted
  → Redirect to login with success message
```

### Admin resets a password

```
Admin clicks "Send password reset" for a user
  → admin_reset_password(con, targetId, baseUrl)
      → invite_create_token() → REPLACE INTO (invalidates old token)
      → invite_send_email()
  → Admin sees: "Password reset email sent to {email}"
```

### Token security

- 64 hex chars (256-bit entropy) — computationally unguessable
- 48-hour expiry
- Single-use: deleted on `invite_complete()`
- `REPLACE INTO` on re-invite: no stale token accumulation
- Cascade delete: tokens removed when user account is deleted

### `web/setpassword.php` (per app)

Thin file (~15 lines) in each app. Responsibilities:
- Call `invite_verify_token()` and `invite_complete()` from the library
- Render using the app's own header/footer helpers
- Redirect to `login.php` on success

---

## Section 3: Per-App Migration

### `erikr/auth`

| File | Action |
|---|---|
| `src/admin.php` | Create |
| `src/invite.php` | Create |
| `composer.json` | Add both to `autoload.files` |
| `db/05_invite_tokens.sql` | Create — `CREATE TABLE auth_invite_tokens` |
| `tests/AdminTest.php` | Create — unit tests (see Section 4) |
| `tests/InviteTest.php` | Create — unit tests (see Section 4) |

### wlmonitor

| File | Action |
|---|---|
| `inc/admin.php` | Replace user management functions with calls to `erikr/auth`. Keep `wl_preferences`/`departures` handling locally — query separately after `admin_list_users()` and merge. |
| `web/admin.php` | Add "Create user" form. Update password reset to show "Email sent" confirmation. |
| `web/setpassword.php` | Create — thin wrapper, uses wlmonitor header/footer |
| `web/register.php` | **Delete** — no longer needed |
| `web/activate.php` | **Delete** — replaced by `setpassword.php` |
| `composer.json` | `composer update erikr/auth` |

### simplechat

| File | Action |
|---|---|
| `inc/admin.php` | Wire the 'users' tab to call shared library functions |
| `web/admin.php` | Implement users section body: list, create, edit, delete, reset |
| `web/setpassword.php` | Create — thin wrapper, uses simplechat's `adminPage()` helper |
| `web/login.php` | Remove any registration link if present |
| `composer.json` | `composer update erikr/auth` |

---

## Section 4: Testing

### `erikr/auth` unit tests (PHPUnit)

**`tests/AdminTest.php`:**
- `admin_create_user()` inserts account with `disabled=1`
- `admin_create_user()` rejects duplicate username
- `admin_create_user()` rejects duplicate email
- `admin_delete_user()` deletes target user
- `admin_delete_user()` blocks self-deletion (returns false)
- `admin_edit_user()` validates rights against whitelist — unknown value coerced to 'User'
- `admin_edit_user()` updates fields correctly

**`tests/InviteTest.php`:**
- `invite_create_token()` stores token with correct 48h expiry
- `invite_create_token()` replaces existing token on re-invite (`REPLACE INTO`)
- `invite_verify_token()` returns `user_id` for valid token
- `invite_verify_token()` returns `null` for expired token
- `invite_verify_token()` returns `null` for unknown token
- `invite_complete()` sets bcrypt-13 hash, sets `disabled=0`, deletes token

### Per-app integration checks (manual)

**Both apps:**
- Admin creates user → invite email arrives → link opens `setpassword.php` → user sets password → login works
- Admin resets password → new email arrives → old token returns "link invalid"
- Non-admin user cannot reach admin pages (redirected to index)
- Expired token (> 48h) shows "link invalid or expired" message

**wlmonitor only:**
- Confirm `register.php` and `activate.php` return 404 after deletion
- `departures` column still appears in wlmonitor user list (app-local query)

**simplechat only:**
- Users tab in admin panel shows full user list and all CRUD actions work
