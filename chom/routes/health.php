<?php

use App\Http\Controllers\HealthController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Health Check Routes
|--------------------------------------------------------------------------
|
| These routes are used by load balancers, orchestrators, and monitoring
| systems to check the health status of the application.
|
| These routes should NOT require authentication or CSRF protection.
|
*/

Route::get('/health', [HealthController::class, 'index'])
    ->name('health.index');

Route::get('/health/ready', [HealthController::class, 'ready'])
    ->name('health.ready');

Route::get('/health/live', [HealthController::class, 'live'])
    ->name('health.live');

Route::get('/health/security', [HealthController::class, 'security'])
    ->name('health.security');

Route::get('/health/dependencies', [HealthController::class, 'dependencies'])
    ->name('health.dependencies');

Route::get('/health/detailed', [HealthController::class, 'detailed'])
    ->name('health.detailed');
