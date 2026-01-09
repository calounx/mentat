<?php

namespace App\Livewire;

use App\Models\VpsServer;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Livewire\Component;

/**
 * VPS Health Monitor Livewire Component
 *
 * Provides real-time monitoring of VPS infrastructure, showing health metrics
 * and statistics. Automatically refreshes every 30 seconds via wire:poll.
 *
 * @property string $vpsId
 * @property array|null $healthData
 * @property array|null $stats
 * @property int $refreshInterval
 * @property bool $processing
 * @property VpsServer|null $vps
 */
class VpsHealthMonitor extends Component
{
    public string $vpsId;
    public ?array $healthData = null;
    public ?array $stats = null;
    public int $refreshInterval = 30;
    public bool $processing = false;
    public ?VpsServer $vps = null;
    public ?string $error = null;

    /**
     * Mount the component and load initial data.
     *
     * @param VpsServer $vps
     * @return void
     * @throws \Illuminate\Auth\Access\AuthorizationException
     */
    public function mount(VpsServer $vps): void
    {
        // Verify tenant access using policy
        Gate::authorize('viewHealth', $vps);

        $this->vps = $vps;
        $this->vpsId = $vps->id;

        // Load initial data
        $this->loadHealth();
        $this->loadStats();
    }

    /**
     * Load health data from the API.
     *
     * @return void
     */
    public function loadHealth(): void
    {
        if (!$this->vps) {
            $this->error = 'VPS server not found';
            return;
        }

        try {
            $this->processing = true;

            $response = Http::timeout(10)
                ->withToken(config('services.api.token'))
                ->get(config('services.api.url') . "/api/v1/vps/{$this->vpsId}/health");

            if ($response->successful()) {
                $this->healthData = $response->json();
                $this->error = null;
            } else {
                $this->error = "Failed to fetch health data: {$response->status()}";
                Log::warning('Failed to fetch VPS health data', [
                    'vps_id' => $this->vpsId,
                    'status' => $response->status(),
                    'body' => $response->body(),
                ]);
            }
        } catch (\Exception $e) {
            $this->error = 'Error fetching health data: ' . $e->getMessage();
            Log::error('Exception fetching VPS health data', [
                'vps_id' => $this->vpsId,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);
        } finally {
            $this->processing = false;
        }
    }

    /**
     * Load statistics data from the API.
     *
     * @return void
     */
    public function loadStats(): void
    {
        if (!$this->vps) {
            $this->error = 'VPS server not found';
            return;
        }

        try {
            $this->processing = true;

            $response = Http::timeout(10)
                ->withToken(config('services.api.token'))
                ->get(config('services.api.url') . "/api/v1/vps/{$this->vpsId}/stats");

            if ($response->successful()) {
                $this->stats = $response->json();
                $this->error = null;
            } else {
                $this->error = "Failed to fetch stats: {$response->status()}";
                Log::warning('Failed to fetch VPS stats', [
                    'vps_id' => $this->vpsId,
                    'status' => $response->status(),
                    'body' => $response->body(),
                ]);
            }
        } catch (\Exception $e) {
            $this->error = 'Error fetching stats: ' . $e->getMessage();
            Log::error('Exception fetching VPS stats', [
                'vps_id' => $this->vpsId,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);
        } finally {
            $this->processing = false;
        }
    }

    /**
     * Manually refresh all data.
     *
     * @return void
     */
    public function refresh(): void
    {
        $this->loadHealth();
        $this->loadStats();
    }

    /**
     * Export health report as PDF.
     *
     * @return \Symfony\Component\HttpFoundation\StreamedResponse
     */
    public function exportPdf(): \Symfony\Component\HttpFoundation\StreamedResponse
    {
        Gate::authorize('viewHealth', $this->vps);

        $filename = "vps-health-{$this->vps->hostname}-" . now()->format('Y-m-d-His') . '.pdf';

        return response()->streamDownload(function () {
            echo $this->generatePdfContent();
        }, $filename, [
            'Content-Type' => 'application/pdf',
        ]);
    }

    /**
     * Export health report as CSV.
     *
     * @return \Symfony\Component\HttpFoundation\StreamedResponse
     */
    public function exportCsv(): \Symfony\Component\HttpFoundation\StreamedResponse
    {
        Gate::authorize('viewHealth', $this->vps);

        $filename = "vps-health-{$this->vps->hostname}-" . now()->format('Y-m-d-His') . '.csv';

        return response()->streamDownload(function () {
            echo $this->generateCsvContent();
        }, $filename, [
            'Content-Type' => 'text/csv',
        ]);
    }

    /**
     * Generate PDF content for health report.
     *
     * @return string
     */
    private function generatePdfContent(): string
    {
        // Simple PDF generation - in production, use a proper PDF library like DomPDF
        $content = "VPS Health Report\n";
        $content .= "==================\n\n";
        $content .= "VPS: {$this->vps->hostname}\n";
        $content .= "IP: {$this->vps->ip_address}\n";
        $content .= "Status: {$this->vps->status}\n";
        $content .= "Generated: " . now()->toDateTimeString() . "\n\n";

        if ($this->healthData) {
            $content .= "Health Status: " . ($this->healthData['status'] ?? 'unknown') . "\n\n";

            if (isset($this->healthData['services'])) {
                $content .= "Services:\n";
                foreach ($this->healthData['services'] as $service => $status) {
                    $content .= "  - {$service}: " . ($status ? 'Running' : 'Down') . "\n";
                }
                $content .= "\n";
            }

            if (isset($this->healthData['resources'])) {
                $content .= "Resources:\n";
                $resources = $this->healthData['resources'];
                $content .= "  - CPU: " . ($resources['cpu_percent'] ?? 'N/A') . "%\n";
                $content .= "  - Memory: " . ($resources['memory_percent'] ?? 'N/A') . "%\n";
                $content .= "  - Disk: " . ($resources['disk_percent'] ?? 'N/A') . "%\n";
            }
        }

        return $content;
    }

    /**
     * Generate CSV content for health report.
     *
     * @return string
     */
    private function generateCsvContent(): string
    {
        $output = fopen('php://output', 'w');

        // Header
        fputcsv($output, ['VPS Health Report']);
        fputcsv($output, ['Generated', now()->toDateTimeString()]);
        fputcsv($output, []);

        // VPS Info
        fputcsv($output, ['Hostname', 'IP Address', 'Status']);
        fputcsv($output, [$this->vps->hostname, $this->vps->ip_address, $this->vps->status]);
        fputcsv($output, []);

        // Health Data
        if ($this->healthData) {
            fputcsv($output, ['Health Status', $this->healthData['status'] ?? 'unknown']);
            fputcsv($output, []);

            if (isset($this->healthData['services'])) {
                fputcsv($output, ['Service', 'Status']);
                foreach ($this->healthData['services'] as $service => $status) {
                    fputcsv($output, [$service, $status ? 'Running' : 'Down']);
                }
                fputcsv($output, []);
            }

            if (isset($this->healthData['resources'])) {
                fputcsv($output, ['Resource', 'Usage']);
                $resources = $this->healthData['resources'];
                fputcsv($output, ['CPU', ($resources['cpu_percent'] ?? 'N/A') . '%']);
                fputcsv($output, ['Memory', ($resources['memory_percent'] ?? 'N/A') . '%']);
                fputcsv($output, ['Disk', ($resources['disk_percent'] ?? 'N/A') . '%']);
            }
        }

        fclose($output);
        return '';
    }

    /**
     * Get overall health status with color coding.
     *
     * @return array{status: string, color: string, icon: string}
     */
    public function getHealthStatusAttribute(): array
    {
        if (!$this->healthData) {
            return [
                'status' => 'Unknown',
                'color' => 'gray',
                'icon' => 'question-mark-circle',
            ];
        }

        $status = $this->healthData['status'] ?? 'unknown';

        return match ($status) {
            'healthy' => [
                'status' => 'Healthy',
                'color' => 'green',
                'icon' => 'check-circle',
            ],
            'warning' => [
                'status' => 'Warning',
                'color' => 'yellow',
                'icon' => 'exclamation-triangle',
            ],
            'critical' => [
                'status' => 'Critical',
                'color' => 'red',
                'icon' => 'x-circle',
            ],
            default => [
                'status' => 'Unknown',
                'color' => 'gray',
                'icon' => 'question-mark-circle',
            ],
        };
    }

    /**
     * Format uptime in human-readable format.
     *
     * @param int $seconds
     * @return string
     */
    public function formatUptime(int $seconds): string
    {
        $days = floor($seconds / 86400);
        $hours = floor(($seconds % 86400) / 3600);
        $minutes = floor(($seconds % 3600) / 60);

        if ($days > 0) {
            return "{$days} days";
        } elseif ($hours > 0) {
            return "{$hours} hours";
        } else {
            return "{$minutes} minutes";
        }
    }

    /**
     * Get sites on this VPS for the current tenant.
     *
     * @return \Illuminate\Database\Eloquent\Collection
     */
    public function getSitesProperty(): \Illuminate\Database\Eloquent\Collection
    {
        return $this->vps->sites()
            ->where('tenant_id', auth()->user()->current_tenant_id)
            ->with(['sslCertificate'])
            ->get();
    }

    /**
     * Get recent alerts for this VPS.
     *
     * @return array
     */
    public function getAlertsProperty(): array
    {
        // In production, this would fetch from an alerts system
        // For now, generate alerts based on current health data
        $alerts = [];

        if (!$this->healthData) {
            return $alerts;
        }

        $resources = $this->healthData['resources'] ?? [];

        if (($resources['disk_percent'] ?? 0) > 80) {
            $alerts[] = [
                'severity' => 'warning',
                'message' => 'Disk usage above 80%',
                'timestamp' => now()->subMinutes(5),
            ];
        }

        if (($resources['memory_percent'] ?? 0) > 85) {
            $alerts[] = [
                'severity' => 'warning',
                'message' => 'Memory usage above 85%',
                'timestamp' => now()->subMinutes(3),
            ];
        }

        if (isset($this->healthData['services'])) {
            foreach ($this->healthData['services'] as $service => $status) {
                if (!$status) {
                    $alerts[] = [
                        'severity' => 'critical',
                        'message' => ucfirst($service) . ' service is down',
                        'timestamp' => now()->subMinutes(1),
                    ];
                }
            }
        }

        return $alerts;
    }

    /**
     * Render the component.
     *
     * @return \Illuminate\View\View
     */
    public function render(): \Illuminate\View\View
    {
        return view('livewire.vps-health-monitor', [
            'healthStatus' => $this->getHealthStatusAttribute(),
            'sites' => $this->getSitesProperty(),
            'alerts' => $this->getAlertsProperty(),
        ]);
    }
}
