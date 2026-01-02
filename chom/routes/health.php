<?php

use App\Http\Controllers\HealthController;
use App\Http\Controllers\MetricsController;
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

/*
|--------------------------------------------------------------------------
| Prometheus Metrics Endpoint
|--------------------------------------------------------------------------
|
| Exposes application metrics in Prometheus text exposition format.
| This endpoint is scraped by Prometheus for metrics collection.
|
| Security Note: In production, this endpoint should be:
| - Protected by IP allowlist (only Prometheus server)
| - Or use basic auth (configured via PROMETHEUS_AUTH_*)
| - Or accessed via internal network only
|
*/

Route::get('/metrics', [MetricsController::class, 'index'])
    ->name('metrics.index')
    ->middleware(config('observability.prometheus.auth.enabled', false) ? 'auth.basic' : []);

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
