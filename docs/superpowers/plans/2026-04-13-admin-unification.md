# Admin Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move shared user management functions into `erikr/auth`, add an invite-based user creation flow, and wire both wlmonitor and simplechat to use the library.

**Architecture:** New files `src/admin.php` and `src/invite.php` are added to `erikr/auth` and loaded via Composer autoload. wlmonitor replaces its existing `inc/admin.php` implementations with thin wrappers that merge app-specific preferences. simplechat's users tab is replaced with auth_accounts CRUD using the same library calls. Both apps get a `web/setpassword.php` for the invitation flow.

**Tech Stack:** PHP 8.2, MySQLi, PHPUnit 13, PHPMailer 7, Composer path-repository (`../auth`).

---

## Repository paths

| Repo | Absolute path |
|---|---|
| `erikr/auth` | `/Users/erikr/Git/auth` |
| `wlmonitor` | `/Users/erikr/Git/wlmonitor` |
| `simplechat-2.1` | `/Users/erikr/Git/simplechat-2.1` |

## Critical context

- Both apps already have `"erikr/auth": "*"` in their `composer.json` via a path repository pointing to `../auth`. After adding new files to the library, run `composer update erikr/auth` in each app — **not** `composer install`. There is no `composer.json` change needed in the apps.
- The `AUTH_DB_PREFIX` constant controls cross-database SQL:
  - wlmonitor: `AUTH_DB_PREFIX = 'jardyx_auth.'` → queries use `jardyx_auth.auth_accounts`
  - simplechat: `AUTH_DB_PREFIX = ''` → `$con` already connects to jardyx_auth directly
  - tests/bootstrap.php: `AUTH_DB_PREFIX = ''`
- All library functions must use `AUTH_DB_PREFIX . 'auth_accounts'` (never hardcode the DB name).
- `appendLog()` (from `src/log.php`) uses the same `$con` — stub `prepare()` handles its queries too.
- wlmonitor already defines `APP_BASE_URL` constant in `inc/initialize.php`. simplechat does not — Task 8 adds it.
- wlmonitor's current `inc/admin.php` defines `admin_list_users()` and `admin_edit_user()`. Once the library defines these names, wlmonitor's versions must be renamed (to `wl_admin_list_users` etc.) to avoid a PHP fatal error.
- simplechat's admin authentication uses `admin.json` + TOTP (not auth_accounts). The `$_SESSION['adminAuthenticated']` guard is separate from `$_SESSION['rights']`. Pass `-1` as `$requestingUserId` to `admin_delete_user()` so self-deletion protection never triggers.

---

## File map

**`erikr/auth` — create:**

| File | Responsibility |
|---|---|
| `db/05_invite_tokens.sql` | Create `auth_invite_tokens` table |
| `src/invite.php` | `invite_create_token`, `invite_send_email`, `invite_verify_token`, `invite_complete` |
| `src/admin.php` | `admin_require`, `admin_list_users`, `admin_create_user`, `admin_edit_user`, `admin_reset_password`, `admin_delete_user` |
| `tests/Unit/InviteTest.php` | 6 unit tests for invite.php |
| `tests/Unit/AdminTest.php` | 7 unit tests for admin.php |

**`erikr/auth` — modify:**

| File | Change |
|---|---|
| `composer.json` | Add `src/invite.php` and `src/admin.php` to `autoload.files` |
| `tests/bootstrap.php` | Add SMTP_* constant definitions (PHPMailer needs them; actual send will fail + be caught) |

**`wlmonitor` — modify:**

| File | Change |
|---|---|
| `inc/admin.php` | Replace with `wl_admin_list_users` and `wl_admin_edit_user` wrappers |
| `web/api.php` | Rename function calls; add `admin_user_create` case; change `admin_user_reset` to email flow |
| `web/admin.php` | Add create-user modal; update reset JS to show "E-Mail versandt" |

**`wlmonitor` — create/delete:**

| File | Action |
|---|---|
| `web/setpassword.php` | Create — thin wrapper using wlmonitor header/footer |
| `web/register.php` | Delete |
| `web/activate.php` | Delete |

**`simplechat-2.1` — modify:**

| File | Change |
|---|---|
| `inc/initialize.php` | Load root `config.yaml`; define `SMTP_*` constants and `APP_BASE_URL` |
| `web/admin.php` | Add POST handlers for user CRUD; replace users section HTML |

**`simplechat-2.1` — create:**

| File | Action |
|---|---|
| `web/setpassword.php` | Create — thin wrapper using simplechat's `adminPage()` helper |

---

## Task 1: erikr/auth — DB migration

**Files:**
- Create: `/Users/erikr/Git/auth/db/05_invite_tokens.sql`

- [ ] **Step 1: Create migration file**

```sql
-- db/05_invite_tokens.sql
-- Run against jardyx_auth before deploying.
CREATE TABLE auth_invite_tokens (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    INT         NOT NULL,
  token      VARCHAR(64) NOT NULL UNIQUE,
  expires_at DATETIME    NOT NULL,
  FOREIGN KEY (user_id) REFERENCES auth_accounts(id) ON DELETE CASCADE
);
```

- [ ] **Step 2: Run migration**

```bash
cd /Users/erikr/Git/auth
mysql -u wlmonitor -p jardyx_auth < db/05_invite_tokens.sql
```

Expected: no errors. If the table already exists: `ERROR 1050` — skip, already applied.

- [ ] **Step 3: Verify**

```bash
mysql -u wlmonitor -p jardyx_auth -e "DESCRIBE auth_invite_tokens;"
```

Expected output includes columns: `id`, `user_id`, `token`, `expires_at`.

- [ ] **Step 4: Commit**

```bash
cd /Users/erikr/Git/auth
git add db/05_invite_tokens.sql
git commit -m "feat: add auth_invite_tokens migration"
```

---

## Task 2: erikr/auth — src/invite.php (TDD)

**Files:**
- Modify: `/Users/erikr/Git/auth/tests/bootstrap.php`
- Create: `/Users/erikr/Git/auth/tests/Unit/InviteTest.php`
- Create: `/Users/erikr/Git/auth/src/invite.php`
- Modify: `/Users/erikr/Git/auth/composer.json`

- [ ] **Step 1: Add SMTP constants to test bootstrap**

Append to `/Users/erikr/Git/auth/tests/bootstrap.php`:

```php
// SMTP constants required by invite_send_email → send_mail.
// Connection to 127.0.0.1:1025 will fail; invite_send_email() catches the exception.
define('SMTP_HOST',      '127.0.0.1');
define('SMTP_PORT',      1025);
define('SMTP_USER',      'test@example.com');
define('SMTP_PASS',      'test');
define('SMTP_FROM',      'test@example.com');
define('SMTP_FROM_NAME', 'Test');
```

- [ ] **Step 2: Write InviteTest.php (failing)**

Create `/Users/erikr/Git/auth/tests/Unit/InviteTest.php`:

```php
<?php

namespace ErikR\Auth\Tests\Unit;

use PHPUnit\Framework\TestCase;

class InviteTest extends TestCase
{
    // ── Helpers ───────────────────────────────────────────────────────────────

    /** Build a stub mysqli where all prepare() calls return the same generic stmt. */
    private function stubCon(?callable $onPrepare = null): \mysqli
    {
        $stmt = $this->createStub(\mysqli_stmt::class);
        $stmt->method('bind_param')->willReturn(true);
        $stmt->method('execute')->willReturn(true);
        $stmt->method('close')->willReturn(true);

        $con = $this->createStub(\mysqli::class);
        if ($onPrepare) {
            $con->method('prepare')->willReturnCallback(
                fn(string $sql) => ($onPrepare($sql) ?? $stmt)
            );
        } else {
            $con->method('prepare')->willReturn($stmt);
        }

        return $con;
    }

    /** Build a stub mysqli_result that returns $row on the first fetch_assoc() call. */
    private function stubResult(?array $row): \mysqli_result
    {
        $result = $this->createStub(\mysqli_result::class);
        $result->method('fetch_assoc')->willReturn($row);
        return $result;
    }

    /** Build a stub con where prepare() returns a stmt whose get_result() returns $result. */
    private function stubConWithResult(\mysqli_result $result): \mysqli
    {
        $stmt = $this->createStub(\mysqli_stmt::class);
        $stmt->method('bind_param')->willReturn(true);
        $stmt->method('execute')->willReturn(true);
        $stmt->method('get_result')->willReturn($result);
        $stmt->method('close')->willReturn(true);

        $con = $this->createStub(\mysqli::class);
        $con->method('prepare')->willReturn($stmt);
        return $con;
    }

    // ── invite_create_token ───────────────────────────────────────────────────

    public function test_create_token_returns_64_hex_chars(): void
    {
        $token = invite_create_token($this->stubCon(), 1);
        $this->assertMatchesRegularExpression('/^[0-9a-f]{64}$/', $token);
    }

    public function test_create_token_uses_replace_into(): void
    {
        $sql = '';
        $stmt = $this->createStub(\mysqli_stmt::class);
        $stmt->method('bind_param')->willReturn(true);
        $stmt->method('execute')->willReturn(true);
        $stmt->method('close')->willReturn(true);

        $con = $this->createMock(\mysqli::class);
        $con->method('prepare')
            ->willReturnCallback(function (string $s) use (&$sql, $stmt) {
                $sql = $s;
                return $stmt;
            });

        invite_create_token($con, 7);
        $this->assertStringContainsString('REPLACE INTO', strtoupper($sql));
    }

    // ── invite_verify_token ───────────────────────────────────────────────────

    public function test_verify_token_returns_user_id_for_valid_token(): void
    {
        $con = $this->stubConWithResult($this->stubResult(['user_id' => 42]));
        $this->assertSame(42, invite_verify_token($con, 'validtoken'));
    }

    public function test_verify_token_returns_null_for_expired_token(): void
    {
        // DB returns no row because expires_at > NOW() filters it out.
        $con = $this->stubConWithResult($this->stubResult(null));
        $this->assertNull(invite_verify_token($con, 'expiredtoken'));
    }

    public function test_verify_token_returns_null_for_unknown_token(): void
    {
        $con = $this->stubConWithResult($this->stubResult(null));
        $this->assertNull(invite_verify_token($con, 'unknowntoken'));
    }

    // ── invite_complete ───────────────────────────────────────────────────────

    public function test_complete_prepares_update_then_delete(): void
    {
        $sqls = [];
        $stmt = $this->createStub(\mysqli_stmt::class);
        $stmt->method('bind_param')->willReturn(true);
        $stmt->method('execute')->willReturn(true);
        $stmt->method('close')->willReturn(true);

        $con = $this->createMock(\mysqli::class);
        $con->method('prepare')
            ->willReturnCallback(function (string $s) use (&$sqls, $stmt) {
                $sqls[] = $s;
                return $stmt;
            });

        invite_complete($con, 5, 'newpassword123');

        $this->assertCount(2, $sqls);
        $this->assertMatchesRegularExpression('/UPDATE/i', $sqls[0]);
        $this->assertMatchesRegularExpression('/DELETE/i', $sqls[1]);
    }
}
```

- [ ] **Step 3: Run tests — expect failure**

```bash
cd /Users/erikr/Git/auth
./vendor/bin/phpunit tests/Unit/InviteTest.php --no-coverage
```

Expected: ERRORS — `Call to undefined function invite_create_token()`

- [ ] **Step 4: Create src/invite.php**

```php
<?php
/**
 * src/invite.php — User invitation and password-set flow.
 *
 * Requires:
 *  - AUTH_DB_PREFIX constant  (e.g. 'jardyx_auth.' or '')
 *  - SMTP_* constants + send_mail() from src/mailer.php
 *  - appendLog() from src/log.php
 */

/**
 * Generate and persist a 48-hour invite token for $userId.
 * Uses REPLACE INTO so re-inviting a user invalidates any existing token.
 *
 * @return string 64-char hex token (256-bit entropy).
 */
function invite_create_token(mysqli $con, int $userId): string
{
    $table   = AUTH_DB_PREFIX . 'auth_invite_tokens';
    $token   = bin2hex(random_bytes(32));
    $expires = date('Y-m-d H:i:s', time() + 48 * 3600);

    $stmt = $con->prepare(
        "REPLACE INTO {$table} (user_id, token, expires_at) VALUES (?, ?, ?)"
    );
    $stmt->bind_param('iss', $userId, $token, $expires);
    $stmt->execute();
    $stmt->close();

    return $token;
}

/**
 * Send "Set your password" email to the user.
 * Link: {baseUrl}/setpassword.php?token={token}
 *
 * @return bool True on success; false if the mailer throws.
 */
function invite_send_email(string $email, string $username, string $token, string $baseUrl): bool
{
    $link    = rtrim($baseUrl, '/') . '/setpassword.php?token=' . urlencode($token);
    $subject = 'Passwort einrichten';
    $bodyHtml = '<p>Hallo ' . htmlspecialchars($username, ENT_QUOTES, 'UTF-8') . ',</p>'
              . '<p>Bitte richten Sie Ihr Passwort ein:</p>'
              . '<p><a href="' . htmlspecialchars($link, ENT_QUOTES, 'UTF-8') . '">'
              . htmlspecialchars($link, ENT_QUOTES, 'UTF-8') . '</a></p>'
              . '<p>Dieser Link ist 48&nbsp;Stunden g&uuml;ltig.</p>';
    $bodyText = "Hallo $username,\n\nBitte richten Sie Ihr Passwort ein:\n$link\n\n"
              . "Dieser Link ist 48 Stunden gültig.";

    try {
        send_mail($email, $username, $subject, $bodyHtml, $bodyText);
        return true;
    } catch (\Throwable $e) {
        return false;
    }
}

/**
 * Verify an invite token.
 *
 * @return int|null user_id if token exists and has not expired; null otherwise.
 */
function invite_verify_token(mysqli $con, string $token): ?int
{
    $table = AUTH_DB_PREFIX . 'auth_invite_tokens';
    $stmt  = $con->prepare(
        "SELECT user_id FROM {$table} WHERE token = ? AND expires_at > NOW()"
    );
    $stmt->bind_param('s', $token);
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    return $row ? (int) $row['user_id'] : null;
}

/**
 * Complete the invitation: hash password, enable account, delete token.
 *
 * @return bool True if the account row was updated.
 */
function invite_complete(mysqli $con, int $userId, string $password): bool
{
    $table      = AUTH_DB_PREFIX . 'auth_accounts';
    $tokenTable = AUTH_DB_PREFIX . 'auth_invite_tokens';
    $hash       = password_hash($password, PASSWORD_BCRYPT, ['cost' => 13]);

    $stmt = $con->prepare(
        "UPDATE {$table} SET password = ?, disabled = 0, activation_code = 'activated' WHERE id = ?"
    );
    $stmt->bind_param('si', $hash, $userId);
    $stmt->execute();
    $ok = $stmt->affected_rows > 0;
    $stmt->close();

    $stmt = $con->prepare("DELETE FROM {$tokenTable} WHERE user_id = ?");
    $stmt->bind_param('i', $userId);
    $stmt->execute();
    $stmt->close();

    return $ok;
}
```

- [ ] **Step 5: Add invite.php to composer.json autoload.files**

Edit `/Users/erikr/Git/auth/composer.json` — add `"src/invite.php"` to the `autoload.files` array:

```json
{
    "name": "erikr/auth",
    "description": "Shared auth, session, CSRF, logging and mailer library",
    "type": "library",
    "require": {
        "php": ">=8.2",
        "phpmailer/phpmailer": "^7.0"
    },
    "require-dev": {
        "phpunit/phpunit": "^13.0"
    },
    "autoload": {
        "files": [
            "src/log.php",
            "src/csrf.php",
            "src/auth.php",
            "src/mailer.php",
            "src/invite.php",
            "src/bootstrap.php"
        ]
    },
    "autoload-dev": {
        "psr-4": {
            "ErikR\\Auth\\Tests\\": "tests/"
        }
    }
}
```

Note: `src/admin.php` will be added in Task 3. Leave `src/bootstrap.php` last — it runs side-effects.

- [ ] **Step 6: Regenerate autoloader**

```bash
cd /Users/erikr/Git/auth
composer dump-autoload
```

- [ ] **Step 7: Run tests — expect pass**

```bash
./vendor/bin/phpunit tests/Unit/InviteTest.php --no-coverage
```

Expected: `OK (6 tests, 6 assertions)` (or similar count — the exact assertion count depends on what PHPUnit counts per test).

---

## Task 3: erikr/auth — src/admin.php (TDD)

**Files:**
- Create: `/Users/erikr/Git/auth/tests/Unit/AdminTest.php`
- Create: `/Users/erikr/Git/auth/src/admin.php`
- Modify: `/Users/erikr/Git/auth/composer.json`

- [ ] **Step 1: Write AdminTest.php (failing)**

Create `/Users/erikr/Git/auth/tests/Unit/AdminTest.php`:

```php
<?php

namespace ErikR\Auth\Tests\Unit;

use PHPUnit\Framework\TestCase;

class AdminTest extends TestCase
{
    // ── Helpers ───────────────────────────────────────────────────────────────

    /** Build a generic stub con where all prepare() calls return $stmt. */
    private function stubCon(\mysqli_stmt $stmt = null): \mysqli
    {
        if ($stmt === null) {
            $stmt = $this->createStub(\mysqli_stmt::class);
            $stmt->method('bind_param')->willReturn(true);
            $stmt->method('execute')->willReturn(true);
            $stmt->method('close')->willReturn(true);
        }
        $con = $this->createStub(\mysqli::class);
        $con->method('prepare')->willReturn($stmt);
        return $con;
    }

    /** Build a mock con that records all SQL strings passed to prepare(). */
    private function captureCon(array &$sqls, \mysqli_stmt $stmt = null): \mysqli
    {
        if ($stmt === null) {
            $stmt = $this->createStub(\mysqli_stmt::class);
            $stmt->method('bind_param')->willReturn(true);
            $stmt->method('execute')->willReturn(true);
            $stmt->method('close')->willReturn(true);
        }
        $con = $this->createMock(\mysqli::class);
        $con->method('prepare')
            ->willReturnCallback(function (string $s) use (&$sqls, $stmt) {
                $sqls[] = $s;
                return $stmt;
            });
        return $con;
    }

    // ── admin_create_user ─────────────────────────────────────────────────────

    public function test_create_user_inserts_with_disabled_flag(): void
    {
        $sqls = [];
        $con  = $this->captureCon($sqls);

        // invite_send_email will try send_mail → connection refused → caught internally.
        admin_create_user($con, 'alice', 'alice@example.com', 'User', 'http://localhost/app');

        $this->assertMatchesRegularExpression('/INSERT INTO.*auth_accounts/i', $sqls[0]);
        $this->assertStringContainsString('disabled', $sqls[0]);
    }

    public function test_create_user_throws_on_duplicate_username(): void
    {
        $this->expectException(\mysqli_sql_exception::class);

        $stmt = $this->createStub(\mysqli_stmt::class);
        $stmt->method('bind_param')->willReturn(true);
        $stmt->method('execute')->willThrowException(
            new \mysqli_sql_exception("Duplicate entry 'alice' for key 'username'", 1062)
        );
        $stmt->method('close')->willReturn(true);

        admin_create_user($this->stubCon($stmt), 'alice', 'alice@example.com', 'User', 'http://localhost/app');
    }

    public function test_create_user_throws_on_duplicate_email(): void
    {
        $this->expectException(\mysqli_sql_exception::class);

        $stmt = $this->createStub(\mysqli_stmt::class);
        $stmt->method('bind_param')->willReturn(true);
        $stmt->method('execute')->willThrowException(
            new \mysqli_sql_exception("Duplicate entry 'alice@example.com' for key 'email'", 1062)
        );
        $stmt->method('close')->willReturn(true);

        admin_create_user($this->stubCon($stmt), 'bob', 'alice@example.com', 'User', 'http://localhost/app');
    }

    // ── admin_delete_user ─────────────────────────────────────────────────────

    public function test_delete_user_blocks_self_deletion(): void
    {
        $con = $this->createMock(\mysqli::class);
        $con->expects($this->never())->method('prepare');

        $result = admin_delete_user($con, 42, 42);
        $this->assertFalse($result);
    }

    public function test_delete_user_prepares_delete_sql(): void
    {
        $sqls = [];
        $con  = $this->captureCon($sqls);

        admin_delete_user($con, 7, 1);

        $this->assertMatchesRegularExpression('/DELETE FROM.*auth_accounts/i', $sqls[0]);
    }

    // ── admin_edit_user ───────────────────────────────────────────────────────

    public function test_edit_user_coerces_invalid_rights_to_user(): void
    {
        $capturedParams = null;
        $stmt = $this->createMock(\mysqli_stmt::class);
        $stmt->method('bind_param')
             ->willReturnCallback(function () use (&$capturedParams) {
                 $capturedParams = func_get_args();
                 return true;
             });
        $stmt->method('execute')->willReturn(true);
        $stmt->method('close')->willReturn(true);

        admin_edit_user($this->stubCon($stmt), 1, 'user@example.com', 'SuperAdmin', 0, 0);

        // bind_param signature: ('ssssi', $email, $rights, $disabled, $debug, $id)
        // Index 0: type string, Index 2: rights value
        $this->assertSame('User', $capturedParams[2]);
    }

    public function test_edit_user_prepares_update_sql(): void
    {
        $sqls = [];
        $con  = $this->captureCon($sqls);

        admin_edit_user($con, 1, 'user@example.com', 'Admin', 0, 0);

        $this->assertMatchesRegularExpression('/UPDATE.*auth_accounts/i', $sqls[0]);
    }
}
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd /Users/erikr/Git/auth
./vendor/bin/phpunit tests/Unit/AdminTest.php --no-coverage
```

Expected: ERRORS — `Call to undefined function admin_create_user()`

- [ ] **Step 3: Create src/admin.php**

```php
<?php
/**
 * src/admin.php — User administration functions.
 *
 * Requires:
 *  - AUTH_DB_PREFIX constant (e.g. 'jardyx_auth.' or '')
 *  - invite_create_token(), invite_send_email() from src/invite.php
 *  - appendLog() from src/log.php
 */

/**
 * Guard: redirect non-admins to index.php.
 * Call at the top of every admin page.
 */
function admin_require(): void
{
    if (($_SESSION['rights'] ?? '') !== 'Admin') {
        header('Location: index.php');
        exit;
    }
}

/**
 * Return a paginated, optionally filtered list of auth_accounts rows.
 *
 * Apps should call this and then merge their own per-user preference tables by id.
 *
 * @return array{
 *   users: array<int, array{id: int, username: string, email: string, rights: string, disabled: int, debug: int}>,
 *   total: int,
 *   page: int,
 *   per_page: int
 * }
 */
function admin_list_users(mysqli $con, int $page = 1, int $perPage = 25, string $filter = ''): array
{
    $table  = AUTH_DB_PREFIX . 'auth_accounts';
    $offset = ($page - 1) * $perPage;

    if ($filter !== '') {
        $escaped = str_replace(['\\', '%', '_'], ['\\\\', '\\%', '\\_'], $filter);
        $like    = '%' . $escaped . '%';
        $stmt    = $con->prepare(
            "SELECT id, username, email, rights, disabled, debug
             FROM {$table} WHERE username LIKE ? ORDER BY username LIMIT ? OFFSET ?"
        );
        $stmt->bind_param('sii', $like, $perPage, $offset);
    } else {
        $stmt = $con->prepare(
            "SELECT id, username, email, rights, disabled, debug
             FROM {$table} ORDER BY username LIMIT ? OFFSET ?"
        );
        $stmt->bind_param('ii', $perPage, $offset);
    }

    $stmt->execute();
    $result = $stmt->get_result();
    $rows   = [];
    while ($row = $result->fetch_assoc()) {
        $rows[] = [
            'id'       => (int) $row['id'],
            'username' => $row['username'],
            'email'    => $row['email'],
            'rights'   => $row['rights'],
            'disabled' => (int) $row['disabled'],
            'debug'    => (int) $row['debug'],
        ];
    }
    $stmt->close();

    if ($filter !== '') {
        $cstmt = $con->prepare("SELECT COUNT(*) FROM {$table} WHERE username LIKE ?");
        $cstmt->bind_param('s', $like);
    } else {
        $cstmt = $con->prepare("SELECT COUNT(*) FROM {$table}");
    }
    $cstmt->execute();
    $total = 0;
    $cstmt->bind_result($total);
    $cstmt->fetch();
    $cstmt->close();

    return ['users' => $rows, 'total' => (int) $total, 'page' => $page, 'per_page' => $perPage];
}

/**
 * Insert a new user account (disabled=1), create an invite token, and send email.
 *
 * @throws \mysqli_sql_exception on duplicate username or email.
 * @return int The new user's id.
 */
function admin_create_user(
    mysqli $con,
    string $username,
    string $email,
    string $rights,
    string $baseUrl
): int {
    $table   = AUTH_DB_PREFIX . 'auth_accounts';
    $rights  = in_array($rights, ['Admin', 'User'], true) ? $rights : 'User';
    $placeholder = password_hash(bin2hex(random_bytes(16)), PASSWORD_BCRYPT, ['cost' => 13]);

    $stmt = $con->prepare(
        "INSERT INTO {$table} (username, email, password, rights, disabled, activation_code)
         VALUES (?, ?, ?, ?, 1, 'invited')"
    );
    $stmt->bind_param('ssss', $username, $email, $placeholder, $rights);
    $stmt->execute();
    $userId = (int) $con->insert_id;
    $stmt->close();

    $token = invite_create_token($con, $userId);
    invite_send_email($email, $username, $token, $baseUrl);

    return $userId;
}

/**
 * Update a user's common fields.
 * Rights values not in ['Admin', 'User'] are silently coerced to 'User'.
 *
 * @return bool True if the row was updated.
 */
function admin_edit_user(
    mysqli $con,
    int    $targetId,
    string $email,
    string $rights,
    int    $disabled,
    int    $debug
): bool {
    $table  = AUTH_DB_PREFIX . 'auth_accounts';
    $rights = in_array($rights, ['Admin', 'User'], true) ? $rights : 'User';

    $stmt = $con->prepare(
        "UPDATE {$table} SET email = ?, rights = ?, disabled = ?, debug = ? WHERE id = ?"
    );
    $stmt->bind_param('ssssi', $email, $rights, $disabled, $debug, $targetId);
    $stmt->execute();
    $ok = $stmt->affected_rows > 0;
    $stmt->close();

    appendLog($con, 'admin', "User #$targetId updated.", 'web');
    return $ok;
}

/**
 * Send a fresh invite email to a user (same flow as creation, invalidates old token).
 *
 * @return bool True if the token was created and email was sent successfully.
 */
function admin_reset_password(mysqli $con, int $targetId, string $baseUrl): bool
{
    $table = AUTH_DB_PREFIX . 'auth_accounts';
    $stmt  = $con->prepare("SELECT email, username FROM {$table} WHERE id = ?");
    $stmt->bind_param('i', $targetId);
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$row) {
        return false;
    }

    $token = invite_create_token($con, $targetId);
    $sent  = invite_send_email($row['email'], $row['username'], $token, $baseUrl);

    appendLog($con, 'admin', "Password reset sent to user #$targetId.", 'web');
    return $sent;
}

/**
 * Permanently delete a user account.
 * Self-deletion is blocked: returns false if $targetId === $requestingUserId.
 *
 * @return bool True if a row was deleted.
 */
function admin_delete_user(mysqli $con, int $targetId, int $requestingUserId): bool
{
    if ($targetId === $requestingUserId) {
        return false;
    }

    $table = AUTH_DB_PREFIX . 'auth_accounts';
    $stmt  = $con->prepare("DELETE FROM {$table} WHERE id = ?");
    $stmt->bind_param('i', $targetId);
    $stmt->execute();
    $ok = $stmt->affected_rows > 0;
    $stmt->close();

    appendLog($con, 'admin', "User #$targetId deleted.", 'web');
    return $ok;
}
```

- [ ] **Step 4: Add admin.php to composer.json autoload.files**

Edit `/Users/erikr/Git/auth/composer.json` — add `"src/admin.php"` before `"src/bootstrap.php"`:

```json
"autoload": {
    "files": [
        "src/log.php",
        "src/csrf.php",
        "src/auth.php",
        "src/mailer.php",
        "src/invite.php",
        "src/admin.php",
        "src/bootstrap.php"
    ]
}
```

- [ ] **Step 5: Regenerate autoloader**

```bash
cd /Users/erikr/Git/auth
composer dump-autoload
```

- [ ] **Step 6: Run all tests — expect pass**

```bash
./vendor/bin/phpunit --no-coverage
```

Expected: `OK (N tests, N assertions)` — all Unit tests pass.

- [ ] **Step 7: Commit erikr/auth**

```bash
cd /Users/erikr/Git/auth
git add composer.json tests/bootstrap.php src/invite.php src/admin.php \
        tests/Unit/InviteTest.php tests/Unit/AdminTest.php
git commit -m "feat: add invite and admin library functions with unit tests"
```

---

## Task 4: wlmonitor — composer update + inc/admin.php

**Files:**
- Modify: `/Users/erikr/Git/wlmonitor/inc/admin.php`

The current file defines `admin_list_users()` and `admin_edit_user()` — these names are now taken by the library. Replace the entire file with thin wrappers named `wl_admin_list_users()` and `wl_admin_edit_user()` that call the library and add departures handling.

- [ ] **Step 1: composer update erikr/auth in wlmonitor**

```bash
cd /Users/erikr/Git/wlmonitor
composer update erikr/auth
```

Expected: Composer resolves the path repository and picks up the new src files.

- [ ] **Step 2: Replace inc/admin.php**

Overwrite `/Users/erikr/Git/wlmonitor/inc/admin.php` with:

```php
<?php
/**
 * inc/admin.php
 *
 * Thin wrappers around the erikr/auth admin library that add wlmonitor-specific
 * per-user preferences (wl_preferences.departures).
 *
 * All functions in this file call library functions from erikr/auth for auth_accounts
 * operations and handle wl_preferences locally.
 *
 * Authorization boundary
 * ──────────────────────
 * These functions do NOT check caller rights. All call sites in api.php must call
 * api_require_admin() before invoking any function here.
 */

/**
 * Paginated user list with wlmonitor departures preference merged in.
 *
 * Calls admin_list_users() from the library (which queries auth_accounts only),
 * then fetches departures from wl_preferences and merges by user_id.
 *
 * @return array Same shape as admin_list_users() but each user row also contains 'departures' key.
 */
function wl_admin_list_users(mysqli $con, int $page = 1, int $perPage = 25, string $filter = ''): array
{
    $data = admin_list_users($con, $page, $perPage, $filter);

    if (empty($data['users'])) {
        return $data;
    }

    $ids          = array_column($data['users'], 'id');
    $placeholders = implode(',', array_fill(0, count($ids), '?'));
    $types        = str_repeat('i', count($ids));
    $stmt         = $con->prepare(
        "SELECT user_id, departures FROM wl_preferences WHERE user_id IN ($placeholders)"
    );
    $stmt->bind_param($types, ...$ids);
    $stmt->execute();
    $result = $stmt->get_result();
    $prefs  = [];
    while ($row = $result->fetch_assoc()) {
        $prefs[(int) $row['user_id']] = (int) $row['departures'];
    }
    $stmt->close();

    foreach ($data['users'] as &$user) {
        $user['departures'] = $prefs[$user['id']] ?? MAX_DEPARTURES;
    }
    unset($user);

    return $data;
}

/**
 * Update a user's auth fields and wlmonitor departures preference.
 *
 * @return bool True if the auth_accounts row was updated.
 */
function wl_admin_edit_user(
    mysqli $con,
    int    $targetId,
    string $email,
    string $rights,
    int    $disabled,
    int    $departures,
    int    $debug
): bool {
    $ok = admin_edit_user($con, $targetId, $email, $rights, $disabled, $debug);

    $stmt = $con->prepare(
        'INSERT INTO wl_preferences (user_id, departures) VALUES (?, ?)
         ON DUPLICATE KEY UPDATE departures = VALUES(departures)'
    );
    $stmt->bind_param('ii', $targetId, $departures);
    $stmt->execute();
    $stmt->close();

    return $ok;
}
```

- [ ] **Step 3: Commit**

```bash
cd /Users/erikr/Git/wlmonitor
git add inc/admin.php
git commit -m "refactor: replace admin.php with thin library wrappers"
```

---

## Task 5: wlmonitor — web/api.php

**Files:**
- Modify: `/Users/erikr/Git/wlmonitor/web/api.php`

Four changes to make:
1. `admin_users` case: call `wl_admin_list_users` instead of `admin_list_users`
2. `admin_user_edit` case: call `wl_admin_edit_user` instead of `admin_edit_user`
3. `admin_user_reset` case: call library `admin_reset_password($con, $id, APP_BASE_URL)`, return `{ok: bool}` instead of `{password: string}`
4. New `admin_user_create` case: call `admin_create_user($con, username, email, rights, APP_BASE_URL)`

- [ ] **Step 1: Update admin_users case**

Find and replace in `web/api.php`:

```php
        case 'admin_users':
            api_require_admin();
            $page   = max(1, (int) ($_GET['page'] ?? 1));
            $filter = $_GET['filter'] ?? '';
            api_json(admin_list_users($con, $page, 25, $filter));
```

Replace with:

```php
        case 'admin_users':
            api_require_admin();
            $page   = max(1, (int) ($_GET['page'] ?? 1));
            $filter = $_GET['filter'] ?? '';
            api_json(wl_admin_list_users($con, $page, 25, $filter));
```

- [ ] **Step 2: Update admin_user_edit case**

Find and replace:

```php
        case 'admin_user_edit':
            api_require_admin();
            api_require_csrf();
            $ok = admin_edit_user(
                $con,
                (int) ($_POST['id']         ?? 0),
                $_POST['email']             ?? '',
                $_POST['rights']            ?? 'User',
                (int) ($_POST['disabled']   ?? 0),
                (int) ($_POST['departures'] ?? MAX_DEPARTURES),
                (int) ($_POST['debug']      ?? 0)
            );
            api_json(['ok' => $ok]);
```

Replace with:

```php
        case 'admin_user_edit':
            api_require_admin();
            api_require_csrf();
            $ok = wl_admin_edit_user(
                $con,
                (int) ($_POST['id']         ?? 0),
                $_POST['email']             ?? '',
                $_POST['rights']            ?? 'User',
                (int) ($_POST['disabled']   ?? 0),
                (int) ($_POST['departures'] ?? MAX_DEPARTURES),
                (int) ($_POST['debug']      ?? 0)
            );
            api_json(['ok' => $ok]);
```

- [ ] **Step 3: Update admin_user_reset case**

Find and replace:

```php
        case 'admin_user_reset':
            api_require_admin();
            api_require_csrf();
            $newPass = admin_reset_password($con, (int) ($_POST['id'] ?? 0));
            api_json(['password' => $newPass]);
```

Replace with:

```php
        case 'admin_user_reset':
            api_require_admin();
            api_require_csrf();
            $ok = admin_reset_password($con, (int) ($_POST['id'] ?? 0), APP_BASE_URL);
            api_json(['ok' => $ok]);
```

- [ ] **Step 4: Add admin_user_create case**

Insert a new case immediately before `case 'admin_user_delete':`:

```php
        case 'admin_user_create':
            api_require_admin();
            api_require_csrf();
            $username = trim($_POST['username'] ?? '');
            $email    = trim($_POST['email']    ?? '');
            $rights   = $_POST['rights']        ?? 'User';
            if ($username === '' || $email === '') {
                api_json(['ok' => false, 'error' => 'Username und E-Mail sind erforderlich.'], 400);
            }
            try {
                admin_create_user($con, $username, $email, $rights, APP_BASE_URL);
                api_json(['ok' => true]);
            } catch (\mysqli_sql_exception $e) {
                api_json(['ok' => false, 'error' => 'Benutzername oder E-Mail bereits vergeben.'], 409);
            }
```

- [ ] **Step 5: Commit**

```bash
cd /Users/erikr/Git/wlmonitor
git add web/api.php
git commit -m "feat: add create-user API endpoint; switch reset to invite-email flow"
```

---

## Task 6: wlmonitor — web/admin.php (UI)

**Files:**
- Modify: `/Users/erikr/Git/wlmonitor/web/admin.php`

Two changes:
1. Add a "Benutzer anlegen" button and create modal (before the filter form).
2. Update the reset button JS: replace plaintext-password alert with "E-Mail versandt."

- [ ] **Step 1: Add create-user button before the filter form**

Find in `web/admin.php`:

```php
<div class="container-fluid">
  <form class="d-flex gap-2 mb-3" method="get">
```

Replace with:

```php
<div class="container-fluid">
  <div class="d-flex justify-content-between align-items-center mb-3">
    <button class="btn btn-sm btn-success" data-modal-open="createModal">
      <?= icon("user-plus", "me-1") ?> Benutzer anlegen
    </button>
  </div>

  <form class="d-flex gap-2 mb-3" method="get">
```

- [ ] **Step 2: Add create modal**

Find the closing `</script>` tag before `<?php include_once(...html_footer...); ?>` and insert the modal HTML before the script block (after the edit modal closing `</div>`):

```html
<!-- Create User Modal -->
<div class="modal fade" id="createModal" tabindex="-1" aria-labelledby="createModalLabel">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title" id="createModalLabel">Benutzer anlegen</h5>
        <button type="button" class="btn-close" data-modal-close></button>
      </div>
      <form id="createForm">
        <div class="modal-body">
          <input type="hidden" name="csrf_token"
                 value="<?= htmlspecialchars($csrfToken, ENT_QUOTES, 'UTF-8') ?>">
          <div class="mb-2">
            <label class="form-label" for="createUsername">Benutzername</label>
            <input type="text" name="username" id="createUsername"
                   class="form-control" required autocomplete="off">
          </div>
          <div class="mb-2">
            <label class="form-label" for="createEmail">E-Mail</label>
            <input type="email" name="email" id="createEmail" class="form-control" required>
          </div>
          <div class="mb-2">
            <label class="form-label" for="createRights">Rechte</label>
            <select name="rights" id="createRights" class="form-select">
              <option value="User">User</option>
              <option value="Admin">Admin</option>
            </select>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-modal-close>Abbrechen</button>
          <button type="submit" class="btn btn-success">Einladung senden</button>
        </div>
      </form>
    </div>
  </div>
</div>
```

- [ ] **Step 3: Update reset button JS**

Find in the `<script>` block:

```js
document.querySelectorAll('.btn-reset').forEach(btn => {
  btn.addEventListener('click', async () => {
    if (!confirm('Passwort fur Benutzer #' + btn.dataset.id + ' zurucksetzen?')) return;
    const res = await adminPost('admin_user_reset', { id: btn.dataset.id });
    if (res.password) {
      showAlert('Neues Passwort: ' + res.password, 'warning');
    } else {
      showAlert('Fehler beim Zurucksetzen.', 'danger');
    }
  });
});
```

Replace with:

```js
document.querySelectorAll('.btn-reset').forEach(btn => {
  btn.addEventListener('click', async () => {
    if (!confirm('Passwort-Reset-E-Mail an Benutzer #' + btn.dataset.id + ' senden?')) return;
    const res = await adminPost('admin_user_reset', { id: btn.dataset.id });
    if (res.ok) {
      showAlert('E-Mail versandt.', 'success');
    } else {
      showAlert('Fehler beim Zurucksenden.', 'danger');
    }
  });
});
```

- [ ] **Step 4: Add create form submit handler to JS**

After the reset handler JS, add:

```js
document.getElementById('createForm').addEventListener('submit', async e => {
  e.preventDefault();
  const fd  = new FormData(e.target);
  const res = await adminPost('admin_user_create', Object.fromEntries(fd));
  if (res.ok) {
    showAlert('Einladung versandt an ' + fd.get('email') + '.', 'success');
    closeModal('createModal');
    e.target.reset();
  } else {
    showAlert('Fehler: ' + (res.error ?? 'Unbekannt'), 'danger');
  }
});
```

- [ ] **Step 5: Commit**

```bash
cd /Users/erikr/Git/wlmonitor
git add web/admin.php
git commit -m "feat: add create-user modal; update reset UI to email flow"
```

---

## Task 7: wlmonitor — setpassword.php + cleanup

**Files:**
- Create: `/Users/erikr/Git/wlmonitor/web/setpassword.php`
- Delete: `/Users/erikr/Git/wlmonitor/web/register.php`
- Delete: `/Users/erikr/Git/wlmonitor/web/activate.php`

- [ ] **Step 1: Create web/setpassword.php**

```php
<?php
/**
 * web/setpassword.php — Invitation and password-reset flow.
 *
 * GET:  Validates token, shows "set password" form.
 * POST: Validates input, calls invite_complete(), redirects to login.
 */
require_once(__DIR__ . '/../inc/initialize.php');

$token  = trim($_GET['token'] ?? $_POST['token'] ?? '');
$error  = '';
$userId = null;

if ($token !== '') {
    $userId = invite_verify_token($con, $token);
}

if ($userId === null) {
    include_once(__DIR__ . '/../inc/html_header.php');
    echo '<div class="container mt-4"><div class="alert alert-danger">Link ungültig oder abgelaufen.</div></div>';
    include_once(__DIR__ . '/../inc/html_footer.php');
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $pw      = $_POST['password']         ?? '';
    $confirm = $_POST['password_confirm'] ?? '';

    if (strlen($pw) < 8) {
        $error = 'Passwort muss mindestens 8 Zeichen haben.';
    } elseif ($pw !== $confirm) {
        $error = 'Passwörter stimmen nicht überein.';
    } else {
        invite_complete($con, $userId, $pw);
        header('Location: login.php?msg=password_set');
        exit;
    }
}

include_once(__DIR__ . '/../inc/html_header.php');
?>
<div class="container mt-4" style="max-width:480px">
  <h4 class="mb-3">Passwort einrichten</h4>
  <?php if ($error): ?>
    <div class="alert alert-danger"><?= htmlspecialchars($error, ENT_QUOTES, 'UTF-8') ?></div>
  <?php endif; ?>
  <form method="post">
    <input type="hidden" name="token"
           value="<?= htmlspecialchars($token, ENT_QUOTES, 'UTF-8') ?>">
    <div class="mb-3">
      <label class="form-label">Passwort</label>
      <input type="password" name="password" class="form-control" required minlength="8" autofocus>
    </div>
    <div class="mb-3">
      <label class="form-label">Passwort bestätigen</label>
      <input type="password" name="password_confirm" class="form-control" required minlength="8">
    </div>
    <button type="submit" class="btn btn-primary">Passwort speichern</button>
  </form>
</div>
<?php include_once(__DIR__ . '/../inc/html_footer.php'); ?>
```

- [ ] **Step 2: Delete register.php and activate.php**

```bash
cd /Users/erikr/Git/wlmonitor
git rm web/register.php web/activate.php
```

- [ ] **Step 3: Commit**

```bash
git add web/setpassword.php
git commit -m "feat: add setpassword.php; remove register.php and activate.php"
```

---

## Task 8: simplechat — inc/initialize.php (SMTP + APP_BASE_URL)

**Files:**
- Modify: `/Users/erikr/Git/simplechat-2.1/inc/initialize.php`

simplechat's `inc/initialize.php` loads `data/config.yaml` (UI settings + auth_db credentials). It does not define SMTP constants or `APP_BASE_URL`. The mcp-generated root `config.yaml` (at the repo root) has both. Add loading of the root config.

- [ ] **Step 1: composer update erikr/auth in simplechat**

```bash
cd /Users/erikr/Git/simplechat-2.1
composer update erikr/auth
```

- [ ] **Step 2: Extend initialize.php**

At the end of `/Users/erikr/Git/simplechat-2.1/inc/initialize.php`, before the closing session lines, add:

```php
// ── Root config (mcp-generated: smtp + app.base_url) ─────────────────────────

$_rootCfg = \Symfony\Component\Yaml\Yaml::parseFile(dirname(__DIR__) . '/config.yaml') ?? [];

define('SMTP_HOST',      $_rootCfg['smtp']['host']      ?? '');
define('SMTP_PORT',      (int) ($_rootCfg['smtp']['port'] ?? 587));
define('SMTP_USER',      $_rootCfg['smtp']['user']      ?? '');
define('SMTP_PASS',      $_rootCfg['smtp']['password']  ?? '');
define('SMTP_FROM',      $_rootCfg['smtp']['from']      ?? '');
define('SMTP_FROM_NAME', $_rootCfg['smtp']['from_name'] ?? '');
define('APP_BASE_URL',   rtrim($_rootCfg['app']['base_url'] ?? '', '/'));

unset($_rootCfg);
```

- [ ] **Step 3: Verify constants load**

```bash
cd /Users/erikr/Git/simplechat-2.1
php -r "
require 'vendor/autoload.php';
\$_yaml = \Symfony\Component\Yaml\Yaml::parseFile('data/config.yaml') ?? [];
function appConfig(\$k='', \$d='') { global \$_yaml; return \$_yaml[\$k] ?? \$d; }
function basePath(\$p='') { return '/chat'.\$p; }
define('AUTH_DB_PREFIX', '');
define('RATE_LIMIT_FILE', '/tmp/rl.json');
require 'inc/initialize.php';
echo SMTP_FROM . PHP_EOL;
echo APP_BASE_URL . PHP_EOL;
"
```

Expected output:
```
chat@jardyx.com
http://localhost/chat
```

(If AUTH_DB_PREFIX is already defined when running initialize.php standalone, adjust the test script accordingly — this is just a sanity check. The actual app bootstrap handles this correctly.)

- [ ] **Step 4: Commit**

```bash
cd /Users/erikr/Git/simplechat-2.1
git add inc/initialize.php
git commit -m "feat: load SMTP constants and APP_BASE_URL from root config.yaml"
```

---

## Task 9: simplechat — web/admin.php (users section)

**Files:**
- Modify: `/Users/erikr/Git/simplechat-2.1/web/admin.php`

Two changes:
1. In the POST handler block (around line 237): add cases for `create_user`, `edit_user`, `delete_user`, `reset_user_password`. Remove `prune_users`.
2. In the `$section === 'users'` display block (around line 771): replace file-based user list with auth_accounts CRUD UI.

- [ ] **Step 1: Replace prune_users POST handler with user CRUD handlers**

Find in the POST handler block:

```php
    // ── Prune inactive users ──────────────────────────────────────────────────
    elseif ($action === 'prune_users') {
        $count = pruneInactiveUsers(12);
        $_SESSION['success'] = $count > 0
            ? $count . ' inaktive Benutzer gelöscht.'
            : 'Keine inaktiven Benutzer gefunden.';
    }
```

Replace with:

```php
    // ── User account management ───────────────────────────────────────────────
    elseif ($action === 'create_user') {
        $username = trim($_POST['username'] ?? '');
        $email    = trim($_POST['email']    ?? '');
        $rights   = $_POST['rights']        ?? 'User';
        if ($username === '' || $email === '') {
            $_SESSION['error'] = 'Benutzername und E-Mail sind erforderlich.';
        } else {
            try {
                admin_create_user($con, $username, $email, $rights, APP_BASE_URL);
                $_SESSION['success'] = 'Einladung versandt an ' . htmlspecialchars($email, ENT_QUOTES, 'UTF-8') . '.';
            } catch (\Throwable $e) {
                $_SESSION['error'] = 'Fehler: Benutzername oder E-Mail bereits vergeben.';
            }
        }
    }

    elseif ($action === 'edit_user') {
        $targetId = (int) ($_POST['user_id']  ?? 0);
        $email    = trim($_POST['email']       ?? '');
        $rights   = $_POST['rights']           ?? 'User';
        $disabled = isset($_POST['disabled'])  ? 1 : 0;
        $debug    = isset($_POST['debug'])     ? 1 : 0;
        admin_edit_user($con, $targetId, $email, $rights, $disabled, $debug);
        $_SESSION['success'] = 'Gespeichert.';
    }

    elseif ($action === 'delete_user') {
        $targetId = (int) ($_POST['user_id'] ?? 0);
        // Pass -1 as requestingUserId: simplechat admin is not an auth_accounts user,
        // so self-deletion via this panel is not possible.
        $ok = admin_delete_user($con, $targetId, -1);
        $_SESSION['success'] = $ok ? 'Benutzer gelöscht.' : 'Fehler beim Löschen.';
    }

    elseif ($action === 'reset_user_password') {
        $targetId = (int) ($_POST['user_id'] ?? 0);
        admin_reset_password($con, $targetId, APP_BASE_URL);
        $_SESSION['success'] = 'Passwort-Reset-E-Mail versandt.';
    }
```

- [ ] **Step 2: Replace the users section display block**

Find (approximately around line 771):

```php
    // ── User management ───────────────────────────────────────────────────────
    if ($section === 'users') {
    $users   = listUserPrefs();
    $cutoff  = strtotime('-12 months');
    $expired = array_filter($users, fn($u) => ($u['last_seen'] ?? 0) < $cutoff);

    echo '<div class="admin-section">
        <h2 class="admin-section-title">Benutzer</h2>';

    if (empty($users)) {
        echo '<p style="font-size:14px;color:var(--color-muted);">Noch keine Benutzerdaten vorhanden.</p>';
    } else {
        echo '<table style="...
        ...
    }  // end users
```

Replace the entire `if ($section === 'users') { ... }  // end users` block with:

```php
    // ── User management ───────────────────────────────────────────────────────
    if ($section === 'users') {
    $page    = max(1, (int) ($_GET['page'] ?? 1));
    $filter  = $_GET['filter'] ?? '';
    $uData   = admin_list_users($con, $page, 25, $filter);
    $uList   = $uData['users'];
    $uTotal  = $uData['total'];
    $uPages  = (int) ceil($uTotal / 25);

    echo '<div class="admin-section">
        <h2 class="admin-section-title">Benutzer</h2>';

    // ── Create user form ──
    echo '<details class="admin-expandable" style="margin-bottom:16px;">
        <summary style="cursor:pointer;font-weight:600;padding:8px 0;">+ Benutzer anlegen</summary>
        <form method="post" action="' . $php . '?section=users" style="margin-top:12px;">
            <input type="hidden" name="csrf_token" value="' . $csrf . '">
            <input type="hidden" name="current_section" value="users">
            <input type="hidden" name="action" value="create_user">
            <div class="form-field">
                <label class="form-label" for="newUsername">Benutzername</label>
                <input type="text" class="form-input" id="newUsername" name="username" required autocomplete="off">
            </div>
            <div class="form-field">
                <label class="form-label" for="newEmail">E-Mail</label>
                <input type="email" class="form-input" id="newEmail" name="email" required>
            </div>
            <div class="form-field">
                <label class="form-label" for="newRights">Rechte</label>
                <select class="form-input" id="newRights" name="rights">
                    <option value="User">User</option>
                    <option value="Admin">Admin</option>
                </select>
            </div>
            <button type="submit" class="btn-primary" style="width:auto;padding:0 20px;">Einladung senden</button>
        </form>
    </details>';

    // ── Filter ──
    echo '<form method="get" action="' . $php . '" style="margin-bottom:12px;display:flex;gap:8px;">
        <input type="hidden" name="section" value="users">
        <input type="text" name="filter" class="form-input" style="max-width:200px;"
               placeholder="Username suchen" value="' . htmlspecialchars($filter, ENT_QUOTES, 'UTF-8') . '">
        <button type="submit" class="btn-secondary" style="width:auto;padding:0 16px;">Suchen</button>
    </form>';

    // ── User table ──
    if (empty($uList)) {
        echo '<p style="font-size:14px;color:var(--color-muted);">Keine Benutzer gefunden.</p>';
    } else {
        echo '<table style="width:100%;border-collapse:collapse;font-size:13px;margin-bottom:16px;">
            <thead>
                <tr style="border-bottom:1px solid var(--color-border);">
                    <th style="text-align:left;padding:6px 8px;">ID</th>
                    <th style="text-align:left;padding:6px 8px;">Username</th>
                    <th style="text-align:left;padding:6px 8px;">E-Mail</th>
                    <th style="text-align:left;padding:6px 8px;">Rechte</th>
                    <th style="text-align:left;padding:6px 8px;">Status</th>
                    <th style="text-align:left;padding:6px 8px;"></th>
                </tr>
            </thead>
            <tbody>';

        foreach ($uList as $u) {
            $safeEmail = htmlspecialchars($u["email"],    ENT_QUOTES, "UTF-8");
            $safeRights= htmlspecialchars($u["rights"],   ENT_QUOTES, "UTF-8");
            $statusStr = $u["disabled"] ? "gesperrt" : "aktiv";
            echo '<tr style="border-bottom:1px solid var(--color-border);">
                <td style="padding:6px 8px;">' . $u["id"] . '</td>
                <td style="padding:6px 8px;">' . htmlspecialchars($u["username"], ENT_QUOTES, "UTF-8") . '</td>
                <td style="padding:6px 8px;">' . $safeEmail . '</td>
                <td style="padding:6px 8px;">' . $safeRights . '</td>
                <td style="padding:6px 8px;">' . $statusStr . '</td>
                <td style="padding:6px 8px;">
                    <details style="display:inline-block;">
                        <summary style="cursor:pointer;font-size:12px;">Aktionen</summary>
                        <div style="background:var(--color-surface-alt);padding:12px;border-radius:6px;margin-top:4px;min-width:240px;">
                            <form method="post" action="' . $php . '?section=users" style="margin-bottom:8px;">
                                <input type="hidden" name="csrf_token" value="' . $csrf . '">
                                <input type="hidden" name="current_section" value="users">
                                <input type="hidden" name="action" value="edit_user">
                                <input type="hidden" name="user_id" value="' . $u["id"] . '">
                                <div style="margin-bottom:6px;">
                                    <label style="font-size:12px;display:block;">E-Mail</label>
                                    <input type="email" name="email" class="form-input"
                                           value="' . $safeEmail . '" style="font-size:12px;padding:4px 8px;">
                                </div>
                                <div style="margin-bottom:6px;">
                                    <label style="font-size:12px;display:block;">Rechte</label>
                                    <select name="rights" class="form-input" style="font-size:12px;padding:4px 8px;">
                                        <option value="User"'  . ($u["rights"] === "User"  ? " selected" : "") . '>User</option>
                                        <option value="Admin"' . ($u["rights"] === "Admin" ? " selected" : "") . '>Admin</option>
                                    </select>
                                </div>
                                <label style="font-size:12px;display:flex;align-items:center;gap:6px;margin-bottom:6px;">
                                    <input type="checkbox" name="disabled" value="1"' . ($u["disabled"] ? " checked" : "") . '> Gesperrt
                                </label>
                                <label style="font-size:12px;display:flex;align-items:center;gap:6px;margin-bottom:8px;">
                                    <input type="checkbox" name="debug" value="1"' . ($u["debug"] ? " checked" : "") . '> Debug
                                </label>
                                <button type="submit" class="btn-primary" style="width:auto;padding:2px 12px;font-size:12px;">Speichern</button>
                            </form>
                            <form method="post" action="' . $php . '?section=users" style="display:inline;">
                                <input type="hidden" name="csrf_token" value="' . $csrf . '">
                                <input type="hidden" name="current_section" value="users">
                                <input type="hidden" name="action" value="reset_user_password">
                                <input type="hidden" name="user_id" value="' . $u["id"] . '">
                                <button type="submit" class="btn-secondary"
                                        style="width:auto;padding:2px 10px;font-size:12px;"
                                        onclick="return confirm(\'Passwort-Reset-E-Mail senden?\')">Reset</button>
                            </form>
                            <form method="post" action="' . $php . '?section=users" style="display:inline;margin-left:6px;">
                                <input type="hidden" name="csrf_token" value="' . $csrf . '">
                                <input type="hidden" name="current_section" value="users">
                                <input type="hidden" name="action" value="delete_user">
                                <input type="hidden" name="user_id" value="' . $u["id"] . '">
                                <button type="submit" class="btn-danger"
                                        style="width:auto;padding:2px 10px;font-size:12px;"
                                        onclick="return confirm(\'Benutzer #' . $u["id"] . ' wirklich löschen?\')">Löschen</button>
                            </form>
                        </div>
                    </details>
                </td>
            </tr>';
        }

        echo '</tbody></table>';
    }

    // ── Pagination ──
    if ($uPages > 1) {
        echo '<div style="display:flex;gap:6px;flex-wrap:wrap;">';
        for ($p = 1; $p <= $uPages; $p++) {
            $active = $p === $page ? 'btn-primary' : 'btn-secondary';
            echo '<a href="' . $php . '?section=users&page=' . $p
               . '&filter=' . urlencode($filter) . '" class="' . $active . '"'
               . ' style="width:auto;padding:2px 10px;text-decoration:none;font-size:13px;">' . $p . '</a>';
        }
        echo '</div>';
    }

    echo '</div>';
    }  // end users
```

- [ ] **Step 3: Commit**

```bash
cd /Users/erikr/Git/simplechat-2.1
git add web/admin.php
git commit -m "feat: replace file-based users tab with auth_accounts CRUD"
```

---

## Task 10: simplechat — web/setpassword.php

**Files:**
- Create: `/Users/erikr/Git/simplechat-2.1/web/setpassword.php`

- [ ] **Step 1: Create web/setpassword.php**

```php
<?php
/**
 * web/setpassword.php — Invitation and password-reset flow.
 *
 * GET:  Validates token, shows "set password" form.
 * POST: Validates input, calls invite_complete(), redirects to login.
 *
 * Uses simplechat's adminPage() helper for consistent layout.
 * No admin authentication required — token is the sole credential.
 */
require_once __DIR__ . '/../inc/initialize.php';
include_once $_SESSION['scriptBasedir'] . '/inc/functions.php';
include_once $_SESSION['scriptBasedir'] . '/inc/html.php';
include_once $_SESSION['scriptBasedir'] . '/inc/admin.php';

$token  = trim($_GET['token'] ?? $_POST['token'] ?? '');
$error  = '';
$userId = null;

if ($token !== '') {
    $userId = invite_verify_token($con, $token);
}

if ($userId === null) {
    adminPage('Link ungültig', function () {
        echo '<p class="inline-error" style="font-size:15px;">Dieser Link ist ungültig oder abgelaufen.</p>';
    });
    exit;
}

// Fetch username for greeting
$stmt = $con->prepare('SELECT username FROM auth_accounts WHERE id = ?');
$stmt->bind_param('i', $userId);
$stmt->execute();
$row      = $stmt->get_result()->fetch_assoc();
$stmt->close();
$username = $row['username'] ?? '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $pw      = $_POST['password']         ?? '';
    $confirm = $_POST['password_confirm'] ?? '';

    if (strlen($pw) < 8) {
        $error = 'Passwort muss mindestens 8 Zeichen haben.';
    } elseif ($pw !== $confirm) {
        $error = 'Passwörter stimmen nicht überein.';
    } else {
        invite_complete($con, $userId, $pw);
        header('Location: ' . basePath('/login.php') . '?msg=password_set');
        exit;
    }
}

adminPage('Passwort einrichten', function () use ($token, $error, $username) {
    if ($error !== '') {
        echo '<p class="inline-error">' . htmlspecialchars($error, ENT_QUOTES, 'UTF-8') . '</p>';
    }
    echo '<p style="margin-bottom:16px;font-size:15px;">Hallo '
       . htmlspecialchars($username, ENT_QUOTES, 'UTF-8')
       . ', bitte richten Sie Ihr Passwort ein.</p>
    <form method="post" action="' . htmlspecialchars($_SERVER["PHP_SELF"]) . '">
        <input type="hidden" name="token" value="' . htmlspecialchars($token, ENT_QUOTES, "UTF-8") . '">
        <div class="form-field">
            <label class="form-label" for="pw">Passwort</label>
            <input type="password" class="form-input" id="pw" name="password" required minlength="8" autofocus>
        </div>
        <div class="form-field">
            <label class="form-label" for="pwc">Passwort bestätigen</label>
            <input type="password" class="form-input" id="pwc" name="password_confirm" required minlength="8">
        </div>
        <button type="submit" class="btn-primary">Passwort speichern</button>
    </form>';
});
```

- [ ] **Step 2: Commit**

```bash
cd /Users/erikr/Git/simplechat-2.1
git add web/setpassword.php
git commit -m "feat: add setpassword.php for invite and password-reset flow"
```

---

## Manual verification checklist

After completing all tasks, verify the following scenarios manually:

**Both apps:**
- [ ] Admin creates user → invite email arrives → link opens `setpassword.php` → user sets password → login works
- [ ] Admin clicks reset → email arrives → old token returns "link ungültig oder abgelaufen"
- [ ] Non-admin user cannot reach admin pages (redirected to index/login)
- [ ] Expired token (> 48h) shows "link ungültig oder abgelaufen"

**wlmonitor only:**
- [ ] `register.php` and `activate.php` return 404
- [ ] `departures` column still appears in user list (wl_preferences query)
- [ ] Edit user still saves departures preference correctly

**simplechat only:**
- [ ] Users tab shows auth_accounts list with CRUD forms
- [ ] Create user → expansion panel opens, form submits → success message
- [ ] Edit, delete, reset all work from the Aktionen detail disclosure
