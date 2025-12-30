# Two-Factor Authentication (2FA) Configuration Guide

## Overview

CHOM implements TOTP-based Two-Factor Authentication (2FA) as a configurable security feature to protect privileged accounts from unauthorized access. This guide explains how to configure 2FA requirements based on your deployment environment and security policies.

**OWASP Reference:** A07:2021 – Identification and Authentication Failures

## Configuration Location

2FA settings are configured in:
- **Config File:** `config/auth.php` → `two_factor_authentication` section
- **Environment Variables:** `.env` file

## Configuration Options

### Global Enable/Disable

Control whether 2FA is globally enabled or disabled:

```env
# Enable 2FA globally (recommended for production)
AUTH_2FA_ENABLED=true

# Disable 2FA (development only - NOT recommended for production)
AUTH_2FA_ENABLED=false
```

**Security Note:** Disabling 2FA significantly reduces security for privileged accounts. Only disable in development environments.

### Role-Based Requirements

Specify which user roles require 2FA (comma-separated list):

```env
# Require 2FA for owner and admin roles (default, recommended)
AUTH_2FA_REQUIRED_ROLES=owner,admin

# Require 2FA for all roles
AUTH_2FA_REQUIRED_ROLES=owner,admin,member,viewer

# Require 2FA for owners only
AUTH_2FA_REQUIRED_ROLES=owner
```

**Available Roles:**
- `owner` - Organization owners (full access)
- `admin` - Organization administrators (full access)
- `member` - Regular members (site management)
- `viewer` - Read-only access

**Best Practice:** At minimum, require 2FA for `owner` and `admin` roles.

### Grace Period

Configure the number of days users have to set up 2FA before enforcement:

```env
# 7-day grace period (default, recommended)
AUTH_2FA_GRACE_PERIOD_DAYS=7

# 14-day grace period (lenient)
AUTH_2FA_GRACE_PERIOD_DAYS=14

# Immediate enforcement (no grace period)
AUTH_2FA_GRACE_PERIOD_DAYS=0
```

**During Grace Period:**
- Users can access the system normally
- Warning headers are sent with each response: `X-2FA-Required-Soon`
- Users should be prompted to set up 2FA

**After Grace Period:**
- Access is blocked with `403 Forbidden` error
- Error code: `2FA_SETUP_REQUIRED`
- Users must set up 2FA to continue

### Session Timeout

Configure how long 2FA verification remains valid in the current session:

```env
# 24-hour session timeout (default, balanced)
AUTH_2FA_SESSION_TIMEOUT_HOURS=24

# 8-hour session timeout (high security)
AUTH_2FA_SESSION_TIMEOUT_HOURS=8

# 72-hour session timeout (lenient)
AUTH_2FA_SESSION_TIMEOUT_HOURS=72
```

**Security Consideration:** Shorter timeouts increase security but may impact user experience.

### Backup Codes

Configure the number of backup recovery codes generated during 2FA setup:

```env
# 8 backup codes (default, recommended)
AUTH_2FA_BACKUP_CODES_COUNT=8

# 10 backup codes (more backups)
AUTH_2FA_BACKUP_CODES_COUNT=10

# 5 backup codes (fewer backups)
AUTH_2FA_BACKUP_CODES_COUNT=5
```

**Backup codes** allow users to access their account if they lose access to their 2FA device.

## Configuration Examples

### Production (High Security)

Recommended for production environments with strict security requirements:

```env
AUTH_2FA_ENABLED=true
AUTH_2FA_REQUIRED_ROLES=owner,admin
AUTH_2FA_GRACE_PERIOD_DAYS=7
AUTH_2FA_SESSION_TIMEOUT_HOURS=8
AUTH_2FA_BACKUP_CODES_COUNT=8
```

### Production (Balanced)

Balanced security and user experience for most production deployments:

```env
AUTH_2FA_ENABLED=true
AUTH_2FA_REQUIRED_ROLES=owner,admin
AUTH_2FA_GRACE_PERIOD_DAYS=7
AUTH_2FA_SESSION_TIMEOUT_HOURS=24
AUTH_2FA_BACKUP_CODES_COUNT=8
```

### Staging

Development/testing environment with 2FA enabled:

```env
AUTH_2FA_ENABLED=true
AUTH_2FA_REQUIRED_ROLES=owner,admin
AUTH_2FA_GRACE_PERIOD_DAYS=14
AUTH_2FA_SESSION_TIMEOUT_HOURS=72
AUTH_2FA_BACKUP_CODES_COUNT=8
```

### Local Development

Local development environment (2FA optional):

```env
# Option 1: Disable 2FA for easier testing
AUTH_2FA_ENABLED=false

# Option 2: Enable with lenient settings
AUTH_2FA_ENABLED=true
AUTH_2FA_REQUIRED_ROLES=owner
AUTH_2FA_GRACE_PERIOD_DAYS=365
AUTH_2FA_SESSION_TIMEOUT_HOURS=720
```

## How It Works

### 1. Role Check

When a user attempts to access a protected resource:

1. Middleware checks if 2FA is globally enabled (`AUTH_2FA_ENABLED`)
2. If disabled, 2FA is skipped entirely
3. If enabled, checks if user's role is in `AUTH_2FA_REQUIRED_ROLES`
4. If role doesn't require 2FA, access is granted

### 2. Grace Period Check

For users whose role requires 2FA but haven't set it up yet:

1. Calculate days since account creation
2. Compare with `AUTH_2FA_GRACE_PERIOD_DAYS`
3. If within grace period, allow access with warning header
4. If grace period expired, block access with `403` error

### 3. Session Verification

For users with 2FA enabled:

1. Check if 2FA was verified in current session (`2fa_verified` session key)
2. Check verification timestamp (`2fa_verified_at`)
3. Compare hours since verification with `AUTH_2FA_SESSION_TIMEOUT_HOURS`
4. If timeout exceeded, require re-verification

## API Error Responses

### 2FA Setup Required

**HTTP Status:** `403 Forbidden`

```json
{
  "success": false,
  "error": {
    "code": "2FA_SETUP_REQUIRED",
    "message": "Two-factor authentication is required for your account. Please set up 2FA to continue.",
    "setup_url": "/auth/2fa/setup",
    "grace_period_expired": true
  }
}
```

### 2FA Verification Required

**HTTP Status:** `403 Forbidden`

```json
{
  "success": false,
  "error": {
    "code": "2FA_VERIFICATION_REQUIRED",
    "message": "Please verify your two-factor authentication code.",
    "verify_url": "/auth/2fa/verify"
  }
}
```

### 2FA Session Expired

**HTTP Status:** `403 Forbidden`

```json
{
  "success": false,
  "error": {
    "code": "2FA_SESSION_EXPIRED",
    "message": "Your two-factor authentication session has expired. Please verify again.",
    "verify_url": "/auth/2fa/verify"
  }
}
```

## Programmatic Access

### Check if 2FA is Required for User

```php
use App\Models\User;

$user = User::find($userId);

if ($user->requires2FA()) {
    // 2FA is required for this user
}
```

### Check if User is in Grace Period

```php
if ($user->requires2FA() && !$user->two_factor_enabled) {
    if ($user->isIn2FAGracePeriod()) {
        // User is within grace period
        $daysRemaining = $user->created_at
            ->addDays(config('auth.two_factor_authentication.grace_period_days'))
            ->diffInDays(now());

        // Show warning to user
    }
}
```

### Get Configuration Values

```php
// Check if 2FA is globally enabled
$enabled = config('auth.two_factor_authentication.enabled');

// Get required roles
$roles = config('auth.two_factor_authentication.required_for_roles');

// Get grace period in days
$gracePeriod = config('auth.two_factor_authentication.grace_period_days');

// Get session timeout in hours
$sessionTimeout = config('auth.two_factor_authentication.session_timeout_hours');
```

## Migration from Hardcoded to Configurable

If migrating from the previous hardcoded implementation:

1. **No database changes required** - 2FA tables remain unchanged
2. **Add environment variables** to `.env`:
   ```bash
   # Copy from .env.example
   AUTH_2FA_ENABLED=true
   AUTH_2FA_REQUIRED_ROLES=owner,admin
   AUTH_2FA_GRACE_PERIOD_DAYS=7
   AUTH_2FA_SESSION_TIMEOUT_HOURS=24
   AUTH_2FA_BACKUP_CODES_COUNT=8
   ```

3. **Clear configuration cache**:
   ```bash
   php artisan config:clear
   php artisan config:cache
   ```

4. **Test configuration**:
   ```bash
   php artisan tinker
   >>> config('auth.two_factor_authentication')
   ```

## Security Best Practices

### 1. Always Enable 2FA in Production

```env
# ✅ CORRECT - Production
AUTH_2FA_ENABLED=true

# ❌ WRONG - Production with 2FA disabled
AUTH_2FA_ENABLED=false
```

### 2. Require 2FA for Privileged Roles

```env
# ✅ CORRECT - Protect privileged accounts
AUTH_2FA_REQUIRED_ROLES=owner,admin

# ⚠️ ACCEPTABLE - All users (high security, impacts UX)
AUTH_2FA_REQUIRED_ROLES=owner,admin,member,viewer

# ❌ WRONG - No 2FA requirement
AUTH_2FA_REQUIRED_ROLES=
```

### 3. Use Reasonable Grace Periods

```env
# ✅ CORRECT - 7 days (balanced)
AUTH_2FA_GRACE_PERIOD_DAYS=7

# ⚠️ ACCEPTABLE - 14 days (lenient)
AUTH_2FA_GRACE_PERIOD_DAYS=14

# ❌ WRONG - 1 year (effectively no enforcement)
AUTH_2FA_GRACE_PERIOD_DAYS=365
```

### 4. Set Appropriate Session Timeouts

```env
# ✅ CORRECT - 24 hours (balanced)
AUTH_2FA_SESSION_TIMEOUT_HOURS=24

# ✅ CORRECT - 8 hours (high security)
AUTH_2FA_SESSION_TIMEOUT_HOURS=8

# ⚠️ ACCEPTABLE - 72 hours (lenient)
AUTH_2FA_SESSION_TIMEOUT_HOURS=72

# ❌ WRONG - 1 month (too long)
AUTH_2FA_SESSION_TIMEOUT_HOURS=720
```

## Troubleshooting

### Users Cannot Disable 2FA

**Expected behavior:** Users with required roles cannot disable 2FA once the grace period expires.

**Solution:** This is a security feature. If users need to disable 2FA:
1. Change their role to one that doesn't require 2FA, OR
2. Modify `AUTH_2FA_REQUIRED_ROLES` configuration

### 2FA Not Being Enforced

**Check:**
1. Is `AUTH_2FA_ENABLED=true`?
2. Is user's role in `AUTH_2FA_REQUIRED_ROLES`?
3. Has grace period expired?
4. Clear config cache: `php artisan config:clear`

### Configuration Changes Not Taking Effect

**Solution:**
```bash
# Clear configuration cache
php artisan config:clear

# Re-cache configuration (production only)
php artisan config:cache

# Restart queue workers
php artisan queue:restart
```

## Related Documentation

- **2FA Setup Guide:** `/docs/2FA-SETUP-GUIDE.md`
- **Security Implementation:** `/SECURITY-IMPLEMENTATION.md`
- **API Authentication:** `/docs/API-AUTHENTICATION.md`
- **Deployment Guide:** `/chom/deploy/DEPLOYMENT-GUIDE.md`

## Support

For issues or questions about 2FA configuration:
- Review error logs: `storage/logs/laravel.log`
- Check audit logs for 2FA events
- Verify configuration: `php artisan config:show auth.two_factor_authentication`

---

**Last Updated:** 2025-12-29
**Configuration Version:** 1.0.0
**Status:** Production Ready ✅
