<?php

namespace App\Policies;

use App\Models\Organization;
use App\Models\User;
use Illuminate\Auth\Access\Response;

class OrganizationPolicy
{
    /**
     * Determine whether the user can view any organizations.
     * Only super admins can view all organizations.
     */
    public function viewAny(User $user): Response
    {
        return $user->is_super_admin
            ? Response::allow()
            : Response::deny('Only super admins can view all organizations.');
    }

    /**
     * Determine whether the user can view the organization.
     * Super admins and organization members can view.
     */
    public function view(User $user, Organization $organization): Response
    {
        return ($user->is_super_admin || $user->organization_id === $organization->id)
            ? Response::allow()
            : Response::deny('You do not have permission to view this organization.');
    }

    /**
     * Determine whether the user can create organizations.
     * Only super admins can create organizations.
     */
    public function create(User $user): Response
    {
        return $user->is_super_admin
            ? Response::allow()
            : Response::deny('Only super admins can create organizations.');
    }

    /**
     * Determine whether the user can update the organization.
     * Super admins or organization owners can update.
     */
    public function update(User $user, Organization $organization): Response
    {
        return ($user->is_super_admin ||
               ($user->organization_id === $organization->id && $user->isOwner()))
            ? Response::allow()
            : Response::deny('You do not have permission to update this organization.');
    }

    /**
     * Determine whether the user can delete the organization.
     * Only super admins can delete, and only if no active resources.
     */
    public function delete(User $user, Organization $organization): Response
    {
        if (!$user->is_super_admin) {
            return Response::deny('Only super admins can delete organizations.');
        }

        if (!$organization->canBeDeleted()) {
            $blockers = implode(', ', $organization->getDeletionBlockers());
            return Response::deny("Cannot delete organization with: {$blockers}");
        }

        return Response::allow();
    }

    /**
     * Determine whether the user can manage members.
     * Super admins or organization admins can manage members.
     */
    public function manageMembers(User $user, Organization $organization): Response
    {
        return ($user->is_super_admin ||
               ($user->organization_id === $organization->id && $user->isAdmin()))
            ? Response::allow()
            : Response::deny('You do not have permission to manage organization members.');
    }

    /**
     * Determine whether the user can restore the organization.
     */
    public function restore(User $user, Organization $organization): Response
    {
        return $user->is_super_admin
            ? Response::allow()
            : Response::deny('Only super admins can restore organizations.');
    }

    /**
     * Determine whether the user can permanently delete the organization.
     */
    public function forceDelete(User $user, Organization $organization): Response
    {
        return $user->is_super_admin
            ? Response::allow()
            : Response::deny('Only super admins can permanently delete organizations.');
    }
}
