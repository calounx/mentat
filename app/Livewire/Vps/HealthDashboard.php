<?php

namespace App\Livewire\Vps;

use App\Models\VpsServer;
use App\Models\Tenant;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Foundation\Auth\Access\AuthorizesRequests;
use Illuminate\Support\Facades\Log;
use Livewire\Component;

class HealthDashboard extends Component
{
    use AuthorizesRequests;

    public ?string $selectedVpsId = null;
    public array $healthData = [];
    public array $dashboardData = [];
    public array $statsData = [];
    public array $securityAuditData = [];

    public bool $isLoading = false;
    public ?string $error = null;
    public ?string $lastUpdated = null;

    /**
     * Ensure the current user has admin privileges.
     * VPS health dashboard is an admin-only feature as it exposes
     * infrastructure details and could show data from other tenants.
     */
    private function ensureAdmin(): void
    {
        $user = auth()->user();

        if (!$user || !$user->isAdmin()) {
            abort(403, 'This action requires administrator privileges.');
        }
    }

    public function mount(?string $vpsId = null): void
    {
        $this->ensureAdmin();

        if ($vpsId) {
            $this->selectedVpsId = $vpsId;
            $this->loadVpsData();
        }
    }

    public function selectVps(string $vpsId): void
    {
        $this->ensureAdmin();

        $this->selectedVpsId = $vpsId;
        $this->loadVpsData();
    }

    public function loadVpsData(): void
    {
        $this->ensureAdmin();

        if (!$this->selectedVpsId) {
            return;
        }

        $vps = $this->getVps();

        if (!$vps) {
            $this->error = 'VPS server not found.';
            return;
        }

        $this->isLoading = true;
        $this->error = null;

        try {
            $bridge = app(VPSManagerBridge::class);

            // Fetch all data from VPS
            $healthResult = $bridge->healthCheck($vps);
            $dashboardResult = $bridge->getDashboard($vps);
            $statsResult = $bridge->getStats($vps);

            $this->healthData = $healthResult['success'] ? ($healthResult['data'] ?? []) : [];
            $this->dashboardData = $dashboardResult['success'] ? ($dashboardResult['data'] ?? []) : [];
            $this->statsData = $statsResult['success'] ? ($statsResult['data'] ?? []) : [];

            if (!$healthResult['success'] && !$dashboardResult['success'] && !$statsResult['success']) {
                $this->error = 'Failed to connect to VPS. Please check the server status.';
            }

            $this->lastUpdated = now()->format('M d, Y H:i:s');

        } catch (\Exception $e) {
            Log::error('VPS health dashboard error', [
                'vps_id' => $this->selectedVpsId,
                'error' => $e->getMessage(),
            ]);
            $this->error = 'Failed to fetch VPS data: ' . $e->getMessage();
        }

        $this->isLoading = false;
    }

    public function runSecurityAudit(): void
    {
        $this->ensureAdmin();

        if (!$this->selectedVpsId) {
            return;
        }

        $vps = $this->getVps();

        if (!$vps) {
            $this->error = 'VPS server not found.';
            return;
        }

        $this->isLoading = true;
        $this->error = null;

        try {
            $bridge = app(VPSManagerBridge::class);
            $result = $bridge->securityAudit($vps);

            if ($result['success']) {
                $this->securityAuditData = $result['data'] ?? [];
                session()->flash('success', 'Security audit completed successfully.');
            } else {
                $this->error = 'Security audit failed. Please try again.';
            }
        } catch (\Exception $e) {
            Log::error('VPS security audit error', [
                'vps_id' => $this->selectedVpsId,
                'error' => $e->getMessage(),
            ]);
            $this->error = 'Security audit failed: ' . $e->getMessage();
        }

        $this->isLoading = false;
    }

    public function refresh(): void
    {
        $this->ensureAdmin();

        $this->loadVpsData();
    }

    private function getVps(): ?VpsServer
    {
        $tenant = $this->getTenant();

        if (!$tenant) {
            return null;
        }

        // Get VPS that the tenant has access to via allocations
        return VpsServer::whereHas('allocations', function ($query) use ($tenant) {
            $query->where('tenant_id', $tenant->id);
        })->find($this->selectedVpsId);
    }

    private function getTenant(): ?Tenant
    {
        return auth()->user()?->currentTenant();
    }

    private function getAccessibleVpsServers()
    {
        $tenant = $this->getTenant();

        if (!$tenant) {
            return collect();
        }

        // Get all VPS servers the tenant has access to
        return VpsServer::whereHas('allocations', function ($query) use ($tenant) {
            $query->where('tenant_id', $tenant->id);
        })->orderBy('hostname')->get();
    }

    public function render()
    {
        $vpsServers = $this->getAccessibleVpsServers();

        return view('livewire.vps.health-dashboard', [
            'vpsServers' => $vpsServers,
        ])->layout('layouts.app', ['title' => 'VPS Health Dashboard']);
    }
}
