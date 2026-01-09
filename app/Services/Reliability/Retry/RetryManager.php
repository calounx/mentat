<?php

declare(strict_types=1);

namespace App\Services\Reliability\Retry;

use Closure;

class RetryManager
{
    private array $policies = [];
    private array $config;

    public function __construct()
    {
        $this->config = config('retry', []);
    }

    /**
     * Get or create a retry policy for a service
     */
    public function policy(string $name): RetryPolicy
    {
        if (!isset($this->policies[$name])) {
            $this->policies[$name] = $this->createPolicy($name);
        }

        return $this->policies[$name];
    }

    /**
     * Create a new retry instance for a service
     */
    public function retry(string $name, ?string $operationName = null): Retry
    {
        $policy = $this->policy($name);
        return new Retry($policy, $operationName ?? $name);
    }

    /**
     * Execute an operation with retries using the specified policy
     *
     * @template T
     * @param string $policyName
     * @param Closure(): T $callback
     * @param string|null $operationName
     * @return T
     */
    public function execute(string $policyName, Closure $callback, ?string $operationName = null): mixed
    {
        return $this->retry($policyName, $operationName)->execute($callback);
    }

    /**
     * Create a new retry policy with configuration
     */
    private function createPolicy(string $name): RetryPolicy
    {
        $config = $this->config['policies'][$name] ?? [];
        $defaults = $this->config;

        return new RetryPolicy(
            maxAttempts: $config['max_attempts'] ?? $defaults['default_max_attempts'] ?? 3,
            initialDelayMs: $config['initial_delay_ms'] ?? $defaults['default_initial_delay_ms'] ?? 100,
            maxDelayMs: $config['max_delay_ms'] ?? $defaults['default_max_delay_ms'] ?? 10000,
            multiplier: $config['multiplier'] ?? $defaults['default_multiplier'] ?? 2.0,
            useJitter: $config['use_jitter'] ?? $defaults['default_use_jitter'] ?? true,
            retryableExceptions: $config['retryable_exceptions'] ?? []
        );
    }

    /**
     * Check if a retry policy is enabled
     */
    public function isEnabled(string $name): bool
    {
        return ($this->config['policies'][$name]['enabled'] ?? true) === true;
    }

    /**
     * Get statistics for all retry policies
     */
    public function getAllStats(): array
    {
        $stats = [];

        foreach ($this->config['policies'] ?? [] as $name => $config) {
            $policy = $this->policy($name);
            $stats[$name] = [
                'enabled' => $this->isEnabled($name),
                'max_attempts' => $policy->getMaxAttempts(),
                'initial_delay_ms' => $policy->getInitialDelayMs(),
                'max_delay_ms' => $policy->getMaxDelayMs(),
                'multiplier' => $policy->getMultiplier(),
                'uses_jitter' => $policy->usesJitter(),
            ];
        }

        return $stats;
    }
}
