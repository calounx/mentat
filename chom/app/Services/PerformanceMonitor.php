<?php

declare(strict_types=1);

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Event;

/**
 * Performance Monitor Service
 *
 * Monitors application performance including database queries,
 * memory usage, and slow operations.
 */
class PerformanceMonitor
{
    private MetricsCollector $metrics;
    private StructuredLogger $logger;
    private array $activeOperations = [];
    private bool $isListening = false;

    public function __construct(MetricsCollector $metrics, StructuredLogger $logger)
    {
        $this->metrics = $metrics;
        $this->logger = $logger;
    }

    /**
     * Start monitoring performance.
     *
     * @return void
     */
    public function start(): void
    {
        if (!config('observability.performance.enabled', true)) {
            return;
        }

        if ($this->isListening) {
            return;
        }

        $this->registerDatabaseQueryListener();
        $this->registerMemoryMonitor();
        $this->isListening = true;
    }

    /**
     * Start tracking an operation.
     *
     * @param string $operation Operation name
     * @param array $context Additional context
     * @return string Operation ID
     */
    public function startOperation(string $operation, array $context = []): string
    {
        $operationId = $this->generateOperationId();

        $this->activeOperations[$operationId] = [
            'operation' => $operation,
            'start_time' => microtime(true),
            'start_memory' => memory_get_usage(true),
            'context' => $context,
        ];

        return $operationId;
    }

    /**
     * Finish tracking an operation and record metrics.
     *
     * @param string $operationId Operation ID
     * @param array $additionalContext Additional context
     * @return void
     */
    public function finishOperation(string $operationId, array $additionalContext = []): void
    {
        if (!isset($this->activeOperations[$operationId])) {
            return;
        }

        $operation = $this->activeOperations[$operationId];
        $duration = microtime(true) - $operation['start_time'];
        $memoryUsed = memory_get_usage(true) - $operation['start_memory'];

        $context = array_merge($operation['context'], $additionalContext, [
            'duration_seconds' => $duration,
            'duration_ms' => round($duration * 1000, 2),
            'memory_used_bytes' => $memoryUsed,
            'memory_used_mb' => round($memoryUsed / 1024 / 1024, 2),
        ]);

        // Log performance metric
        $this->logger->performance($operation['operation'], $duration, $context);

        // Record metrics
        $this->metrics->observeHistogram(
            'operation_duration_seconds',
            $duration,
            ['operation' => $operation['operation']]
        );

        // Clean up
        unset($this->activeOperations[$operationId]);
    }

    /**
     * Track a callable's performance.
     *
     * @param string $operation Operation name
     * @param callable $callback
     * @param array $context Additional context
     * @return mixed Result of the callback
     */
    public function track(string $operation, callable $callback, array $context = []): mixed
    {
        $operationId = $this->startOperation($operation, $context);

        try {
            $result = $callback();
            $this->finishOperation($operationId, ['success' => true]);
            return $result;
        } catch (\Throwable $e) {
            $this->finishOperation($operationId, [
                'success' => false,
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }

    /**
     * Get current memory usage statistics.
     *
     * @return array
     */
    public function getMemoryUsage(): array
    {
        return [
            'current_bytes' => memory_get_usage(true),
            'current_mb' => round(memory_get_usage(true) / 1024 / 1024, 2),
            'peak_bytes' => memory_get_peak_usage(true),
            'peak_mb' => round(memory_get_peak_usage(true) / 1024 / 1024, 2),
            'limit_mb' => $this->getMemoryLimit(),
            'usage_percent' => $this->getMemoryUsagePercent(),
        ];
    }

    /**
     * Check if memory usage is high.
     *
     * @return bool
     */
    public function isMemoryUsageHigh(): bool
    {
        $threshold = config('observability.performance.memory.threshold_mb', 256);
        $currentMb = memory_get_usage(true) / 1024 / 1024;

        return $currentMb > $threshold;
    }

    /**
     * Get active operations.
     *
     * @return array
     */
    public function getActiveOperations(): array
    {
        $operations = [];

        foreach ($this->activeOperations as $id => $operation) {
            $operations[] = [
                'id' => $id,
                'operation' => $operation['operation'],
                'elapsed_seconds' => microtime(true) - $operation['start_time'],
                'context' => $operation['context'],
            ];
        }

        return $operations;
    }

    /**
     * Register database query listener.
     *
     * @return void
     */
    private function registerDatabaseQueryListener(): void
    {
        if (!config('observability.performance.queries.enabled', true)) {
            return;
        }

        DB::listen(function ($query) {
            $duration = $query->time / 1000; // Convert ms to seconds

            // Record query metric
            $this->metrics->recordDatabaseQuery(
                $this->sanitizeQuery($query->sql),
                $duration,
                $query->connectionName
            );

            // Log slow queries
            $slowThreshold = config('observability.performance.queries.slow_threshold_ms', 100) / 1000;
            if ($duration > $slowThreshold) {
                $bindings = config('observability.performance.queries.log_bindings', false)
                    ? $query->bindings
                    : [];

                $this->logger->slowQuery($query->sql, $duration, $bindings);

                // Record slow query metric
                $this->metrics->incrementCounter('db_queries_slow_total', [
                    'connection' => $query->connectionName,
                ]);
            }
        });
    }

    /**
     * Register memory monitor.
     *
     * @return void
     */
    private function registerMemoryMonitor(): void
    {
        if (!config('observability.performance.memory.enabled', true)) {
            return;
        }

        // Check memory usage periodically
        register_tick_function(function () {
            static $lastCheck = 0;
            $now = time();

            // Only check every 10 seconds
            if ($now - $lastCheck < 10) {
                return;
            }

            $lastCheck = $now;

            $memoryMb = memory_get_usage(true) / 1024 / 1024;
            $this->metrics->setGauge('memory_usage_mb', $memoryMb);

            if ($this->isMemoryUsageHigh() && config('observability.performance.memory.log_on_threshold', true)) {
                $this->logger->warning('High memory usage detected', $this->getMemoryUsage());
            }
        });
    }

    /**
     * Sanitize SQL query for logging.
     *
     * @param string $query
     * @return string
     */
    private function sanitizeQuery(string $query): string
    {
        // Truncate very long queries
        if (strlen($query) > 500) {
            return substr($query, 0, 500) . '...';
        }

        return $query;
    }

    /**
     * Get memory limit in MB.
     *
     * @return float
     */
    private function getMemoryLimit(): float
    {
        $limit = ini_get('memory_limit');

        if ($limit === '-1') {
            return -1; // Unlimited
        }

        // Parse the limit string (e.g., "128M", "1G")
        $value = (int) $limit;
        $unit = strtoupper(substr($limit, -1));

        return match ($unit) {
            'G' => $value * 1024,
            'M' => $value,
            'K' => $value / 1024,
            default => $value / 1024 / 1024,
        };
    }

    /**
     * Get memory usage as a percentage.
     *
     * @return float
     */
    private function getMemoryUsagePercent(): float
    {
        $limit = $this->getMemoryLimit();

        if ($limit <= 0) {
            return 0; // Unlimited or invalid
        }

        $currentMb = memory_get_usage(true) / 1024 / 1024;

        return round(($currentMb / $limit) * 100, 2);
    }

    /**
     * Generate a unique operation ID.
     *
     * @return string
     */
    private function generateOperationId(): string
    {
        return \Illuminate\Support\Str::uuid()->toString();
    }
}
