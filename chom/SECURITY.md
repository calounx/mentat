# Security Best Practices

## Overview

CHOM implements enterprise-grade security features to protect against OWASP Top 10 vulnerabilities and ensure data protection for our multi-tenant hosting platform.

## Table of Contents

1. [Authentication & Authorization](#authentication--authorization)
2. [Data Protection](#data-protection)
3. [API Security](#api-security)
4. [Input Validation](#input-validation)
5. [Rate Limiting](#rate-limiting)
6. [Security Headers](#security-headers)
7. [Audit Logging](#audit-logging)
8. [Secrets Management](#secrets-management)
9. [Incident Response](#incident-response)
10. [Security Checklist](#security-checklist)

## Authentication & Authorization

### Session Security

**Features:**
- Session fixation protection (regenerate on login)
- IP address validation
- User agent validation
- Suspicious login detection
- Device fingerprinting

**Configuration:**
```php
// config/security.php
'session' => [
    'regenerate_on_login' => true,
    'validate_ip' => true,
    'validate_user_agent' => true,
    'allow_subnet_changes' => false,
    'lifetime' => 120, // minutes
    'idle_timeout' => 30, // minutes
],
```

**Usage:**
```php
use App\Services\SessionSecurityService;

$sessionSecurity = app(SessionSecurityService::class);

// Initialize session on login
$sessionSecurity->initializeSession($request, $user);

// Validate session on each request
$result = $sessionSecurity->validateSession($request, $user);
if (!$result['valid']) {
    // Handle invalid session
    abort(401, $result['message']);
}
```

### Account Lockout

**Protection:** Prevents brute force attacks by locking accounts after repeated failed login attempts.

**Configuration:**
```php
'account_lockout' => [
    'enabled' => true,
    'max_attempts' => 5,
    'lockout_duration' => 15, // minutes
    'attempt_window' => 15, // minutes
    'progressive_lockout' => true,
],
```

**Usage:**
```php
// Record failed login
$result = $sessionSecurity->recordFailedLogin($email, $ipAddress);

if ($result['locked']) {
    $unlockAt = date('Y-m-d H:i:s', $result['unlock_at']);
    return response()->json([
        'message' => "Account locked. Try again after {$unlockAt}",
    ], 423);
}

// Check if account is locked before login attempt
$lockStatus = $sessionSecurity->isAccountLocked($email);
if ($lockStatus['locked']) {
    return response()->json([
        'message' => 'Account is locked',
    ], 423);
}
```

## Data Protection

### Encryption at Rest

**Implementation:** AES-256-GCM encryption for sensitive data

**Features:**
- Unique IV for each encryption
- Authentication tags to detect tampering
- Key rotation support
- Access audit logging

**Usage:**
```php
use App\Services\SecretsManagerService;

$secrets = app(SecretsManagerService::class);

// Store encrypted secret
$secretId = $secrets->storeSecret(
    secretType: 'vps_password',
    plaintext: 'super-secret-password',
    identifier: $vpsId,
    metadata: ['created_by' => $userId]
);

// Retrieve secret
$password = $secrets->retrieveSecret($secretId);

// Rotate secret
$secrets->rotateSecret($secretId);

// Delete secret
$secrets->deleteSecret($secretId);
```

### VPS Credential Rotation

**Best Practice:** Rotate VPS credentials every 30 days.

```php
// Rotate VPS credentials
$result = $secrets->rotateVpsCredentials($vpsId);

// Returns: ['secret_id', 'password', 'vps_id']
```

### API Key Management

**Features:**
- SHA-256 hashed storage
- Automatic expiration
- Scoped permissions
- Usage tracking

```php
// Generate API key
$apiKey = $secrets->generateApiKey($userId, [
    'scope' => 'read:sites,write:sites',
    'description' => 'CI/CD deployment key',
]);

// Returns plaintext key (only shown once)
// User should save: $apiKey['api_key']

// Revoke API key
$secrets->revokeApiKey($keyId);
```

## API Security

### API Authentication

**Supported Methods:**
1. JWT Bearer Tokens
2. API Key Authentication

**Configuration:**
```php
'api' => [
    'jwt' => [
        'enabled' => true,
        'ttl' => 3600, // 1 hour
        'refresh_ttl' => 604800, // 7 days
    ],
    'api_key' => [
        'enabled' => true,
        'header_name' => 'X-API-Key',
    ],
],
```

**Usage:**
```php
// Apply API security middleware
Route::middleware(['api.security'])->group(function () {
    Route::get('/sites', [SiteController::class, 'index']);
});

// JWT Authentication
// Header: Authorization: Bearer {token}

// API Key Authentication
// Header: X-API-Key: chom_{key}
```

### CORS Configuration

**Security:** Strict origin validation prevents unauthorized cross-origin access.

```php
'cors' => [
    'enabled' => true,
    'allowed_origins' => [
        'https://app.chom.com',
        'https://*.chom.com', // Wildcard subdomain
    ],
    'allowed_methods' => ['GET', 'POST', 'PUT', 'DELETE'],
    'supports_credentials' => true,
],
```

### Request Signing

**For Critical Operations:**

```php
// Enable request signing for critical operations
'request_signing' => [
    'enabled' => true,
    'algorithm' => 'sha256',
    'max_timestamp_drift' => 300, // 5 minutes
],

// Sign request
$timestamp = time();
$signature = hash_hmac('sha256',
    $method . "\n" . $path . "\n" . $timestamp . "\n" . $body,
    $secret
);

// Headers:
// X-Signature: {signature}
// X-Timestamp: {timestamp}
```

## Input Validation

### Validation Rules

**Available Rules:**
- `DomainNameRule`: RFC-compliant domain validation with IDN homograph protection
- `IpAddressRule`: IPv4/IPv6 validation with private range detection
- `SecureEmailRule`: RFC 5322 validation with disposable email detection
- `NoSqlInjectionRule`: SQL injection pattern detection
- `NoXssRule`: XSS pattern detection

**Usage:**
```php
use App\Rules\DomainNameRule;
use App\Rules\SecureEmailRule;
use App\Rules\NoSqlInjectionRule;

$request->validate([
    'domain' => ['required', new DomainNameRule()],
    'email' => ['required', new SecureEmailRule()],
    'description' => ['required', new NoSqlInjectionRule(), new NoXssRule()],
]);
```

**Example:**
```php
// Domain validation
new DomainNameRule(
    allowIdn: false, // Block internationalized domains
    requireValidTld: true // Require valid TLD
)

// Email validation
new SecureEmailRule(
    blockDisposable: true, // Block temporary email providers
    blockRoleBased: false, // Allow admin@, info@, etc.
    blockPlusAddressing: false // Allow user+tag@domain.com
)

// SQL injection detection
new NoSqlInjectionRule(
    strictMode: true // More aggressive pattern matching
)
```

## Rate Limiting

### Configuration

```php
'rate_limiting' => [
    'enabled' => true,

    // Per-user limits
    'authenticated' => [
        'requests' => 100,
        'decay_minutes' => 1,
    ],

    // Anonymous limits
    'anonymous' => [
        'requests' => 20,
        'decay_minutes' => 1,
    ],

    // Per-tenant limits (by subscription tier)
    'tenant_limits' => [
        'free' => ['requests_per_hour' => 1000],
        'basic' => ['requests_per_hour' => 5000],
        'professional' => ['requests_per_hour' => 20000],
        'enterprise' => ['requests_per_hour' => 100000],
    ],

    // Critical operations
    'critical_operations' => [
        'login' => [
            'requests' => 5,
            'decay_minutes' => 15,
        ],
    ],
],
```

### Usage

```php
// Apply to routes
Route::middleware(['rate.limit'])->group(function () {
    Route::post('/api/data', [DataController::class, 'store']);
});

// Custom limiter for specific operations
Route::post('/login', [AuthController::class, 'login'])
    ->middleware('rate.limit:login');
```

## Security Headers

### Headers Applied

**Middleware:** `SecurityHeadersMiddleware`

**Headers:**
- `X-Frame-Options: DENY` - Prevents clickjacking
- `X-Content-Type-Options: nosniff` - Prevents MIME sniffing
- `X-XSS-Protection: 1; mode=block` - Enables XSS filter
- `Strict-Transport-Security` - Forces HTTPS
- `Referrer-Policy: strict-origin-when-cross-origin` - Controls referrer leakage
- `Permissions-Policy` - Restricts browser features
- `Content-Security-Policy` - Prevents XSS and injection

### Content Security Policy

```php
'content_security_policy' => [
    'enabled' => true,
    'directives' => [
        'default-src' => "'self'",
        'script-src' => "'self' 'nonce-{nonce}'",
        'style-src' => "'self' 'nonce-{nonce}' 'unsafe-inline'",
        'img-src' => "'self' data: https:",
        'font-src' => "'self' data:",
        'connect-src' => "'self'",
        'frame-ancestors' => "'none'",
    ],
],
```

**Usage in Blade Templates:**
```blade
{{-- Use CSP nonce for inline scripts --}}
<script nonce="{{ csp_nonce() }}">
    // Inline JavaScript
</script>
```

## Audit Logging

### Features

- Tamper-proof logging with SHA-256 hash chains
- Severity levels (low, medium, high, critical)
- Automatic logging of authentication events
- Sensitive operation tracking
- Hash chain integrity verification

### Usage

```php
use App\Services\AuditLogger;

$audit = app(AuditLogger::class);

// Log general event
$audit->log('site.created', 'medium', [
    'site_id' => $site->id,
    'domain' => $site->domain,
]);

// Log authentication event
$audit->logAuthentication('login_success', $user->id, [
    'method' => '2fa',
]);

// Log authorization failure
$audit->logAuthorizationFailure(
    action: 'site.delete',
    userId: $user->id,
    resourceType: 'site',
    resourceId: $site->id
);

// Log sensitive operation
$audit->logSensitiveOperation(
    operation: 'user.role.changed',
    resourceType: 'user',
    resourceId: $targetUser->id,
    context: [
        'old_role' => $oldRole,
        'new_role' => $newRole,
    ]
);

// Verify hash chain integrity
$result = $audit->verifyHashChain();
if (!$result['valid']) {
    // ALERT: Tampering detected!
    Log::critical('Audit log tampering detected', $result);
}
```

### Sensitive Operations

These operations are automatically logged with critical severity:

- `user.role.changed`
- `user.deleted`
- `site.deleted`
- `vps.credentials.rotated`
- `api_key.created`
- `api_key.revoked`
- `subscription.changed`
- `payment_method.added`
- `team.member.removed`

## Secrets Management

### Best Practices

1. **Never commit secrets to version control**
   - Use `.env` files (excluded in `.gitignore`)
   - Use environment variables
   - Use secrets manager service

2. **Rotate credentials regularly**
   ```php
   // Check for expiring secrets
   $expiring = $secrets->findSecretsRequiringRotation(warningDays: 7);

   foreach ($expiring as $secret) {
       // Notify admin or auto-rotate
   }
   ```

3. **Minimum key requirements**
   - Passwords: 32+ characters, mixed case, numbers, symbols
   - API keys: 256-bit entropy
   - Encryption keys: AES-256 (32 bytes)

4. **Access control**
   - Log all secret access
   - Implement least privilege
   - Regular access audits

## Incident Response

### Security Event Types

Monitor `security_events` table for:

- `brute_force` - Multiple failed login attempts
- `account_takeover` - Suspicious login from new location/device
- `sql_injection_attempt` - SQL injection pattern detected
- `xss_attempt` - XSS pattern detected
- `unauthorized_access` - Authorization failure
- `data_exfiltration` - Large data export
- `privilege_escalation` - Role change attempt

### Response Procedures

1. **Detect:** Monitor security events and audit logs
2. **Analyze:** Review event data and context
3. **Contain:** Lock affected accounts, revoke compromised keys
4. **Eradicate:** Remove malicious access, patch vulnerability
5. **Recover:** Restore normal operations
6. **Learn:** Update security policies, improve detection

### Emergency Contacts

```env
SECURITY_ALERT_EMAIL=security@chom.com
SECURITY_ALERT_SLACK_WEBHOOK=https://hooks.slack.com/...
```

## Security Checklist

### Pre-Production

- [ ] `APP_KEY` is set and never committed
- [ ] `DB_PASSWORD` uses strong password (32+ characters)
- [ ] `REDIS_PASSWORD` is set
- [ ] `JWT_SECRET` is set (different from APP_KEY)
- [ ] All `.env` variables validated on boot
- [ ] HTTPS enforced (HSTS enabled)
- [ ] Security headers middleware registered
- [ ] Rate limiting enabled
- [ ] Audit logging enabled
- [ ] Database backups encrypted
- [ ] Secrets using AES-256-GCM encryption

### Post-Production

- [ ] Monitor security events daily
- [ ] Review audit logs weekly
- [ ] Rotate VPS credentials monthly
- [ ] Rotate API keys quarterly
- [ ] Test incident response procedures
- [ ] Update dependencies regularly
- [ ] Security training for team
- [ ] Penetration testing annually

### Code Review Checklist

- [ ] No hardcoded secrets
- [ ] All user input validated
- [ ] SQL queries use parameter binding
- [ ] Output is properly escaped
- [ ] Authentication required for sensitive operations
- [ ] Authorization checks on all resources
- [ ] Audit logging for sensitive operations
- [ ] Rate limiting on public endpoints
- [ ] CSRF protection on state-changing operations
- [ ] Security headers configured

## Reporting Security Issues

**DO NOT** open public GitHub issues for security vulnerabilities.

**Email:** security@chom.com

**PGP Key:** Available at https://chom.com/.well-known/pgp-key.txt

**Response Time:** Within 24 hours

**Disclosure Policy:** 90 days coordinated disclosure

## Additional Resources

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [OWASP API Security Top 10](https://owasp.org/www-project-api-security/)
- [Laravel Security](https://laravel.com/docs/security)
- [PHP Security Guide](https://www.php.net/manual/en/security.php)
