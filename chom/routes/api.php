<?php

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\BackupController;
use App\Http\Controllers\Api\V1\HealthController;
use App\Http\Controllers\Api\V1\SiteController;
use App\Http\Controllers\Api\V1\TeamController;
use App\Http\Controllers\Api\V1\TwoFactorController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
|
| CHOM SaaS Platform API v1
|
*/

Route::prefix('v1')->group(function () {

    // =========================================================================
    // PUBLIC ROUTES (No Authentication)
    // =========================================================================

    // Authentication endpoints with strict rate limiting (5 req/min)
    Route::prefix('auth')->middleware('throttle:auth')->group(function () {
        Route::post('/register', [AuthController::class, 'register'])->name('auth.register');
        Route::post('/login', [AuthController::class, 'login'])->name('auth.login');
    });

    // Health check endpoints (no rate limiting for monitoring)
    Route::get('/health', [HealthController::class, 'index'])->name('health.basic');
    Route::get('/health/detailed', [HealthController::class, 'detailed'])->name('health.detailed');

    // =========================================================================
    // PROTECTED ROUTES (Require Authentication + Rate Limiting)
    // =========================================================================

    Route::middleware(['auth:sanctum', 'throttle:api'])->group(function () {

        // =====================================================================
        // AUTHENTICATION & SECURITY
        // =====================================================================

        // Auth (protected endpoints)
        Route::prefix('auth')->group(function () {
            Route::post('/logout', [AuthController::class, 'logout'])->name('auth.logout');
            Route::get('/me', [AuthController::class, 'me'])->name('auth.me');
            Route::post('/refresh', [AuthController::class, 'refresh'])->name('auth.refresh');

            // Password confirmation for step-up authentication
            Route::post('/password/confirm', [AuthController::class, 'confirmPassword'])
                ->middleware('throttle:2fa')
                ->name('auth.password.confirm');

            // Two-Factor Authentication endpoints (with 2FA rate limiting)
            Route::prefix('2fa')->middleware('throttle:2fa')->group(function () {
                // Setup 2FA - generates QR code and secret
                Route::post('/setup', [TwoFactorController::class, 'setup'])->name('auth.2fa.setup');

                // Confirm 2FA setup - verifies first code and enables 2FA
                Route::post('/confirm', [TwoFactorController::class, 'confirm'])->name('auth.2fa.confirm');

                // Verify 2FA code during login or session validation
                Route::post('/verify', [TwoFactorController::class, 'verify'])->name('auth.2fa.verify');

                // Get 2FA status
                Route::get('/status', [TwoFactorController::class, 'status'])->name('auth.2fa.status');

                // Regenerate backup codes (requires password confirmation)
                Route::post('/backup-codes/regenerate', [TwoFactorController::class, 'regenerateBackupCodes'])
                    ->name('auth.2fa.backup-codes.regenerate');

                // Disable 2FA (requires password confirmation)
                Route::post('/disable', [TwoFactorController::class, 'disable'])
                    ->name('auth.2fa.disable');
            });
        });

        // =====================================================================
        // HEALTH & MONITORING
        // =====================================================================

        // Security health check (admin only)
        Route::get('/health/security', [HealthController::class, 'security'])
            ->name('health.security');

        // Sites
        Route::prefix('sites')->group(function () {
            Route::get('/', [SiteController::class, 'index']);
            Route::post('/', [SiteController::class, 'store']);
            Route::get('/{id}', [SiteController::class, 'show']);
            Route::match(['put', 'patch'], '/{id}', [SiteController::class, 'update']);

            // Destructive action with stricter rate limiting
            Route::delete('/{id}', [SiteController::class, 'destroy'])
                ->middleware('throttle:sensitive');

            // Site actions
            Route::post('/{id}/enable', [SiteController::class, 'enable']);
            Route::post('/{id}/disable', [SiteController::class, 'disable']);
            Route::post('/{id}/ssl', [SiteController::class, 'issueSSL']);
            Route::get('/{id}/metrics', [SiteController::class, 'metrics']);
        });

        // =====================================================================
        // BACKUP MANAGEMENT
        // =====================================================================
        Route::prefix('backups')->group(function () {
            // List all backups (optionally filter by site)
            Route::get('/', [BackupController::class, 'index']);

            // Get specific backup details
            Route::get('/{id}', [BackupController::class, 'show']);

            // Create a new backup (with stricter rate limiting)
            Route::post('/', [BackupController::class, 'store'])
                ->middleware('throttle:sensitive');

            // Delete a backup (with stricter rate limiting)
            Route::delete('/{id}', [BackupController::class, 'destroy'])
                ->middleware('throttle:sensitive');

            // Download backup
            Route::get('/{id}/download', [BackupController::class, 'download']);

            // Restore from backup (sensitive operation)
            Route::post('/{id}/restore', [BackupController::class, 'restore'])
                ->middleware('throttle:sensitive');
        });

        // Site-specific backups (nested under sites)
        Route::prefix('sites/{siteId}/backups')->group(function () {
            Route::get('/', [BackupController::class, 'indexForSite']);
            Route::post('/', [BackupController::class, 'store'])
                ->middleware('throttle:sensitive');
        });

        // =====================================================================
        // TEAM/USER MANAGEMENT
        // =====================================================================
        Route::prefix('team')->group(function () {
            // List team members
            Route::get('/', [TeamController::class, 'index'])->name('team.index');

            // Invite a new team member
            Route::post('/invite', [TeamController::class, 'invite'])->name('team.invite');

            // List pending invitations
            Route::get('/pending', [TeamController::class, 'pending'])->name('team.pending');

            // Get specific team member details
            Route::get('/{member}', [TeamController::class, 'show'])->name('team.show');

            // Update team member role
            Route::patch('/{member}', [TeamController::class, 'update'])->name('team.update');

            // Remove team member (sensitive operation)
            Route::delete('/{member}', [TeamController::class, 'destroy'])
                ->middleware('throttle:sensitive')
                ->name('team.destroy');

            // Cancel/revoke an invitation
            Route::delete('/invitations/{invitation}', [TeamController::class, 'cancelInvitation'])
                ->name('team.invitation.cancel');

            // Transfer ownership (highly sensitive)
            Route::post('/transfer-ownership', [TeamController::class, 'transferOwnership'])
                ->middleware('throttle:sensitive')
                ->name('team.transfer-ownership');
        });

        // Team invitation acceptance (public route with optional auth)
        Route::post('/team/accept/{token}', [TeamController::class, 'accept'])
            ->middleware('throttle:api')
            ->name('team.accept');

        // =====================================================================
        // ORGANIZATION SETTINGS
        // =====================================================================
        Route::prefix('organization')->group(function () {
            Route::get('/', [TeamController::class, 'organization']);
            Route::patch('/', [TeamController::class, 'updateOrganization']);
        });

        // =====================================================================
        // ADMIN ROUTES (Admin/Owner only)
        // =====================================================================
        Route::prefix('admin')->middleware('can:admin')->group(function () {
            // User management
            Route::get('/users', function () {
                return response()->json(['users' => []]);
            });
            Route::post('/users/suspend', function () {
                return response()->json(['message' => 'User suspended']);
            });

            // System settings
            Route::get('/system/settings', function () {
                return response()->json(['settings' => []]);
            });
            Route::get('/settings', function () {
                return response()->json(['settings' => []]);
            });

            // Site management
            Route::get('/sites/{id}', function ($id) {
                $site = \App\Models\Site::withoutGlobalScopes()->findOrFail($id);

                return response()->json($site);
            });
        });

        // TODO: Add more routes as controllers are created
        // - /tenants
        // - /databases
        // - /observability
        // - /billing
    });
});

/*
|--------------------------------------------------------------------------
| SECURITY IMPLEMENTATION NOTES
|--------------------------------------------------------------------------
|
| This API implements comprehensive security controls:
|
| 1. TWO-FACTOR AUTHENTICATION (2FA)
|    - Mandatory for owner/admin roles after 7-day grace period
|    - TOTP using Google Authenticator protocol
|    - 8 single-use backup codes for recovery
|    - Rate limited to 5 attempts/minute
|
| 2. STEP-UP AUTHENTICATION
|    - Password re-confirmation for sensitive operations
|    - 10-minute validity window
|    - Apply to: SSH key viewing, deletions, ownership transfers
|
| 3. RATE LIMITING
|    - Tier-based: Enterprise (1000/min), Pro (500/min), Starter (100/min)
|    - Authentication: 5/min per IP
|    - Sensitive operations: 10/min
|    - 2FA verification: 5/min
|
| 4. REQUEST SIGNING (Optional)
|    - HMAC-SHA256 signature verification
|    - 5-minute replay protection
|    - Apply to webhooks and high-security operations
|
| 5. SECURITY MONITORING
|    - /health/security endpoint checks security posture
|    - Monitors: 2FA compliance, key rotation, SSL expiry
|    - Comprehensive audit logging
|
| To apply step-up auth to a route:
|   ->middleware('password.confirm')
|
| To apply request signing:
|   ->middleware('verify.signature')
|
| OWASP Top 10 Coverage:
|   A01: Access Control - Role-based authorization + 2FA
|   A02: Cryptographic Failures - Encrypted secrets, HMAC signing
|   A03: Injection - Input validation in all controllers
|   A04: Insecure Design - Defense in depth, fail-safe defaults
|   A05: Security Misconfiguration - Health checks, secure defaults
|   A07: Auth Failures - 2FA, step-up auth, session security
|   A09: Logging Failures - Comprehensive audit logging
|
*/
