<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Queue;

/**
 * Health Check Controller
 *
 * Provides health check endpoints for monitoring application status.
 * Supports liveness, readiness, and detailed health checks.
 */
class HealthCheckController extends Controller
{
    /**
     * Basic liveness check.
     *
     * Returns 200 if the application is running.
     * Used by load balancers and orchestrators.
     *
     * @return JsonResponse
     */
    public function liveness(): JsonResponse
    {
        return response()->json([
            'status' => 'ok',
            'timestamp' => now()->toIso8601String(),
        ]);
    }

    /**
     * Readiness check.
     *
     * Returns 200 if the application is ready to serve traffic.
     * Checks critical dependencies.
     *
     * @return JsonResponse
     */
    public function readiness(): JsonResponse
    {
        $checks = [];
        $healthy = true;

        // Check database
        if (config('observability.health.checks.database.enabled', true)) {
            $dbCheck = $this->checkDatabase();
            $checks['database'] = $dbCheck;
            if (!$dbCheck['healthy']) {
                $healthy = false;
            }
        }

        // Check Redis if enabled
        if (config('observability.health.checks.redis.enabled', false)) {
            $redisCheck = $this->checkRedis();
            $checks['redis'] = $redisCheck;
            if (!$redisCheck['healthy']) {
                $healthy = false;
            }
        }

        $status = $healthy ? 'ready' : 'not_ready';
        $httpStatus = $healthy ? 200 : 503;

        return response()->json([
            'status' => $status,
            'checks' => $checks,
            'timestamp' => now()->toIso8601String(),
        ], $httpStatus);
    }

    /**
     * Detailed health check.
     *
     * Returns comprehensive health information about all subsystems.
     * Should be restricted to internal networks.
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function detailed(Request $request): JsonResponse
    {
        // Check IP whitelist
        if (!$this->isAllowedIp($request->ip())) {
            return response()->json([
                'error' => 'Access denied',
            ], 403);
        }

        $checks = [];
        $healthy = true;

        // Database check
        if (config('observability.health.checks.database.enabled', true)) {
            $checks['database'] = $this->checkDatabase();
            if (!$checks['database']['healthy']) {
                $healthy = false;
            }
        }

        // Redis check
        if (config('observability.health.checks.redis.enabled', false)) {
            $checks['redis'] = $this->checkRedis();
            if (!$checks['redis']['healthy']) {
                $healthy = false;
            }
        }

        // Queue check
        if (config('observability.health.checks.queue.enabled', true)) {
            $checks['queue'] = $this->checkQueue();
            if (!$checks['queue']['healthy']) {
                $healthy = false;
            }
        }

        // Storage check
        if (config('observability.health.checks.storage.enabled', true)) {
            $checks['storage'] = $this->checkStorage();
            if (!$checks['storage']['healthy']) {
                $healthy = false;
            }
        }

        // VPS check
        if (config('observability.health.checks.vps.enabled', false)) {
            $checks['vps'] = $this->checkVpsConnectivity();
            if (!$checks['vps']['healthy']) {
                $healthy = false;
            }
        }

        // System information
        $systemInfo = $this->getSystemInfo();

        $status = $healthy ? 'healthy' : 'unhealthy';
        $httpStatus = $healthy ? 200 : 503;

        return response()->json([
            'status' => $status,
            'checks' => $checks,
            'system' => $systemInfo,
            'timestamp' => now()->toIso8601String(),
        ], $httpStatus);
    }

    /**
     * Check database connectivity and performance.
     *
     * @return array
     */
    private function checkDatabase(): array
    {
        $timeout = config('observability.health.checks.database.timeout', 5);
        $startTime = microtime(true);

        try {
            // Execute a simple query
            DB::select('SELECT 1');

            $duration = microtime(true) - $startTime;
            $durationMs = round($duration * 1000, 2);

            // Check if query is slow
            $isSlow = $durationMs > ($timeout * 1000);

            return [
                'healthy' => true,
                'duration_ms' => $durationMs,
                'connection' => config('database.default'),
                'warning' => $isSlow ? 'Database query is slow' : null,
            ];
        } catch (\Exception $e) {
            return [
                'healthy' => false,
                'error' => $e->getMessage(),
                'connection' => config('database.default'),
            ];
        }
    }

    /**
     * Check Redis connectivity.
     *
     * @return array
     */
    private function checkRedis(): array
    {
        $timeout = config('observability.health.checks.redis.timeout', 3);
        $startTime = microtime(true);

        try {
            Redis::ping();

            $duration = microtime(true) - $startTime;
            $durationMs = round($duration * 1000, 2);

            $info = Redis::info();
            $memoryUsedMb = isset($info['used_memory'])
                ? round($info['used_memory'] / 1024 / 1024, 2)
                : null;

            return [
                'healthy' => true,
                'duration_ms' => $durationMs,
                'memory_used_mb' => $memoryUsedMb,
                'connected_clients' => $info['connected_clients'] ?? null,
            ];
        } catch (\Exception $e) {
            return [
                'healthy' => false,
                'error' => $e->getMessage(),
            ];
        }
    }

    /**
     * Check queue health.
     *
     * @return array
     */
    private function checkQueue(): array
    {
        try {
            $connection = config('queue.default');
            $maxBacklog = config('observability.health.checks.queue.max_backlog', 1000);

            // Get queue size (implementation varies by driver)
            $queueSize = $this->getQueueSize($connection);

            $isBacklogged = $queueSize > $maxBacklog;

            return [
                'healthy' => !$isBacklogged,
                'connection' => $connection,
                'size' => $queueSize,
                'max_backlog' => $maxBacklog,
                'warning' => $isBacklogged ? 'Queue backlog detected' : null,
            ];
        } catch (\Exception $e) {
            return [
                'healthy' => false,
                'error' => $e->getMessage(),
            ];
        }
    }

    /**
     * Check storage health.
     *
     * @return array
     */
    private function checkStorage(): array
    {
        try {
            $storagePath = storage_path();
            $minFreePercent = config('observability.health.checks.storage.min_free_space_percent', 10);

            $totalSpace = disk_total_space($storagePath);
            $freeSpace = disk_free_space($storagePath);

            if ($totalSpace === false || $freeSpace === false) {
                throw new \RuntimeException('Unable to get disk space information');
            }

            $freePercent = ($freeSpace / $totalSpace) * 100;
            $isLow = $freePercent < $minFreePercent;

            return [
                'healthy' => !$isLow,
                'path' => $storagePath,
                'total_gb' => round($totalSpace / 1024 / 1024 / 1024, 2),
                'free_gb' => round($freeSpace / 1024 / 1024 / 1024, 2),
                'free_percent' => round($freePercent, 2),
                'min_free_percent' => $minFreePercent,
                'warning' => $isLow ? 'Low disk space' : null,
            ];
        } catch (\Exception $e) {
            return [
                'healthy' => false,
                'error' => $e->getMessage(),
            ];
        }
    }

    /**
     * Check VPS connectivity.
     *
     * @return array
     */
    private function checkVpsConnectivity(): array
    {
        try {
            $provider = config('infrastructure.vps.provider');

            if ($provider === 'local' || $provider === 'null') {
                return [
                    'healthy' => true,
                    'provider' => $provider,
                    'note' => 'Local provider - no connectivity check needed',
                ];
            }

            // In production, this would actually check VPS provider API
            return [
                'healthy' => true,
                'provider' => $provider,
                'note' => 'VPS connectivity check not implemented',
            ];
        } catch (\Exception $e) {
            return [
                'healthy' => false,
                'error' => $e->getMessage(),
            ];
        }
    }

    /**
     * Get system information.
     *
     * @return array
     */
    private function getSystemInfo(): array
    {
        return [
            'app' => [
                'name' => config('app.name'),
                'env' => config('app.env'),
                'debug' => config('app.debug'),
                'version' => config('app.version', '1.0.0'),
            ],
            'php' => [
                'version' => PHP_VERSION,
                'memory_limit' => ini_get('memory_limit'),
                'memory_usage_mb' => round(memory_get_usage(true) / 1024 / 1024, 2),
                'memory_peak_mb' => round(memory_get_peak_usage(true) / 1024 / 1024, 2),
            ],
            'laravel' => [
                'version' => app()->version(),
            ],
            'uptime' => $this->getUptime(),
        ];
    }

    /**
     * Get application uptime.
     *
     * @return array
     */
    private function getUptime(): array
    {
        // In production, this would track actual application start time
        // For now, we'll return a simple uptime
        $uptimeFile = storage_path('framework/uptime');

        if (!file_exists($uptimeFile)) {
            file_put_contents($uptimeFile, (string)time());
        }

        $startTime = (int)file_get_contents($uptimeFile);
        $uptime = time() - $startTime;

        return [
            'seconds' => $uptime,
            'human' => $this->formatUptime($uptime),
        ];
    }

    /**
     * Format uptime in human-readable format.
     *
     * @param int $seconds
     * @return string
     */
    private function formatUptime(int $seconds): string
    {
        $days = floor($seconds / 86400);
        $hours = floor(($seconds % 86400) / 3600);
        $minutes = floor(($seconds % 3600) / 60);

        return sprintf('%dd %dh %dm', $days, $hours, $minutes);
    }

    /**
     * Get queue size for a given connection.
     *
     * @param string $connection
     * @return int
     */
    private function getQueueSize(string $connection): int
    {
        try {
            $driver = config("queue.connections.{$connection}.driver");

            if ($driver === 'redis') {
                // Get Redis queue size
                $queue = config("queue.connections.{$connection}.queue", 'default');
                return (int)Redis::llen("queues:{$queue}");
            }

            if ($driver === 'database') {
                // Get database queue size
                return DB::table('jobs')->count();
            }

            return 0;
        } catch (\Exception $e) {
            \Log::warning('Failed to get queue size', ['error' => $e->getMessage()]);
            return 0;
        }
    }

    /**
     * Check if IP is allowed to access detailed health check.
     *
     * @param string $ip
     * @return bool
     */
    private function isAllowedIp(string $ip): bool
    {
        $whitelist = config('observability.health.detailed_ip_whitelist', ['127.0.0.1', '::1']);

        if (empty($whitelist)) {
            return true; // No whitelist configured, allow all
        }

        return in_array($ip, $whitelist);
    }
}
