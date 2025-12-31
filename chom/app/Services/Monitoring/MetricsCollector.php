<?php

namespace App\Services\Monitoring;

use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Cache;
use Exception;

class MetricsCollector
{
    protected string $prefix;
    protected string $driver;

    public function __construct()
    {
        $this->prefix = config('monitoring.storage.prefix', 'metrics:');
        $this->driver = config('monitoring.storage.driver', 'redis');
    }

    /**
     * Record a counter metric (increments)
     */
    public function increment(string $metric, array $labels = [], int $value = 1): void
    {
        if (!config('monitoring.enabled')) {
            return;
        }

        try {
            $key = $this->buildKey($metric, $labels);
            $this->incrementValue($key, $value);

            if (config('monitoring.debug')) {
                logger()->debug("Metric incremented: {$metric}", ['labels' => $labels, 'value' => $value]);
            }
        } catch (Exception $e) {
            logger()->error('Failed to increment metric', [
                'metric' => $metric,
                'labels' => $labels,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Record a gauge metric (sets absolute value)
     */
    public function gauge(string $metric, float $value, array $labels = []): void
    {
        if (!config('monitoring.enabled')) {
            return;
        }

        try {
            $key = $this->buildKey($metric, $labels);
            $this->setValue($key, $value);

            if (config('monitoring.debug')) {
                logger()->debug("Metric gauge set: {$metric}", ['labels' => $labels, 'value' => $value]);
            }
        } catch (Exception $e) {
            logger()->error('Failed to set gauge metric', [
                'metric' => $metric,
                'labels' => $labels,
                'value' => $value,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Record a histogram metric (for distributions like response times)
     */
    public function histogram(string $metric, float $value, array $labels = []): void
    {
        if (!config('monitoring.enabled')) {
            return;
        }

        try {
            $key = $this->buildKey($metric, $labels);
            $this->addToHistogram($key, $value);

            if (config('monitoring.debug')) {
                logger()->debug("Metric histogram recorded: {$metric}", ['labels' => $labels, 'value' => $value]);
            }
        } catch (Exception $e) {
            logger()->error('Failed to record histogram metric', [
                'metric' => $metric,
                'labels' => $labels,
                'value' => $value,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Record request metrics
     */
    public function recordRequest(
        string $method,
        string $path,
        int $statusCode,
        float $duration,
        int $memoryUsed,
        int $queryCount
    ): void {
        if (!config('monitoring.metrics.request_metrics.enabled')) {
            return;
        }

        $labels = [
            'method' => $method,
            'status' => (string) $statusCode,
            'path' => $this->normalizePath($path),
        ];

        $this->increment('http_requests_total', $labels);

        if (config('monitoring.metrics.request_metrics.track_response_time')) {
            $this->histogram('http_request_duration_ms', $duration, $labels);
        }

        if (config('monitoring.metrics.request_metrics.track_memory_usage')) {
            $this->histogram('http_request_memory_bytes', $memoryUsed, $labels);
        }

        if (config('monitoring.metrics.request_metrics.track_query_count')) {
            $this->histogram('http_request_query_count', $queryCount, $labels);
        }

        // Track errors
        if ($statusCode >= 500) {
            $this->increment('http_errors_total', ['type' => '5xx', 'status' => (string) $statusCode]);
        } elseif ($statusCode >= 400) {
            $this->increment('http_errors_total', ['type' => '4xx', 'status' => (string) $statusCode]);
        }
    }

    /**
     * Record database query metrics
     */
    public function recordQuery(string $sql, float $duration): void
    {
        if (!config('monitoring.performance.log_slow_queries')) {
            return;
        }

        $threshold = config('monitoring.performance.slow_query_threshold', 1000);

        if ($duration >= $threshold) {
            logger('slow_queries')->warning('Slow query detected', [
                'sql' => $sql,
                'duration_ms' => $duration,
                'threshold_ms' => $threshold,
            ]);

            $this->increment('slow_queries_total', [
                'type' => $this->classifyQuery($sql),
            ]);
        }

        $this->histogram('db_query_duration_ms', $duration, [
            'type' => $this->classifyQuery($sql),
        ]);
    }

    /**
     * Record cache metrics
     */
    public function recordCacheHit(string $key): void
    {
        if (!config('monitoring.metrics.application_metrics.track_cache_hits')) {
            return;
        }

        $this->increment('cache_hits_total', ['result' => 'hit']);
    }

    public function recordCacheMiss(string $key): void
    {
        if (!config('monitoring.metrics.application_metrics.track_cache_hits')) {
            return;
        }

        $this->increment('cache_hits_total', ['result' => 'miss']);
    }

    /**
     * Record queue metrics
     */
    public function recordJobProcessed(string $jobClass, bool $success, float $duration): void
    {
        $this->increment('queue_jobs_processed_total', [
            'job' => class_basename($jobClass),
            'status' => $success ? 'success' : 'failed',
        ]);

        $this->histogram('queue_job_duration_ms', $duration, [
            'job' => class_basename($jobClass),
        ]);
    }

    public function recordQueueDepth(string $queue, int $depth): void
    {
        if (!config('monitoring.metrics.application_metrics.track_queue_depth')) {
            return;
        }

        $this->gauge('queue_depth', $depth, ['queue' => $queue]);
    }

    /**
     * Record business metrics
     */
    public function recordSiteCreated(string $tier): void
    {
        if (!config('monitoring.metrics.business_metrics.track_sites_created')) {
            return;
        }

        $this->increment('sites_created_total', ['tier' => $tier]);
    }

    public function recordBackupCompleted(string $type, bool $success): void
    {
        if (!config('monitoring.metrics.business_metrics.track_backups_run')) {
            return;
        }

        $this->increment('backups_completed_total', [
            'type' => $type,
            'status' => $success ? 'success' : 'failed',
        ]);
    }

    public function recordDeployment(string $environment, bool $success): void
    {
        if (!config('monitoring.metrics.business_metrics.track_deployments')) {
            return;
        }

        $this->increment('deployments_total', [
            'environment' => $environment,
            'status' => $success ? 'success' : 'failed',
        ]);
    }

    /**
     * Record system metrics
     */
    public function recordSystemMetrics(): void
    {
        if (!config('monitoring.metrics.system_metrics.enabled')) {
            return;
        }

        if (config('monitoring.metrics.system_metrics.track_memory')) {
            $memoryUsage = memory_get_usage(true);
            $memoryLimit = $this->convertToBytes(ini_get('memory_limit'));

            $this->gauge('system_memory_usage_bytes', $memoryUsage);

            if ($memoryLimit > 0) {
                $this->gauge('system_memory_usage_percent', ($memoryUsage / $memoryLimit) * 100);
            }
        }

        if (config('monitoring.metrics.system_metrics.track_disk')) {
            $storagePath = storage_path();
            $freeSpace = disk_free_space($storagePath);
            $totalSpace = disk_total_space($storagePath);
            $usedSpace = $totalSpace - $freeSpace;

            $this->gauge('system_disk_free_bytes', $freeSpace);
            $this->gauge('system_disk_used_bytes', $usedSpace);
            $this->gauge('system_disk_usage_percent', ($usedSpace / $totalSpace) * 100);
        }
    }

    /**
     * Get metric value
     */
    public function get(string $metric, array $labels = []): mixed
    {
        $key = $this->buildKey($metric, $labels);

        return match ($this->driver) {
            'redis' => Redis::get($key),
            'cache' => Cache::get($key),
            default => null,
        };
    }

    /**
     * Get all metrics matching a pattern
     */
    public function getAll(string $pattern = '*'): array
    {
        $fullPattern = $this->prefix . $pattern;

        return match ($this->driver) {
            'redis' => $this->getFromRedis($fullPattern),
            default => [],
        };
    }

    /**
     * Export metrics in Prometheus format
     */
    public function exportPrometheus(): string
    {
        $metrics = $this->getAll();
        $output = [];

        foreach ($metrics as $key => $value) {
            $metricName = str_replace($this->prefix, '', $key);
            $output[] = "{$metricName} {$value}";
        }

        return implode("\n", $output);
    }

    /**
     * Clear old metrics based on retention policy
     */
    public function clearOldMetrics(): int
    {
        $deleted = 0;
        $highResRetention = config('monitoring.retention.high_resolution', 24) * 3600;

        if ($this->driver === 'redis') {
            $keys = Redis::keys($this->prefix . '*');

            foreach ($keys as $key) {
                $ttl = Redis::ttl($key);

                if ($ttl === -1) {
                    // No TTL set, set one
                    Redis::expire($key, $highResRetention);
                }
            }
        }

        return $deleted;
    }

    /**
     * Build metric key with labels
     */
    protected function buildKey(string $metric, array $labels = []): string
    {
        $key = $this->prefix . $metric;

        if (!empty($labels)) {
            ksort($labels);
            $labelString = http_build_query($labels, '', ',');
            $key .= '{' . $labelString . '}';
        }

        return $key;
    }

    /**
     * Increment value based on driver
     */
    protected function incrementValue(string $key, int $value): void
    {
        match ($this->driver) {
            'redis' => Redis::incrby($key, $value),
            'cache' => Cache::increment($key, $value),
            default => null,
        };
    }

    /**
     * Set value based on driver
     */
    protected function setValue(string $key, float $value): void
    {
        match ($this->driver) {
            'redis' => Redis::set($key, $value),
            'cache' => Cache::put($key, $value, 3600),
            default => null,
        };
    }

    /**
     * Add value to histogram
     */
    protected function addToHistogram(string $key, float $value): void
    {
        if ($this->driver === 'redis') {
            $histogramKey = $key . ':histogram';
            Redis::zadd($histogramKey, $value, microtime(true));

            // Keep only recent data
            $cutoff = time() - (config('monitoring.retention.high_resolution', 24) * 3600);
            Redis::zremrangebyscore($histogramKey, '-inf', $cutoff);
        }
    }

    /**
     * Get metrics from Redis
     */
    protected function getFromRedis(string $pattern): array
    {
        $keys = Redis::keys($pattern);
        $metrics = [];

        foreach ($keys as $key) {
            $metrics[$key] = Redis::get($key);
        }

        return $metrics;
    }

    /**
     * Normalize URL path for metrics
     */
    protected function normalizePath(string $path): string
    {
        // Replace IDs with placeholders
        $path = preg_replace('/\/\d+/', '/{id}', $path);
        $path = preg_replace('/\/[a-f0-9-]{36}/', '/{uuid}', $path);

        return $path;
    }

    /**
     * Classify SQL query type
     */
    protected function classifyQuery(string $sql): string
    {
        $sql = strtolower(trim($sql));

        return match (true) {
            str_starts_with($sql, 'select') => 'select',
            str_starts_with($sql, 'insert') => 'insert',
            str_starts_with($sql, 'update') => 'update',
            str_starts_with($sql, 'delete') => 'delete',
            default => 'other',
        };
    }

    /**
     * Convert memory size string to bytes
     */
    protected function convertToBytes(string $value): int
    {
        if ($value === '-1') {
            return -1;
        }

        $value = trim($value);
        $last = strtolower($value[strlen($value) - 1]);
        $value = (int) $value;

        return match ($last) {
            'g' => $value * 1024 * 1024 * 1024,
            'm' => $value * 1024 * 1024,
            'k' => $value * 1024,
            default => $value,
        };
    }
}
