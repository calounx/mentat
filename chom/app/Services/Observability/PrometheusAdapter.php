<?php

namespace App\Services\Observability;

use App\Models\Tenant;
use App\Models\VpsServer;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Prometheus Adapter.
 *
 * Handles interactions with Prometheus metrics service.
 * Follows Single Responsibility Principle - only handles Prometheus queries.
 */
class PrometheusAdapter
{
    private string $prometheusUrl;

    public function __construct()
    {
        $this->prometheusUrl = config('chom.observability.prometheus_url', 'http://localhost:9090');
    }

    /**
     * Query Prometheus metrics with tenant scoping.
     */
    public function queryMetrics(Tenant $tenant, string $query, array $options = []): array
    {
        // Inject tenant_id label into query for isolation
        $scopedQuery = $this->injectTenantScope($query, $tenant->id);

        try {
            $response = Http::timeout(30)->get("{$this->prometheusUrl}/api/v1/query", [
                'query' => $scopedQuery,
                'time' => $options['time'] ?? null,
            ]);

            if ($response->successful()) {
                return $response->json();
            }

            Log::warning('Prometheus query failed', [
                'query' => $scopedQuery,
                'status' => $response->status(),
                'body' => $response->body(),
            ]);

            return ['status' => 'error', 'error' => $response->body()];
        } catch (\Exception $e) {
            Log::error('Prometheus query exception', [
                'query' => $scopedQuery,
                'error' => $e->getMessage(),
            ]);

            return ['status' => 'error', 'error' => $e->getMessage()];
        }
    }

    /**
     * Query Prometheus range (for graphs).
     */
    public function queryRange(
        Tenant $tenant,
        string $query,
        string $start,
        string $end,
        string $step = '60s'
    ): array {
        $scopedQuery = $this->injectTenantScope($query, $tenant->id);

        try {
            $response = Http::timeout(60)->get("{$this->prometheusUrl}/api/v1/query_range", [
                'query' => $scopedQuery,
                'start' => $start,
                'end' => $end,
                'step' => $step,
            ]);

            return $response->json();
        } catch (\Exception $e) {
            Log::error('Prometheus range query exception', [
                'error' => $e->getMessage(),
            ]);

            return ['status' => 'error', 'error' => $e->getMessage()];
        }
    }

    /**
     * Get active alerts for a tenant.
     */
    public function getActiveAlerts(Tenant $tenant): array
    {
        try {
            $response = Http::timeout(15)->get("{$this->prometheusUrl}/api/v1/alerts");

            if (! $response->successful()) {
                return [];
            }

            $alerts = $response->json()['data']['alerts'] ?? [];

            // Filter alerts by tenant_id label
            return array_filter($alerts, function ($alert) use ($tenant) {
                return ($alert['labels']['tenant_id'] ?? '') === (string) $tenant->id;
            });
        } catch (\Exception $e) {
            Log::error('Failed to fetch alerts', ['error' => $e->getMessage()]);

            return [];
        }
    }

    /**
     * Get VPS metrics summary.
     */
    public function getVpsSummary(VpsServer $vps): array
    {
        $escapedIp = $this->escapePromQLLabelValue($vps->ip_address);

        $queries = [
            'cpu_usage' => "100 - (avg by(instance)(irate(node_cpu_seconds_total{mode='idle',instance=~'{$escapedIp}:.*'}[5m])) * 100)",
            'memory_usage' => "(1 - node_memory_MemAvailable_bytes{instance=~'{$escapedIp}:.*'} / node_memory_MemTotal_bytes{instance=~'{$escapedIp}:.*'}) * 100",
            'disk_usage' => "(1 - node_filesystem_avail_bytes{instance=~'{$escapedIp}:.*',mountpoint='/'} / node_filesystem_size_bytes{instance=~'{$escapedIp}:.*',mountpoint='/'}) * 100",
            'load_average' => "node_load1{instance=~'{$escapedIp}:.*'}",
        ];

        $results = [];

        foreach ($queries as $metric => $query) {
            $response = $this->queryDirect($query);
            $results[$metric] = $this->extractValue($response);
        }

        return $results;
    }

    /**
     * Query bandwidth usage for a tenant.
     *
     * @return float Bandwidth in GB
     */
    public function queryBandwidth(Tenant $tenant, string $period = '30d'): float
    {
        $escapedTenantId = $this->escapePromQLLabelValue((string) $tenant->id);
        $query = "sum(increase(node_network_transmit_bytes_total{tenant_id=\"{$escapedTenantId}\"}[{$period}]))";

        $response = $this->queryDirect($query);
        $bytes = $this->extractValue($response) ?? 0;

        // Convert to GB
        return round($bytes / (1024 * 1024 * 1024), 2);
    }

    /**
     * Query disk usage for a tenant.
     *
     * @return float Disk usage in GB
     */
    public function queryDiskUsage(Tenant $tenant): float
    {
        $escapedTenantId = $this->escapePromQLLabelValue((string) $tenant->id);
        $query = "sum(node_filesystem_size_bytes{tenant_id=\"{$escapedTenantId}\",mountpoint=\"/\"} - node_filesystem_avail_bytes{tenant_id=\"{$escapedTenantId}\",mountpoint=\"/\"})";

        $response = $this->queryDirect($query);
        $bytes = $this->extractValue($response) ?? 0;

        // Convert to GB
        return round($bytes / (1024 * 1024 * 1024), 2);
    }

    /**
     * Check if Prometheus is healthy.
     */
    public function isHealthy(): bool
    {
        try {
            $response = Http::timeout(5)->get("{$this->prometheusUrl}/-/healthy");

            return $response->successful();
        } catch (\Exception $e) {
            return false;
        }
    }

    /**
     * Generate scrape config for a VPS.
     */
    public function generateScrapeConfig(VpsServer $vps, Tenant $tenant): array
    {
        return [
            'targets' => ["{$vps->ip_address}:9100"],
            'labels' => [
                'job' => 'node',
                'tenant_id' => (string) $tenant->id,
                'hostname' => $vps->hostname,
                'provider' => $vps->provider,
                'tier' => $tenant->tier,
            ],
        ];
    }

    /**
     * Query Prometheus without tenant scoping (for internal queries).
     */
    private function queryDirect(string $query): array
    {
        try {
            $response = Http::timeout(15)->get("{$this->prometheusUrl}/api/v1/query", [
                'query' => $query,
            ]);

            return $response->json();
        } catch (\Exception $e) {
            return ['status' => 'error', 'error' => $e->getMessage()];
        }
    }

    /**
     * Extract single value from Prometheus response.
     */
    private function extractValue(array $response): ?float
    {
        $result = $response['data']['result'][0] ?? null;
        if ($result && isset($result['value'][1])) {
            return round((float) $result['value'][1], 2);
        }

        return null;
    }

    /**
     * Inject tenant_id label into PromQL query.
     * Uses proper escaping to prevent PromQL injection attacks.
     */
    private function injectTenantScope(string $query, string $tenantId): string
    {
        // Escape tenant ID to prevent PromQL injection
        $escapedTenantId = $this->escapePromQLLabelValue($tenantId);

        // For metrics that support tenant_id label, add the filter
        // This is a simplified approach - production would need proper PromQL parsing
        return preg_replace(
            '/(\w+)\{/',
            '$1{tenant_id="'.$escapedTenantId.'",',
            $query
        );
    }

    /**
     * Escape a string for safe use in PromQL label values.
     * Prevents PromQL injection by escaping special characters.
     */
    private function escapePromQLLabelValue(string $value): string
    {
        // Escape backslashes first, then double quotes, newlines
        // Also escape regex special characters since this is used in regex matchers
        $escaped = str_replace(
            ['\\', '"', "\n", '.', '*', '+', '?', '[', ']', '(', ')', '{', '}', '|', '^', '$'],
            ['\\\\', '\\"', '\\n', '\\.', '\\*', '\\+', '\\?', '\\[', '\\]', '\\(', '\\)', '\\{', '\\}', '\\|', '\\^', '\\$'],
            $value
        );

        return $escaped;
    }
}
