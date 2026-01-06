<?php

namespace App\Livewire\Admin;

use App\Models\Organization;
use Illuminate\Foundation\Auth\Access\AuthorizesRequests;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Livewire\Component;
use Livewire\WithPagination;

class OrganizationManagement extends Component
{
    use WithPagination, AuthorizesRequests;

    public string $search = '';
    public string $statusFilter = '';
    public ?string $selectedOrgId = null;
    public bool $showDetailsModal = false;
    public bool $showCreateModal = false;
    public bool $showEditModal = false;
    public array $formData = [];
    public ?string $deletingOrgId = null;
    public array $deleteBlockers = [];
    public ?string $error = null;
    public ?string $success = null;

    protected $queryString = ['search', 'statusFilter'];

    public function mount(): void
    {
        $this->authorize('viewAny', Organization::class);
    }

    public function updatingSearch(): void
    {
        $this->resetPage();
    }

    public function updatingStatusFilter(): void
    {
        $this->resetPage();
    }

    public function clearFilters(): void
    {
        $this->search = '';
        $this->statusFilter = '';
        $this->resetPage();
    }

    public function viewDetails(string $orgId): void
    {
        $this->selectedOrgId = $orgId;
        $this->showDetailsModal = true;
    }

    public function closeDetailsModal(): void
    {
        $this->showDetailsModal = false;
        $this->selectedOrgId = null;
    }

    public function openCreateModal(): void
    {
        $this->authorize('create', Organization::class);

        $this->formData = [
            'name' => '',
            'billing_email' => '',
        ];
        $this->showCreateModal = true;
        $this->error = null;
    }

    public function closeCreateModal(): void
    {
        $this->showCreateModal = false;
        $this->formData = [];
        $this->error = null;
    }

    public function createOrganization(): void
    {
        $this->authorize('create', Organization::class);

        $this->validate([
            'formData.name' => 'required|string|max:255|unique:organizations,name',
            'formData.billing_email' => 'required|email|max:255',
        ]);

        try {
            $organization = Organization::create([
                'name' => $this->formData['name'],
                'slug' => Str::slug($this->formData['name']) . '-' . Str::random(6),
                'billing_email' => $this->formData['billing_email'],
                'status' => 'active',
            ]);

            // Create default tenant
            $organization->tenants()->create([
                'name' => 'Default',
                'slug' => 'default',
                'tier' => 'starter',
                'status' => 'active',
            ]);

            $this->success = "Organization '{$organization->name}' created successfully.";
            $this->closeCreateModal();

            Log::info('Organization created', [
                'organization_id' => $organization->id,
                'created_by' => auth()->id(),
            ]);
        } catch (\Exception $e) {
            Log::error('Organization creation error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to create organization: ' . $e->getMessage();
        }
    }

    public function openEditModal(string $orgId): void
    {
        $organization = Organization::findOrFail($orgId);
        $this->authorize('update', $organization);

        $this->selectedOrgId = $orgId;
        $this->formData = [
            'name' => $organization->name,
            'billing_email' => $organization->billing_email,
        ];
        $this->showEditModal = true;
        $this->error = null;
    }

    public function closeEditModal(): void
    {
        $this->showEditModal = false;
        $this->selectedOrgId = null;
        $this->formData = [];
        $this->error = null;
    }

    public function saveOrganization(): void
    {
        $organization = Organization::findOrFail($this->selectedOrgId);
        $this->authorize('update', $organization);

        $this->validate([
            'formData.name' => 'required|string|max:255|unique:organizations,name,' . $organization->id,
            'formData.billing_email' => 'required|email|max:255',
        ]);

        try {
            $organization->update([
                'name' => $this->formData['name'],
                'billing_email' => $this->formData['billing_email'],
            ]);

            $this->success = "Organization '{$organization->name}' updated successfully.";
            $this->closeEditModal();

            Log::info('Organization updated', [
                'organization_id' => $organization->id,
                'updated_by' => auth()->id(),
            ]);
        } catch (\Exception $e) {
            Log::error('Organization update error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to update organization: ' . $e->getMessage();
        }
    }

    public function confirmDelete(string $orgId): void
    {
        $organization = Organization::findOrFail($orgId);
        $this->authorize('delete', $organization);

        $this->deletingOrgId = $orgId;
        $this->deleteBlockers = $organization->getDeletionBlockers();
    }

    public function cancelDelete(): void
    {
        $this->deletingOrgId = null;
        $this->deleteBlockers = [];
    }

    public function deleteOrganization(): void
    {
        $organization = Organization::findOrFail($this->deletingOrgId);
        $this->authorize('delete', $organization);

        if (!$organization->canBeDeleted()) {
            $this->error = 'Cannot delete organization with active resources.';
            $this->cancelDelete();
            return;
        }

        try {
            $name = $organization->name;
            $organization->delete();

            $this->success = "Organization '{$name}' deleted successfully.";
            $this->cancelDelete();

            Log::info('Organization deleted', [
                'organization_id' => $organization->id,
                'deleted_by' => auth()->id(),
            ]);
        } catch (\Exception $e) {
            Log::error('Organization deletion error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to delete organization: ' . $e->getMessage();
            $this->cancelDelete();
        }
    }

    public function suspendOrganization(string $orgId): void
    {
        $organization = Organization::findOrFail($orgId);
        $this->authorize('update', $organization);

        try {
            $organization->suspend();
            $this->success = "Organization '{$organization->name}' suspended successfully.";

            Log::info('Organization suspended', [
                'organization_id' => $organization->id,
                'suspended_by' => auth()->id(),
            ]);
        } catch (\Exception $e) {
            Log::error('Organization suspension error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to suspend organization: ' . $e->getMessage();
        }
    }

    public function activateOrganization(string $orgId): void
    {
        $organization = Organization::findOrFail($orgId);
        $this->authorize('update', $organization);

        try {
            $organization->activate();
            $this->success = "Organization '{$organization->name}' activated successfully.";

            Log::info('Organization activated', [
                'organization_id' => $organization->id,
                'activated_by' => auth()->id(),
            ]);
        } catch (\Exception $e) {
            Log::error('Organization activation error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to activate organization: ' . $e->getMessage();
        }
    }

    public function render()
    {
        $query = Organization::query()
            ->withCount(['users', 'tenants'])
            ->with('subscription:id,organization_id,stripe_status');

        if ($this->search) {
            $query->where(function($q) {
                $q->where('name', 'like', '%' . $this->search . '%')
                  ->orWhere('billing_email', 'like', '%' . $this->search . '%');
            });
        }

        if ($this->statusFilter) {
            $query->where('status', $this->statusFilter);
        }

        $organizations = $query->orderBy('created_at', 'desc')->paginate(15);

        // Get viewing organization for details modal
        $viewingOrganization = null;
        if ($this->selectedOrgId && $this->showDetailsModal) {
            $viewingOrganization = Organization::with([
                'users:id,name,email,role,organization_id',
                'tenants:id,organization_id,name,tier,status',
                'subscription',
            ])->find($this->selectedOrgId);
        }

        // Stats
        $stats = [
            'total' => Organization::count(),
            'active' => Organization::where('status', 'active')->count(),
            'suspended' => Organization::where('status', 'suspended')->count(),
            'cancelled' => Organization::where('status', 'cancelled')->count(),
        ];

        return view('livewire.admin.organization-management', [
            'organizations' => $organizations,
            'viewingOrganization' => $viewingOrganization,
            'stats' => $stats,
        ])->layout('layouts.app', ['title' => 'Organization Management']);
    }
}
