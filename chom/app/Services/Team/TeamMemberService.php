<?php

namespace App\Services\Team;

use App\Models\Organization;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Team Member Service
 *
 * Handles team member management operations including
 * role updates, member removal, and member listing.
 */
class TeamMemberService
{
    /**
     * Update a team member's role.
     *
     * @param Organization $organization
     * @param User $member The member to update
     * @param string $newRole The new role
     * @param User $updater The user performing the update
     * @return array{success: bool, message: string}
     */
    public function updateMemberRole(
        Organization $organization,
        User $member,
        string $newRole,
        User $updater
    ): array {
        // Validate permissions
        if (!$this->canUpdateRole($updater, $member, $newRole)) {
            return [
                'success' => false,
                'message' => 'You do not have permission to perform this action',
            ];
        }

        // Cannot modify owner's role
        if ($member->isOwner()) {
            return [
                'success' => false,
                'message' => 'Cannot modify the organization owner\'s role',
            ];
        }

        try {
            $oldRole = $member->role;
            $member->update(['role' => $newRole]);

            Log::info('Team member role updated', [
                'organization_id' => $organization->id,
                'member_id' => $member->id,
                'old_role' => $oldRole,
                'new_role' => $newRole,
                'updated_by' => $updater->id,
            ]);

            return [
                'success' => true,
                'message' => 'Member role updated successfully',
            ];

        } catch (\Exception $e) {
            Log::error('Failed to update member role', [
                'member_id' => $member->id,
                'error' => $e->getMessage(),
            ]);

            return [
                'success' => false,
                'message' => 'Failed to update member role',
            ];
        }
    }

    /**
     * Remove a member from the organization.
     *
     * @param Organization $organization
     * @param User $member The member to remove
     * @param User $remover The user performing the removal
     * @return array{success: bool, message: string}
     */
    public function removeMember(
        Organization $organization,
        User $member,
        User $remover
    ): array {
        // Validate permissions
        if (!$this->canRemoveMember($remover, $member)) {
            return [
                'success' => false,
                'message' => 'You do not have permission to remove this member',
            ];
        }

        // Cannot remove self
        if ($member->id === $remover->id) {
            return [
                'success' => false,
                'message' => 'You cannot remove yourself from the organization',
            ];
        }

        // Cannot remove owner
        if ($member->isOwner()) {
            return [
                'success' => false,
                'message' => 'Cannot remove the organization owner',
            ];
        }

        try {
            DB::transaction(function () use ($member) {
                // Revoke all tokens
                $member->tokens()->delete();

                // Remove from organization
                $member->update([
                    'organization_id' => null,
                    'role' => 'viewer',
                ]);
            });

            Log::info('Team member removed', [
                'organization_id' => $organization->id,
                'member_id' => $member->id,
                'removed_by' => $remover->id,
            ]);

            return [
                'success' => true,
                'message' => 'Member removed successfully',
            ];

        } catch (\Exception $e) {
            Log::error('Failed to remove team member', [
                'member_id' => $member->id,
                'error' => $e->getMessage(),
            ]);

            return [
                'success' => false,
                'message' => 'Failed to remove member',
            ];
        }
    }

    /**
     * Get formatted member list.
     *
     * @param Organization $organization
     * @return \Illuminate\Database\Eloquent\Collection
     */
    public function getMembers(Organization $organization)
    {
        return $organization->users()
            ->orderByRaw("FIELD(role, 'owner', 'admin', 'member', 'viewer')")
            ->orderBy('name')
            ->get();
    }

    /**
     * Get member statistics for the organization.
     *
     * @param Organization $organization
     * @return array{total: int, by_role: array<string, int>}
     */
    public function getMemberStats(Organization $organization): array
    {
        $members = $organization->users;

        $byRole = $members->groupBy('role')->map(fn($group) => $group->count())->toArray();

        return [
            'total' => $members->count(),
            'by_role' => $byRole,
        ];
    }

    /**
     * Check if updater can update member's role.
     *
     * @param User $updater
     * @param User $member
     * @param string $newRole
     * @return bool
     */
    protected function canUpdateRole(User $updater, User $member, string $newRole): bool
    {
        // Must be at least admin
        if (!$updater->isAdmin()) {
            return false;
        }

        // Cannot modify owner
        if ($member->isOwner()) {
            return false;
        }

        // Only owners can promote to admin
        if ($newRole === 'admin' && !$updater->isOwner()) {
            return false;
        }

        // Admins cannot modify other admins
        if ($member->isAdmin() && !$updater->isOwner()) {
            return false;
        }

        return true;
    }

    /**
     * Check if remover can remove member.
     *
     * @param User $remover
     * @param User $member
     * @return bool
     */
    protected function canRemoveMember(User $remover, User $member): bool
    {
        // Must be at least admin
        if (!$remover->isAdmin()) {
            return false;
        }

        // Cannot remove owner
        if ($member->isOwner()) {
            return false;
        }

        // Cannot remove self
        if ($remover->id === $member->id) {
            return false;
        }

        // Only owners can remove admins
        if ($member->isAdmin() && !$remover->isOwner()) {
            return false;
        }

        return true;
    }

    /**
     * Validate role name.
     *
     * @param string $role
     * @param bool $ownerAllowed Whether owner role is allowed
     * @return bool
     */
    public function isValidRole(string $role, bool $ownerAllowed = false): bool
    {
        $validRoles = ['admin', 'member', 'viewer'];

        if ($ownerAllowed) {
            $validRoles[] = 'owner';
        }

        return in_array($role, $validRoles);
    }
}
