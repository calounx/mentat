<?php

namespace App\Livewire\Sites;

use App\Models\Site;
use App\Models\Tenant;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Foundation\Auth\Access\AuthorizesRequests;
use Livewire\Component;
use Livewire\WithPagination;

class SiteList extends Component
{
    use WithPagination, AuthorizesRequests;

    public string $search = '';
    public string $statusFilter = '';
    public ?string $deletingSiteId = null;

    protected $queryString = [
        'search' => ['except' => ''],
        'statusFilter' => ['except' => ''],
    ];

    public function updatingSearch(): void
    {
        $this->resetPage();
    }

    public function updatingStatusFilter(): void
    {
        $this->resetPage();
    }

    public function confirmDelete(string $siteId): void
    {
        $this->deletingSiteId = $siteId;
    }

    public function cancelDelete(): void
    {
        $this->deletingSiteId = null;
    }

    public function deleteSite(): void
    {
        if (!$this->deletingSiteId) {
            return;
        }

        $tenant = $this->getTenant();
        $site = $tenant->sites()->find($this->deletingSiteId);

        if (!$site) {
            $this->deletingSiteId = null;
            return;
        }

        // Authorization check
        $this->authorize('delete', $site);

        try {
            // Delete from VPS if active
            if ($site->vpsServer && $site->status === 'active') {
                $vpsManager = app(VPSManagerBridge::class);
                $vpsManager->deleteSite($site->vpsServer, $site->domain, force: true);
            }

            $site->delete();

            session()->flash('success', "Site {$site->domain} deleted successfully.");
        } catch (\Exception $e) {
            session()->flash('error', 'Failed to delete site: ' . $e->getMessage());
        }

        $this->deletingSiteId = null;
    }

    public function toggleSite(string $siteId): void
    {
        $tenant = $this->getTenant();
        $site = $tenant->sites()->with('vpsServer')->find($siteId);

        if (!$site || !$site->vpsServer) {
            return;
        }

        // Authorization check for enable/disable
        $action = $site->status === 'active' ? 'disable' : 'enable';
        $this->authorize($action, $site);

        try {
            $vpsManager = app(VPSManagerBridge::class);

            if ($site->status === 'active') {
                $result = $vpsManager->disableSite($site->vpsServer, $site->domain);
                if ($result['success']) {
                    $site->update(['status' => 'disabled']);
                    session()->flash('success', "Site {$site->domain} disabled.");
                }
            } else {
                $result = $vpsManager->enableSite($site->vpsServer, $site->domain);
                if ($result['success']) {
                    $site->update(['status' => 'active']);
                    session()->flash('success', "Site {$site->domain} enabled.");
                }
            }
        } catch (\Exception $e) {
            session()->flash('error', 'Failed to toggle site: ' . $e->getMessage());
        }
    }

    private function getTenant(): Tenant
    {
        return auth()->user()->currentTenant();
    }

    public function render()
    {
        $tenant = $this->getTenant();

        $query = $tenant->sites()
            ->with('vpsServer:id,hostname')
            ->orderBy('created_at', 'desc');

        if ($this->search) {
            $query->where('domain', 'like', '%' . $this->search . '%');
        }

        if ($this->statusFilter) {
            $query->where('status', $this->statusFilter);
        }

        $sites = $query->paginate(10);

        return view('livewire.sites.site-list', [
            'sites' => $sites,
        ])->layout('layouts.app', ['title' => 'Sites']);
    }
}
