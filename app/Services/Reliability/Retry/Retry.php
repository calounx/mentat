<?php

declare(strict_types=1);

namespace App\Services\Reliability\Retry;

use Closure;
use Exception;
use Illuminate\Support\Facades\Log;
use Throwable;

class Retry
{
    private RetryPolicy $policy;
    private ?string $operationName;

    public function __construct(RetryPolicy $policy, ?string $operationName = null)
    {
        $this->policy = $policy;
        $this->operationName = $operationName;
    }

    /**
     * Execute an operation with retries
     *
     * @template T
     * @param Closure(): T $callback
     * @param Closure(Throwable, int): void|null $onRetry
     * @return T
     * @throws MaxRetriesExceededException
     */
    public function execute(Closure $callback, ?Closure $onRetry = null): mixed
    {
        $attempt = 0;
        $lastException = null;

        while ($attempt < $this->policy->getMaxAttempts()) {
            try {
                $result = $callback();

                // Log successful retry recovery
                if ($attempt > 0) {
                    Log::info("Retry succeeded for {$this->operationName}", [
                        'operation' => $this->operationName,
                        'attempt' => $attempt + 1,
                        'total_attempts' => $attempt + 1,
                    ]);
                }

                return $result;
            } catch (Throwable $e) {
                $lastException = $e;

                // Check if we should retry
                if (!$this->policy->shouldRetry($e, $attempt)) {
                    throw $e;
                }

                // Calculate delay
                $delayMs = $this->policy->calculateDelay($attempt);

                // Log retry attempt
                Log::warning("Retrying operation {$this->operationName}", [
                    'operation' => $this->operationName,
                    'attempt' => $attempt + 1,
                    'max_attempts' => $this->policy->getMaxAttempts(),
                    'delay_ms' => $delayMs,
                    'exception' => get_class($e),
                    'message' => $e->getMessage(),
                ]);

                // Call retry callback if provided
                if ($onRetry) {
                    $onRetry($e, $attempt);
                }

                // Sleep before retry (convert ms to microseconds)
                usleep($delayMs * 1000);

                $attempt++;
            }
        }

        // All retries exhausted
        Log::error("Max retries exceeded for {$this->operationName}", [
            'operation' => $this->operationName,
            'attempts' => $attempt,
            'last_exception' => get_class($lastException),
            'message' => $lastException?->getMessage(),
        ]);

        throw new MaxRetriesExceededException(
            "Operation '{$this->operationName}' failed after {$attempt} attempts",
            0,
            $lastException
        );
    }

    /**
     * Execute an operation with retries and return null on failure
     *
     * @template T
     * @param Closure(): T $callback
     * @return T|null
     */
    public function executeOrNull(Closure $callback): mixed
    {
        try {
            return $this->execute($callback);
        } catch (MaxRetriesExceededException $e) {
            return null;
        }
    }

    /**
     * Execute an operation with retries and return default value on failure
     *
     * @template T
     * @param Closure(): T $callback
     * @param T $default
     * @return T
     */
    public function executeOrDefault(Closure $callback, mixed $default): mixed
    {
        try {
            return $this->execute($callback);
        } catch (MaxRetriesExceededException $e) {
            return $default;
        }
    }

    /**
     * Get the retry policy
     */
    public function getPolicy(): RetryPolicy
    {
        return $this->policy;
    }

    /**
     * Get statistics about the last execution
     */
    public function getStats(): array
    {
        return [
            'operation' => $this->operationName,
            'max_attempts' => $this->policy->getMaxAttempts(),
            'initial_delay_ms' => $this->policy->getInitialDelayMs(),
            'max_delay_ms' => $this->policy->getMaxDelayMs(),
            'multiplier' => $this->policy->getMultiplier(),
            'uses_jitter' => $this->policy->usesJitter(),
        ];
    }
}

class MaxRetriesExceededException extends Exception
{
    //
}
