# Identity & Access Module

## Overview

The Identity & Access module is a bounded context within the CHOM application responsible for all authentication and authorization operations. This module provides secure user authentication, two-factor authentication (2FA), password management, and session control.

## Responsibilities

- User authentication (login/logout)
- Two-factor authentication (2FA)
- Password management and reset
- Session management and security
- Authentication event tracking

## Architecture

### Service Contracts

- `AuthenticationInterface` - Core authentication operations
- `TwoFactorInterface` - Two-factor authentication operations

### Services

- `AuthenticationService` - Implements core authentication logic
- `TwoFactorService` - Implements 2FA operations

### Events

- `UserAuthenticated` - Dispatched when user logs in
- `UserLoggedOut` - Dispatched when user logs out
- `TwoFactorEnabled` - Dispatched when 2FA is enabled
- `TwoFactorDisabled` - Dispatched when 2FA is disabled

### Value Objects

- `TwoFactorSecret` - Encapsulates 2FA secret data

## Usage Examples

### Authentication

```php
use App\Modules\Auth\Contracts\AuthenticationInterface;

$authService = app(AuthenticationInterface::class);

// Authenticate user
$user = $authService->authenticate([
    'email' => 'user@example.com',
    'password' => 'secret'
], remember: true);

// Logout
$authService->logout($userId);

// Verify credentials
$valid = $authService->verifyCredentials($credentials);
```

### Two-Factor Authentication

```php
use App\Modules\Auth\Contracts\TwoFactorInterface;

$twoFactorService = app(TwoFactorInterface::class);

// Enable 2FA
$result = $twoFactorService->enable($userId);
// Returns: ['secret' => '...', 'qr_code_url' => '...', 'recovery_codes' => [...]]

// Verify 2FA code
$valid = $twoFactorService->verify($userId, $code);

// Disable 2FA
$twoFactorService->disable($userId, $password);
```

## Module Dependencies

This module has minimal external dependencies and can operate independently:

- Laravel Auth facade
- Laravel Hashing
- Google2FA package (for 2FA operations)

## Security Considerations

1. All passwords are hashed using bcrypt
2. 2FA secrets are encrypted before storage
3. Recovery codes are encrypted and invalidated after use
4. Session regeneration on login/logout
5. All authentication attempts are logged

## Testing

Test the module using:

```bash
php artisan test --filter=Auth
```

## Future Enhancements

- OAuth2 provider integration
- Biometric authentication support
- Risk-based authentication
- Device fingerprinting
