<?php

declare(strict_types=1);

namespace App\Livewire\Admin;

use App\Models\Site;
use App\Models\VpsServer;
use App\Models\Tenant;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Support\Facades\Log;
use Livewire\Component;
use Livewire\WithPagination;

class SiteOverview extends Component
{
    use WithPagination;

    // Filters
    public string $search = '';
    public string $statusFilter = '';
    public string $typeFilter = '';
    public string $vpsFilter = '';
    public string $tenantFilter = '';
    public bool $sslExpiringOnly = false;

    // Edit modal
    public bool $showEditModal = false;
    public ?string $selectedSiteId = null;
    public array $editFormData = [];

    public ?string $error = null;
    public ?string $success = null;

    protected $rules = [
        'editFormData.php_version' => 'required|string|in:7.4,8.0,8.1,8.2,8.3',
        'editFormData.document_root' => 'nullable|string|max:255',
    ];

    protected $queryString = [
        'search' => ['except' => ''],
        'statusFilter' => ['except' => ''],
        'typeFilter' => ['except' => ''],
        'vpsFilter' => ['except' => ''],
        'tenantFilter' => ['except' => ''],
        'sslExpiringOnly' => ['except' => false, 'as' => 'ssl_expiring'],
    ];

    public function mount(): void
    {
        // Check for URL parameter from dashboard
        if (request()->has('ssl_expiring')) {
            $this->sslExpiringOnly = true;
        }
    }

    public function updatingSearch(): void
    {
        $this->resetPage();
    }

    public function updatingStatusFilter(): void
    {
        $this->resetPage();
    }

    public function updatingTypeFilter(): void
    {
        $this->resetPage();
    }

    public function updatingVpsFilter(): void
    {
        $this->resetPage();
    }

    public function updatingTenantFilter(): void
    {
        $this->resetPage();
    }

    public function toggleSite(string $siteId): void
    {
        try {
            $site = Site::findOrFail($siteId);
            $vps = $site->vpsServer;

            if (!$vps) {
                $this->error = 'VPS server not found for this site.';
                return;
            }

            $bridge = app(VPSManagerBridge::class);

            if ($site->status === 'active') {
                $result = $bridge->disableSite($vps, $site->domain);
                if ($result['success']) {
                    $site->update(['status' => 'disabled']);
                    $this->success = "Site '{$site->domain}' disabled successfully.";
                } else {
                    $this->error = 'Failed to disable site on VPS.';
                }
            } else {
                $result = $bridge->enableSite($vps, $site->domain);
                if ($result['success']) {
                    $site->update(['status' => 'active']);
                    $this->success = "Site '{$site->domain}' enabled successfully.";
                } else {
                    $this->error = 'Failed to enable site on VPS.';
                }
            }
        } catch (\Exception $e) {
            Log::error('Site toggle error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to toggle site: ' . $e->getMessage();
        }
    }

    public function renewSSL(string $siteId): void
    {
        try {
            $site = Site::findOrFail($siteId);
            $vps = $site->vpsServer;

            if (!$vps) {
                $this->error = 'VPS server not found for this site.';
                return;
            }

            $bridge = app(VPSManagerBridge::class);
            $result = $bridge->renewSSL($vps, $site->domain);

            if ($result['success']) {
                $this->success = "SSL renewal initiated for '{$site->domain}'.";
            } else {
                $this->error = 'Failed to renew SSL certificate.';
            }
        } catch (\Exception $e) {
            Log::error('SSL renewal error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to renew SSL: ' . $e->getMessage();
        }
    }

    public function openEditModal(string $siteId): void
    {
        $site = Site::findOrFail($siteId);
        $this->selectedSiteId = $siteId;
        $this->editFormData = [
            'php_version' => $site->php_version,
            'document_root' => $site->document_root ?? '',
        ];
        $this->showEditModal = true;
        $this->error = null;
    }

    public function closeEditModal(): void
    {
        $this->showEditModal = false;
        $this->selectedSiteId = null;
        $this->editFormData = [];
        $this->error = null;
    }

    public function saveSite(): void
    {
        $this->validate();
        $this->error = null;

        try {
            $site = Site::findOrFail($this->selectedSiteId);
            $site->update($this->editFormData);
            $this->success = "Site '{$site->domain}' updated successfully.";
            $this->closeEditModal();
        } catch (\Exception $e) {
            Log::error('Site save error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to update site: ' . $e->getMessage();
        }
    }

    public function deleteSite(string $siteId): void
    {
        try {
            $site = Site::findOrFail($siteId);
            $vps = $site->vpsServer;
            $domain = $site->domain;

            // If VPS is available, try to delete from VPS first
            if ($vps) {
                $bridge = app(VPSManagerBridge::class);
                $result = $bridge->deleteSite($vps, $domain);

                if (!$result['success']) {
                    Log::warning('Failed to delete site from VPS, proceeding with DB deletion', [
                        'domain' => $domain,
                        'error' => $result['error'] ?? 'Unknown error',
                    ]);
                }
            }

            $site->delete();
            $this->success = "Site '{$domain}' deleted successfully.";
        } catch (\Exception $e) {
            Log::error('Site delete error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to delete site: ' . $e->getMessage();
        }
    }

    public function clearFilters(): void
    {
        $this->search = '';
        $this->statusFilter = '';
        $this->typeFilter = '';
        $this->vpsFilter = '';
        $this->tenantFilter = '';
        $this->sslExpiringOnly = false;
        $this->resetPage();
    }

    public function render()
    {
        $query = Site::query()
            ->with(['tenant', 'vpsServer']);

        if ($this->search) {
            $query->where(function ($q) {
                $q->where('domain', 'like', "%{$this->search}%")
                    ->orWhereHas('tenant', function ($t) {
                        $t->where('name', 'like', "%{$this->search}%");
                    });
            });
        }

        if ($this->statusFilter) {
            $query->where('status', $this->statusFilter);
        }

        if ($this->typeFilter) {
            $query->where('site_type', $this->typeFilter);
        }

        if ($this->vpsFilter) {
            $query->where('vps_id', $this->vpsFilter);
        }

        if ($this->tenantFilter) {
            $query->where('tenant_id', $this->tenantFilter);
        }

        if ($this->sslExpiringOnly) {
            $query->sslExpiringSoon(14);
        }

        $sites = $query->orderBy('domain')->paginate(20);

        // Get filter options
        $vpsServers = VpsServer::orderBy('hostname')->get(['id', 'hostname']);
        $tenants = Tenant::orderBy('name')->get(['id', 'name']);

        // Get stats
        $stats = [
            'total' => Site::count(),
            'active' => Site::active()->count(),
            'ssl_enabled' => Site::where('ssl_enabled', true)->count(),
            'ssl_expiring' => Site::sslExpiringSoon(14)->count(),
        ];

        return view('livewire.admin.site-overview', [
            'sites' => $sites,
            'vpsServers' => $vpsServers,
            'tenants' => $tenants,
            'stats' => $stats,
        ])->layout('layouts.admin', ['title' => 'Site Overview']);
    }
}
