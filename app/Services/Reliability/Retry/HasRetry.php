<?php

declare(strict_types=1);

namespace App\Services\Reliability\Retry;

use Closure;

/**
 * Trait for adding retry capabilities to classes
 */
trait HasRetry
{
    /**
     * Execute an operation with retries
     *
     * @template T
     * @param string $policyName
     * @param Closure(): T $callback
     * @param string|null $operationName
     * @return T
     */
    protected function retry(string $policyName, Closure $callback, ?string $operationName = null): mixed
    {
        $manager = app(RetryManager::class);
        return $manager->execute($policyName, $callback, $operationName);
    }

    /**
     * Execute an operation with retries and return null on failure
     *
     * @template T
     * @param string $policyName
     * @param Closure(): T $callback
     * @param string|null $operationName
     * @return T|null
     */
    protected function retryOrNull(string $policyName, Closure $callback, ?string $operationName = null): mixed
    {
        $manager = app(RetryManager::class);
        $retry = $manager->retry($policyName, $operationName);
        return $retry->executeOrNull($callback);
    }

    /**
     * Execute an operation with retries and return default value on failure
     *
     * @template T
     * @param string $policyName
     * @param Closure(): T $callback
     * @param T $default
     * @param string|null $operationName
     * @return T
     */
    protected function retryOrDefault(string $policyName, Closure $callback, mixed $default, ?string $operationName = null): mixed
    {
        $manager = app(RetryManager::class);
        $retry = $manager->retry($policyName, $operationName);
        return $retry->executeOrDefault($callback, $default);
    }

    /**
     * Get a retry policy
     */
    protected function retryPolicy(string $policyName): RetryPolicy
    {
        $manager = app(RetryManager::class);
        return $manager->policy($policyName);
    }
}
