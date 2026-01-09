<?php

declare(strict_types=1);

namespace App\Services\Reliability\CircuitBreaker;

use App\Services\Reliability\CircuitBreaker\Stores\CacheCircuitBreakerStore;
use App\Services\Reliability\CircuitBreaker\Stores\CircuitBreakerStore;

class CircuitBreakerManager
{
    private CircuitBreakerStore $store;
    private array $breakers = [];
    private array $config;

    public function __construct(?CircuitBreakerStore $store = null)
    {
        $this->store = $store ?? new CacheCircuitBreakerStore();
        $this->config = config('circuit-breaker', []);
    }

    /**
     * Get or create a circuit breaker for a service
     */
    public function breaker(string $name): CircuitBreaker
    {
        if (!isset($this->breakers[$name])) {
            $this->breakers[$name] = $this->createBreaker($name);
        }

        return $this->breakers[$name];
    }

    /**
     * Create a new circuit breaker with configuration
     */
    private function createBreaker(string $name): CircuitBreaker
    {
        $config = $this->config['breakers'][$name] ?? [];
        $defaults = $this->config;

        return new CircuitBreaker(
            name: $name,
            store: $this->store,
            failureThreshold: $config['failure_threshold'] ?? $defaults['default_failure_threshold'] ?? 5,
            successThreshold: $config['success_threshold'] ?? $defaults['default_success_threshold'] ?? 2,
            timeout: $config['timeout'] ?? $defaults['default_timeout'] ?? 60,
            halfOpenTimeout: $config['half_open_timeout'] ?? $defaults['default_half_open_timeout'] ?? 30
        );
    }

    /**
     * Get statistics for all circuit breakers
     */
    public function getAllStats(): array
    {
        $stats = [];

        // Get configured breakers
        foreach ($this->config['breakers'] ?? [] as $name => $config) {
            $stats[$name] = $this->breaker($name)->getStats();
        }

        return $stats;
    }

    /**
     * Check if a specific breaker is enabled
     */
    public function isEnabled(string $name): bool
    {
        return ($this->config['breakers'][$name]['enabled'] ?? true) === true;
    }
}
