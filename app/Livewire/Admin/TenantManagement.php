<?php

declare(strict_types=1);

namespace App\Livewire\Admin;

use App\Models\Tenant;
use App\Models\Organization;
use App\Models\User;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Livewire\Component;
use Livewire\WithPagination;

class TenantManagement extends Component
{
    use WithPagination;

    // Filters
    public string $search = '';
    public string $tierFilter = '';
    public string $statusFilter = '';

    // Selected tenant for details view
    public ?string $selectedTenantId = null;
    public ?Tenant $selectedTenant = null;
    public bool $showDetailsModal = false;

    // Edit form
    public bool $showEditModal = false;
    public array $editFormData = [];

    // Create form
    public bool $showCreateModal = false;
    public array $createFormData = [
        'name' => '',
        'organization_id' => '',
        'tier' => 'starter',
    ];

    public ?string $error = null;
    public ?string $success = null;

    // User assignment modal
    public bool $showUserModal = false;
    public ?string $userModalTenantId = null;
    public ?Tenant $userModalTenant = null;

    protected $queryString = [
        'search' => ['except' => ''],
        'tierFilter' => ['except' => ''],
        'statusFilter' => ['except' => ''],
    ];

    protected function rules(): array
    {
        return [
            'editFormData.tier' => 'required|in:starter,pro,enterprise',
            'editFormData.status' => 'required|in:active,suspended,cancelled',
            'editFormData.metrics_retention_days' => 'required|integer|min:1|max:365',
            'createFormData.name' => 'required|string|max:255',
            'createFormData.organization_id' => 'required|exists:organizations,id',
            'createFormData.tier' => 'required|in:starter,pro,enterprise',
        ];
    }

    public function updatingSearch(): void
    {
        $this->resetPage();
    }

    public function updatingTierFilter(): void
    {
        $this->resetPage();
    }

    public function updatingStatusFilter(): void
    {
        $this->resetPage();
    }

    public function openCreateModal(): void
    {
        $this->createFormData = [
            'name' => '',
            'organization_id' => '',
            'tier' => 'starter',
        ];
        $this->showCreateModal = true;
        $this->error = null;
    }

    public function closeCreateModal(): void
    {
        $this->showCreateModal = false;
        $this->createFormData = [
            'name' => '',
            'organization_id' => '',
            'tier' => 'starter',
        ];
        $this->error = null;
    }

    public function createTenant(): void
    {
        $this->validate([
            'createFormData.name' => 'required|string|max:255',
            'createFormData.organization_id' => 'required|exists:organizations,id',
            'createFormData.tier' => 'required|in:starter,pro,enterprise',
        ]);

        $this->error = null;

        try {
            $org = Organization::findOrFail($this->createFormData['organization_id']);

            $tenant = Tenant::create([
                'organization_id' => $org->id,
                'name' => $this->createFormData['name'],
                'slug' => \Illuminate\Support\Str::slug($this->createFormData['name']) . '-' . \Illuminate\Support\Str::random(6),
                'tier' => $this->createFormData['tier'],
                'status' => 'active',
            ]);

            $this->success = "Tenant '{$tenant->name}' created successfully.";
            $this->closeCreateModal();
        } catch (\Exception $e) {
            Log::error('Tenant create error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to create tenant: ' . $e->getMessage();
        }
    }

    public function viewDetails(string $tenantId): void
    {
        $this->selectedTenant = Tenant::with(['organization', 'sites', 'vpsAllocations.vps'])
            ->findOrFail($tenantId);
        $this->selectedTenantId = $tenantId;
        $this->showDetailsModal = true;
    }

    public function closeDetailsModal(): void
    {
        $this->showDetailsModal = false;
        $this->selectedTenant = null;
        $this->selectedTenantId = null;
    }

    public function openEditModal(string $tenantId): void
    {
        $tenant = Tenant::findOrFail($tenantId);
        $this->selectedTenantId = $tenantId;
        $this->editFormData = [
            'tier' => $tenant->tier,
            'status' => $tenant->status,
            'metrics_retention_days' => $tenant->metrics_retention_days,
        ];
        $this->showEditModal = true;
        $this->error = null;
    }

    public function closeEditModal(): void
    {
        $this->showEditModal = false;
        $this->selectedTenantId = null;
        $this->editFormData = [];
        $this->error = null;
    }

    public function saveTenant(): void
    {
        $this->validate();
        $this->error = null;

        try {
            $tenant = Tenant::findOrFail($this->selectedTenantId);
            $tenant->update($this->editFormData);
            $this->success = "Tenant '{$tenant->name}' updated successfully.";
            $this->closeEditModal();
        } catch (\Exception $e) {
            Log::error('Tenant save error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to update tenant: ' . $e->getMessage();
        }
    }

    public function updateStatus(string $tenantId, string $status): void
    {
        try {
            $tenant = Tenant::findOrFail($tenantId);
            $tenant->update(['status' => $status]);
            $this->success = "Tenant '{$tenant->name}' status updated to {$status}.";
        } catch (\Exception $e) {
            Log::error('Tenant status update error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to update status: ' . $e->getMessage();
        }
    }

    public function deleteTenant(string $tenantId): void
    {
        try {
            $tenant = Tenant::findOrFail($tenantId);

            // Check if tenant has sites
            if ($tenant->sites()->count() > 0) {
                $this->error = "Cannot delete tenant '{$tenant->name}' because it has {$tenant->sites()->count()} active site(s). Delete the sites first.";
                return;
            }

            $name = $tenant->name;
            $tenant->delete();
            $this->success = "Tenant '{$name}' deleted successfully.";
        } catch (\Exception $e) {
            Log::error('Tenant delete error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to delete tenant: ' . $e->getMessage();
        }
    }

    public function approveTenant(string $tenantId): void
    {
        try {
            $tenant = Tenant::findOrFail($tenantId);
            $tenant->approve(auth()->user());
            $this->success = "Tenant '{$tenant->name}' has been approved. They can now create sites.";
        } catch (\Exception $e) {
            Log::error('Tenant approval error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to approve tenant: ' . $e->getMessage();
        }
    }

    public function revokeApproval(string $tenantId): void
    {
        try {
            $tenant = Tenant::findOrFail($tenantId);
            $tenant->revokeApproval();
            $this->success = "Approval revoked for tenant '{$tenant->name}'. They can no longer create new sites.";
        } catch (\Exception $e) {
            Log::error('Tenant revoke approval error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to revoke approval: ' . $e->getMessage();
        }
    }

    public function openUserModal(string $tenantId): void
    {
        $this->userModalTenant = Tenant::with(['users', 'organization'])
            ->findOrFail($tenantId);
        $this->userModalTenantId = $tenantId;
        $this->showUserModal = true;
        $this->error = null;
    }

    public function closeUserModal(): void
    {
        $this->showUserModal = false;
        $this->userModalTenant = null;
        $this->userModalTenantId = null;
        $this->error = null;
    }

    public function assignUser(string $userId): void
    {
        try {
            $tenant = Tenant::findOrFail($this->userModalTenantId);
            $user = User::findOrFail($userId);

            // Check if user belongs to same organization
            if ($user->organization_id !== $tenant->organization_id) {
                $this->error = 'User must belong to the same organization as the tenant.';
                return;
            }

            // Assign user to tenant
            $tenant->assignUser($user);

            $this->success = "User '{$user->name}' assigned to tenant '{$tenant->name}'.";

            // Refresh modal data
            $this->userModalTenant = Tenant::with(['users', 'organization'])
                ->findOrFail($this->userModalTenantId);

            Log::info('User assigned to tenant', [
                'user_id' => $user->id,
                'tenant_id' => $tenant->id,
                'assigned_by' => auth()->id(),
            ]);
        } catch (\Exception $e) {
            Log::error('User assignment error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to assign user: ' . $e->getMessage();
        }
    }

    public function removeUser(string $userId): void
    {
        try {
            $tenant = Tenant::findOrFail($this->userModalTenantId);
            $user = User::findOrFail($userId);

            // Remove user from tenant
            $tenant->removeUser($user);

            $this->success = "User '{$user->name}' removed from tenant '{$tenant->name}'.";

            // Refresh modal data
            $this->userModalTenant = Tenant::with(['users', 'organization'])
                ->findOrFail($this->userModalTenantId);

            Log::info('User removed from tenant', [
                'user_id' => $user->id,
                'tenant_id' => $tenant->id,
                'removed_by' => auth()->id(),
            ]);
        } catch (\Exception $e) {
            Log::error('User removal error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to remove user: ' . $e->getMessage();
        }
    }

    public function render()
    {
        $query = Tenant::query()
            ->with(['organization'])
            ->withCount(['sites', 'vpsAllocations']);

        if ($this->search) {
            $query->where(function ($q) {
                $q->where('name', 'like', "%{$this->search}%")
                    ->orWhere('slug', 'like', "%{$this->search}%")
                    ->orWhereHas('organization', function ($org) {
                        $org->where('name', 'like', "%{$this->search}%");
                    });
            });
        }

        if ($this->tierFilter) {
            $query->where('tier', $this->tierFilter);
        }

        if ($this->statusFilter) {
            $query->where('status', $this->statusFilter);
        }

        $tenants = $query->orderBy('name')->paginate(15);

        // Get organizations for create modal
        $organizations = Organization::orderBy('name')->get(['id', 'name']);

        // Get organization users for user assignment modal
        $organizationUsers = collect();
        if ($this->showUserModal && $this->userModalTenant) {
            $organizationUsers = User::where('organization_id', $this->userModalTenant->organization_id)
                ->orderBy('name')
                ->get();
        }

        // Get stats for summary
        $stats = [
            'total' => Tenant::count(),
            'active' => Tenant::where('status', 'active')->count(),
            'pending_approval' => Tenant::where('is_approved', false)->count(),
            'by_tier' => Tenant::selectRaw('tier, count(*) as count')
                ->groupBy('tier')
                ->pluck('count', 'tier')
                ->toArray(),
        ];

        return view('livewire.admin.tenant-management', [
            'tenants' => $tenants,
            'stats' => $stats,
            'organizations' => $organizations,
            'organizationUsers' => $organizationUsers,
        ])->layout('layouts.admin', ['title' => 'Tenant Management']);
    }
}
