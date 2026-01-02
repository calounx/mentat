<?php

namespace App\Services\Observability;

use App\Models\Tenant;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Loki Adapter.
 *
 * Handles interactions with Loki log aggregation service.
 * Follows Single Responsibility Principle - only handles Loki queries.
 */
class LokiAdapter
{
    private string $lokiUrl;

    public function __construct()
    {
        $this->lokiUrl = config('chom.observability.loki_url', 'http://localhost:3100');
    }

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
     * Query logs with time range.
     */
    public function queryRange(
        Tenant $tenant,
        string $query,
        string $start,
        string $end,
        int $limit = 1000
    ): array {
        return $this->queryLogs($tenant, $query, [
            'start' => $start,
            'end' => $end,
            'limit' => $limit,
        ]);
    }

    /**
     * Get recent logs for a site.
     */
    public function getSiteLogs(Tenant $tenant, string $domain, int $limit = 100): array
    {
        $query = '{domain="'.$this->escapeLogQLString($domain).'"}';

        return $this->queryLogs($tenant, $query, ['limit' => $limit]);
    }

    /**
     * Search logs by keyword.
     */
    public function searchLogs(Tenant $tenant, string $search, array $options = []): array
    {
        $query = '{} |~ "'.$this->escapeLogQLString($search).'"';

        return $this->queryLogs($tenant, $query, $options);
    }

    /**
     * Check if Loki is healthy.
     */
    public function isHealthy(): bool
    {
        try {
            $response = Http::timeout(5)->get("{$this->lokiUrl}/ready");

            return $response->successful();
        } catch (\Exception $e) {
            return false;
        }
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
}
