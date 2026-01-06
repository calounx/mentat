<?php

declare(strict_types=1);

namespace App\Livewire\Profile;

use App\Models\User;
use Illuminate\Foundation\Auth\Access\AuthorizesRequests;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\Rules\Password;
use Livewire\Component;

class ProfileSettings extends Component
{
    use AuthorizesRequests;

    public ?string $success = null;
    public ?string $error = null;

    // The user being viewed/edited
    public $viewingUser = null;
    public bool $isViewingSelf = true;

    // Profile fields
    public string $name = '';
    public string $email = '';

    // Password change fields (only for own profile)
    public string $current_password = '';
    public string $new_password = '';
    public string $new_password_confirmation = '';

    // Role editing (admin only)
    public string $role = '';
    public bool $canEditRole = false;
    public ?string $roleError = null;
    public ?string $roleSuccess = null;

    public function mount(?string $userId = null): void
    {
        $currentUser = auth()->user();

        // If no userId provided, view own profile
        if (!$userId) {
            $this->viewingUser = $currentUser;
            $this->isViewingSelf = true;
        } else {
            // Admin viewing another user's profile
            $this->viewingUser = User::findOrFail($userId);
            $this->isViewingSelf = $currentUser->id === $this->viewingUser->id;

            // Check authorization to view this profile
            $this->authorize('view', $this->viewingUser);
        }

        $this->name = $this->viewingUser->name;
        $this->email = $this->viewingUser->email;
        $this->role = $this->viewingUser->role;

        // Determine if current user can edit the target user's role
        $this->canEditRole = !$this->isViewingSelf &&
            ($currentUser->isAdmin() || $currentUser->isOwner() || $currentUser->is_super_admin) &&
            $currentUser->organization_id === $this->viewingUser->organization_id;
    }

    public function updateProfile(): void
    {
        // Only allow updating if viewing own profile or is admin
        if (!$this->isViewingSelf && !auth()->user()->isAdmin()) {
            $this->error = 'You do not have permission to update this profile.';
            return;
        }

        $this->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|email|unique:users,email,' . $this->viewingUser->id,
        ]);

        try {
            $this->viewingUser->update([
                'name' => $this->name,
                'email' => $this->email,
            ]);

            $this->success = 'Profile updated successfully.';
            $this->error = null;

            Log::info('User profile updated', [
                'user_id' => $this->viewingUser->id,
                'updated_by' => auth()->id(),
            ]);
        } catch (\Exception $e) {
            Log::error('Profile update error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to update profile: ' . $e->getMessage();
        }
    }

    public function updatePassword(): void
    {
        // Password can only be changed for own account
        if (!$this->isViewingSelf) {
            $this->error = 'You cannot change another user\'s password.';
            return;
        }

        $this->validate([
            'current_password' => 'required',
            'new_password' => ['required', 'confirmed', Password::min(8)->mixedCase()->numbers()],
        ]);

        try {
            // Verify current password
            if (!Hash::check($this->current_password, $this->viewingUser->password)) {
                $this->addError('current_password', 'The current password is incorrect.');
                return;
            }

            // Update password
            $this->viewingUser->update([
                'password' => Hash::make($this->new_password),
            ]);

            // Clear password fields
            $this->reset(['current_password', 'new_password', 'new_password_confirmation']);

            $this->success = 'Password updated successfully.';
            $this->error = null;

            Log::info('User password changed', [
                'user_id' => $this->viewingUser->id,
            ]);
        } catch (\Exception $e) {
            Log::error('Password update error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to update password: ' . $e->getMessage();
        }
    }

    public function updateRole(): void
    {
        $this->roleError = null;
        $this->roleSuccess = null;

        if (!$this->canEditRole) {
            $this->roleError = 'You do not have permission to edit roles.';
            return;
        }

        $this->validate([
            'role' => 'required|in:owner,admin,member,viewer',
        ]);

        try {
            // Check authorization using policy
            $this->authorize('updateRole', $this->viewingUser);

            $oldRole = $this->viewingUser->role;
            $this->viewingUser->update(['role' => $this->role]);

            $this->roleSuccess = "Role updated successfully from {$oldRole} to {$this->role}.";

            Log::info('User role updated', [
                'user_id' => $this->viewingUser->id,
                'old_role' => $oldRole,
                'new_role' => $this->role,
                'updated_by' => auth()->id(),
            ]);
        } catch (\Illuminate\Auth\Access\AuthorizationException $e) {
            $this->roleError = $e->getMessage();
        } catch (\Exception $e) {
            Log::error('Role update error', [
                'error' => $e->getMessage(),
                'user_id' => $this->viewingUser->id,
            ]);
            $this->roleError = 'Failed to update role: ' . $e->getMessage();
        }
    }

    public function render()
    {
        $availableRoles = ['owner', 'admin', 'member', 'viewer'];

        // Load user's tenants and sites
        $userTenants = $this->viewingUser->tenants()
            ->with(['sites'])
            ->orderBy('name')
            ->get();

        // Count total accessible sites across all tenants
        $totalSites = $userTenants->sum(function ($tenant) {
            return $tenant->sites->count();
        });

        return view('livewire.profile.profile-settings', [
            'availableRoles' => $availableRoles,
            'userTenants' => $userTenants,
            'totalSites' => $totalSites,
        ])->layout('layouts.app', ['title' => $this->isViewingSelf ? 'Profile Settings' : 'User Profile']);
    }
}
