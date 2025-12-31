<?php

namespace App\Livewire\Dashboard;

use App\Models\Site;
use App\Models\Tenant;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Livewire\Component;

class Overview extends Component
{
    public ?Tenant $tenant = null;
    public array $stats = [];
    public array $recentSites = [];

    public function mount(): void
    {
        $user = auth()->user();

        if (!$user) {
            return;
        }

        $this->tenant = $user->currentTenant();

        if ($this->tenant) {
            $this->loadStats();
            $this->loadRecentSites();
        }
    }

    public function loadStats(): void
    {
        if (!$this->tenant) {
            $this->stats = [
                'total_sites' => 0,
                'active_sites' => 0,
                'storage_used_mb' => 0,
                'ssl_expiring_soon' => 0,
            ];
            return;
        }

        $this->stats = $this->getCachedDashboardStats();
    }

    /**
     * Get cached dashboard statistics with 5-minute TTL
     * Cache key is tenant-specific to avoid cross-tenant data leaks
     */
    protected function getCachedDashboardStats(): array
    {
        $cacheKey = "tenant:{$this->tenant->id}:dashboard_stats";

        return Cache::remember($cacheKey, 300, function () {
            try {
                // Batch all site stats into a single query using conditional aggregation
                $siteStats = DB::table('sites')
                    ->where('tenant_id', $this->tenant->id)
                    ->selectRaw('
                        COUNT(*) as total_sites,
                        SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) as active_sites,
                        SUM(CASE WHEN ssl_enabled = 1 AND ssl_expiry_date IS NOT NULL AND ssl_expiry_date <= ? THEN 1 ELSE 0 END) as ssl_expiring_soon
                    ', ['active', now()->addDays(30)])
                    ->first();

                return [
                    'total_sites' => (int) ($siteStats->total_sites ?? 0),
                    'active_sites' => (int) ($siteStats->active_sites ?? 0),
                    'storage_used_mb' => $this->tenant->getStorageUsedMb() ?? 0,
                    'ssl_expiring_soon' => (int) ($siteStats->ssl_expiring_soon ?? 0),
                ];
            } catch (\Exception $e) {
                Log::error('Failed to load dashboard stats', [
                    'tenant_id' => $this->tenant->id,
                    'error' => $e->getMessage(),
                ]);

                return [
                    'total_sites' => 0,
                    'active_sites' => 0,
                    'storage_used_mb' => 0,
                    'ssl_expiring_soon' => 0,
                ];
            }
        });
    }

    /**
     * Invalidate dashboard cache for a specific tenant
     * Call this method when site data changes (create, update, delete)
     */
    public static function invalidateDashboardCache(int $tenantId): void
    {
        Cache::forget("tenant:{$tenantId}:dashboard_stats");
    }

    public function loadRecentSites(): void
    {
        if (!$this->tenant) {
            $this->recentSites = [];
            return;
        }

        try {
            $this->recentSites = $this->tenant->sites()
                ->with('vpsServer:id,hostname')
                ->orderBy('created_at', 'desc')
                ->limit(5)
                ->get()
                ->map(fn($site) => [
                    'id' => $site->id,
                    'domain' => $site->domain,
                    'status' => $site->status,
                    'ssl_enabled' => $site->ssl_enabled,
                    'created_at' => $site->created_at->diffForHumans(),
                ])
                ->toArray();
        } catch (\Exception $e) {
            Log::error('Failed to load recent sites', [
                'tenant_id' => $this->tenant->id,
                'error' => $e->getMessage(),
            ]);

            $this->recentSites = [];
        }
    }

    public function render()
    {
        return view('livewire.dashboard.overview')
            ->layout('layouts.app', ['title' => 'Dashboard']);
    }
}
