# Two-Factor Authentication API Documentation

## Overview

The CHOM application now provides comprehensive Two-Factor Authentication (2FA) API endpoints through the `TwoFactorAuthenticationController`. This implementation follows OWASP security best practices and integrates seamlessly with the existing User model.

## Architecture

### Components Created

1. **Controller**: `/app/Http/Controllers/Api/V1/TwoFactorAuthenticationController.php`
2. **Form Requests**:
   - `/app/Http/Requests/V1/TwoFactor/ConfirmTwoFactorRequest.php`
   - `/app/Http/Requests/V1/TwoFactor/DisableTwoFactorRequest.php`
3. **User Model Methods** (added to existing `/app/Models/User.php`):
   - `enableTwoFactorAuthentication()`
   - `confirmTwoFactorAuthentication()`
   - `disableTwoFactorAuthentication()`
   - `generateRecoveryCodes()`
   - `verifyTwoFactorCode()`

## API Endpoints

All endpoints require authentication via `auth:sanctum` middleware and are rate-limited.

### 1. Enable 2FA

**Endpoint**: `POST /api/v1/auth/2fa/enable`

**Description**: Generates a new 2FA secret, QR code, and recovery codes. Does not enable 2FA until confirmed.

**Authentication**: Required

**Request**:
```bash
curl -X POST https://your-app.com/api/v1/auth/2fa/enable \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Accept: application/json"
```

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Two-factor authentication has been initialized. Please scan the QR code and verify with a code.",
  "data": {
    "qr_code": "<svg>...</svg>",
    "secret": "BASE32ENCODEDSECRET",
    "recovery_codes": [
      "ABCD123456",
      "EFGH789012",
      "IJKL345678",
      "MNOP901234",
      "QRST567890",
      "UVWX123456",
      "YZAB789012",
      "CDEF345678"
    ],
    "manual_entry_key": "BASE 32EN CODE DSEC RET",
    "next_step": "Scan QR code with authenticator app and call /confirm endpoint"
  }
}
```

**Error Responses**:
- `403 Forbidden`: Password confirmation required (if 2FA already enabled)
- `500 Internal Server Error`: Failed to enable 2FA

---

### 2. Confirm 2FA Setup

**Endpoint**: `POST /api/v1/auth/2fa/confirm`

**Description**: Verifies the TOTP code from authenticator app and enables 2FA.

**Authentication**: Required

**Request**:
```bash
curl -X POST https://your-app.com/api/v1/auth/2fa/confirm \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{
    "code": "123456"
  }'
```

**Validation Rules**:
- `code`: required, string, exactly 6 digits, numeric only

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Two-factor authentication has been enabled successfully.",
  "data": {
    "enabled": true,
    "confirmed_at": "2026-01-02T12:00:00Z",
    "recovery_codes_remaining": 8
  }
}
```

**Error Responses**:
- `400 Bad Request`: 2FA not initialized or already enabled
- `422 Unprocessable Entity`: Invalid verification code

---

### 3. Verify 2FA Code

**Endpoint**: `POST /api/v1/auth/2fa/verify`

**Description**: Verifies a TOTP code (6 digits) or recovery code (10 characters) during login or session validation.

**Authentication**: Required

**Request** (TOTP):
```bash
curl -X POST https://your-app.com/api/v1/auth/2fa/verify \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{
    "code": "123456"
  }'
```

**Request** (Recovery Code):
```bash
curl -X POST https://your-app.com/api/v1/auth/2fa/verify \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{
    "code": "ABCD123456"
  }'
```

**Validation Rules**:
- `code`: required, string, 6-10 characters

**Response** (200 OK - TOTP):
```json
{
  "success": true,
  "message": "Two-factor authentication verified successfully.",
  "data": {
    "verified_at": "2026-01-02T12:00:00Z",
    "method": "totp"
  }
}
```

**Response** (200 OK - Recovery Code with Warning):
```json
{
  "success": true,
  "message": "Two-factor authentication verified successfully.",
  "data": {
    "verified_at": "2026-01-02T12:00:00Z",
    "method": "recovery",
    "recovery_codes_remaining": 2,
    "warning": "You have only 2 recovery codes remaining. Consider regenerating them."
  }
}
```

**Error Responses**:
- `400 Bad Request`: 2FA not enabled
- `422 Unprocessable Entity`: Invalid or already-used code

---

### 4. Get Recovery Codes Status

**Endpoint**: `GET /api/v1/auth/2fa/recovery-codes`

**Description**: Returns the count of remaining recovery codes. Requires password confirmation.

**Authentication**: Required

**Request**:
```bash
curl -X GET https://your-app.com/api/v1/auth/2fa/recovery-codes \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Accept: application/json"
```

**Response** (200 OK):
```json
{
  "success": true,
  "data": {
    "recovery_codes_remaining": 5,
    "warning": null,
    "note": "Recovery codes are hashed and cannot be retrieved. Use /regenerate endpoint to create new codes."
  }
}
```

**Response** (Low Codes):
```json
{
  "success": true,
  "data": {
    "recovery_codes_remaining": 2,
    "warning": "You have only 2 recovery codes remaining. Consider regenerating them.",
    "note": "Recovery codes are hashed and cannot be retrieved. Use /regenerate endpoint to create new codes."
  }
}
```

**Error Responses**:
- `400 Bad Request`: 2FA not enabled
- `403 Forbidden`: Password confirmation required

---

### 5. Regenerate Recovery Codes

**Endpoint**: `POST /api/v1/auth/2fa/regenerate-recovery-codes`

**Description**: Generates new recovery codes and invalidates all existing ones. Requires password confirmation.

**Authentication**: Required

**Request**:
```bash
curl -X POST https://your-app.com/api/v1/auth/2fa/regenerate-recovery-codes \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Accept: application/json"
```

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Recovery codes have been regenerated successfully.",
  "data": {
    "recovery_codes": [
      "NEWCODE001",
      "NEWCODE002",
      "NEWCODE003",
      "NEWCODE004",
      "NEWCODE005",
      "NEWCODE006",
      "NEWCODE007",
      "NEWCODE008"
    ],
    "warning": "Previous recovery codes are now invalid. Store these codes securely - they will not be shown again."
  }
}
```

**Error Responses**:
- `400 Bad Request`: 2FA not enabled
- `403 Forbidden`: Password confirmation required

---

### 6. Disable 2FA

**Endpoint**: `POST /api/v1/auth/2fa/disable`

**Description**: Disables 2FA and clears all secrets and recovery codes. Requires password confirmation.

**Authentication**: Required

**Request**:
```bash
curl -X POST https://your-app.com/api/v1/auth/2fa/disable \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{
    "password": "your-password"
  }'
```

**Validation Rules**:
- `password`: required, string, must match user's current password

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Two-factor authentication has been disabled successfully.",
  "data": {
    "enabled": false
  }
}
```

**Error Responses**:
- `400 Bad Request`: 2FA not enabled
- `403 Forbidden`: 2FA required for role (cannot disable)
- `422 Unprocessable Entity`: Incorrect password

---

## Security Features

### 1. Encryption & Hashing
- **TOTP Secrets**: Encrypted at rest using AES-256-CBC via Laravel's encrypted cast
- **Recovery Codes**: One-way hashed using bcrypt before storage
- **QR Codes**: Generated on-demand, never stored

### 2. Step-Up Authentication
- Sensitive operations (disable, regenerate codes) require password confirmation
- Password confirmation valid for 10 minutes (configured in User model)

### 3. Rate Limiting
- All 2FA endpoints use the `throttle:2fa` middleware (5 requests/minute)
- Prevents brute force attacks on verification codes

### 4. Audit Logging
All 2FA operations are logged via `AuditLog`:
- `user.2fa_enable_initiated`
- `user.2fa_enabled`
- `user.2fa_confirm_failed`
- `user.2fa_verified`
- `user.2fa_verification_failed`
- `user.2fa_recovery_codes_regenerated`
- `user.2fa_recovery_codes_low`
- `user.2fa_disabled`

### 5. Recovery Code Management
- 8 recovery codes generated by default
- Single-use only (removed after use)
- Warning when 2 or fewer codes remain
- Automatic audit log when running low

### 6. Role-Based Requirements
- Users with certain roles (owner, admin) may have 2FA enforced
- Grace period of 7 days for new accounts
- Cannot disable 2FA if required for role

---

## User Model Methods

### enableTwoFactorAuthentication()

Generates 2FA secret, QR code, and recovery codes.

```php
$data = $user->enableTwoFactorAuthentication();
// Returns: ['secret' => '...', 'qr_code' => '<svg>...', 'recovery_codes' => [...]]
```

### confirmTwoFactorAuthentication()

Marks 2FA as enabled and confirmed.

```php
$user->confirmTwoFactorAuthentication();
```

### disableTwoFactorAuthentication()

Disables 2FA and clears all related data.

```php
$user->disableTwoFactorAuthentication();
```

### generateRecoveryCodes($count = 8)

Generates new recovery codes (returns plain text, stores hashed).

```php
$codes = $user->generateRecoveryCodes();
// Returns: ['ABCD123456', 'EFGH789012', ...]
```

### verifyTwoFactorCode($code)

Verifies a TOTP or recovery code.

```php
$valid = $user->verifyTwoFactorCode('123456');
// Returns: true/false
```

---

## Integration with Routes

These endpoints should be added to `/routes/api.php`:

```php
Route::middleware(['auth:sanctum', 'throttle:2fa'])->prefix('auth/2fa')->group(function () {
    Route::post('/enable', [TwoFactorAuthenticationController::class, 'enable']);
    Route::post('/confirm', [TwoFactorAuthenticationController::class, 'confirm']);
    Route::post('/verify', [TwoFactorAuthenticationController::class, 'verify']);
    Route::get('/recovery-codes', [TwoFactorAuthenticationController::class, 'recoveryCodes']);
    Route::post('/regenerate-recovery-codes', [TwoFactorAuthenticationController::class, 'regenerateRecoveryCodes']);
    Route::post('/disable', [TwoFactorAuthenticationController::class, 'disable']);
});
```

**Note**: Routes for the existing `TwoFactorController` already exist. You may want to either:
1. Replace those routes with these new ones
2. Use different route paths (e.g., `/auth/2fa-v2/...`)
3. Keep both implementations for backward compatibility

---

## Testing the Implementation

### 1. Enable 2FA
```bash
# Step 1: Initialize 2FA
curl -X POST http://localhost/api/v1/auth/2fa/enable \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Accept: application/json"

# Save the QR code and scan it with Google Authenticator
```

### 2. Confirm 2FA
```bash
# Step 2: Verify with code from authenticator app
curl -X POST http://localhost/api/v1/auth/2fa/confirm \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"code": "123456"}'
```

### 3. Verify During Login
```bash
# Step 3: Test verification
curl -X POST http://localhost/api/v1/auth/2fa/verify \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"code": "123456"}'
```

### 4. Disable 2FA
```bash
# Step 4: Disable (requires password)
curl -X POST http://localhost/api/v1/auth/2fa/disable \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"password": "your-password"}'
```

---

## Dependencies

This implementation requires the following packages (already included based on existing `TwoFactorController`):

- `pragmarx/google2fa`: TOTP generation and verification
- `bacon/bacon-qr-code`: QR code generation

If not installed, add them via Composer:

```bash
composer require pragmarx/google2fa bacon/bacon-qr-code
```

---

## Comparison with Existing TwoFactorController

| Feature | TwoFactorController | TwoFactorAuthenticationController |
|---------|---------------------|-----------------------------------|
| Setup Method | `setup()` (session-based) | `enable()` (database-based) |
| Confirmation | `confirm()` | `confirm()` |
| Verification | `verify()` | `verify()` |
| Recovery Codes | `regenerateBackupCodes()` | `regenerateRecoveryCodes()` + `recoveryCodes()` |
| Disable | `disable()` | `disable()` |
| Status | `status()` | Not included |
| Form Requests | No | Yes (dedicated validation classes) |
| Secret Storage | Session then DB | Immediately to DB |

**Recommendation**: Choose one implementation based on your needs:
- **TwoFactorController**: Session-based setup, includes status endpoint
- **TwoFactorAuthenticationController**: Database-first approach, stronger form validation

---

## OWASP Compliance

This implementation addresses:

- **A07:2021 – Identification and Authentication Failures**
  - Multi-factor authentication
  - Strong TOTP implementation
  - Recovery code management

- **A02:2021 – Cryptographic Failures**
  - Encrypted secret storage
  - Hashed recovery codes
  - Secure random generation

- **A09:2021 – Security Logging and Monitoring Failures**
  - Comprehensive audit logging
  - Failed attempt tracking
  - Low recovery code warnings

---

## Files Created

1. `/app/Http/Controllers/Api/V1/TwoFactorAuthenticationController.php` (17KB)
2. `/app/Http/Requests/V1/TwoFactor/ConfirmTwoFactorRequest.php` (1.6KB)
3. `/app/Http/Requests/V1/TwoFactor/DisableTwoFactorRequest.php` (2.1KB)
4. **Modified**: `/app/Models/User.php` (added 6 new methods)

---

## Next Steps

1. **Add Routes**: Update `/routes/api.php` with the new endpoints
2. **Testing**: Create PHPUnit tests for all endpoints
3. **Frontend Integration**: Build UI components for 2FA management
4. **Documentation**: Add to API documentation and user guides
5. **Migration**: If replacing `TwoFactorController`, create migration plan

---

## Support

For issues or questions:
- Review the comprehensive inline documentation in each file
- Check audit logs for debugging (`AuditLog` model)
- Refer to OWASP guidelines for 2FA best practices
