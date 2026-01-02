<?php

namespace App\Policies;

use App\Models\Organization;
use App\Models\User;
use Illuminate\Auth\Access\Response;

class TeamPolicy
{
    /**
     * Determine whether the user can view team members.
     * All authenticated users in the organization can view members.
     */
    public function viewAny(User $user): Response
    {
        return Response::allow();
    }

    /**
     * Determine whether the user can invite new members.
     * Only owner and admin roles can invite members.
     */
    public function invite(User $user): Response
    {
        if ($user->isAdmin()) {
            return Response::allow();
        }

        return Response::deny('You do not have permission to invite members.');
    }

    /**
     * Determine whether the user can update a team member.
     * Only owner and admin roles can update members.
     * Owners cannot be modified by admins.
     */
    public function update(User $user, User $member): Response
    {
        if (! $this->belongsToOrganization($user, $member)) {
            return Response::deny('You do not have access to this member.');
        }

        // Only owner can modify another owner
        if ($member->isOwner() && ! $user->isOwner()) {
            return Response::deny('Only the owner can modify owner settings.');
        }

        if ($user->isAdmin()) {
            return Response::allow();
        }

        return Response::deny('You do not have permission to update members.');
    }

    /**
     * Determine whether the user can remove a team member.
     * Only owner and admin roles can remove members.
     * Users cannot remove themselves.
     * The last owner cannot be removed.
     */
    public function remove(User $user, User $member): Response
    {
        if (! $this->belongsToOrganization($user, $member)) {
            return Response::deny('You do not have access to this member.');
        }

        // Prevent self-deletion
        if ($user->id === $member->id) {
            return Response::deny('You cannot remove yourself from the team.');
        }

        // Only owner can remove another owner
        if ($member->isOwner() && ! $user->isOwner()) {
            return Response::deny('Only the owner can remove other owners.');
        }

        if ($user->isAdmin()) {
            return Response::allow();
        }

        return Response::deny('You do not have permission to remove members.');
    }

    /**
     * Check if both users belong to the same organization.
     */
    private function belongsToOrganization(User $user, User $member): bool
    {
        return $user->organization_id === $member->organization_id;
    }
}
