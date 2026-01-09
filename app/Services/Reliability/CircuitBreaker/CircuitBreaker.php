<?php

declare(strict_types=1);

namespace App\Services\Reliability\CircuitBreaker;

use App\Services\Reliability\CircuitBreaker\Stores\CircuitBreakerStore;
use Closure;
use Exception;
use Illuminate\Support\Facades\Log;

class CircuitBreaker
{
    private string $name;
    private CircuitBreakerStore $store;
    private int $failureThreshold;
    private int $successThreshold;
    private int $timeout;
    private int $halfOpenTimeout;

    public function __construct(
        string $name,
        CircuitBreakerStore $store,
        int $failureThreshold = 5,
        int $successThreshold = 2,
        int $timeout = 60,
        int $halfOpenTimeout = 30
    ) {
        $this->name = $name;
        $this->store = $store;
        $this->failureThreshold = $failureThreshold;
        $this->successThreshold = $successThreshold;
        $this->timeout = $timeout;
        $this->halfOpenTimeout = $halfOpenTimeout;
    }

    /**
     * Execute a callback with circuit breaker protection
     */
    public function call(Closure $callback, ?Closure $fallback = null): mixed
    {
        $state = $this->getState();

        if ($state->isOpen()) {
            if ($this->shouldAttemptReset()) {
                $this->transitionToHalfOpen();
            } else {
                Log::debug("Circuit breaker {$this->name} is OPEN - failing fast");
                return $this->executeFallback($fallback, new CircuitOpenException("Circuit breaker {$this->name} is open"));
            }
        }

        try {
            $result = $callback();
            $this->recordSuccess();
            return $result;
        } catch (Exception $e) {
            $this->recordFailure($e);

            if ($fallback) {
                return $this->executeFallback($fallback, $e);
            }

            throw $e;
        }
    }

    /**
     * Get current state
     */
    public function getState(): CircuitBreakerState
    {
        return $this->store->getState($this->name);
    }

    /**
     * Record a successful call
     */
    public function recordSuccess(): void
    {
        $state = $this->getState();

        if ($state->isHalfOpen()) {
            $successCount = $this->store->incrementSuccessCount($this->name);

            if ($successCount >= $this->successThreshold) {
                $this->close();
                Log::info("Circuit breaker {$this->name} CLOSED after successful recovery");
            }
        } elseif ($state->isClosed()) {
            // Reset failure count on success
            $this->store->resetFailureCount($this->name);
        }
    }

    /**
     * Record a failed call
     */
    public function recordFailure(Exception $e): void
    {
        $state = $this->getState();

        Log::warning("Circuit breaker {$this->name} recorded failure", [
            'error' => $e->getMessage(),
            'current_state' => $state->value,
        ]);

        if ($state->isHalfOpen()) {
            // Failure during half-open immediately reopens circuit
            $this->open();
            return;
        }

        if ($state->isClosed()) {
            $failureCount = $this->store->incrementFailureCount($this->name);

            if ($failureCount >= $this->failureThreshold) {
                $this->open();
            }
        }
    }

    /**
     * Check if we should attempt to reset the circuit
     */
    private function shouldAttemptReset(): bool
    {
        $nextAttemptAt = $this->store->getNextAttemptAt($this->name);
        return $nextAttemptAt && now()->isAfter($nextAttemptAt);
    }

    /**
     * Transition to half-open state
     */
    private function transitionToHalfOpen(): void
    {
        $this->store->setState($this->name, CircuitBreakerState::HALF_OPEN);
        $this->store->resetSuccessCount($this->name);

        Log::info("Circuit breaker {$this->name} transitioned to HALF_OPEN");
    }

    /**
     * Open the circuit
     */
    private function open(): void
    {
        $this->store->setState($this->name, CircuitBreakerState::OPEN);
        $this->store->setNextAttemptAt($this->name, now()->addSeconds($this->timeout));

        Log::warning("Circuit breaker {$this->name} OPENED", [
            'next_attempt_at' => now()->addSeconds($this->timeout)->toIso8601String(),
        ]);
    }

    /**
     * Close the circuit
     */
    private function close(): void
    {
        $this->store->setState($this->name, CircuitBreakerState::CLOSED);
        $this->store->resetFailureCount($this->name);
        $this->store->resetSuccessCount($this->name);
        $this->store->setNextAttemptAt($this->name, null);
    }

    /**
     * Execute fallback callback
     */
    private function executeFallback(?Closure $fallback, Exception $originalException): mixed
    {
        if (!$fallback) {
            throw $originalException;
        }

        try {
            return $fallback();
        } catch (Exception $e) {
            Log::error("Circuit breaker {$this->name} fallback failed", [
                'error' => $e->getMessage(),
            ]);
            throw $originalException;
        }
    }

    /**
     * Get circuit breaker statistics
     */
    public function getStats(): array
    {
        return [
            'name' => $this->name,
            'state' => $this->getState()->value,
            'failure_count' => $this->store->getFailureCount($this->name),
            'success_count' => $this->store->getSuccessCount($this->name),
            'next_attempt_at' => $this->store->getNextAttemptAt($this->name)?->toIso8601String(),
            'thresholds' => [
                'failure' => $this->failureThreshold,
                'success' => $this->successThreshold,
                'timeout' => $this->timeout,
            ],
        ];
    }
}

class CircuitOpenException extends Exception
{
    //
}
