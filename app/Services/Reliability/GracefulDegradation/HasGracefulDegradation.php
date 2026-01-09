<?php

declare(strict_types=1);

namespace App\Services\Reliability\GracefulDegradation;

/**
 * Trait for adding graceful degradation capabilities to classes
 */
trait HasGracefulDegradation
{
    /**
     * Execute operation with degraded fallback
     */
    protected function withFallback(callable $operation, callable $fallback, ?string $featureName = null): mixed
    {
        $manager = app(DegradationManager::class);
        return $manager->executeWithFallback($operation, $fallback, $featureName);
    }

    /**
     * Get cached fallback data
     */
    protected function cachedFallback(string $key, callable $fetcher, int $ttl = 3600): mixed
    {
        $manager = app(DegradationManager::class);
        return $manager->getCachedFallback($key, $fetcher, $ttl);
    }

    /**
     * Check if a feature should degrade
     */
    protected function shouldDegrade(string $feature): bool
    {
        $manager = app(DegradationManager::class);
        return $manager->shouldDegrade($feature);
    }

    /**
     * Mark dependency as unhealthy
     */
    protected function markUnhealthy(string $dependency, int $ttl = 300): void
    {
        $manager = app(DegradationManager::class);
        $manager->markDependencyUnhealthy($dependency, $ttl);
    }

    /**
     * Mark dependency as healthy
     */
    protected function markHealthy(string $dependency): void
    {
        $manager = app(DegradationManager::class);
        $manager->markDependencyHealthy($dependency);
    }
}
