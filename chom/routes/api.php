<?php

declare(strict_types=1);

use App\Http\Controllers\Api\V1\SiteController;
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
});
