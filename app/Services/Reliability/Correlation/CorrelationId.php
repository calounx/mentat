<?php

declare(strict_types=1);

namespace App\Services\Reliability\Correlation;

use App\Http\Middleware\RequestCorrelationId;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class CorrelationId
{
    private static ?string $current = null;

    /**
     * Get the current correlation ID
     */
    public static function get(): ?string
    {
        // Try from request context first
        if (request()->attributes->has(RequestCorrelationId::CONTEXT_KEY)) {
            return request()->attributes->get(RequestCorrelationId::CONTEXT_KEY);
        }

        // Try from log context
        $context = Log::sharedContext();
        if (isset($context[RequestCorrelationId::CONTEXT_KEY])) {
            return $context[RequestCorrelationId::CONTEXT_KEY];
        }

        // Return stored value
        return self::$current;
    }

    /**
     * Set the current correlation ID
     */
    public static function set(string $correlationId): void
    {
        self::$current = $correlationId;

        // Add to log context
        Log::withContext([
            RequestCorrelationId::CONTEXT_KEY => $correlationId,
        ]);
    }

    /**
     * Generate a new correlation ID and set it as current
     */
    public static function generate(): string
    {
        $correlationId = now()->timestamp . '-' . Str::random(8);
        self::set($correlationId);
        return $correlationId;
    }

    /**
     * Create a child correlation ID for sub-operations
     */
    public static function createChild(string $operation): string
    {
        $parent = self::get() ?? self::generate();
        return $parent . ':' . $operation;
    }

    /**
     * Execute a callback with a specific correlation ID
     */
    public static function with(string $correlationId, callable $callback): mixed
    {
        $previous = self::$current;

        try {
            self::set($correlationId);
            return $callback();
        } finally {
            self::$current = $previous;
        }
    }

    /**
     * Execute a callback with a child correlation ID
     */
    public static function withChild(string $operation, callable $callback): mixed
    {
        $childId = self::createChild($operation);
        return self::with($childId, $callback);
    }

    /**
     * Get HTTP headers for propagating correlation ID
     */
    public static function getHeaders(): array
    {
        $correlationId = self::get();

        if (!$correlationId) {
            return [];
        }

        return [
            RequestCorrelationId::HEADER_NAME => $correlationId,
        ];
    }

    /**
     * Log with correlation context
     */
    public static function log(string $level, string $message, array $context = []): void
    {
        $context[RequestCorrelationId::CONTEXT_KEY] = self::get();
        Log::log($level, $message, $context);
    }
}
