<?php

declare(strict_types=1);

namespace App\Services\Reliability\GracefulDegradation;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;

class DegradationManager
{
    private const CACHE_PREFIX = 'degradation:';
    private const STATUS_CACHE_TTL = 60; // seconds

    /**
     * Check if a feature should be degraded based on dependency health
     */
    public function shouldDegrade(string $feature): bool
    {
        $cacheKey = self::CACHE_PREFIX . 'should_degrade:' . $feature;

        return Cache::remember($cacheKey, self::STATUS_CACHE_TTL, function () use ($feature) {
            $config = config("degradation.features.{$feature}");

            if (!$config || !($config['enabled'] ?? true)) {
                return false;
            }

            // Check if any required dependencies are unhealthy
            $dependencies = $config['dependencies'] ?? [];
            foreach ($dependencies as $dependency) {
                if ($this->isDependencyUnhealthy($dependency)) {
                    Log::info("Feature {$feature} degraded due to unhealthy dependency: {$dependency}");
                    return true;
                }
            }

            return false;
        });
    }

    /**
     * Check if a specific dependency is unhealthy
     */
    public function isDependencyUnhealthy(string $dependency): bool
    {
        $cacheKey = self::CACHE_PREFIX . 'dependency_health:' . $dependency;

        return Cache::get($cacheKey, false);
    }

    /**
     * Mark a dependency as unhealthy
     */
    public function markDependencyUnhealthy(string $dependency, int $ttl = 300): void
    {
        $cacheKey = self::CACHE_PREFIX . 'dependency_health:' . $dependency;
        Cache::put($cacheKey, true, $ttl);

        Log::warning("Dependency marked as unhealthy", [
            'dependency' => $dependency,
            'ttl' => $ttl,
        ]);
    }

    /**
     * Mark a dependency as healthy (clear unhealthy status)
     */
    public function markDependencyHealthy(string $dependency): void
    {
        $cacheKey = self::CACHE_PREFIX . 'dependency_health:' . $dependency;
        Cache::forget($cacheKey);

        Log::info("Dependency marked as healthy", [
            'dependency' => $dependency,
        ]);
    }

    /**
     * Get or create cached fallback data
     */
    public function getCachedFallback(string $key, callable $fetcher, int $ttl = 3600): mixed
    {
        $cacheKey = self::CACHE_PREFIX . 'fallback:' . $key;

        // Try to get fresh data
        try {
            $data = $fetcher();

            // Store as fallback for future degraded operations
            Cache::put($cacheKey, $data, $ttl);

            return $data;
        } catch (\Throwable $e) {
            Log::warning("Failed to fetch fresh data, using cached fallback", [
                'key' => $key,
                'error' => $e->getMessage(),
            ]);

            // Return cached fallback if available
            return Cache::get($cacheKey);
        }
    }

    /**
     * Execute operation with degraded fallback
     */
    public function executeWithFallback(callable $operation, callable $fallback, string $featureName = null): mixed
    {
        // Check if feature should be degraded
        if ($featureName && $this->shouldDegrade($featureName)) {
            Log::info("Using degraded mode for feature: {$featureName}");
            return $fallback();
        }

        try {
            return $operation();
        } catch (\Throwable $e) {
            Log::warning("Operation failed, using fallback", [
                'feature' => $featureName,
                'error' => $e->getMessage(),
            ]);

            return $fallback();
        }
    }

    /**
     * Get degradation status for all features
     */
    public function getDegradationStatus(): array
    {
        $features = config('degradation.features', []);
        $status = [];

        foreach ($features as $featureName => $config) {
            $status[$featureName] = [
                'degraded' => $this->shouldDegrade($featureName),
                'enabled' => $config['enabled'] ?? true,
                'dependencies' => array_map(
                    fn($dep) => [
                        'name' => $dep,
                        'healthy' => !$this->isDependencyUnhealthy($dep),
                    ],
                    $config['dependencies'] ?? []
                ),
            ];
        }

        return $status;
    }

    /**
     * Clear all degradation state
     */
    public function clearDegradationState(): void
    {
        $pattern = self::CACHE_PREFIX . '*';

        // This is a simplified approach - in production you'd want to track keys
        Cache::forget($pattern);

        Log::info('Cleared all degradation state');
    }
}
