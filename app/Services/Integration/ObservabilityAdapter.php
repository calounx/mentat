<?php

namespace App\Services\Integration;

use App\Models\Tenant;
use App\Models\VpsServer;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Cache;

class ObservabilityAdapter
{
    private string $prometheusUrl;
    private string $lokiUrl;
    private string $grafanaUrl;
    private ?string $grafanaApiKey;

    public function __construct()
    {
        $this->prometheusUrl = config('chom.observability.prometheus_url');
        $this->lokiUrl = config('chom.observability.loki_url');
        $this->grafanaUrl = config('chom.observability.grafana_url');
        $this->grafanaApiKey = config('chom.observability.grafana_api_key');

        // Validate required URLs are configured
        if (!$this->prometheusUrl || !$this->lokiUrl || !$this->grafanaUrl) {
            throw new \RuntimeException(
                'Observability URLs must be configured in .env file. ' .
                'Set CHOM_PROMETHEUS_URL, CHOM_LOKI_URL, and CHOM_GRAFANA_URL.'
            );
        }
    }

    // =========================================================================
    // PROMETHEUS QUERIES
    // =========================================================================

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
    public function queryMetricsRange(
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

            if (!$response->successful()) {
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
            $response = $this->queryMetricsDirect($query);
            $results[$metric] = $this->extractValue($response);
        }

        return $results;
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

    /**
     * Query Prometheus without tenant scoping (for internal queries).
     */
    private function queryMetricsDirect(string $query): array
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
     */
    private function injectTenantScope(string $query, string $tenantId): string
    {
        // For metrics that support tenant_id label, add the filter
        // This is a simplified approach - production would need proper PromQL parsing
        return preg_replace(
            '/(\w+)\{/',
            '$1{tenant_id="' . $tenantId . '",',
            $query
        );
    }

    // =========================================================================
    // LOKI QUERIES
    // =========================================================================

    /**
     * Query Loki logs with tenant isolation.
     */
    public function queryLogs(Tenant $tenant, string $query, array $options = []): array
    {
        $start = $options['start'] ?? (now()->subHour()->timestamp * 1000000000);
        $end = $options['end'] ?? (now()->timestamp * 1000000000);
        $limit = $options['limit'] ?? 1000;

        try {
            // Loki uses X-Loki-Org-Id header for tenant isolation
            $response = Http::timeout(30)
                ->withHeaders([
                    'X-Loki-Org-Id' => (string) $tenant->id,
                ])
                ->get("{$this->lokiUrl}/loki/api/v1/query_range", [
                    'query' => $query,
                    'start' => (string) $start,
                    'end' => (string) $end,
                    'limit' => $limit,
                ]);

            return $response->json();
        } catch (\Exception $e) {
            Log::error('Loki query exception', [
                'query' => $query,
                'error' => $e->getMessage(),
            ]);

            return ['status' => 'error', 'error' => $e->getMessage()];
        }
    }

    /**
     * Get recent logs for a site.
     */
    public function getSiteLogs(Tenant $tenant, string $domain, int $limit = 100): array
    {
        $query = '{domain="' . $this->escapeLogQLString($domain) . '"}';
        return $this->queryLogs($tenant, $query, ['limit' => $limit]);
    }

    /**
     * Search logs by keyword.
     */
    public function searchLogs(Tenant $tenant, string $search, array $options = []): array
    {
        $query = '{} |~ "' . $this->escapeLogQLString($search) . '"';
        return $this->queryLogs($tenant, $query, $options);
    }

    /**
     * Escape a string for safe use in LogQL queries.
     * Prevents LogQL injection by escaping special characters.
     */
    private function escapeLogQLString(string $value): string
    {
        // Escape backslashes first, then double quotes, newlines, carriage returns, and tabs
        $escaped = str_replace(
            ['\\', '"', "\n", "\r", "\t"],
            ['\\\\', '\\"', '\\n', '\\r', '\\t'],
            $value
        );

        return $escaped;
    }

    // =========================================================================
    // GRAFANA INTEGRATION
    // =========================================================================

    /**
     * Get Grafana dashboards.
     */
    public function getDashboards(): array
    {
        try {
            $response = Http::timeout(15)
                ->withHeaders($this->grafanaHeaders())
                ->get("{$this->grafanaUrl}/api/search", [
                    'type' => 'dash-db',
                ]);

            return $response->json();
        } catch (\Exception $e) {
            Log::error('Failed to fetch Grafana dashboards', ['error' => $e->getMessage()]);
            return [];
        }
    }

    /**
     * Get embedded dashboard URL.
     */
    public function getEmbeddedDashboardUrl(string $dashboardUid, Tenant $tenant): string
    {
        return "{$this->grafanaUrl}/d/{$dashboardUid}?var-tenant_id={$tenant->id}&kiosk";
    }

    /**
     * Get Grafana headers for API calls.
     */
    private function grafanaHeaders(): array
    {
        $headers = ['Accept' => 'application/json'];

        if ($this->grafanaApiKey) {
            $headers['Authorization'] = 'Bearer ' . $this->grafanaApiKey;
        }

        return $headers;
    }

    // =========================================================================
    // HOST REGISTRATION
    // =========================================================================

    /**
     * Register a new VPS with the observability stack.
     */
    public function registerHost(VpsServer $vps, Tenant $tenant): bool
    {
        // This would be called via SSH on the observability server
        // or through a custom API endpoint

        $hostConfig = [
            'name' => $vps->hostname,
            'ip' => $vps->ip_address,
            'description' => "Tenant: {$tenant->name}",
            'labels' => [
                'tenant_id' => (string) $tenant->id,
                'tier' => $tenant->tier,
                'provider' => $vps->provider,
            ],
            'exporters' => [
                'node_exporter',
            ],
        ];

        // Store host config for provisioning
        Cache::put("host_registration:{$vps->id}", $hostConfig, now()->addHour());

        Log::info('Host registered for observability', [
            'vps' => $vps->hostname,
            'tenant' => $tenant->name,
        ]);

        return true;
    }

    /**
     * Generate Prometheus scrape config for a VPS.
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

    // =========================================================================
    // HEALTH CHECKS
    // =========================================================================

    /**
     * Check if Prometheus is healthy.
     */
    public function isPrometheusHealthy(): bool
    {
        try {
            $response = Http::timeout(5)->get("{$this->prometheusUrl}/-/healthy");
            return $response->successful();
        } catch (\Exception $e) {
            return false;
        }
    }

    /**
     * Check if Loki is healthy.
     */
    public function isLokiHealthy(): bool
    {
        try {
            $response = Http::timeout(5)->get("{$this->lokiUrl}/ready");
            return $response->successful();
        } catch (\Exception $e) {
            return false;
        }
    }

    /**
     * Check if Grafana is healthy.
     */
    public function isGrafanaHealthy(): bool
    {
        try {
            $response = Http::timeout(5)->get("{$this->grafanaUrl}/api/health");
            return $response->successful();
        } catch (\Exception $e) {
            return false;
        }
    }

    /**
     * Get overall observability health status.
     */
    public function getHealthStatus(): array
    {
        return [
            'prometheus' => $this->isPrometheusHealthy(),
            'loki' => $this->isLokiHealthy(),
            'grafana' => $this->isGrafanaHealthy(),
            'all_healthy' => $this->isPrometheusHealthy() && $this->isLokiHealthy() && $this->isGrafanaHealthy(),
        ];
    }

    // =========================================================================
    // BANDWIDTH / USAGE METRICS
    // =========================================================================

    /**
     * Query bandwidth usage for a tenant.
     */
    public function queryBandwidth(Tenant $tenant, string $period = '30d'): float
    {
        // Query network traffic for all VPS belonging to tenant
        $query = "sum(increase(node_network_transmit_bytes_total{tenant_id=\"{$tenant->id}\"}[{$period}]))";

        $response = $this->queryMetricsDirect($query);
        $bytes = $this->extractValue($response) ?? 0;

        // Convert to GB
        return round($bytes / (1024 * 1024 * 1024), 2);
    }

    /**
     * Query disk usage for a tenant.
     */
    public function queryDiskUsage(Tenant $tenant): float
    {
        $query = "sum(node_filesystem_size_bytes{tenant_id=\"{$tenant->id}\",mountpoint=\"/\"} - node_filesystem_avail_bytes{tenant_id=\"{$tenant->id}\",mountpoint=\"/\"})";

        $response = $this->queryMetricsDirect($query);
        $bytes = $this->extractValue($response) ?? 0;

        // Convert to GB
        return round($bytes / (1024 * 1024 * 1024), 2);
    }
}
