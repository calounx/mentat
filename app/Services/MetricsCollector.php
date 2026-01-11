<?php

declare(strict_types=1);

namespace App\Services;

use Illuminate\Support\Facades\Redis;

/**
 * Metrics Collector Service
 *
 * Collects and exposes application metrics in Prometheus format.
 * This service is thread-safe and uses Redis for metric storage to support
 * multi-process environments.
 */
class MetricsCollector
{
    private const REDIS_PREFIX = 'metrics:';
    private const COUNTER_SUFFIX = ':counter';
    private const GAUGE_SUFFIX = ':gauge';
    private const HISTOGRAM_SUFFIX = ':histogram';

    private string $namespace;
    private string $subsystem;
    private array $buckets;

    public function __construct()
    {
        $this->namespace = config('observability.metrics.namespace', 'chom');
        $this->subsystem = config('observability.metrics.subsystem', 'laravel');
        $this->buckets = config('observability.metrics.buckets', []);
    }

    /**
     * Increment a counter metric.
     *
     * @param string $name Metric name
     * @param array $labels Label key-value pairs
     * @param float $value Value to increment by (default: 1)
     * @return void
     */
    public function incrementCounter(string $name, array $labels = [], float $value = 1.0): void
    {
        if (!config('observability.metrics.enabled', true)) {
            return;
        }

        $metricKey = $this->buildMetricKey($name, $labels, self::COUNTER_SUFFIX);

        try {
            Redis::incrByFloat($metricKey, $value);
        } catch (\Exception $e) {
            // Fail silently to avoid breaking application flow
            \Log::debug('Failed to increment counter metric', [
                'metric' => $name,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Set a gauge metric value.
     *
     * @param string $name Metric name
     * @param float $value Current value
     * @param array $labels Label key-value pairs
     * @return void
     */
    public function setGauge(string $name, float $value, array $labels = []): void
    {
        if (!config('observability.metrics.enabled', true)) {
            return;
        }

        $metricKey = $this->buildMetricKey($name, $labels, self::GAUGE_SUFFIX);

        try {
            Redis::set($metricKey, (string)$value);
        } catch (\Exception $e) {
            \Log::debug('Failed to set gauge metric', [
                'metric' => $name,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Increment a gauge metric value.
     *
     * @param string $name Metric name
     * @param float $value Value to increment by
     * @param array $labels Label key-value pairs
     * @return void
     */
    public function incrementGauge(string $name, float $value, array $labels = []): void
    {
        if (!config('observability.metrics.enabled', true)) {
            return;
        }

        $metricKey = $this->buildMetricKey($name, $labels, self::GAUGE_SUFFIX);

        try {
            Redis::incrByFloat($metricKey, $value);
        } catch (\Exception $e) {
            \Log::debug('Failed to increment gauge metric', [
                'metric' => $name,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Decrement a gauge metric value.
     *
     * @param string $name Metric name
     * @param float $value Value to decrement by
     * @param array $labels Label key-value pairs
     * @return void
     */
    public function decrementGauge(string $name, float $value, array $labels = []): void
    {
        $this->incrementGauge($name, -$value, $labels);
    }

    /**
     * Record a histogram observation.
     *
     * @param string $name Metric name
     * @param float $value Observed value
     * @param array $labels Label key-value pairs
     * @param string|null $bucketType Bucket type (http_duration, db_query_duration, etc.)
     * @return void
     */
    public function observeHistogram(
        string $name,
        float $value,
        array $labels = [],
        ?string $bucketType = null
    ): void {
        if (!config('observability.metrics.enabled', true)) {
            return;
        }

        $buckets = $bucketType && isset($this->buckets[$bucketType])
            ? $this->buckets[$bucketType]
            : [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10];

        try {
            // Record count
            $countKey = $this->buildMetricKey($name . '_count', $labels, self::HISTOGRAM_SUFFIX);
            Redis::incr($countKey);

            // Record sum
            $sumKey = $this->buildMetricKey($name . '_sum', $labels, self::HISTOGRAM_SUFFIX);
            Redis::incrByFloat($sumKey, $value);

            // Record buckets
            foreach ($buckets as $bucket) {
                if ($value <= $bucket) {
                    $bucketLabels = array_merge($labels, ['le' => (string)$bucket]);
                    $bucketKey = $this->buildMetricKey($name . '_bucket', $bucketLabels, self::HISTOGRAM_SUFFIX);
                    Redis::incr($bucketKey);
                }
            }

            // Record +Inf bucket
            $infLabels = array_merge($labels, ['le' => '+Inf']);
            $infKey = $this->buildMetricKey($name . '_bucket', $infLabels, self::HISTOGRAM_SUFFIX);
            Redis::incr($infKey);
        } catch (\Exception $e) {
            \Log::debug('Failed to observe histogram metric', [
                'metric' => $name,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Record HTTP request metrics.
     *
     * @param string $method HTTP method
     * @param string $route Route name
     * @param int $statusCode HTTP status code
     * @param float $duration Request duration in seconds
     * @return void
     */
    public function recordHttpRequest(string $method, string $route, int $statusCode, float $duration): void
    {
        $labels = [
            'method' => $method,
            'route' => $route,
            'status' => (string)$statusCode,
        ];

        // Increment request counter
        $this->incrementCounter('http_requests_total', $labels);

        // Record duration histogram
        $this->observeHistogram('http_request_duration_seconds', $duration, $labels, 'http_duration');

        // Track error rate
        if ($statusCode >= 500) {
            $this->incrementCounter('http_requests_errors_total', $labels);
        }
    }

    /**
     * Record database query metrics.
     *
     * @param string $query Query (sanitized)
     * @param float $duration Duration in seconds
     * @param string $connection Connection name
     * @return void
     */
    public function recordDatabaseQuery(string $query, float $duration, string $connection = 'default'): void
    {
        $labels = [
            'connection' => $connection,
            'type' => $this->extractQueryType($query),
        ];

        $this->incrementCounter('db_queries_total', $labels);
        $this->observeHistogram('db_query_duration_seconds', $duration, $labels, 'db_query_duration');

        // Track slow queries
        $slowThreshold = config('observability.logging.performance.slow_query_threshold_ms', 100) / 1000;
        if ($duration > $slowThreshold) {
            $this->incrementCounter('db_queries_slow_total', $labels);
        }
    }

    /**
     * Record cache operation metrics.
     *
     * @param string $operation Operation type (hit, miss, set, delete)
     * @param string $store Cache store
     * @return void
     */
    public function recordCacheOperation(string $operation, string $store = 'default'): void
    {
        $labels = [
            'operation' => $operation,
            'store' => $store,
        ];

        $this->incrementCounter('cache_operations_total', $labels);
    }

    /**
     * Record queue job metrics.
     *
     * @param string $jobName Job class name
     * @param string $queue Queue name
     * @param float $duration Duration in seconds
     * @param bool $success Whether job succeeded
     * @return void
     */
    public function recordQueueJob(string $jobName, string $queue, float $duration, bool $success): void
    {
        $labels = [
            'job' => $jobName,
            'queue' => $queue,
            'status' => $success ? 'success' : 'failed',
        ];

        $this->incrementCounter('queue_jobs_total', $labels);
        $this->observeHistogram('queue_job_duration_seconds', $duration, $labels, 'queue_job_duration');

        if (!$success) {
            $this->incrementCounter('queue_jobs_failed_total', ['job' => $jobName, 'queue' => $queue]);
        }
    }

    /**
     * Record VPS operation metrics.
     *
     * @param string $operation Operation type
     * @param float $duration Duration in seconds
     * @param bool $success Whether operation succeeded
     * @param string|null $provider VPS provider
     * @return void
     */
    public function recordVpsOperation(
        string $operation,
        float $duration,
        bool $success,
        ?string $provider = null
    ): void {
        $labels = [
            'operation' => $operation,
            'status' => $success ? 'success' : 'failed',
        ];

        if ($provider) {
            $labels['provider'] = $provider;
        }

        $this->incrementCounter('vps_operations_total', $labels);
        $this->observeHistogram('vps_operation_duration_seconds', $duration, $labels, 'vps_operation_duration');

        if (!$success) {
            $this->incrementCounter('vps_operations_failed_total', ['operation' => $operation]);
        }
    }

    /**
     * Record site provisioning metrics.
     *
     * @param string $siteType Site type
     * @param bool $success Whether provisioning succeeded
     * @param float|null $duration Duration in seconds
     * @return void
     */
    public function recordSiteProvisioning(string $siteType, bool $success, ?float $duration = null): void
    {
        $labels = [
            'site_type' => $siteType,
            'status' => $success ? 'success' : 'failed',
        ];

        $this->incrementCounter('site_provisioning_total', $labels);

        if ($duration !== null) {
            $this->observeHistogram('site_provisioning_duration_seconds', $duration, $labels, 'vps_operation_duration');
        }

        if (!$success) {
            $this->incrementCounter('site_provisioning_failed_total', ['site_type' => $siteType]);
        }
    }

    /**
     * Record tenant resource usage.
     *
     * @param string $tenantId Tenant ID
     * @param int $sitesCount Number of sites
     * @param float $storageGb Storage in GB
     * @param int $backupsCount Number of backups
     * @return void
     */
    public function recordTenantUsage(string $tenantId, int $sitesCount, float $storageGb, int $backupsCount): void
    {
        $labels = ['tenant_id' => $tenantId];

        $this->setGauge('tenant_sites_count', (float)$sitesCount, $labels);
        $this->setGauge('tenant_storage_gb', $storageGb, $labels);
        $this->setGauge('tenant_backups_count', (float)$backupsCount, $labels);
    }

    /**
     * Record cross-tenant access attempt (security violation).
     *
     * @param string $tenantId Requesting tenant ID
     * @param string $targetTenantId Target tenant ID attempted
     * @param string $resource Resource type accessed
     * @return void
     */
    public function recordCrossTenantAccessAttempt(string $tenantId, string $targetTenantId, string $resource): void
    {
        $labels = [
            'tenant_id' => $tenantId,
            'target_tenant_id' => $targetTenantId,
            'resource' => $resource,
        ];

        $this->incrementCounter('security_cross_tenant_access_total', $labels);

        // Also log this as a critical security event
        \Log::critical('Cross-tenant access attempt detected', [
            'tenant_id' => $tenantId,
            'target_tenant_id' => $targetTenantId,
            'resource' => $resource,
        ]);
    }

    /**
     * Record tenant isolation violation.
     *
     * @param string $violationType Type of violation (data_leak, query_breach, file_access, etc.)
     * @param string|null $tenantId Tenant ID if applicable
     * @param array $context Additional context
     * @return void
     */
    public function recordIsolationViolation(string $violationType, ?string $tenantId = null, array $context = []): void
    {
        $labels = ['violation_type' => $violationType];

        if ($tenantId) {
            $labels['tenant_id'] = $tenantId;
        }

        $this->incrementCounter('security_isolation_violations_total', $labels);

        // Log critical security event
        \Log::critical('Tenant isolation violation detected', array_merge([
            'violation_type' => $violationType,
            'tenant_id' => $tenantId,
        ], $context));
    }

    /**
     * Record orphaned resources detected by health checks.
     *
     * @param string $resourceType Type of orphaned resource (site, user, backup, etc.)
     * @param int $count Number of orphaned resources
     * @return void
     */
    public function recordOrphanedResources(string $resourceType, int $count): void
    {
        $labels = ['resource_type' => $resourceType];

        $this->setGauge('health_orphaned_resources_total', (float)$count, $labels);

        if ($count > 0) {
            \Log::warning('Orphaned resources detected', [
                'resource_type' => $resourceType,
                'count' => $count,
            ]);
        }
    }

    /**
     * Record self-healing operation result.
     *
     * @param string $healingType Type of self-healing operation
     * @param bool $success Whether operation succeeded
     * @param string|null $failureReason Reason for failure if applicable
     * @return void
     */
    public function recordSelfHealing(string $healingType, bool $success, ?string $failureReason = null): void
    {
        $labels = [
            'healing_type' => $healingType,
            'status' => $success ? 'success' : 'failed',
        ];

        $this->incrementCounter('health_self_healing_total', $labels);

        if (!$success) {
            $failureLabels = [
                'failure_type' => $healingType,
                'reason' => $failureReason ?? 'unknown',
            ];
            $this->incrementCounter('health_self_healing_failures_total', $failureLabels);

            \Log::error('Self-healing operation failed', [
                'healing_type' => $healingType,
                'reason' => $failureReason,
            ]);
        }
    }

    /**
     * Record site isolation status.
     *
     * @param string $siteId Site ID
     * @param string $tenantId Tenant ID
     * @param string $vpsInstance VPS instance hostname
     * @param bool $userIsolationOk Whether OS-level user isolation is working
     * @param string $isolationStatus Status: isolated, shared, violation
     * @return void
     */
    public function recordSiteIsolationStatus(
        string $siteId,
        string $tenantId,
        string $vpsInstance,
        bool $userIsolationOk,
        string $isolationStatus
    ): void {
        $labels = [
            'site_id' => $siteId,
            'tenant_id' => $tenantId,
            'vps_instance' => $vpsInstance,
        ];

        $this->setGauge('site_user_isolation_ok', $userIsolationOk ? 1.0 : 0.0, $labels);
        $this->setGauge('site_isolation_status', $this->mapIsolationStatus($isolationStatus), array_merge($labels, [
            'status' => $isolationStatus,
        ]));
    }

    /**
     * Record VPS capacity metrics.
     *
     * @param string $vpsInstance VPS instance hostname
     * @param int $currentSites Current number of sites
     * @param int $maxSites Maximum sites capacity
     * @return void
     */
    public function recordVpsCapacity(string $vpsInstance, int $currentSites, int $maxSites): void
    {
        $labels = ['vps_instance' => $vpsInstance];

        $this->setGauge('vps_capacity_sites_current', (float)$currentSites, $labels);
        $this->setGauge('vps_capacity_sites_max', (float)$maxSites, $labels);
        $this->setGauge('vps_capacity_utilization', $maxSites > 0 ? $currentSites / $maxSites : 0.0, $labels);
    }

    /**
     * Record tenant site limit.
     *
     * @param string $tenantId Tenant ID
     * @param int $siteLimit Maximum sites allowed for tenant
     * @return void
     */
    public function recordTenantSiteLimit(string $tenantId, int $siteLimit): void
    {
        $labels = ['tenant_id' => $tenantId];
        $this->setGauge('tenant_site_limit', (float)$siteLimit, $labels);
    }

    /**
     * Map isolation status to numeric value for Prometheus.
     *
     * @param string $status Status string
     * @return float Numeric representation
     */
    private function mapIsolationStatus(string $status): float
    {
        return match ($status) {
            'isolated' => 1.0,
            'shared' => 0.5,
            'violation' => 0.0,
            default => -1.0,
        };
    }

    /**
     * Export all metrics in Prometheus format.
     *
     * @return string Prometheus-formatted metrics
     */
    public function export(): string
    {
        if (!config('observability.metrics.enabled', true)) {
            return '';
        }

        $output = [];
        $output[] = '# Prometheus metrics for CHOM Laravel application';
        $output[] = '# Generated at ' . now()->toIso8601String();
        $output[] = '';

        try {
            $keys = Redis::keys(self::REDIS_PREFIX . '*');

            if (empty($keys)) {
                return implode("\n", $output);
            }

            $metrics = $this->groupMetricsByName($keys);

            foreach ($metrics as $metricName => $metricData) {
                $output[] = $this->formatMetric($metricName, $metricData);
            }
        } catch (\Exception $e) {
            \Log::error('Failed to export metrics', ['error' => $e->getMessage()]);
            $output[] = '# Error exporting metrics';
        }

        return implode("\n", $output);
    }

    /**
     * Clear all metrics.
     *
     * @return void
     */
    public function clear(): void
    {
        try {
            $keys = Redis::keys(self::REDIS_PREFIX . '*');
            if (!empty($keys)) {
                Redis::del($keys);
            }
        } catch (\Exception $e) {
            \Log::error('Failed to clear metrics', ['error' => $e->getMessage()]);
        }
    }

    /**
     * Build a metric key for storage.
     *
     * @param string $name Metric name
     * @param array $labels Labels
     * @param string $suffix Metric type suffix
     * @return string
     */
    private function buildMetricKey(string $name, array $labels, string $suffix): string
    {
        $fullName = $this->namespace . '_' . $this->subsystem . '_' . $name;

        if (empty($labels)) {
            return self::REDIS_PREFIX . $fullName . $suffix;
        }

        ksort($labels);
        $labelString = http_build_query($labels, '', ',');

        return self::REDIS_PREFIX . $fullName . '{' . $labelString . '}' . $suffix;
    }

    /**
     * Extract query type from SQL query.
     *
     * @param string $query SQL query
     * @return string Query type
     */
    private function extractQueryType(string $query): string
    {
        $query = strtoupper(trim($query));

        if (str_starts_with($query, 'SELECT')) {
            return 'select';
        }
        if (str_starts_with($query, 'INSERT')) {
            return 'insert';
        }
        if (str_starts_with($query, 'UPDATE')) {
            return 'update';
        }
        if (str_starts_with($query, 'DELETE')) {
            return 'delete';
        }

        return 'other';
    }

    /**
     * Group metrics by name for export.
     *
     * @param array $keys Redis keys
     * @return array Grouped metrics
     */
    private function groupMetricsByName(array $keys): array
    {
        $metrics = [];
        // Redis::keys() returns full keys with Laravel prefix,
        // but Redis::get() adds the prefix automatically, so we need to strip it
        $redisPrefix = config('database.redis.options.prefix', '');

        foreach ($keys as $key) {
            // Strip Laravel prefix before calling get()
            $keyWithoutPrefix = $redisPrefix ? substr($key, strlen($redisPrefix)) : $key;
            $value = Redis::get($keyWithoutPrefix);
            if ($value === null) {
                continue;
            }

            // Parse metric key (expects full key with prefix)
            $parsed = $this->parseMetricKey($key);
            if ($parsed === null) {
                continue;
            }

            $metricName = $parsed['name'];
            if (!isset($metrics[$metricName])) {
                $metrics[$metricName] = [
                    'type' => $parsed['type'],
                    'samples' => [],
                ];
            }

            $metrics[$metricName]['samples'][] = [
                'labels' => $parsed['labels'],
                'value' => $value,
            ];
        }

        return $metrics;
    }

    /**
     * Parse a metric key.
     *
     * @param string $key Redis key
     * @return array|null Parsed data
     */
    private function parseMetricKey(string $key): ?array
    {
        // Handle Laravel Redis connection prefix (e.g., "chom-database-")
        // Redis::keys() returns full keys including the connection prefix
        $redisPrefix = config('database.redis.options.prefix', '');
        $fullPrefix = $redisPrefix . self::REDIS_PREFIX;

        if (!str_starts_with($key, $fullPrefix)) {
            return null;
        }

        $key = substr($key, strlen($fullPrefix));

        // Extract type suffix
        $type = 'counter';
        if (str_ends_with($key, self::COUNTER_SUFFIX)) {
            $key = substr($key, 0, -strlen(self::COUNTER_SUFFIX));
            $type = 'counter';
        } elseif (str_ends_with($key, self::GAUGE_SUFFIX)) {
            $key = substr($key, 0, -strlen(self::GAUGE_SUFFIX));
            $type = 'gauge';
        } elseif (str_ends_with($key, self::HISTOGRAM_SUFFIX)) {
            $key = substr($key, 0, -strlen(self::HISTOGRAM_SUFFIX));
            $type = 'histogram';
        }

        // Extract labels
        $labels = [];
        if (preg_match('/^(.+)\{(.+)\}$/', $key, $matches)) {
            $key = $matches[1];
            parse_str(str_replace(',', '&', $matches[2]), $labels);
        }

        return [
            'name' => $key,
            'type' => $type,
            'labels' => $labels,
        ];
    }

    /**
     * Format metric for Prometheus export.
     *
     * @param string $name Metric name
     * @param array $data Metric data
     * @return string Formatted metric
     */
    private function formatMetric(string $name, array $data): string
    {
        $output = [];

        // Add type and help
        $output[] = "# HELP {$name} Application metric";
        $output[] = "# TYPE {$name} {$data['type']}";

        // Add samples
        foreach ($data['samples'] as $sample) {
            $labelString = '';
            if (!empty($sample['labels'])) {
                $pairs = [];
                foreach ($sample['labels'] as $key => $value) {
                    $pairs[] = $key . '="' . addslashes($value) . '"';
                }
                $labelString = '{' . implode(',', $pairs) . '}';
            }

            $output[] = "{$name}{$labelString} {$sample['value']}";
        }

        $output[] = '';

        return implode("\n", $output);
    }
}
