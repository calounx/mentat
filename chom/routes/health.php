<?php

declare(strict_types=1);

use App\Http\Controllers\HealthCheckController;
use App\Http\Controllers\MetricsController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Health Check and Observability Routes
|--------------------------------------------------------------------------
|
| These routes provide health check endpoints and metrics for monitoring.
| They should be accessible without authentication for external monitoring.
|
*/

// Health check endpoints
Route::get(
    config('observability.health.endpoints.liveness', '/health'),
    [HealthCheckController::class, 'liveness']
)->name('health.liveness');

Route::get(
    config('observability.health.endpoints.readiness', '/health/ready'),
    [HealthCheckController::class, 'readiness']
)->name('health.readiness');

Route::get(
    config('observability.health.endpoints.detailed', '/health/detailed'),
    [HealthCheckController::class, 'detailed']
)->name('health.detailed');

// Metrics endpoint
Route::get(
    config('observability.metrics.endpoint.path', '/metrics'),
    [MetricsController::class, 'index']
)->name('metrics.index');
