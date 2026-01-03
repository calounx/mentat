<?php

declare(strict_types=1);

namespace App\Modules\Infrastructure\Services;

use App\Modules\Infrastructure\Contracts\ObservabilityInterface;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Observability Service
 *
 * Handles monitoring, logging, metrics, and system health checks.
 */
class ObservabilityService implements ObservabilityInterface
{
    /**
     * Record a metric.
     *
     * @param string $name Metric name
     * @param float $value Metric value
     * @param array $tags Metric tags
     * @return bool Success status
     */
    public function recordMetric(string $name, float $value, array $tags = []): bool
    {
        try {
            Log::debug('Metric recorded', [
                'name' => $name,
                'value' => $value,
                'tags' => $tags,
            ]);

            // Store in cache for aggregation
            $key = "metrics:{$name}:" . md5(json_encode($tags));
            Cache::put($key, $value, now()->addHours(24));

            return true;
        } catch (\Exception $e) {
            Log::error('Failed to record metric', [
                'name' => $name,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Increment a counter.
     *
     * @param string $name Counter name
     * @param int $amount Amount to increment
     * @param array $tags Counter tags
     * @return bool Success status
     */
    public function incrementCounter(string $name, int $amount = 1, array $tags = []): bool
    {
        try {
            $key = "counter:{$name}:" . md5(json_encode($tags));
            Cache::increment($key, $amount);

            Log::debug('Counter incremented', [
                'name' => $name,
                'amount' => $amount,
                'tags' => $tags,
            ]);

            return true;
        } catch (\Exception $e) {
            Log::error('Failed to increment counter', [
                'name' => $name,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Record a timing.
     *
     * @param string $name Timer name
     * @param float $milliseconds Duration in milliseconds
     * @param array $tags Timer tags
     * @return bool Success status
     */
    public function recordTiming(string $name, float $milliseconds, array $tags = []): bool
    {
        try {
            Log::debug('Timing recorded', [
                'name' => $name,
                'duration_ms' => $milliseconds,
                'tags' => $tags,
            ]);

            $this->recordMetric("{$name}.duration", $milliseconds, $tags);

            return true;
        } catch (\Exception $e) {
            Log::error('Failed to record timing', [
                'name' => $name,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Log an event.
     *
     * @param string $level Log level (info, warning, error, critical)
     * @param string $message Log message
     * @param array $context Additional context
     * @return bool Success status
     */
    public function logEvent(string $level, string $message, array $context = []): bool
    {
        try {
            Log::log($level, $message, $context);

            return true;
        } catch (\Exception $e) {
            return false;
        }
    }

    /**
     * Record an exception.
     *
     * @param \Throwable $exception Exception to record
     * @param array $context Additional context
     * @return bool Success status
     */
    public function recordException(\Throwable $exception, array $context = []): bool
    {
        try {
            Log::error('Exception recorded', [
                'exception' => get_class($exception),
                'message' => $exception->getMessage(),
                'file' => $exception->getFile(),
                'line' => $exception->getLine(),
                'trace' => $exception->getTraceAsString(),
                'context' => $context,
            ]);

            $this->incrementCounter('exceptions.count', 1, [
                'exception' => get_class($exception),
            ]);

            return true;
        } catch (\Exception $e) {
            return false;
        }
    }

    /**
     * Check system health.
     *
     * @return array Health check results
     */
    public function checkHealth(): array
    {
        $checks = [];

        // Database health
        try {
            DB::connection()->getPdo();
            $checks['database'] = [
                'status' => 'healthy',
                'message' => 'Database connection successful',
            ];
        } catch (\Exception $e) {
            $checks['database'] = [
                'status' => 'unhealthy',
                'message' => 'Database connection failed: ' . $e->getMessage(),
            ];
        }

        // Cache health
        try {
            Cache::put('health_check', true, 60);
            $checks['cache'] = [
                'status' => 'healthy',
                'message' => 'Cache connection successful',
            ];
        } catch (\Exception $e) {
            $checks['cache'] = [
                'status' => 'unhealthy',
                'message' => 'Cache connection failed: ' . $e->getMessage(),
            ];
        }

        // Disk space
        $diskFree = disk_free_space('/');
        $diskTotal = disk_total_space('/');
        $diskUsagePercent = round((1 - ($diskFree / $diskTotal)) * 100, 2);

        $checks['disk'] = [
            'status' => $diskUsagePercent < 90 ? 'healthy' : 'warning',
            'usage_percent' => $diskUsagePercent,
            'free_gb' => round($diskFree / 1024 / 1024 / 1024, 2),
            'total_gb' => round($diskTotal / 1024 / 1024 / 1024, 2),
        ];

        // Memory usage
        $memoryUsage = memory_get_usage(true);
        $memoryLimit = ini_get('memory_limit');

        $checks['memory'] = [
            'status' => 'healthy',
            'usage_mb' => round($memoryUsage / 1024 / 1024, 2),
            'limit' => $memoryLimit,
        ];

        // Overall health
        $unhealthyCount = collect($checks)->filter(fn($check) => $check['status'] === 'unhealthy')->count();

        return [
            'status' => $unhealthyCount === 0 ? 'healthy' : 'unhealthy',
            'timestamp' => now()->toIso8601String(),
            'checks' => $checks,
        ];
    }
}
