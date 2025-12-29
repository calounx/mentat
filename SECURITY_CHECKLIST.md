# Security Implementation Checklist

Quick reference guide for implementing security fixes from the comprehensive audit.

---

## Critical Fixes (Do First)

### 1. VPSManagerBridge Command Validation

**File:** `chom/app/Services/Integration/VPSManagerBridge.php`

```php
// Add command whitelist constant
private const ALLOWED_COMMANDS = [
    'site:create', 'site:delete', 'site:enable', 'site:disable',
    'site:list', 'site:info', 'ssl:issue', 'ssl:renew', 'ssl:status',
    'backup:create', 'backup:list', 'backup:restore',
    'database:export', 'database:optimize',
    'monitor:health', 'monitor:dashboard', 'cache:clear', 'security:audit',
    '--version'
];

// Add to execute() method at line 66
public function execute(VpsServer $vps, string $command, array $args = []): array
{
    // Validate command
    if (!in_array($command, self::ALLOWED_COMMANDS, true)) {
        Log::warning('Blocked unauthorized VPS command', [
            'command' => $command,
            'vps' => $vps->hostname,
        ]);
        throw new \InvalidArgumentException("Command not allowed: {$command}");
    }

    // Validate argument keys
    foreach ($args as $key => $value) {
        if (!is_numeric($key) && !preg_match('/^[a-z][a-z0-9-]*$/i', $key)) {
            throw new \InvalidArgumentException("Invalid argument key: {$key}");
        }
    }

    // Rest of implementation...
}
```

**Test:**
```bash
php artisan test --filter VPSManagerBridgeTest
```

---

### 2. Shell Script Variable Quoting

**Files:** All `.sh` files in `observability-stack/`

**Find unquoted variables:**
```bash
cd observability-stack
shellcheck -f gcc scripts/**/*.sh | grep "SC2086"
```

**Fix pattern:**
```bash
# Before (UNSAFE)
backup_dir=$STACK_ROOT/.backup-$(date +%Y%m%d)
cp $file "$BACKUP_DIR/backup"

# After (SAFE)
backup_dir="$STACK_ROOT/.backup-$(date +%Y%m%d)"
cp "$file" "$BACKUP_DIR/backup"
```

**Automated fix helper:**
```bash
# Create fix-quotes.sh
#!/bin/bash
find . -name "*.sh" -type f -print0 | while IFS= read -r -d '' file; do
    echo "Checking: $file"
    shellcheck -f diff "$file" | grep -A5 "SC2086" || true
done
```

---

### 3. Path Traversal Protection

**File:** `observability-stack/scripts/lib/common.sh` (add new function)

```bash
# Add path validation function
validate_path_within_directory() {
    local path="$1"
    local allowed_dir="$2"

    # Resolve to absolute canonical path
    local canonical_path
    canonical_path=$(realpath -m "$path" 2>/dev/null) || {
        log_error "Invalid path: $path"
        return 1
    }

    local canonical_dir
    canonical_dir=$(realpath -m "$allowed_dir" 2>/dev/null) || {
        log_error "Invalid directory: $allowed_dir"
        return 1
    }

    # Check if path starts with allowed directory
    if [[ "$canonical_path" != "$canonical_dir"/* ]] && [[ "$canonical_path" != "$canonical_dir" ]]; then
        log_error "Path traversal detected: $path is outside $allowed_dir"
        return 1
    fi

    echo "$canonical_path"
}

# Usage in other scripts:
safe_path=$(validate_path_within_directory "$user_input" "$BACKUP_DIR") || exit 1
cp "$file" "$safe_path"
```

**Update backup scripts:**
```bash
# In backup-related scripts
BACKUP_DIR="/opt/observability-stack/backups"

# Before any user-provided path operations
validate_path_within_directory "$backup_file" "$BACKUP_DIR" || exit 1
```

---

## High Priority Fixes (Within 1 Week)

### 4. SSH Key Generation with Secure Permissions

**File:** `chom/app/Console/Commands/GenerateSSHKey.php` (create new)

```php
<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

class GenerateSSHKey extends Command
{
    protected $signature = 'chom:generate-ssh-key {--force}';
    protected $description = 'Generate SSH deployment key with secure permissions';

    public function handle()
    {
        $keyPath = config('chom.ssh_key_path');
        $keyDir = dirname($keyPath);

        if (file_exists($keyPath) && !$this->option('force')) {
            $this->error("SSH key already exists at: {$keyPath}");
            $this->info("Use --force to regenerate");
            return 1;
        }

        // Create directory with secure permissions
        if (!is_dir($keyDir)) {
            mkdir($keyDir, 0700, true);
            $this->info("Created directory: {$keyDir}");
        }

        // Generate SSH key pair
        $command = sprintf(
            'ssh-keygen -t ed25519 -f %s -N "" -C "chom-deploy-key@%s" 2>&1',
            escapeshellarg($keyPath),
            escapeshellarg(gethostname())
        );

        exec($command, $output, $result);

        if ($result !== 0) {
            $this->error('Failed to generate SSH key');
            $this->line(implode("\n", $output));
            return 1;
        }

        // Set secure permissions
        chmod($keyPath, 0600);
        chmod($keyPath . '.pub', 0644);

        $this->info("✓ SSH key generated: {$keyPath}");
        $this->info("✓ Permissions set: 0600 (private), 0644 (public)");

        // Display public key
        $this->newLine();
        $this->info("Public key (add to authorized_keys on VPS servers):");
        $this->line(file_get_contents($keyPath . '.pub'));

        Log::info('Generated new SSH deployment key', ['path' => $keyPath]);

        return 0;
    }
}
```

**Run:**
```bash
php artisan chom:generate-ssh-key
```

---

### 5. Password Policy Strengthening

**File:** `chom/app/Providers/AppServiceProvider.php`

```php
use Illuminate\Validation\Rules\Password;

public function boot(): void
{
    // Set strong password defaults
    Password::defaults(function () {
        return $this->app->isProduction()
            ? Password::min(14)
                ->mixedCase()
                ->numbers()
                ->symbols()
                ->uncompromised()  // Check Have I Been Pwned
            : Password::min(8);    // Relaxed for development
    });
}
```

**Test:**
```bash
# Should fail
curl -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "weak",
    "password_confirmation": "weak",
    "name": "Test User",
    "organization_name": "Test Org"
  }'

# Should succeed
curl -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "MyStr0ng!P@ssw0rd",
    "password_confirmation": "MyStr0ng!P@ssw0rd",
    "name": "Test User",
    "organization_name": "Test Org"
  }'
```

---

### 6. Email Verification Enforcement

**File:** `chom/app/Http/Middleware/EnsureEmailIsVerifiedApi.php` (create new)

```php
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class EnsureEmailIsVerifiedApi
{
    public function handle(Request $request, Closure $next)
    {
        if (!$request->user() || !$request->user()->hasVerifiedEmail()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'EMAIL_NOT_VERIFIED',
                    'message' => 'Your email address is not verified. Please check your email for a verification link.',
                ],
            ], 403);
        }

        return $next($request);
    }
}
```

**Register middleware:**
```php
// In app/Http/Kernel.php
protected $middlewareAliases = [
    // ...
    'verified.api' => \App\Http\Middleware\EnsureEmailIsVerifiedApi::class,
];
```

**Apply to routes:**
```php
// In routes/api.php
Route::middleware(['auth:sanctum', 'throttle:api', 'verified.api'])->group(function () {
    // Protected routes requiring email verification
});
```

---

## Medium Priority (Within 1 Month)

### 7. Security Headers Middleware

**File:** `chom/app/Http/Middleware/SecurityHeaders.php` (create new)

```php
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class SecurityHeaders
{
    public function handle(Request $request, Closure $next)
    {
        $response = $next($request);

        // Security headers
        $response->headers->set('X-Content-Type-Options', 'nosniff');
        $response->headers->set('X-Frame-Options', 'DENY');
        $response->headers->set('X-XSS-Protection', '1; mode=block');
        $response->headers->set('Referrer-Policy', 'strict-origin-when-cross-origin');

        // Content Security Policy
        $csp = implode('; ', [
            "default-src 'self'",
            "script-src 'self' 'unsafe-inline' 'unsafe-eval'",  // Adjust for Livewire
            "style-src 'self' 'unsafe-inline'",
            "img-src 'self' data: https:",
            "font-src 'self' data:",
            "connect-src 'self'",
            "frame-ancestors 'none'",
        ]);
        $response->headers->set('Content-Security-Policy', $csp);

        return $response;
    }
}
```

**Register in bootstrap/app.php (Laravel 12):**
```php
->withMiddleware(function (Middleware $middleware) {
    $middleware->append(\App\Http\Middleware\SecurityHeaders::class);
})
```

---

### 8. Database Credential Encryption

**File:** `chom/app/Models/Site.php`

```php
use Illuminate\Support\Facades\Crypt;

protected $casts = [
    'ssl_enabled' => 'boolean',
    'ssl_expires_at' => 'datetime',
    'settings' => 'array',
    'db_password' => 'encrypted',  // Add this
];

// Add to $hidden array
protected $hidden = [
    'db_user',
    'db_name',
    'db_password',
    'document_root',
];
```

**Migration:**
```php
// Create migration: php artisan make:migration add_db_password_to_sites_table

public function up()
{
    Schema::table('sites', function (Blueprint $table) {
        $table->text('db_password')->nullable()->after('db_user');
    });

    // Encrypt existing passwords if any
    // This is a one-time migration
}
```

---

### 9. Security Event Logging

**File:** `chom/app/Services/SecurityLogger.php` (create new)

```php
<?php

namespace App\Services;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use App\Models\User;

class SecurityLogger
{
    public function logAuthFailure(Request $request, string $email): void
    {
        Log::channel('security')->warning('Authentication failed', [
            'email' => $email,
            'ip' => $request->ip(),
            'user_agent' => $request->userAgent(),
            'timestamp' => now()->toIso8601String(),
        ]);
    }

    public function logSuspiciousActivity(Request $request, string $type, array $context = []): void
    {
        Log::channel('security')->alert('Suspicious activity detected', [
            'type' => $type,
            'user_id' => $request->user()?->id,
            'ip' => $request->ip(),
            'user_agent' => $request->userAgent(),
            'context' => $context,
            'timestamp' => now()->toIso8601String(),
        ]);
    }

    public function logPrivilegeChange(User $user, string $oldRole, string $newRole, ?User $changedBy = null): void
    {
        Log::channel('security')->warning('User privilege changed', [
            'user_id' => $user->id,
            'email' => $user->email,
            'old_role' => $oldRole,
            'new_role' => $newRole,
            'changed_by' => $changedBy?->id,
            'timestamp' => now()->toIso8601String(),
        ]);
    }

    public function logCommandExecution(string $vpsHostname, string $command, bool $success): void
    {
        Log::channel('security')->info('VPS command executed', [
            'vps' => $vpsHostname,
            'command' => $command,
            'success' => $success,
            'timestamp' => now()->toIso8601String(),
        ]);
    }
}
```

**Configure logging channel:**
```php
// In config/logging.php
'channels' => [
    'security' => [
        'driver' => 'daily',
        'path' => storage_path('logs/security.log'),
        'level' => 'info',
        'days' => 90,
        'permission' => 0600,
    ],
],
```

**Use in controllers:**
```php
use App\Services\SecurityLogger;

class AuthController extends Controller
{
    public function __construct(
        private SecurityLogger $securityLogger
    ) {}

    public function login(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'string', 'email'],
            'password' => ['required', 'string'],
        ]);

        if (!Auth::attempt($validated)) {
            // Log failed attempt
            $this->securityLogger->logAuthFailure($request, $validated['email']);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'INVALID_CREDENTIALS',
                    'message' => 'The provided credentials are incorrect.',
                ],
            ], 401);
        }

        // Success...
    }
}
```

---

## Automated Security Scanning

### 10. CI/CD Security Pipeline

**File:** `.github/workflows/security-scan.yml` (create new)

```yaml
name: Security Scan

on:
  push:
    branches: [master, develop]
  pull_request:
    branches: [master, develop]
  schedule:
    # Run weekly on Mondays at 9am
    - cron: '0 9 * * 1'

jobs:
  composer-audit:
    name: PHP Dependency Audit
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: '8.2'

      - name: Install dependencies
        working-directory: ./chom
        run: composer install --no-interaction --prefer-dist

      - name: Composer Audit
        working-directory: ./chom
        run: |
          composer audit --format=json > audit.json
          cat audit.json
          VULN_COUNT=$(jq '.advisories | length' audit.json)
          if [ "$VULN_COUNT" -gt 0 ]; then
            echo "::error::Found $VULN_COUNT security vulnerabilities"
            exit 1
          fi

  npm-audit:
    name: NPM Dependency Audit
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Node
        uses: actions/setup-node@v3
        with:
          node-version: '18'

      - name: Install dependencies
        working-directory: ./chom
        run: npm ci

      - name: NPM Audit
        working-directory: ./chom
        run: npm audit --audit-level=high

  shellcheck:
    name: Shell Script Security
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Run ShellCheck
        run: |
          find observability-stack -name "*.sh" -type f -print0 | \
            xargs -0 shellcheck --severity=warning

  secret-scan:
    name: Secret Scanning
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0

      - name: Gitleaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  sast:
    name: Static Application Security Testing
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Semgrep
        run: |
          pip install semgrep
          semgrep --config=auto --json --output=semgrep.json .

      - name: Check results
        run: |
          FINDINGS=$(jq '.results | length' semgrep.json)
          if [ "$FINDINGS" -gt 0 ]; then
            echo "::warning::Found $FINDINGS potential security issues"
            jq '.results' semgrep.json
          fi
```

---

## Testing Security Fixes

### Test Suite for VPSManagerBridge

**File:** `chom/tests/Feature/VPSManagerBridgeSecurityTest.php` (create new)

```php
<?php

namespace Tests\Feature;

use Tests\TestCase;
use App\Models\VpsServer;
use App\Services\Integration\VPSManagerBridge;

class VPSManagerBridgeSecurityTest extends TestCase
{
    public function test_blocks_invalid_commands()
    {
        $vps = VpsServer::factory()->create();
        $bridge = new VPSManagerBridge();

        $this->expectException(\InvalidArgumentException::class);
        $this->expectExceptionMessage('Command not allowed');

        $bridge->execute($vps, 'rm -rf /', []);
    }

    public function test_blocks_command_injection_in_arguments()
    {
        $vps = VpsServer::factory()->create();
        $bridge = new VPSManagerBridge();

        $this->expectException(\InvalidArgumentException::class);
        $this->expectExceptionMessage('Invalid argument key');

        $bridge->execute($vps, 'site:create', [
            'domain; rm -rf /' => 'malicious',
        ]);
    }

    public function test_allows_valid_commands()
    {
        $vps = VpsServer::factory()->create();
        $bridge = new VPSManagerBridge();

        // This should not throw exception
        // Mock SSH connection for testing
        $this->expectNotToPerformAssertions();

        try {
            $bridge->execute($vps, 'site:list', []);
        } catch (\RuntimeException $e) {
            // Connection failure is OK for this test
            if (!str_contains($e->getMessage(), 'SSH')) {
                throw $e;
            }
        }
    }
}
```

**Run tests:**
```bash
php artisan test --filter VPSManagerBridgeSecurityTest
```

---

## Quick Verification Commands

```bash
# 1. Check for unquoted variables in shell scripts
cd observability-stack
shellcheck -f gcc scripts/**/*.sh | grep "SC2086"

# 2. Check for hard-coded secrets
git grep -i "password\s*=\s*['\"]" | grep -v ".example" | grep -v "test"

# 3. Check file permissions
find . -name "*.sh" -exec ls -la {} \; | grep -E "rwxrwxrwx|666|777"

# 4. Check for SQL injection patterns
cd chom
grep -r "DB::raw\|->raw(" app/ | grep -v "// Safe"

# 5. Verify SSH key permissions
ls -la storage/app/ssh/chom_deploy_key

# 6. Check session security
grep -E "SESSION_ENCRYPT|SESSION_SECURE" .env

# 7. Audit dependencies
cd chom && composer audit && npm audit
```

---

## Security Review Checklist for PRs

Before merging any PR, verify:

- [ ] All shell variables are quoted
- [ ] No user input in SQL raw queries
- [ ] File paths validated against path traversal
- [ ] SSH commands use whitelisted operations only
- [ ] Secrets not hard-coded or in git
- [ ] Passwords meet strength requirements
- [ ] Authentication required for sensitive endpoints
- [ ] Rate limiting on new endpoints
- [ ] Input validation on all user data
- [ ] Error messages don't leak information
- [ ] File uploads validated (type, size, content)
- [ ] Logging doesn't include sensitive data
- [ ] Tests include security test cases

---

## Emergency Response

### If a Security Vulnerability is Discovered:

1. **Assess Impact**
   ```bash
   # Check logs for exploitation
   cd chom
   grep -i "suspicious\|unauthorized\|failed" storage/logs/security*.log

   # Check for unauthorized access
   php artisan tinker
   > User::whereDate('created_at', today())->get();
   > AuditLog::whereDate('created_at', today())->where('action', 'LIKE', '%unauthorized%')->get();
   ```

2. **Immediate Mitigation**
   ```bash
   # Block suspicious IPs
   sudo ufw deny from <IP_ADDRESS>

   # Disable affected functionality
   php artisan down --secret="emergency-access-token"

   # Rotate credentials
   php artisan tinker
   > User::all()->each(fn($u) => $u->tokens()->delete());
   ```

3. **Deploy Fix**
   ```bash
   git checkout -b hotfix/security-YYYYMMDD
   # Make fix
   git commit -m "Security fix: [brief description]"
   git push origin hotfix/security-YYYYMMDD
   # Deploy immediately after review
   ```

4. **Post-Incident**
   - Review audit logs
   - Notify affected users if needed
   - Document in security incident log
   - Update security tests to prevent regression

---

## Resources

- **OWASP Top 10:** https://owasp.org/Top10/
- **Laravel Security Best Practices:** https://laravel.com/docs/11.x/security
- **ShellCheck:** https://www.shellcheck.net/
- **Have I Been Pwned API:** https://haveibeenpwned.com/API/v3
- **Security Headers:** https://securityheaders.com/

---

**Last Updated:** 2025-12-29
