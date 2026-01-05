<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;

/**
 * HealthController
 *
 * Provides health check endpoints for load balancers and monitoring systems.
 * These endpoints are PUBLIC and do not require authentication.
 */
class HealthController extends Controller
{
    /**
     * Liveness probe - Basic check that the application is running.
     *
     * Use this for Kubernetes liveness probes or basic uptime monitoring.
     * Returns 200 if the PHP process is alive and can respond.
     *
     * GET /api/v1/health/liveness
     */
    public function liveness(): JsonResponse
    {
        return response()->json([
            'status' => 'ok',
        ]);
    }

    /**
     * Readiness probe - Check if the application is ready to accept traffic.
     *
     * Verifies all critical dependencies (database, cache) are accessible.
     * Returns 503 if any dependency is unhealthy.
     *
     * GET /api/v1/health/readiness
     */
    public function readiness(): JsonResponse
    {
        $checks = [
            'database' => $this->checkDatabase(),
            'cache' => $this->checkCache(),
        ];

        $allHealthy = collect($checks)->every(fn($check) => $check['healthy']);

        return response()->json([
            'status' => $allHealthy ? 'ready' : 'not_ready',
            'checks' => $checks,
            'timestamp' => now()->toIso8601String(),
        ], $allHealthy ? 200 : 503);
    }

    /**
     * Combined health endpoint - Overall application health status.
     *
     * Returns comprehensive health information including app version,
     * environment, and status of all dependencies.
     *
     * GET /api/v1/health
     */
    public function index(): JsonResponse
    {
        $databaseCheck = $this->checkDatabase();
        $cacheCheck = $this->checkCache();

        $allHealthy = $databaseCheck['healthy'] && $cacheCheck['healthy'];

        return response()->json([
            'success' => true,
            'data' => [
                'status' => $allHealthy ? 'healthy' : 'degraded',
                'app' => [
                    'name' => config('app.name'),
                    'version' => config('app.version', '1.0.0'),
                    'environment' => config('app.env'),
                ],
                'checks' => [
                    'database' => $databaseCheck,
                    'cache' => $cacheCheck,
                ],
                'timestamp' => now()->toIso8601String(),
            ],
        ], $allHealthy ? 200 : 503);
    }

    /**
     * Check database connectivity.
     */
    private function checkDatabase(): array
    {
        try {
            DB::connection()->getPdo();

            // Run a simple query to verify the connection is functional
            DB::select('SELECT 1');

            return [
                'healthy' => true,
                'message' => 'Database connection successful',
            ];
        } catch (\Exception $e) {
            return [
                'healthy' => false,
                'message' => 'Database connection failed',
                'error' => config('app.debug') ? $e->getMessage() : 'Connection error',
            ];
        }
    }

    /**
     * Check cache/Redis connectivity.
     *
     * If Redis is not configured or available, falls back to checking
     * the default cache driver.
     */
    private function checkCache(): array
    {
        try {
            $testKey = 'health_check_' . uniqid();
            $testValue = 'test_' . time();

            // Test write
            Cache::put($testKey, $testValue, 10);

            // Test read
            $retrieved = Cache::get($testKey);

            // Clean up
            Cache::forget($testKey);

            if ($retrieved === $testValue) {
                return [
                    'healthy' => true,
                    'message' => 'Cache system operational',
                    'driver' => config('cache.default'),
                ];
            }

            return [
                'healthy' => false,
                'message' => 'Cache read/write verification failed',
                'driver' => config('cache.default'),
            ];
        } catch (\Exception $e) {
            return [
                'healthy' => false,
                'message' => 'Cache system error',
                'driver' => config('cache.default'),
                'error' => config('app.debug') ? $e->getMessage() : 'Connection error',
            ];
        }
    }
}
