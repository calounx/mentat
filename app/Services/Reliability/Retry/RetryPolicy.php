<?php

declare(strict_types=1);

namespace App\Services\Reliability\Retry;

class RetryPolicy
{
    private int $maxAttempts;
    private int $initialDelayMs;
    private int $maxDelayMs;
    private float $multiplier;
    private bool $useJitter;
    private array $retryableExceptions;

    public function __construct(
        int $maxAttempts = 3,
        int $initialDelayMs = 100,
        int $maxDelayMs = 10000,
        float $multiplier = 2.0,
        bool $useJitter = true,
        array $retryableExceptions = []
    ) {
        $this->maxAttempts = $maxAttempts;
        $this->initialDelayMs = $initialDelayMs;
        $this->maxDelayMs = $maxDelayMs;
        $this->multiplier = $multiplier;
        $this->useJitter = $useJitter;
        $this->retryableExceptions = $retryableExceptions;
    }

    /**
     * Calculate delay for a given attempt using exponential backoff
     */
    public function calculateDelay(int $attempt): int
    {
        // Exponential backoff: initialDelay * (multiplier ^ attempt)
        $delay = $this->initialDelayMs * pow($this->multiplier, $attempt);

        // Cap at max delay
        $delay = min($delay, $this->maxDelayMs);

        // Add jitter to prevent thundering herd
        if ($this->useJitter) {
            $jitter = mt_rand(0, (int) ($delay * 0.1)); // +/- 10% jitter
            $delay = $delay + $jitter;
        }

        return (int) $delay;
    }

    /**
     * Check if an exception should trigger a retry
     */
    public function shouldRetry(\Throwable $exception, int $attempt): bool
    {
        // Don't retry if max attempts reached
        if ($attempt >= $this->maxAttempts) {
            return false;
        }

        // If no specific exceptions configured, retry all
        if (empty($this->retryableExceptions)) {
            return true;
        }

        // Check if exception is in retryable list
        foreach ($this->retryableExceptions as $retryableClass) {
            if ($exception instanceof $retryableClass) {
                return true;
            }
        }

        return false;
    }

    public function getMaxAttempts(): int
    {
        return $this->maxAttempts;
    }

    public function getInitialDelayMs(): int
    {
        return $this->initialDelayMs;
    }

    public function getMaxDelayMs(): int
    {
        return $this->maxDelayMs;
    }

    public function getMultiplier(): float
    {
        return $this->multiplier;
    }

    public function usesJitter(): bool
    {
        return $this->useJitter;
    }

    public function getRetryableExceptions(): array
    {
        return $this->retryableExceptions;
    }
}
