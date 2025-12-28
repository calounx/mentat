<?php

namespace App\Livewire\Observability;

use App\Models\Site;
use App\Models\Tenant;
use App\Services\Integration\ObservabilityAdapter;
use Livewire\Component;
use Illuminate\Support\Facades\Log;

class MetricsDashboard extends Component
{
    public ?string $siteFilter = '';
    public string $timeRange = '1h';
    public string $refreshInterval = '30';

    public array $cpuData = [];
    public array $memoryData = [];
    public array $diskData = [];
    public array $networkData = [];
    public array $httpData = [];

    public bool $loading = true;
    public ?string $error = null;

    protected $queryString = [
        'siteFilter' => ['except' => ''],
        'timeRange' => ['except' => '1h'],
    ];

    public function mount(): void
    {
        $this->loadMetrics();
    }

    public function updatedSiteFilter(): void
    {
        $this->loadMetrics();
    }

    public function updatedTimeRange(): void
    {
        $this->loadMetrics();
    }

    public function refresh(): void
    {
        $this->loadMetrics();
    }

    public function loadMetrics(): void
    {
        $this->loading = true;
        $this->error = null;

        try {
            $tenant = $this->getTenant();
            $adapter = app(ObservabilityAdapter::class);

            $timeRange = $this->getTimeRangeSeconds();
            $step = $this->calculateStep($timeRange);

            // Build site filter for queries
            $siteFilter = '';
            if ($this->siteFilter) {
                $site = $tenant->sites()->find($this->siteFilter);
                if ($site) {
                    $siteFilter = ",domain=\"{$site->domain}\"";
                }
            }

            // CPU Usage
            $this->cpuData = $adapter->queryMetrics($tenant,
                "100 - (avg by (instance) (irate(node_cpu_seconds_total{mode=\"idle\"{$siteFilter}}[5m])) * 100)",
                ['start' => now()->subSeconds($timeRange)->timestamp, 'end' => now()->timestamp, 'step' => $step]
            );

            // Memory Usage
            $this->memoryData = $adapter->queryMetrics($tenant,
                "(1 - (node_memory_MemAvailable_bytes{$siteFilter} / node_memory_MemTotal_bytes{$siteFilter})) * 100",
                ['start' => now()->subSeconds($timeRange)->timestamp, 'end' => now()->timestamp, 'step' => $step]
            );

            // Disk Usage
            $this->diskData = $adapter->queryMetrics($tenant,
                "(1 - (node_filesystem_avail_bytes{mountpoint=\"/\"{$siteFilter}} / node_filesystem_size_bytes{mountpoint=\"/\"{$siteFilter}})) * 100",
                ['start' => now()->subSeconds($timeRange)->timestamp, 'end' => now()->timestamp, 'step' => $step]
            );

            // Network I/O
            $this->networkData = $adapter->queryMetrics($tenant,
                "irate(node_network_receive_bytes_total{device!=\"lo\"{$siteFilter}}[5m])",
                ['start' => now()->subSeconds($timeRange)->timestamp, 'end' => now()->timestamp, 'step' => $step]
            );

            // HTTP Request Rate (if nginx metrics available)
            $this->httpData = $adapter->queryMetrics($tenant,
                "sum(rate(nginx_http_requests_total{$siteFilter}[5m])) by (status)",
                ['start' => now()->subSeconds($timeRange)->timestamp, 'end' => now()->timestamp, 'step' => $step]
            );

        } catch (\Exception $e) {
            Log::error('Failed to load metrics', ['error' => $e->getMessage()]);
            $this->error = 'Failed to load metrics. Please check your observability stack connection.';
        }

        $this->loading = false;
    }

    private function getTimeRangeSeconds(): int
    {
        return match ($this->timeRange) {
            '15m' => 900,
            '30m' => 1800,
            '1h' => 3600,
            '3h' => 10800,
            '6h' => 21600,
            '12h' => 43200,
            '24h' => 86400,
            '7d' => 604800,
            default => 3600,
        };
    }

    private function calculateStep(int $timeRange): int
    {
        // Return appropriate step size based on time range
        return match (true) {
            $timeRange <= 3600 => 15,      // 1h or less: 15s steps
            $timeRange <= 21600 => 60,     // 6h or less: 1m steps
            $timeRange <= 86400 => 300,    // 24h or less: 5m steps
            default => 900,                 // 7d: 15m steps
        };
    }

    private function getTenant(): Tenant
    {
        return auth()->user()->currentTenant();
    }

    public function getLatestValue(array $data, string $default = 'N/A'): string
    {
        if (empty($data['data']['result'])) {
            return $default;
        }

        $result = $data['data']['result'][0] ?? null;
        if (!$result || empty($result['value'])) {
            return $default;
        }

        $value = $result['value'][1] ?? null;
        if ($value === null) {
            return $default;
        }

        return number_format((float) $value, 1) . '%';
    }

    public function render()
    {
        $tenant = $this->getTenant();
        $sites = $tenant->sites()->orderBy('domain')->get();

        return view('livewire.observability.metrics-dashboard', [
            'sites' => $sites,
        ])->layout('layouts.app', ['title' => 'Metrics Dashboard']);
    }
}
