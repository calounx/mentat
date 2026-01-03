<?php

declare(strict_types=1);

namespace App\Modules\Infrastructure\Contracts;

/**
 * Observability Service Contract
 *
 * Defines the contract for monitoring, logging, and metrics operations.
 */
interface ObservabilityInterface
{
    /**
     * Record a metric.
     *
     * @param string $name Metric name
     * @param float $value Metric value
     * @param array $tags Metric tags
     * @return bool Success status
     */
    public function recordMetric(string $name, float $value, array $tags = []): bool;

    /**
     * Increment a counter.
     *
     * @param string $name Counter name
     * @param int $amount Amount to increment
     * @param array $tags Counter tags
     * @return bool Success status
     */
    public function incrementCounter(string $name, int $amount = 1, array $tags = []): bool;

    /**
     * Record a timing.
     *
     * @param string $name Timer name
     * @param float $milliseconds Duration in milliseconds
     * @param array $tags Timer tags
     * @return bool Success status
     */
    public function recordTiming(string $name, float $milliseconds, array $tags = []): bool;

    /**
     * Log an event.
     *
     * @param string $level Log level (info, warning, error, critical)
     * @param string $message Log message
     * @param array $context Additional context
     * @return bool Success status
     */
    public function logEvent(string $level, string $message, array $context = []): bool;

    /**
     * Record an exception.
     *
     * @param \Throwable $exception Exception to record
     * @param array $context Additional context
     * @return bool Success status
     */
    public function recordException(\Throwable $exception, array $context = []): bool;

    /**
     * Check system health.
     *
     * @return array Health check results
     */
    public function checkHealth(): array;
}
