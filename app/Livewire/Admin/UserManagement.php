<?php

namespace App\Livewire\Admin;

use App\Models\Organization;
use App\Models\User;
use Illuminate\Foundation\Auth\Access\AuthorizesRequests;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Livewire\Component;
use Livewire\WithPagination;

class UserManagement extends Component
{
    use WithPagination, AuthorizesRequests;

    public string $search = '';
    public string $organizationFilter = '';
    public string $roleFilter = '';
    public ?string $selectedUserId = null;
    public bool $showDetailsModal = false;
    public bool $showEditModal = false;
    public bool $showCreateModal = false;
    public array $formData = [];
    public ?string $deletingUserId = null;
    public ?string $error = null;
    public ?string $success = null;

    protected $queryString = ['search', 'organizationFilter', 'roleFilter'];

    public function mount(): void
    {
        $this->authorize('viewAny', User::class);
    }

    public function updatingSearch(): void
    {
        $this->resetPage();
    }

    public function updatingOrganizationFilter(): void
    {
        $this->resetPage();
    }

    public function updatingRoleFilter(): void
    {
        $this->resetPage();
    }

    public function clearFilters(): void
    {
        $this->search = '';
        $this->organizationFilter = '';
        $this->roleFilter = '';
        $this->resetPage();
    }

    public function viewDetails(string $userId): void
    {
        $this->selectedUserId = $userId;
        $this->showDetailsModal = true;
    }

    public function closeDetailsModal(): void
    {
        $this->showDetailsModal = false;
        $this->selectedUserId = null;
    }

    public function openCreateModal(): void
    {
        $this->authorize('create', User::class);

        $this->formData = [
            'name' => '',
            'email' => '',
            'password' => '',
            'organization_id' => '',
            'role' => 'member',
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

    public function createUser(): void
    {
        $this->authorize('create', User::class);

        $this->validate([
            'formData.name' => 'required|string|max:255',
            'formData.email' => 'required|email|max:255|unique:users,email',
            'formData.password' => 'required|string|min:8',
            'formData.organization_id' => 'required|exists:organizations,id',
            'formData.role' => 'required|in:owner,admin,member,viewer',
        ]);

        try {
            $user = User::create([
                'name' => $this->formData['name'],
                'email' => $this->formData['email'],
                'password' => Hash::make($this->formData['password']),
                'organization_id' => $this->formData['organization_id'],
                'role' => $this->formData['role'],
            ]);

            // Assign to default tenant of the organization
            $defaultTenant = Organization::find($this->formData['organization_id'])
                ->tenants()
                ->where('slug', 'default')
                ->first();

            if ($defaultTenant) {
                $user->tenants()->attach($defaultTenant->id);
            }

            $this->success = "User '{$user->name}' created successfully.";
            $this->closeCreateModal();

            Log::info('User created', [
                'user_id' => $user->id,
                'created_by' => auth()->id(),
            ]);
        } catch (\Exception $e) {
            Log::error('User creation error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to create user: ' . $e->getMessage();
        }
    }

    public function openEditModal(string $userId): void
    {
        $user = User::findOrFail($userId);
        $this->authorize('update', $user);

        $this->selectedUserId = $userId;
        $this->formData = [
            'name' => $user->name,
            'email' => $user->email,
            'organization_id' => $user->organization_id,
            'role' => $user->role,
        ];
        $this->showEditModal = true;
        $this->error = null;
    }

    public function closeEditModal(): void
    {
        $this->showEditModal = false;
        $this->selectedUserId = null;
        $this->formData = [];
        $this->error = null;
    }

    public function saveUser(): void
    {
        $user = User::findOrFail($this->selectedUserId);
        $this->authorize('update', $user);

        $this->validate([
            'formData.name' => 'required|string|max:255',
            'formData.email' => 'required|email|max:255|unique:users,email,' . $user->id,
            'formData.organization_id' => 'required|exists:organizations,id',
            'formData.role' => 'required|in:owner,admin,member,viewer',
        ]);

        try {
            $user->update([
                'name' => $this->formData['name'],
                'email' => $this->formData['email'],
                'organization_id' => $this->formData['organization_id'],
                'role' => $this->formData['role'],
            ]);

            $this->success = "User '{$user->name}' updated successfully.";
            $this->closeEditModal();

            Log::info('User updated', [
                'user_id' => $user->id,
                'updated_by' => auth()->id(),
            ]);
        } catch (\Exception $e) {
            Log::error('User update error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to update user: ' . $e->getMessage();
        }
    }

    public function confirmDelete(string $userId): void
    {
        $user = User::findOrFail($userId);
        $this->authorize('delete', $user);

        $this->deletingUserId = $userId;
    }

    public function cancelDelete(): void
    {
        $this->deletingUserId = null;
    }

    public function deleteUser(): void
    {
        $user = User::findOrFail($this->deletingUserId);
        $this->authorize('delete', $user);

        try {
            $name = $user->name;
            $user->delete();

            $this->success = "User '{$name}' deleted successfully.";
            $this->cancelDelete();

            Log::info('User deleted', [
                'user_id' => $user->id,
                'deleted_by' => auth()->id(),
            ]);
        } catch (\Exception $e) {
            Log::error('User deletion error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to delete user: ' . $e->getMessage();
            $this->cancelDelete();
        }
    }

    public function render()
    {
        $currentUser = auth()->user();
        $query = User::query()
            ->with(['organization:id,name', 'tenants:id,name,tier,status']);

        // Apply hierarchy-based filtering
        if ($currentUser->is_super_admin) {
            // Super admins see all users - no filtering needed
        } elseif ($currentUser->isOwner() || $currentUser->isAdmin()) {
            // Organization owners/admins only see users in their organization
            $query->where('organization_id', $currentUser->organization_id);
        } else {
            // Regular users should not access this panel (policy will prevent this)
            // But as a safeguard, show only themselves
            $query->where('id', $currentUser->id);
        }

        if ($this->search) {
            $query->where(function($q) {
                $q->where('name', 'like', '%' . $this->search . '%')
                  ->orWhere('email', 'like', '%' . $this->search . '%');
            });
        }

        if ($this->organizationFilter) {
            // For non-super-admins, ensure they can only filter within their org
            if (!$currentUser->is_super_admin) {
                if ($this->organizationFilter == $currentUser->organization_id) {
                    $query->where('organization_id', $this->organizationFilter);
                }
                // Ignore invalid organization filter for non-super-admins
            } else {
                $query->where('organization_id', $this->organizationFilter);
            }
        }

        if ($this->roleFilter) {
            $query->where('role', $this->roleFilter);
        }

        $users = $query->orderBy('created_at', 'desc')->paginate(15);

        // Get viewing user for details modal
        $viewingUser = null;
        if ($this->selectedUserId && $this->showDetailsModal) {
            $viewingUser = User::with([
                'organization:id,name,status',
                'tenants:id,name,tier,status',
            ])->find($this->selectedUserId);
        }

        // Get organizations based on user's access level
        if ($currentUser->is_super_admin) {
            // Super admins see all organizations
            $organizations = Organization::orderBy('name')->get();
        } else {
            // Org owners/admins only see their own organization
            $organizations = Organization::where('id', $currentUser->organization_id)
                ->orderBy('name')
                ->get();
        }

        // Stats - scoped to user's access level
        if ($currentUser->is_super_admin) {
            $stats = [
                'total' => User::count(),
                'owners' => User::where('role', 'owner')->count(),
                'admins' => User::where('role', 'admin')->count(),
                'members' => User::where('role', 'member')->count(),
            ];
        } else {
            // Org owners/admins see stats for their organization only
            $stats = [
                'total' => User::where('organization_id', $currentUser->organization_id)->count(),
                'owners' => User::where('organization_id', $currentUser->organization_id)
                    ->where('role', 'owner')->count(),
                'admins' => User::where('organization_id', $currentUser->organization_id)
                    ->where('role', 'admin')->count(),
                'members' => User::where('organization_id', $currentUser->organization_id)
                    ->where('role', 'member')->count(),
            ];
        }

        return view('livewire.admin.user-management', [
            'users' => $users,
            'viewingUser' => $viewingUser,
            'organizations' => $organizations,
            'stats' => $stats,
        ])->layout('layouts.app', ['title' => 'User Management']);
    }
}
