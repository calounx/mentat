<?php

namespace App\Services\Observability;

use App\Models\Tenant;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Grafana Adapter.
 *
 * Handles interactions with Grafana visualization service.
 * Follows Single Responsibility Principle - only handles Grafana operations.
 */
class GrafanaAdapter
{
    private string $grafanaUrl;
    private ?string $grafanaApiKey;

    public function __construct()
    {
        $this->grafanaUrl = config('chom.observability.grafana_url', 'http://localhost:3000');
        $this->grafanaApiKey = config('chom.observability.grafana_api_key');
    }

    /**
     * Get Grafana dashboards.
     *
     * @return array
     */
    public function getDashboards(): array
    {
        try {
            $response = Http::timeout(15)
                ->withHeaders($this->getHeaders())
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
     *
     * @param string $dashboardUid
     * @param Tenant $tenant
     * @param array $vars Additional variables
     * @return string
     */
    public function getEmbeddedDashboardUrl(
        string $dashboardUid,
        Tenant $tenant,
        array $vars = []
    ): string {
        $params = array_merge(
            ['var-tenant_id' => $tenant->id, 'kiosk' => ''],
            $vars
        );

        $queryString = http_build_query($params);
        return "{$this->grafanaUrl}/d/{$dashboardUid}?{$queryString}";
    }

    /**
     * Get dashboard by UID.
     *
     * @param string $uid
     * @return array|null
     */
    public function getDashboard(string $uid): ?array
    {
        try {
            $response = Http::timeout(15)
                ->withHeaders($this->getHeaders())
                ->get("{$this->grafanaUrl}/api/dashboards/uid/{$uid}");

            if ($response->successful()) {
                return $response->json();
            }

            return null;
        } catch (\Exception $e) {
            Log::error('Failed to fetch Grafana dashboard', [
                'uid' => $uid,
                'error' => $e->getMessage(),
            ]);
            return null;
        }
    }

    /**
     * Create a dashboard.
     *
     * @param array $dashboard
     * @return array|null
     */
    public function createDashboard(array $dashboard): ?array
    {
        try {
            $response = Http::timeout(30)
                ->withHeaders($this->getHeaders())
                ->post("{$this->grafanaUrl}/api/dashboards/db", [
                    'dashboard' => $dashboard,
                    'overwrite' => false,
                ]);

            if ($response->successful()) {
                return $response->json();
            }

            Log::warning('Failed to create Grafana dashboard', [
                'status' => $response->status(),
                'body' => $response->body(),
            ]);

            return null;
        } catch (\Exception $e) {
            Log::error('Failed to create Grafana dashboard', [
                'error' => $e->getMessage(),
            ]);
            return null;
        }
    }

    /**
     * Update a dashboard.
     *
     * @param array $dashboard
     * @return array|null
     */
    public function updateDashboard(array $dashboard): ?array
    {
        try {
            $response = Http::timeout(30)
                ->withHeaders($this->getHeaders())
                ->post("{$this->grafanaUrl}/api/dashboards/db", [
                    'dashboard' => $dashboard,
                    'overwrite' => true,
                ]);

            if ($response->successful()) {
                return $response->json();
            }

            return null;
        } catch (\Exception $e) {
            Log::error('Failed to update Grafana dashboard', [
                'error' => $e->getMessage(),
            ]);
            return null;
        }
    }

    /**
     * Delete a dashboard.
     *
     * @param string $uid
     * @return bool
     */
    public function deleteDashboard(string $uid): bool
    {
        try {
            $response = Http::timeout(15)
                ->withHeaders($this->getHeaders())
                ->delete("{$this->grafanaUrl}/api/dashboards/uid/{$uid}");

            return $response->successful();
        } catch (\Exception $e) {
            Log::error('Failed to delete Grafana dashboard', [
                'uid' => $uid,
                'error' => $e->getMessage(),
            ]);
            return false;
        }
    }

    /**
     * Check if Grafana is healthy.
     *
     * @return bool
     */
    public function isHealthy(): bool
    {
        try {
            $response = Http::timeout(5)->get("{$this->grafanaUrl}/api/health");
            return $response->successful();
        } catch (\Exception $e) {
            return false;
        }
    }

    /**
     * Get Grafana headers for API calls.
     *
     * @return array
     */
    private function getHeaders(): array
    {
        $headers = ['Accept' => 'application/json'];

        if ($this->grafanaApiKey) {
            $headers['Authorization'] = 'Bearer ' . $this->grafanaApiKey;
        }

        return $headers;
    }
}
