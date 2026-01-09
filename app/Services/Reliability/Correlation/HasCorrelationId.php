<?php

declare(strict_types=1);

namespace App\Services\Reliability\Correlation;

use Illuminate\Support\Facades\Http;

/**
 * Trait for adding correlation ID tracking to classes
 */
trait HasCorrelationId
{
    /**
     * Get the current correlation ID
     */
    protected function correlationId(): ?string
    {
        return CorrelationId::get();
    }

    /**
     * Execute with a child correlation ID
     */
    protected function withChildCorrelation(string $operation, callable $callback): mixed
    {
        return CorrelationId::withChild($operation, $callback);
    }

    /**
     * Create an HTTP client with correlation ID headers
     */
    protected function httpWithCorrelation(): \Illuminate\Http\Client\PendingRequest
    {
        return Http::withHeaders(CorrelationId::getHeaders());
    }

    /**
     * Log with correlation context
     */
    protected function logWithCorrelation(string $level, string $message, array $context = []): void
    {
        CorrelationId::log($level, $message, $context);
    }
}
