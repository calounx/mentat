<?php

namespace App\Livewire\Sites;

use App\Jobs\ProvisionSiteJob;
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

    // Edit modal
    public bool $showEditModal = false;
    public ?string $editingSiteId = null;
    public array $editForm = [
        'php_version' => '8.2',
        'document_root' => '',
    ];
    public ?string $editError = null;
    public ?string $editSuccess = null;

    protected $queryString = [
        'search' => ['except' => ''],
        'statusFilter' => ['except' => ''],
    ];

    protected $rules = [
        'editForm.php_version' => 'required|in:7.4,8.0,8.1,8.2,8.3',
        'editForm.document_root' => 'nullable|string|max:255',
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

    public function openEditModal(string $siteId): void
    {
        $tenant = $this->getTenant();
        $site = $tenant->sites()->find($siteId);

        if (!$site) {
            return;
        }

        $this->editingSiteId = $siteId;
        $this->editForm = [
            'php_version' => $site->php_version,
            'document_root' => $site->document_root ?? '',
        ];
        $this->editError = null;
        $this->showEditModal = true;
    }

    public function closeEditModal(): void
    {
        $this->showEditModal = false;
        $this->editingSiteId = null;
        $this->editError = null;
    }

    public function saveSite(): void
    {
        $this->validate();

        $tenant = $this->getTenant();
        $site = $tenant->sites()->find($this->editingSiteId);

        if (!$site) {
            $this->editError = 'Site not found.';
            return;
        }

        try {
            $this->authorize('update', $site);

            $site->update([
                'php_version' => $this->editForm['php_version'],
                'document_root' => $this->editForm['document_root'] ?: null,
            ]);

            session()->flash('success', "Site {$site->domain} updated successfully.");
            $this->closeEditModal();
        } catch (\Illuminate\Auth\Access\AuthorizationException $e) {
            $this->editError = 'You do not have permission to update this site.';
        } catch (\Exception $e) {
            $this->editError = 'Failed to update site: ' . $e->getMessage();
        }
    }

    public function retrySite(string $siteId): void
    {
        $tenant = $this->getTenant();
        $site = $tenant->sites()->find($siteId);

        if (!$site || $site->status !== 'failed') {
            return;
        }

        try {
            $this->authorize('update', $site);

            // Reset status to creating and dispatch job again
            $site->update(['status' => 'creating']);
            ProvisionSiteJob::dispatch($site);

            session()->flash('success', "Retrying provisioning for {$site->domain}. This may take a few minutes.");
        } catch (\Illuminate\Auth\Access\AuthorizationException $e) {
            session()->flash('error', 'You do not have permission to retry this site.');
        } catch (\Exception $e) {
            session()->flash('error', 'Failed to retry: ' . $e->getMessage());
        }
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
