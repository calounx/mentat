<?php

declare(strict_types=1);

namespace App\Livewire\Admin;

use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\Tenant;
use App\Models\VpsServer;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Livewire\Component;

class AdminDashboard extends Component
{
    public array $stats = [];
    public array $vpsHealthSummary = [];
    public array $recentAlerts = [];
    public bool $isLoading = false;
    public ?string $error = null;

    public function mount(): void
    {
        $this->loadDashboardData();
    }

    public function loadDashboardData(): void
    {
        $this->isLoading = true;
        $this->error = null;

        try {
            // Load system-wide statistics
            $this->stats = $this->getSystemStats();

            // Load VPS health summary
            $this->vpsHealthSummary = $this->getVpsHealthSummary();

            // Load recent alerts (sites with issues, expiring SSL, etc.)
            $this->recentAlerts = $this->getRecentAlerts();

        } catch (\Exception $e) {
            Log::error('Admin dashboard error', [
                'error' => $e->getMessage(),
            ]);
            $this->error = 'Failed to load dashboard data.';
        }

        $this->isLoading = false;
    }

    public function refresh(): void
    {
        // Clear cached data
        Cache::forget('admin.dashboard.stats');
        Cache::forget('admin.dashboard.vps_health');

        $this->loadDashboardData();
    }

    private function getSystemStats(): array
    {
        return Cache::remember('admin.dashboard.stats', 60, function () {
            return [
                'total_vps' => VpsServer::count(),
                'active_vps' => VpsServer::active()->count(),
                'total_tenants' => Tenant::count(),
                'active_tenants' => Tenant::where('status', 'active')->count(),
                'total_sites' => Site::count(),
                'active_sites' => Site::active()->count(),
                'total_backups' => SiteBackup::count(),
                'ssl_expiring_soon' => Site::sslExpiringSoon()->count(),
            ];
        });
    }

    private function getVpsHealthSummary(): array
    {
        return Cache::remember('admin.dashboard.vps_health', 60, function () {
            $vpsServers = VpsServer::all();

            $summary = [
                'healthy' => 0,
                'degraded' => 0,
                'unhealthy' => 0,
                'unknown' => 0,
            ];

            foreach ($vpsServers as $vps) {
                $status = $vps->health_status ?? 'unknown';
                if (isset($summary[$status])) {
                    $summary[$status]++;
                } else {
                    $summary['unknown']++;
                }
            }

            return $summary;
        });
    }

    private function getRecentAlerts(): array
    {
        $alerts = [];

        // Sites with SSL expiring soon
        $expiringSSL = Site::sslExpiringSoon(14)->with('tenant')->limit(5)->get();
        foreach ($expiringSSL as $site) {
            $alerts[] = [
                'type' => 'warning',
                'title' => 'SSL Expiring Soon',
                'message' => "SSL for {$site->domain} expires on " . $site->ssl_expires_at->format('M d, Y'),
                'tenant' => $site->tenant->name ?? 'Unknown',
                'link' => route('admin.sites.index'),
            ];
        }

        // VPS servers with issues
        $unhealthyVps = VpsServer::whereIn('health_status', ['unhealthy', 'degraded'])->limit(5)->get();
        foreach ($unhealthyVps as $vps) {
            $alerts[] = [
                'type' => $vps->health_status === 'unhealthy' ? 'error' : 'warning',
                'title' => 'VPS Health Issue',
                'message' => "{$vps->hostname} is {$vps->health_status}",
                'tenant' => null,
                'link' => route('admin.vps.index'),
            ];
        }

        // Sites in failed state
        $failedSites = Site::where('status', 'failed')->with('tenant')->limit(5)->get();
        foreach ($failedSites as $site) {
            $alerts[] = [
                'type' => 'error',
                'title' => 'Site Failed',
                'message' => "{$site->domain} is in failed state",
                'tenant' => $site->tenant->name ?? 'Unknown',
                'link' => route('admin.sites.index'),
            ];
        }

        // Sort alerts by severity (errors first)
        usort($alerts, function ($a, $b) {
            $priority = ['error' => 0, 'warning' => 1, 'info' => 2];
            return ($priority[$a['type']] ?? 3) <=> ($priority[$b['type']] ?? 3);
        });

        return array_slice($alerts, 0, 10);
    }

    public function render()
    {
        return view('livewire.admin.admin-dashboard')
            ->layout('layouts.admin', ['title' => 'Dashboard']);
    }
}
