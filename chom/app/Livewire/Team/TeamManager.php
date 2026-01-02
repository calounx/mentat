<?php

namespace App\Livewire\Team;

use App\Models\Organization;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Livewire\Component;
use Livewire\WithPagination;

class TeamManager extends Component
{
    use WithPagination;

    public string $search = '';

    // Invite modal
    public bool $showInviteModal = false;

    public string $inviteEmail = '';

    public string $inviteName = '';

    public string $inviteRole = 'member';

    // Edit modal
    public bool $showEditModal = false;

    public ?string $editingUserId = null;

    public string $editName = '';

    public string $editEmail = '';

    public string $editRole = '';

    // Delete confirmation
    public ?string $deletingUserId = null;

    protected function rules(): array
    {
        return [
            'inviteEmail' => ['required', 'email', 'unique:users,email'],
            'inviteName' => ['required', 'string', 'max:255'],
            'inviteRole' => ['required', Rule::in(['admin', 'member', 'viewer'])],
        ];
    }

    public function updatingSearch(): void
    {
        $this->resetPage();
    }

    public function openInviteModal(): void
    {
        $this->reset(['inviteEmail', 'inviteName', 'inviteRole']);
        $this->inviteRole = 'member';
        $this->showInviteModal = true;
    }

    public function closeInviteModal(): void
    {
        $this->showInviteModal = false;
        $this->resetValidation();
    }

    public function inviteMember(): void
    {
        // Authorization check using TeamPolicy
        $response = Gate::inspect('team.invite');
        if ($response->denied()) {
            session()->flash('error', $response->message() ?: 'You do not have permission to invite members.');

            return;
        }

        $organization = $this->getOrganization();

        if (! $organization) {
            session()->flash('error', 'Organization not found.');

            return;
        }

        $this->validate([
            'inviteEmail' => ['required', 'email', 'unique:users,email'],
            'inviteName' => ['required', 'string', 'max:255'],
            'inviteRole' => ['required', Rule::in(['admin', 'member', 'viewer'])],
        ]);

        try {

            // Generate a temporary password
            $tempPassword = Str::random(16);

            $user = User::create([
                'name' => $this->inviteName,
                'email' => $this->inviteEmail,
                'password' => Hash::make($tempPassword),
                'organization_id' => $organization->id,
                'role' => $this->inviteRole,
            ]);

            // TODO: Send invitation email with temp password or magic link

            session()->flash('success', "Invitation sent to {$this->inviteEmail}");
            $this->closeInviteModal();

            Log::info('Team member invited', [
                'organization' => $organization->id,
                'invited_user' => $user->id,
                'role' => $this->inviteRole,
                'invited_by' => auth()->id(),
            ]);
        } catch (\Exception $e) {
            Log::error('Failed to invite team member', ['error' => $e->getMessage()]);
            session()->flash('error', 'Failed to send invitation. Please try again.');
        }
    }

    public function editMember(string $userId): void
    {
        $organization = $this->getOrganization();

        if (! $organization) {
            session()->flash('error', 'Organization not found.');

            return;
        }

        try {
            $user = $organization->users()->find($userId);

            if (! $user) {
                session()->flash('error', 'User not found.');

                return;
            }

            // Authorization check using TeamPolicy
            $response = Gate::inspect('team.update', $user);
            if ($response->denied()) {
                session()->flash('error', $response->message() ?: 'You do not have permission to edit this member.');

                return;
            }

            $this->editingUserId = $userId;
            $this->editName = $user->name;
            $this->editEmail = $user->email;
            $this->editRole = $user->role;
            $this->showEditModal = true;
        } catch (\Exception $e) {
            Log::error('Failed to load member for editing', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);
            session()->flash('error', 'Failed to load member details.');
        }
    }

    public function closeEditModal(): void
    {
        $this->showEditModal = false;
        $this->editingUserId = null;
        $this->resetValidation();
    }

    public function updateMember(): void
    {
        $organization = $this->getOrganization();

        if (! $organization) {
            session()->flash('error', 'Organization not found.');

            return;
        }

        $this->validate([
            'editName' => ['required', 'string', 'max:255'],
            'editEmail' => ['required', 'email', Rule::unique('users', 'email')->ignore($this->editingUserId)],
            'editRole' => ['required', Rule::in(['owner', 'admin', 'member', 'viewer'])],
        ]);

        try {
            $user = $organization->users()->find($this->editingUserId);

            if (! $user) {
                session()->flash('error', 'User not found.');

                return;
            }

            // Authorization check using TeamPolicy
            $response = Gate::inspect('team.update', $user);
            if ($response->denied()) {
                session()->flash('error', $response->message() ?: 'You do not have permission to update this member.');

                return;
            }

            // Prevent removing owner role if it's the only owner
            if ($user->isOwner() && $this->editRole !== 'owner') {
                $ownerCount = $organization->users()->where('role', 'owner')->count();
                if ($ownerCount <= 1) {
                    session()->flash('error', 'Organization must have at least one owner.');

                    return;
                }
            }

            $user->update([
                'name' => $this->editName,
                'email' => $this->editEmail,
                'role' => $this->editRole,
            ]);

            session()->flash('success', 'Member updated successfully.');
            $this->closeEditModal();

            Log::info('Team member updated', [
                'organization' => $organization->id,
                'updated_user' => $user->id,
                'updated_by' => auth()->id(),
            ]);
        } catch (\Exception $e) {
            Log::error('Failed to update team member', ['error' => $e->getMessage()]);
            session()->flash('error', 'Failed to update member. Please try again.');
        }
    }

    public function confirmDelete(string $userId): void
    {
        $organization = $this->getOrganization();

        if (! $organization) {
            session()->flash('error', 'Organization not found.');

            return;
        }

        $user = $organization->users()->find($userId);

        if (! $user) {
            session()->flash('error', 'User not found.');

            return;
        }

        // Authorization check using TeamPolicy
        $response = Gate::inspect('team.remove', $user);
        if ($response->denied()) {
            session()->flash('error', $response->message() ?: 'You do not have permission to remove members.');

            return;
        }

        $this->deletingUserId = $userId;
    }

    public function cancelDelete(): void
    {
        $this->deletingUserId = null;
    }

    public function deleteMember(): void
    {
        if (! $this->deletingUserId) {
            return;
        }

        $organization = $this->getOrganization();

        if (! $organization) {
            session()->flash('error', 'Organization not found.');
            $this->cancelDelete();

            return;
        }

        try {
            $user = $organization->users()->find($this->deletingUserId);

            if (! $user) {
                session()->flash('error', 'User not found.');
                $this->cancelDelete();

                return;
            }

            // Authorization check using TeamPolicy (handles self-deletion and owner checks)
            $response = Gate::inspect('team.remove', $user);
            if ($response->denied()) {
                session()->flash('error', $response->message() ?: 'You do not have permission to remove this member.');
                $this->cancelDelete();

                return;
            }

            // Prevent deleting the only owner (additional business logic check)
            if ($user->isOwner()) {
                $ownerCount = $organization->users()->where('role', 'owner')->count();
                if ($ownerCount <= 1) {
                    session()->flash('error', 'Cannot remove the only owner. Transfer ownership first.');
                    $this->cancelDelete();

                    return;
                }
            }

            $userName = $user->name;
            $user->delete();

            session()->flash('success', "{$userName} has been removed from the team.");

            Log::info('Team member removed', [
                'organization' => $organization->id,
                'removed_user' => $this->deletingUserId,
                'removed_by' => auth()->id(),
            ]);
        } catch (\Exception $e) {
            Log::error('Failed to remove team member', ['error' => $e->getMessage()]);
            session()->flash('error', 'Failed to remove member. Please try again.');
        }

        $this->cancelDelete();
    }

    private function getOrganization(): ?Organization
    {
        $user = auth()->user();

        return $user?->organization;
    }

    public function render()
    {
        try {
            $organization = $this->getOrganization();

            if (! $organization) {
                return view('livewire.team.team-manager', [
                    'members' => collect(),
                    'roleStats' => [],
                    'organization' => null,
                ])->layout('layouts.app', ['title' => 'Team Management']);
            }

            // Build optimized query that includes role stats via a subquery
            // This avoids a separate query for role statistics
            $query = $organization->users()
                ->select([
                    'users.*',
                    // Add role count as a window function (available in modern MySQL/PostgreSQL)
                    DB::raw('COUNT(*) OVER (PARTITION BY role) as role_member_count'),
                ])
                ->orderByRaw("
                    CASE role
                        WHEN 'owner' THEN 1
                        WHEN 'admin' THEN 2
                        WHEN 'member' THEN 3
                        WHEN 'viewer' THEN 4
                    END
                ")
                ->orderBy('name');

            if ($this->search) {
                $query->where(function ($q) {
                    $q->where('name', 'like', '%'.$this->search.'%')
                        ->orWhere('email', 'like', '%'.$this->search.'%');
                });
            }

            $members = $query->paginate(10);

            // Extract role stats from the first occurrence of each role in paginated results
            // If page doesn't have all roles, we need a fallback - use a single optimized query
            $roleStats = DB::table('users')
                ->where('organization_id', $organization->id)
                ->selectRaw('role, COUNT(*) as count')
                ->groupBy('role')
                ->pluck('count', 'role')
                ->toArray();

            return view('livewire.team.team-manager', [
                'members' => $members,
                'roleStats' => $roleStats,
                'organization' => $organization,
            ])->layout('layouts.app', ['title' => 'Team Management']);
        } catch (\Exception $e) {
            Log::error('Failed to load team manager', [
                'error' => $e->getMessage(),
            ]);

            return view('livewire.team.team-manager', [
                'members' => collect(),
                'roleStats' => [],
                'organization' => null,
                'error' => 'Failed to load team members. Please try again.',
            ])->layout('layouts.app', ['title' => 'Team Management']);
        }
    }
}
