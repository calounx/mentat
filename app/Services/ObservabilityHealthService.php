<?php

declare(strict_types=1);

namespace App\Services;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class ObservabilityHealthService
{
    private const CACHE_TTL = 30; // seconds
    private const TIMEOUT = 5; // seconds

    /**
     * Check overall observability stack health
     *
     * @return array
     */
    public function checkOverall(): array
    {
        return Cache::remember('observability:health:overall', self::CACHE_TTL, function () {
            $components = [
                'prometheus' => $this->checkPrometheus(),
                'grafana' => $this->checkGrafana(),
                'loki' => $this->checkLoki(),
                'alertmanager' => $this->checkAlertmanager(),
            ];

            $overallStatus = $this->calculateOverallStatus($components);

            return [
                'status' => $overallStatus,
                'components' => $components,
                'cached_at' => now()->toIso8601String(),
                'cache_ttl' => self::CACHE_TTL,
            ];
        });
    }

    /**
     * Check Prometheus health
     *
     * @return array
     */
    public function checkPrometheus(): array
    {
        $url = config('chom.prometheus_url');
        if (!$url) {
            return [
                'status' => 'unconfigured',
                'message' => 'Prometheus URL not configured',
            ];
        }

        try {
            $startTime = microtime(true);
            $response = Http::timeout(self::TIMEOUT)->get("{$url}/-/healthy");
            $responseTime = round((microtime(true) - $startTime) * 1000, 2);

            if ($response->successful()) {
                return [
                    'status' => 'healthy',
                    'response_time_ms' => $responseTime,
                    'url' => $url,
                ];
            }

            return [
                'status' => 'unhealthy',
                'message' => "HTTP {$response->status()}",
                'url' => $url,
            ];
        } catch (\Exception $e) {
            Log::warning('Prometheus health check failed', [
                'url' => $url,
                'error' => $e->getMessage(),
            ]);

            return [
                'status' => 'unhealthy',
                'message' => $e->getMessage(),
                'url' => $url,
            ];
        }
    }

    /**
     * Check Grafana health
     *
     * @return array
     */
    public function checkGrafana(): array
    {
        $url = config('chom.grafana_url');
        if (!$url) {
            return [
                'status' => 'unconfigured',
                'message' => 'Grafana URL not configured',
            ];
        }

        try {
            $startTime = microtime(true);
            $response = Http::timeout(self::TIMEOUT)->get("{$url}/api/health");
            $responseTime = round((microtime(true) - $startTime) * 1000, 2);

            if ($response->successful()) {
                return [
                    'status' => 'healthy',
                    'response_time_ms' => $responseTime,
                    'url' => $url,
                ];
            }

            return [
                'status' => 'unhealthy',
                'message' => "HTTP {$response->status()}",
                'url' => $url,
            ];
        } catch (\Exception $e) {
            Log::warning('Grafana health check failed', [
                'url' => $url,
                'error' => $e->getMessage(),
            ]);

            return [
                'status' => 'unhealthy',
                'message' => $e->getMessage(),
                'url' => $url,
            ];
        }
    }

    /**
     * Check Loki health
     *
     * @return array
     */
    public function checkLoki(): array
    {
        $url = config('chom.loki_url');
        if (!$url) {
            return [
                'status' => 'unconfigured',
                'message' => 'Loki URL not configured',
            ];
        }

        try {
            $startTime = microtime(true);
            $response = Http::timeout(self::TIMEOUT)->get("{$url}/ready");
            $responseTime = round((microtime(true) - $startTime) * 1000, 2);

            if ($response->successful()) {
                return [
                    'status' => 'healthy',
                    'response_time_ms' => $responseTime,
                    'url' => $url,
                ];
            }

            return [
                'status' => 'unhealthy',
                'message' => "HTTP {$response->status()}",
                'url' => $url,
            ];
        } catch (\Exception $e) {
            Log::warning('Loki health check failed', [
                'url' => $url,
                'error' => $e->getMessage(),
            ]);

            return [
                'status' => 'unhealthy',
                'message' => $e->getMessage(),
                'url' => $url,
            ];
        }
    }

    /**
     * Check Alertmanager health
     *
     * @return array
     */
    public function checkAlertmanager(): array
    {
        $url = config('chom.alertmanager_url');
        if (!$url) {
            return [
                'status' => 'unconfigured',
                'message' => 'Alertmanager URL not configured',
            ];
        }

        try {
            $startTime = microtime(true);
            $response = Http::timeout(self::TIMEOUT)->get("{$url}/-/healthy");
            $responseTime = round((microtime(true) - $startTime) * 1000, 2);

            if ($response->successful()) {
                return [
                    'status' => 'healthy',
                    'response_time_ms' => $responseTime,
                    'url' => $url,
                ];
            }

            return [
                'status' => 'unhealthy',
                'message' => "HTTP {$response->status()}",
                'url' => $url,
            ];
        } catch (\Exception $e) {
            Log::warning('Alertmanager health check failed', [
                'url' => $url,
                'error' => $e->getMessage(),
            ]);

            return [
                'status' => 'unhealthy',
                'message' => $e->getMessage(),
                'url' => $url,
            ];
        }
    }

    /**
     * Calculate overall status from component statuses
     *
     * @param array $components
     * @return string
     */
    private function calculateOverallStatus(array $components): string
    {
        $statuses = array_column($components, 'status');

        // If any component is unhealthy, overall is degraded
        if (in_array('unhealthy', $statuses)) {
            return 'degraded';
        }

        // If all components are healthy, overall is healthy
        if (array_unique($statuses) === ['healthy']) {
            return 'healthy';
        }

        // If some are unconfigured, overall is partial
        if (in_array('unconfigured', $statuses)) {
            return 'partial';
        }

        return 'unknown';
    }

    /**
     * Clear health check cache
     *
     * @return void
     */
    public function clearCache(): void
    {
        Cache::forget('observability:health:overall');
    }
}
