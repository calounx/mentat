# Security Features - Quick Reference Guide

**For Developers:** Fast reference for using security features in CHOM platform

---

## 1. Two-Factor Authentication (2FA)

### Check if User Requires 2FA
```php
if ($user->requires2FA()) {
    // User is owner or admin - 2FA required
}
```

### Check 2FA Status
```php
$user->two_factor_enabled        // bool: Is 2FA enabled?
$user->isIn2FAGracePeriod()      // bool: Within 7-day grace period?
```

### 2FA Middleware
```php
// Apply to route groups (already applied globally)
Route::middleware(['auth:sanctum', '2fa.required'])->group(function () {
    // Routes requiring 2FA verification
});
```

### 2FA API Endpoints
```bash
POST /api/v1/auth/2fa/setup              # Get QR code
POST /api/v1/auth/2fa/confirm            # Enable 2FA
POST /api/v1/auth/2fa/verify             # Verify code
GET  /api/v1/auth/2fa/status             # Check status
POST /api/v1/auth/2fa/backup-codes/regenerate  # New backup codes
POST /api/v1/auth/2fa/disable            # Disable (not for admins)
```

---

## 2. Step-Up Authentication (Password Confirmation)

### Check Password Confirmation
```php
if ($user->hasRecentPasswordConfirmation()) {
    // User confirmed password within last 10 minutes
}
```

### Record Password Confirmation
```php
$user->confirmPassword();  // Sets password_confirmed_at to now()
```

### Apply to Sensitive Routes
```php
Route::delete('/sites/{id}', [SiteController::class, 'destroy'])
    ->middleware(['auth:sanctum', 'password.confirm', 'throttle:sensitive']);

Route::post('/team/transfer-ownership', [TeamController::class, 'transferOwnership'])
    ->middleware(['auth:sanctum', 'password.confirm']);
```

### Password Confirmation Endpoint
```bash
POST /api/v1/auth/password/confirm
{
  "password": "user_password"
}
```

---

## 3. Secrets Rotation

### Check if Keys Need Rotation
```php
if ($user->needsKeyRotation()) {
    // SSH keys are >90 days old
}

if ($vps->key_rotated_at && $vps->key_rotated_at->addDays(90)->isPast()) {
    // VPS keys need rotation
}
```

### Rotate VPS Credentials
```php
use App\Services\Secrets\SecretsRotationService;

$service = app(SecretsRotationService::class);

// Rotate specific VPS
$result = $service->rotateVpsCredentials($vps);

// Get servers needing rotation
$servers = $service->getServersNeedingRotation();

// Rotate all due credentials
$results = $service->rotateAllDueCredentials();
```

### CLI Commands
```bash
# Check what needs rotation (dry run)
php artisan secrets:rotate --dry-run

# Rotate all due credentials
php artisan secrets:rotate --all

# Rotate specific VPS
php artisan secrets:rotate --vps=123

# Force rotation
php artisan secrets:rotate --vps=123 --force
```

### Schedule Automated Rotation
```php
// In app/Console/Kernel.php
protected function schedule(Schedule $schedule)
{
    $schedule->command('secrets:rotate --all')->daily();
}
```

---

## 4. Rate Limiting

### Standard Rate Limiters

```php
// Authentication: 5/min per IP
Route::middleware('throttle:auth')

// API calls: Tier-based (60-1000/min per user)
Route::middleware('throttle:api')

// Sensitive operations: 10/min per user
Route::middleware('throttle:sensitive')

// 2FA verification: 5/min per user
Route::middleware('throttle:2fa')
```

### Rate Limit Tiers

| Tier         | Requests/Minute |
|--------------|-----------------|
| Enterprise   | 1,000          |
| Professional | 500            |
| Starter      | 100            |
| Free         | 60             |

### Apply Custom Rate Limit
```php
Route::post('/expensive-operation', ...)
    ->middleware('throttle:10,1');  // 10 requests per 1 minute
```

### Get User's Rate Limit
```php
$tier = $user->organization->subscription->tier ?? 'free';
$limit = match($tier) {
    'enterprise' => 1000,
    'professional' => 500,
    'starter' => 100,
    default => 60,
};
```

---

## 5. Security Health Monitoring

### Health Check Endpoints
```bash
# Basic health (public)
GET /api/v1/health

# Detailed health (authenticated)
GET /api/v1/health/detailed

# Security posture (admin only)
GET /api/v1/health/security
```

### Programmatic Health Checks
```php
use App\Http\Controllers\Api\V1\HealthController;

$controller = app(HealthController::class);

// Get security status
$response = $controller->security($request, $rotationService);
$data = $response->getData();

// Check security score
if ($data->security_score < 85) {
    // Alert security team
}

// Check for critical issues
if ($data->summary->critical_issues > 0) {
    // Immediate action required
}
```

### Security Health Checks Performed

- ✓ Admin accounts without 2FA
- ✓ Stale SSH keys (>90 days)
- ✓ SSL certificates expiring soon
- ✓ Audit log integrity
- ✓ Session security settings
- ✓ Environment configuration

---

## 6. Request Signature Verification

### Apply to Routes
```php
Route::post('/webhooks/payment', [WebhookController::class, 'handlePayment'])
    ->middleware('verify.signature');

// Or with custom secret
Route::post('/webhooks/stripe', ...)
    ->middleware('verify.signature:stripe_secret');
```

### Client-Side Signing (JavaScript)
```javascript
const crypto = require('crypto');

function signRequest(method, uri, body, secret) {
    const timestamp = Math.floor(Date.now() / 1000);

    // Build canonical request
    const canonical = [
        timestamp,
        method,
        uri,
        JSON.stringify(body)
    ].join('\n');

    // Compute HMAC-SHA256
    const hmac = crypto
        .createHmac('sha256', secret)
        .update(canonical)
        .digest('hex');

    return {
        signature: `sha256=${hmac}`,
        timestamp: timestamp.toString()
    };
}

// Usage
const { signature, timestamp } = signRequest(
    'POST',
    '/api/v1/webhooks/payment',
    { amount: 1000 },
    process.env.SIGNING_SECRET
);

fetch(url, {
    method: 'POST',
    headers: {
        'X-Signature': signature,
        'X-Signature-Timestamp': timestamp,
        'Content-Type': 'application/json'
    },
    body: JSON.stringify({ amount: 1000 })
});
```

### Client-Side Signing (PHP)
```php
function signRequest($method, $uri, $body, $secret) {
    $timestamp = time();

    // Build canonical request
    $canonical = implode("\n", [
        $timestamp,
        $method,
        $uri,
        json_encode($body)
    ]);

    // Compute HMAC-SHA256
    $hmac = hash_hmac('sha256', $canonical, $secret);
    $signature = "sha256={$hmac}";

    return [
        'signature' => $signature,
        'timestamp' => (string) $timestamp,
    ];
}

// Usage
$signed = signRequest('POST', '/api/v1/webhooks/payment', ['amount' => 1000], $secret);

$response = Http::withHeaders([
    'X-Signature' => $signed['signature'],
    'X-Signature-Timestamp' => $signed['timestamp'],
])->post($url, ['amount' => 1000]);
```

---

## 7. Audit Logging

### Log Security Events
```php
use App\Models\AuditLog;

// Log successful 2FA verification
AuditLog::log(
    'user.2fa_verified',
    userId: $user->id,
    resourceType: 'User',
    resourceId: $user->id,
    metadata: [
        'method' => 'totp',
        'ip_address' => $request->ip(),
    ],
    severity: 'low'
);

// Log failed authentication
AuditLog::log(
    'auth.login_failed',
    userId: null,
    resourceType: null,
    resourceId: null,
    metadata: [
        'email' => $request->input('email'),
        'ip_address' => $request->ip(),
        'user_agent' => $request->userAgent(),
    ],
    severity: 'high'
);

// Log sensitive operation
AuditLog::log(
    'site.deleted',
    userId: $user->id,
    resourceType: 'Site',
    resourceId: $site->id,
    metadata: [
        'site_name' => $site->name,
        'password_confirmed' => true,
    ],
    severity: 'high'
);
```

### Severity Levels
- `critical` - System compromise, data breach
- `high` - Failed authentication, sensitive operations
- `medium` - Configuration changes, key rotation
- `low` - Successful authentication, routine operations

---

## 8. Common Security Patterns

### Protect Sensitive Operation
```php
public function destroy(Request $request, $id)
{
    // 1. Authenticate user
    $user = $request->user();

    // 2. Authorize action
    $site = Site::findOrFail($id);
    $this->authorize('delete', $site);

    // 3. Verify password confirmation (middleware handles this)
    // Middleware: 'password.confirm'

    // 4. Validate input
    $request->validate([
        'confirmation' => 'required|string|in:DELETE',
    ]);

    // 5. Rate limit (middleware handles this)
    // Middleware: 'throttle:sensitive'

    // 6. Execute operation
    $site->delete();

    // 7. Audit log
    AuditLog::log('site.deleted',
        userId: $user->id,
        resourceType: 'Site',
        resourceId: $site->id,
        severity: 'high'
    );

    return response()->json(['success' => true]);
}
```

### Protect Route
```php
Route::delete('/sites/{id}', [SiteController::class, 'destroy'])
    ->middleware([
        'auth:sanctum',           // 1. Authentication
        '2fa.required',           // 2. Two-factor auth
        'password.confirm',       // 3. Password confirmation
        'throttle:sensitive',     // 4. Rate limiting
    ])
    ->name('sites.destroy');
```

---

## 9. Configuration

### Environment Variables (.env)
```bash
# Security
APP_SIGNING_SECRET=your_random_256_bit_secret

# Session Security
SESSION_DRIVER=redis
SESSION_SECURE_COOKIE=true
SESSION_HTTP_ONLY=true
SESSION_SAME_SITE=strict

# 2FA
GOOGLE_2FA_COMPANY=CHOM
```

### Generate Secure Secret
```bash
# Generate signing secret
php artisan key:generate --show

# Or using OpenSSL
openssl rand -base64 32
```

---

## 10. Error Handling

### Common Security Error Codes

| Code | HTTP | Meaning | Action |
|------|------|---------|--------|
| `2FA_SETUP_REQUIRED` | 403 | 2FA not set up | Redirect to 2FA setup |
| `2FA_VERIFICATION_REQUIRED` | 403 | 2FA not verified | Request 2FA code |
| `2FA_SESSION_EXPIRED` | 403 | 2FA expired (24h) | Re-verify 2FA |
| `PASSWORD_CONFIRMATION_REQUIRED` | 403 | Need password | Confirm password |
| `SIGNATURE_MISSING` | 401 | No signature | Add signature headers |
| `SIGNATURE_EXPIRED` | 401 | Old signature | Generate new signature |
| `SIGNATURE_INVALID` | 401 | Bad signature | Check signing logic |
| `RATE_LIMIT_EXCEEDED` | 429 | Too many requests | Wait and retry |

### Handle Security Errors (Frontend)
```javascript
async function apiCall(url, options = {}) {
    const response = await fetch(url, options);

    if (!response.ok) {
        const error = await response.json();

        switch (error.error.code) {
            case '2FA_SETUP_REQUIRED':
                // Redirect to 2FA setup
                window.location.href = '/auth/2fa/setup';
                break;

            case '2FA_VERIFICATION_REQUIRED':
                // Show 2FA verification modal
                show2FAModal();
                break;

            case 'PASSWORD_CONFIRMATION_REQUIRED':
                // Show password confirmation modal
                showPasswordConfirmModal();
                break;

            case 'RATE_LIMIT_EXCEEDED':
                // Show rate limit message with retry_after
                showRateLimitMessage(error.error.retry_after);
                break;

            default:
                // Generic error handling
                showError(error.error.message);
        }
    }

    return response.json();
}
```

---

## 11. Testing

### Test 2FA Flow
```php
// Feature test
public function test_admin_requires_2fa()
{
    $admin = User::factory()->create(['role' => 'admin']);

    $response = $this->actingAs($admin)
        ->getJson('/api/v1/sites');

    $response->assertStatus(403)
        ->assertJson(['error' => ['code' => '2FA_SETUP_REQUIRED']]);
}
```

### Test Rate Limiting
```php
public function test_authentication_rate_limiting()
{
    for ($i = 0; $i < 6; $i++) {
        $response = $this->postJson('/api/v1/auth/login', [
            'email' => 'test@example.com',
            'password' => 'wrong',
        ]);
    }

    $response->assertStatus(429);
}
```

### Test Password Confirmation
```php
public function test_sensitive_operation_requires_password_confirmation()
{
    $user = User::factory()->create();
    $site = Site::factory()->create(['user_id' => $user->id]);

    $response = $this->actingAs($user)
        ->deleteJson("/api/v1/sites/{$site->id}");

    $response->assertStatus(403)
        ->assertJson(['error' => ['code' => 'PASSWORD_CONFIRMATION_REQUIRED']]);
}
```

---

## 12. Troubleshooting

### 2FA Issues

**Problem:** "2FA_SETUP_REQUIRED" even though 2FA is enabled
**Solution:** Check session has 2FA verified flag
```php
session(['2fa_verified' => true, '2fa_verified_at' => now()]);
```

**Problem:** QR code not displaying
**Solution:** Check dependencies installed
```bash
composer require pragmarx/google2fa bacon/bacon-qr-code
```

### Rate Limiting Issues

**Problem:** Rate limited too quickly
**Solution:** Check tier limits in AppServiceProvider
```php
$tier = $user->organization->subscription->tier;
// Verify tier is set correctly
```

**Problem:** Rate limits not working
**Solution:** Check Redis connection
```bash
redis-cli ping
```

### Signature Verification Issues

**Problem:** "SIGNATURE_INVALID" on valid signature
**Solution:** Check timestamp synchronization (NTP)
```bash
# Sync time
ntpdate -s time.nist.gov
```

**Problem:** Signature works locally but not production
**Solution:** Check APP_SIGNING_SECRET is same on both
```bash
# .env
APP_SIGNING_SECRET=same_secret_everywhere
```

---

## Quick Reference Summary

### Must-Use Security Middleware
```php
'auth:sanctum'         // Authentication
'2fa.required'         // Two-factor (auto-applied globally)
'password.confirm'     // Password confirmation (sensitive ops)
'throttle:sensitive'   // Rate limiting (deletions, etc.)
'verify.signature'     // Request signing (webhooks)
```

### Common Operations
```bash
# Check security health
php artisan health:security

# Rotate secrets
php artisan secrets:rotate --all

# Run migrations
php artisan migrate

# Generate secure secret
openssl rand -base64 32
```

### Security Checklist
- [ ] 2FA enabled for all admins
- [ ] Password confirmation on sensitive operations
- [ ] Rate limiting applied to all routes
- [ ] Secrets rotation scheduled
- [ ] Security health monitoring active
- [ ] Audit logging enabled
- [ ] SSL certificates current
- [ ] Environment configured securely

---

**For Full Documentation:** See [SECURITY-IMPLEMENTATION.md](./SECURITY-IMPLEMENTATION.md)

**For Audit Report:** See [SECURITY-AUDIT-REPORT.md](./SECURITY-AUDIT-REPORT.md)
