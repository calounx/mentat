# CHOM - Application Security Guide

> For general security policy, vulnerability reporting, and best practices, see the [main Security Policy](../../../SECURITY.md).

This document covers security considerations specific to CHOM (Cloud Hosting Operations Manager), a Laravel-based application for managing VPS deployments and monitoring.

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.1.x   | :white_check_mark: |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting Vulnerabilities

**Please use the unified reporting procedure outlined in [main SECURITY.md](../../../SECURITY.md#reporting-a-vulnerability).**

For CHOM-specific vulnerabilities, include:
- Component affected (e.g., `SiteController.php`, API endpoint)
- Type of vulnerability (e.g., SQL injection, XSS, CSRF)
- Laravel version and CHOM version
- Steps to reproduce

---

## Environment Variable Security

### Critical Configuration

**NEVER commit `.env` files with real credentials:**

```bash
# Bad - DO NOT DO THIS
git add .env

# Good - Only commit examples
git add .env.example
```

### Required Security Settings

**Production environment (.env):**

```env
# Application
APP_ENV=production
APP_DEBUG=false
APP_KEY=base64:...  # Generate with: php artisan key:generate

# Database
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=chom
DB_USERNAME=chom_user
DB_PASSWORD=<strong_random_password_here>

# Session & Cache
SESSION_DRIVER=database  # or redis (more secure than file)
CACHE_DRIVER=redis       # or database

# Queue
QUEUE_CONNECTION=database  # or redis

# Stripe (Payment Processing)
STRIPE_KEY=pk_live_...
STRIPE_SECRET=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...  # Critical for webhook validation

# Observability
PROMETHEUS_URL=https://your-monitoring.example.com/prometheus
LOKI_URL=https://your-monitoring.example.com/loki
PROMETHEUS_USERNAME=prometheus_user
PROMETHEUS_PASSWORD=<strong_password>

# Mail
MAIL_MAILER=smtp
MAIL_HOST=smtp.example.com
MAIL_PORT=587
MAIL_USERNAME=your_username
MAIL_PASSWORD=<strong_password>
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=noreply@example.com
```

### Development vs Production

**Key differences:**

| Setting | Development | Production |
|---------|------------|------------|
| APP_ENV | local | production |
| APP_DEBUG | true | false |
| SESSION_DRIVER | file | database/redis |
| CACHE_DRIVER | file | redis |
| DB_PASSWORD | simple | strong (16+ chars) |
| STRIPE_* | test keys | live keys |

**Security implications:**
- `APP_DEBUG=true` exposes sensitive information (stack traces, env vars)
- File-based sessions are less secure than database/redis
- Test Stripe keys prevent actual charges but have different security profiles

---

## API Security

### Authentication

**Laravel Sanctum:**

All API endpoints use Laravel Sanctum for token-based authentication:

```php
// API routes (routes/api.php)
Route::middleware('auth:sanctum')->group(function () {
    Route::get('/user', [UserController::class, 'show']);
    Route::apiResource('sites', SiteController::class);
    Route::apiResource('vps-servers', VpsController::class);
});
```

**Token generation:**

```php
// Generate API token for user
$token = $user->createToken('token-name')->plainTextToken;

// Token expires based on config/sanctum.php settings
// Default: tokens don't expire (consider setting expiration)
```

**Best practices:**
- Use HTTPS only for API endpoints
- Set token expiration: `'expiration' => 60` (minutes) in `config/sanctum.php`
- Implement token rotation for long-lived tokens
- Revoke tokens on logout: `$request->user()->currentAccessToken()->delete()`

### Rate Limiting

**Configured in routes/api.php:**

```php
Route::middleware(['throttle:api'])->group(function () {
    // Rate limit: 60 requests per minute per user
    // Configured in app/Providers/RouteServiceProvider.php
});

// Custom rate limits for sensitive endpoints
Route::middleware(['throttle:10,1'])->group(function () {
    Route::post('/deploy', [DeployController::class, 'deploy']);
});
```

**Adjust rate limits in RouteServiceProvider:**

```php
RateLimiter::for('api', function (Request $request) {
    return Limit::perMinute(60)->by($request->user()?->id ?: $request->ip());
});
```

### CSRF Protection

**Web routes automatically protected:**

```php
// CSRF middleware enabled by default for web routes
// Token included in forms via @csrf blade directive

<form method="POST" action="/sites">
    @csrf
    <!-- form fields -->
</form>
```

**API routes exempt from CSRF:**
- API routes use token authentication instead
- CSRF not needed for stateless API requests
- Configured in `app/Http/Middleware/VerifyCsrfToken.php`

### Input Validation

**All endpoints validate input:**

```php
// Example: SiteController validation
public function store(Request $request)
{
    $validated = $request->validate([
        'name' => 'required|string|max:255',
        'domain' => 'required|string|regex:/^[a-z0-9.-]+$/i',
        'vps_id' => 'required|exists:vps_servers,id',
        'git_repo' => 'required|url',
    ]);

    // Validated data is safe to use
    Site::create($validated);
}
```

**Validation rules:**
- Use `exists:table,column` to prevent foreign key injection
- Use `regex` for domain/URL validation
- Sanitize file uploads with `mimes`, `max` rules
- Use `confirmed` for password confirmation

---

## Tenant Isolation

CHOM implements multi-tenancy where each user can only access their own resources.

### Database-Level Isolation

**Eloquent global scopes:**

```php
// Models automatically scope queries by user
class Site extends Model
{
    protected static function booted()
    {
        static::addGlobalScope('user', function (Builder $builder) {
            if (auth()->check()) {
                $builder->where('user_id', auth()->id());
            }
        });
    }
}
```

### Policy-Based Authorization

**Laravel Policies enforce access control:**

```php
// app/Policies/SitePolicy.php
public function view(User $user, Site $site)
{
    return $user->id === $site->user_id;
}

public function update(User $user, Site $site)
{
    return $user->id === $site->user_id;
}
```

**Usage in controllers:**

```php
// Automatic policy enforcement
public function update(Request $request, Site $site)
{
    $this->authorize('update', $site);  // Throws 403 if unauthorized

    // Update logic here
}
```

### Prometheus/Loki Query Scoping

**Tenant-specific metrics:**

```php
// Queries automatically scoped by tenant_id label
$query = "up{tenant_id=\"{$user->tenant_id}\"}";

// This prevents cross-tenant data access
```

**Security measures:**
- Tenant ID stored in database per user
- Metrics labeled with tenant_id at export time
- Query service validates tenant_id matches authenticated user

### VPS Operations

**SSH operations are user-scoped:**

```php
// Only operates on VPS servers owned by the authenticated user
public function executeCommand(VpsServer $vps, string $command)
{
    $this->authorize('manage', $vps);

    // SSH connection using user's VPS credentials
    SSH::connect($vps)->execute($command);
}
```

### Site Backups

**Backup isolation:**

```php
// Backups stored in user-specific directories
$backupPath = storage_path("app/backups/user_{$user->id}/site_{$site->id}/");

// Restoration limited to user's own sites
public function restore(Backup $backup)
{
    $this->authorize('view', $backup->site);
    // Restore logic
}
```

---

## SSH Key Management

### Storage Location

**SSH keys stored in Laravel storage:**

```bash
# Key storage
storage/app/ssh/chom_deploy_key
storage/app/ssh/chom_deploy_key.pub

# Correct permissions (enforced by deployment scripts)
chmod 600 storage/app/ssh/chom_deploy_key
chmod 644 storage/app/ssh/chom_deploy_key.pub
chown www-data:www-data storage/app/ssh/*
```

### Key Generation

**Generate deployment keys:**

```bash
# Generate ED25519 key (more secure than RSA)
ssh-keygen -t ed25519 -f storage/app/ssh/chom_deploy_key -N "" -C "chom-deploy"

# Add public key to target servers
ssh-copy-id -i storage/app/ssh/chom_deploy_key.pub user@vps-server
```

### Security Best Practices

**Key management:**
- Never commit SSH keys to git (in `.gitignore`)
- Use separate keys for each environment (dev/staging/prod)
- Rotate keys every 90 days
- Use passphrases for keys (if possible with automation)
- Limit key permissions on target servers (read-only where possible)

**SSH config security:**

```php
// app/Services/SshService.php
public function connect(VpsServer $vps)
{
    return SSH::create(
        $vps->hostname,
        $vps->ssh_user,
        22,
        [
            'private_key' => storage_path('app/ssh/chom_deploy_key'),
            'timeout' => 30,
            'strict_host_key_checking' => true,  // Prevent MITM attacks
        ]
    );
}
```

### Per-VPS Key Storage

**User-specific VPS credentials:**

```php
// VPS credentials encrypted in database
class VpsServer extends Model
{
    protected $casts = [
        'ssh_key' => 'encrypted',  // Laravel encryption
        'ssh_password' => 'encrypted',
    ];
}
```

**Encryption keys:**
- Stored in `APP_KEY` environment variable
- Generated via `php artisan key:generate`
- Never commit to version control
- Rotate periodically (requires re-encryption of data)

---

## Laravel-Specific Security

### Security Features Enabled

**Built-in protections:**

1. **Password Hashing**
   - Uses bcrypt by default (cost factor: 10)
   - Configure in `config/hashing.php`
   - Automatically rehashes on login if cost changes

2. **CSRF Protection**
   - Enabled for all web routes
   - Token rotation on authentication state change
   - Configurable in `app/Http/Middleware/VerifyCsrfToken.php`

3. **XSS Protection**
   - Blade escapes output by default: `{{ $variable }}`
   - Use `{!! $variable !!}` only for trusted HTML
   - Configure Content Security Policy headers

4. **SQL Injection Protection**
   - Eloquent ORM uses parameterized queries
   - Query Builder escapes inputs
   - Avoid `DB::raw()` with user input

5. **Mass Assignment Protection**
   - Use `$fillable` or `$guarded` on models
   - Validate request data before assignment

### Middleware Security

**Security-related middleware:**

```php
// app/Http/Kernel.php
protected $middlewareGroups = [
    'web' => [
        \App\Http\Middleware\EncryptCookies::class,
        \Illuminate\Cookie\Middleware\AddQueuedCookiesToResponse::class,
        \Illuminate\Session\Middleware\StartSession::class,
        \Illuminate\View\Middleware\ShareErrorsFromSession::class,
        \App\Http\Middleware\VerifyCsrfToken::class,
        \Illuminate\Routing\Middleware\SubstituteBindings::class,
    ],
    'api' => [
        'throttle:api',
        \Illuminate\Routing\Middleware\SubstituteBindings::class,
    ],
];
```

### File Upload Security

**Secure file handling:**

```php
// Validate file uploads
$request->validate([
    'backup' => 'required|file|mimes:zip,tar,gz|max:102400', // 100MB max
]);

// Store with generated filename
$path = $request->file('backup')->store('backups', 'private');

// Never trust original filename
// Never execute uploaded files
// Scan for malware if possible
```

### Database Security

**Connection security:**

```env
# Use SSL for database connections (if available)
DB_SSL_MODE=VERIFY_IDENTITY
DB_SSL_CA=/path/to/ca-cert.pem
```

**MySQL Exporter credentials:**

```php
// Limited read-only access for monitoring
// Separate user for MySQL exporter
// GRANT SELECT ON performance_schema.* TO 'exporter'@'localhost';
```

---

## Stripe Integration Security

### Webhook Signature Validation

**Critical for payment security:**

```php
// app/Http/Controllers/StripeWebhookController.php
public function handleWebhook(Request $request)
{
    $payload = $request->getContent();
    $sig_header = $request->header('Stripe-Signature');
    $endpoint_secret = config('services.stripe.webhook_secret');

    try {
        $event = \Stripe\Webhook::constructEvent(
            $payload, $sig_header, $endpoint_secret
        );
    } catch(\UnexpectedValueException $e) {
        return response()->json(['error' => 'Invalid payload'], 400);
    } catch(\Stripe\Exception\SignatureVerificationException $e) {
        return response()->json(['error' => 'Invalid signature'], 400);
    }

    // Process validated event
    $this->handleStripeEvent($event);
}
```

**Webhook endpoint protection:**
- Always validate webhook signatures
- Never trust webhook data without validation
- Use HTTPS for webhook endpoints
- Log all webhook events for audit trail

### API Key Security

**Separate keys for environments:**

```env
# Test mode (development)
STRIPE_KEY=pk_test_...
STRIPE_SECRET=sk_test_...

# Live mode (production) - NEVER commit these
STRIPE_KEY=pk_live_...
STRIPE_SECRET=sk_live_...
```

**Key rotation:**
- Rotate keys if compromised immediately
- Test with new keys before deploying
- Update webhook secrets when rotating keys

---

## Security Checklist

### Before Deployment

**Application:**
- [ ] `APP_DEBUG=false` in production
- [ ] `APP_ENV=production` set correctly
- [ ] `APP_KEY` generated and secure
- [ ] All `.env` variables configured
- [ ] No secrets in git repository

**Database:**
- [ ] Strong database password (16+ characters)
- [ ] Database user has minimal required privileges
- [ ] SSL enabled for database connections (if remote)
- [ ] Regular backups configured

**Authentication:**
- [ ] Password requirements enforced (min 8 chars, complexity)
- [ ] Rate limiting enabled on login endpoints
- [ ] Session driver set to database or redis
- [ ] CSRF protection enabled

**API Security:**
- [ ] Sanctum configured correctly
- [ ] API rate limiting enabled
- [ ] All endpoints require authentication
- [ ] Input validation on all endpoints

**File Security:**
- [ ] SSH keys have correct permissions (600)
- [ ] SSH keys not in git repository
- [ ] File upload validation enabled
- [ ] Storage directories have correct permissions

**External Services:**
- [ ] Stripe webhook signature validation enabled
- [ ] Prometheus/Loki use HTTPS
- [ ] SMTP credentials secured
- [ ] All API tokens rotated from defaults

### During Operations

**Regular monitoring:**
- [ ] Review Laravel logs weekly: `storage/logs/laravel.log`
- [ ] Monitor failed login attempts
- [ ] Check for unusual API usage patterns
- [ ] Review Stripe webhook logs for failures
- [ ] Verify database backup integrity

**Maintenance:**
- [ ] Update Laravel and dependencies monthly: `composer update`
- [ ] Run security audit: `composer audit`
- [ ] Update npm packages: `npm update`
- [ ] Run npm security audit: `npm audit`
- [ ] Rotate API tokens every 90 days
- [ ] Review user permissions quarterly

### After Security Incident

1. [ ] Isolate affected systems
2. [ ] Rotate all credentials (DB, API keys, SSH keys)
3. [ ] Review Laravel logs for suspicious activity
4. [ ] Check database for unauthorized access
5. [ ] Restore from backup if compromised
6. [ ] Notify affected users within 24 hours
7. [ ] Report to main security policy: [../../../SECURITY.md](../../../SECURITY.md)
8. [ ] Update security procedures
9. [ ] Document lessons learned

---

## Common Vulnerabilities & Mitigations

### SQL Injection

**Risk:** Attackers inject malicious SQL via user inputs

**Mitigation:**
- Always use Eloquent ORM or Query Builder
- Never concatenate user input into SQL queries
- Avoid `DB::raw()` with user-supplied data
- Validate all inputs

```php
// BAD - Vulnerable to SQL injection
$users = DB::select("SELECT * FROM users WHERE email = '{$request->email}'");

// GOOD - Parameterized query
$users = DB::table('users')->where('email', $request->email)->get();
```

### XSS (Cross-Site Scripting)

**Risk:** Attackers inject malicious JavaScript into pages

**Mitigation:**
- Use Blade's escaped output: `{{ $variable }}`
- Only use `{!! $variable !!}` for trusted, sanitized HTML
- Implement Content Security Policy headers
- Validate and sanitize user input

```php
// BAD - Vulnerable to XSS
{!! $request->input('name') !!}

// GOOD - Escaped output
{{ $request->input('name') }}
```

### CSRF (Cross-Site Request Forgery)

**Risk:** Attackers trick users into performing unwanted actions

**Mitigation:**
- CSRF middleware enabled by default
- Include `@csrf` in all forms
- Validate tokens on state-changing requests
- Use SameSite cookie attribute

```blade
<!-- GOOD - CSRF token included -->
<form method="POST" action="/sites">
    @csrf
    <!-- form fields -->
</form>
```

### Mass Assignment

**Risk:** Attackers modify unintended model attributes

**Mitigation:**
- Define `$fillable` or `$guarded` on all models
- Validate request data before assignment
- Use Form Requests for complex validation

```php
// BAD - Allows mass assignment of any field
Site::create($request->all());

// GOOD - Only allowed fields
class Site extends Model {
    protected $fillable = ['name', 'domain', 'vps_id'];
}
Site::create($request->validated());
```

### Insecure Direct Object References (IDOR)

**Risk:** Users access resources they shouldn't by changing IDs

**Mitigation:**
- Use policies to authorize all resource access
- Implement tenant isolation via global scopes
- Never trust user-supplied IDs without authorization

```php
// BAD - No authorization check
$site = Site::findOrFail($request->id);

// GOOD - Policy enforcement
$site = Site::findOrFail($request->id);
$this->authorize('view', $site);
```

---

## Security Resources

### Internal Documentation

- [Main Security Policy](../../../SECURITY.md) - Unified security policy and reporting
- [Laravel Documentation](https://laravel.com/docs/security) - Laravel security features

### External Resources

- [OWASP Top 10](https://owasp.org/www-project-top-ten/) - Common web vulnerabilities
- [Laravel Security Best Practices](https://laravel.com/docs/11.x/security)
- [Stripe Security](https://stripe.com/docs/security) - Payment security guidelines
- [Sanctum Documentation](https://laravel.com/docs/11.x/sanctum) - API authentication

### Dependency Auditing

```bash
# Check PHP dependencies for vulnerabilities
composer audit

# Check JavaScript dependencies for vulnerabilities
npm audit

# Update dependencies
composer update
npm update
```

---

## Contact

**For security vulnerabilities:**
- Report via: [GitHub Security Advisory](https://github.com/calounx/mentat/security/advisories/new)
- See reporting procedures in [main Security Policy](../../../SECURITY.md)

**For general issues:**
- GitHub Issues: https://github.com/calounx/mentat/issues
- Documentation: [CHOM README](../../README.md)

---

**Last Updated:** 2025-12-28
**Document Version:** 1.0 (initial)
**Applies to:** CHOM v1.1.x and v1.0.x
