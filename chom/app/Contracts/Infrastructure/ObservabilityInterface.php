<?php

declare(strict_types=1);

namespace App\Contracts\Infrastructure;

use App\ValueObjects\TraceId;
use Throwable;

/**
 * Observability Interface
 *
 * Defines the contract for monitoring, metrics, tracing, and error tracking.
 * Provides abstraction over observability platforms (Prometheus, Grafana, Datadog, etc.)
 *
 * Design Pattern: Adapter Pattern - adapts different observability platforms
 * SOLID Principle: Dependency Inversion - depend on abstraction, not concrete implementations
 *
 * @package App\Contracts\Infrastructure
 */
interface ObservabilityInterface
{
    /**
     * Record a metric value
     *
     * @param string $name Metric name (e.g., 'http.requests', 'database.queries')
     * @param float $value Metric value
     * @param array<string, string|int|float> $tags Additional tags/labels
     * @return void
     */
    public function recordMetric(string $name, float $value, array $tags = []): void;

    /**
     * Increment a counter metric
     *
     * @param string $name Counter name
     * @param int $value Increment amount (default: 1)
     * @param array<string, string|int|float> $tags Additional tags/labels
     * @return void
     */
    public function incrementCounter(string $name, int $value = 1, array $tags = []): void;

    /**
     * Record a timing metric
     *
     * @param string $name Timing name (e.g., 'http.response_time')
     * @param int $milliseconds Duration in milliseconds
     * @param array<string, string|int|float> $tags Additional tags/labels
     * @return void
     */
    public function recordTiming(string $name, int $milliseconds, array $tags = []): void;

    /**
     * Record an event
     *
     * @param string $name Event name
     * @param array<string, mixed> $data Event data
     * @return void
     */
    public function recordEvent(string $name, array $data = []): void;

    /**
     * Start a distributed trace
     *
     * @param string $name Trace name (e.g., 'http.request', 'job.process')
     * @param array<string, mixed> $context Trace context
     * @return TraceId Unique trace identifier
     */
    public function startTrace(string $name, array $context = []): TraceId;

    /**
     * End a distributed trace
     *
     * @param TraceId $traceId Trace identifier to close
     * @param array<string, mixed> $metadata Additional trace metadata
     * @return void
     */
    public function endTrace(TraceId $traceId, array $metadata = []): void;

    /**
     * Log an error/exception
     *
     * @param Throwable $exception Exception to log
     * @param array<string, mixed> $context Additional error context
     * @return void
     */
    public function logError(Throwable $exception, array $context = []): void;

    /**
     * Record a gauge metric (current value)
     *
     * @param string $name Gauge name
     * @param float $value Current value
     * @param array<string, string|int|float> $tags Additional tags/labels
     * @return void
     */
    public function recordGauge(string $name, float $value, array $tags = []): void;

    /**
     * Record a histogram metric (distribution)
     *
     * @param string $name Histogram name
     * @param float $value Value to record
     * @param array<string, string|int|float> $tags Additional tags/labels
     * @return void
     */
    public function recordHistogram(string $name, float $value, array $tags = []): void;

    /**
     * Flush any buffered metrics
     *
     * @return void
     */
    public function flush(): void;
}
