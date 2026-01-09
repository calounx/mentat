<?php

declare(strict_types=1);

use App\Http\Controllers\Api\V1\SiteController;
use App\Http\Controllers\Api\V1\VpsManagerController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
|
| API routes for CHOM application.
| All routes are prefixed with /api and use Sanctum authentication.
|
*/

// V1 API Routes
Route::prefix('v1')->group(function () {
    // Site tenant mappings endpoint - Owner only
    // Used by observability exporters to get site→tenant mappings for labeling
    Route::middleware(['auth:sanctum'])
        ->get('/sites/tenant-mappings', [SiteController::class, 'tenantMappings'])
        ->name('api.v1.sites.tenant-mappings');

    // VPSManager Operations - Requires authentication
    Route::middleware(['auth:sanctum'])->group(function () {
        // SSL Management
        Route::post('/sites/{site}/ssl/issue', [VpsManagerController::class, 'issueSSL'])
            ->name('api.v1.sites.ssl.issue');
        Route::post('/sites/{site}/ssl/renew', [VpsManagerController::class, 'renewSSL'])
            ->name('api.v1.sites.ssl.renew');
        Route::get('/sites/{site}/ssl/status', [VpsManagerController::class, 'getSSLStatus'])
            ->name('api.v1.sites.ssl.status');

        // Database Management
        Route::post('/sites/{site}/database/export', [VpsManagerController::class, 'exportDatabase'])
            ->name('api.v1.sites.database.export');
        Route::post('/sites/{site}/database/optimize', [VpsManagerController::class, 'optimizeDatabase'])
            ->name('api.v1.sites.database.optimize');

        // Cache Management
        Route::post('/sites/{site}/cache/clear', [VpsManagerController::class, 'clearCache'])
            ->name('api.v1.sites.cache.clear');

        // VPS Monitoring
        Route::get('/vps/{vps}/health', [VpsManagerController::class, 'getVpsHealth'])
            ->name('api.v1.vps.health');
        Route::get('/vps/{vps}/stats', [VpsManagerController::class, 'getVpsStats'])
            ->name('api.v1.vps.stats');
    });
});
