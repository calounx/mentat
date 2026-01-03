<?php

declare(strict_types=1);

namespace App\Infrastructure\Observability;

use App\Contracts\Infrastructure\ObservabilityInterface;
use App\ValueObjects\TraceId;
use Throwable;

/**
 * Null Observability Implementation
 *
 * No-op implementation for testing and development.
 * All methods do nothing, allowing tests to run without observability dependencies.
 *
 * Pattern: Null Object Pattern - provides safe no-op implementation
 * Use Case: Testing, development, disabled observability
 *
 * @package App\Infrastructure\Observability
 */
class NullObservability implements ObservabilityInterface
{
    /**
     * {@inheritDoc}
     */
    public function recordMetric(string $name, float $value, array $tags = []): void
    {
        // No-op
    }

    /**
     * {@inheritDoc}
     */
    public function incrementCounter(string $name, int $value = 1, array $tags = []): void
    {
        // No-op
    }

    /**
     * {@inheritDoc}
     */
    public function recordTiming(string $name, int $milliseconds, array $tags = []): void
    {
        // No-op
    }

    /**
     * {@inheritDoc}
     */
    public function recordEvent(string $name, array $data = []): void
    {
        // No-op
    }

    /**
     * {@inheritDoc}
     */
    public function startTrace(string $name, array $context = []): TraceId
    {
        return TraceId::generate();
    }

    /**
     * {@inheritDoc}
     */
    public function endTrace(TraceId $traceId, array $metadata = []): void
    {
        // No-op
    }

    /**
     * {@inheritDoc}
     */
    public function logError(Throwable $exception, array $context = []): void
    {
        // No-op
    }

    /**
     * {@inheritDoc}
     */
    public function recordGauge(string $name, float $value, array $tags = []): void
    {
        // No-op
    }

    /**
     * {@inheritDoc}
     */
    public function recordHistogram(string $name, float $value, array $tags = []): void
    {
        // No-op
    }

    /**
     * {@inheritDoc}
     */
    public function flush(): void
    {
        // No-op
    }
}
