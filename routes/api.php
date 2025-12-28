<?php

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\BackupController;
use App\Http\Controllers\Api\V1\SiteController;
use App\Http\Controllers\Api\V1\TeamController;
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
        Route::post('/register', [AuthController::class, 'register']);
        Route::post('/login', [AuthController::class, 'login']);
    });

    // Health check (no rate limiting for monitoring)
    Route::get('/health', function () {
        return response()->json([
            'status' => 'ok',
            'timestamp' => now()->toIso8601String(),
        ]);
    });

    // =========================================================================
    // PROTECTED ROUTES (Require Authentication + Rate Limiting)
    // =========================================================================

    Route::middleware(['auth:sanctum', 'throttle:api'])->group(function () {

        // Auth (protected endpoints)
        Route::prefix('auth')->group(function () {
            Route::post('/logout', [AuthController::class, 'logout']);
            Route::get('/me', [AuthController::class, 'me']);
            Route::post('/refresh', [AuthController::class, 'refresh']);
        });

        // Sites
        Route::prefix('sites')->group(function () {
            Route::get('/', [SiteController::class, 'index']);
            Route::post('/', [SiteController::class, 'store']);
            Route::get('/{id}', [SiteController::class, 'show']);
            Route::patch('/{id}', [SiteController::class, 'update']);

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
            Route::get('/members', [TeamController::class, 'index']);

            // Invite a new team member
            Route::post('/invitations', [TeamController::class, 'invite']);

            // List pending invitations
            Route::get('/invitations', [TeamController::class, 'invitations']);

            // Cancel/revoke an invitation
            Route::delete('/invitations/{id}', [TeamController::class, 'cancelInvitation']);

            // Get specific team member details
            Route::get('/members/{id}', [TeamController::class, 'show']);

            // Update team member role
            Route::patch('/members/{id}', [TeamController::class, 'update']);

            // Remove team member (sensitive operation)
            Route::delete('/members/{id}', [TeamController::class, 'destroy'])
                ->middleware('throttle:sensitive');

            // Transfer ownership (highly sensitive)
            Route::post('/transfer-ownership', [TeamController::class, 'transferOwnership'])
                ->middleware('throttle:sensitive');
        });

        // =====================================================================
        // ORGANIZATION SETTINGS
        // =====================================================================
        Route::prefix('organization')->group(function () {
            Route::get('/', [TeamController::class, 'organization']);
            Route::patch('/', [TeamController::class, 'updateOrganization']);
        });

        // TODO: Add more routes as controllers are created
        // - /tenants
        // - /databases
        // - /observability
        // - /billing
    });
});
