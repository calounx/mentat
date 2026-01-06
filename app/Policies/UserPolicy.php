<?php

namespace App\Policies;

use App\Models\User;
use Illuminate\Auth\Access\Response;

class UserPolicy
{
    /**
     * Determine if the user can view another user's profile.
     */
    public function view(User $currentUser, User $targetUser): Response
    {
        // Super admins can view any profile
        if ($currentUser->is_super_admin) {
            return Response::allow();
        }

        // Users can view their own profile
        if ($currentUser->id === $targetUser->id) {
            return Response::allow();
        }

        // Organization admins and owners can view profiles in their organization
        if ($currentUser->organization_id === $targetUser->organization_id &&
            ($currentUser->isOwner() || $currentUser->isAdmin())) {
            return Response::allow();
        }

        return Response::deny('You do not have permission to view this profile.');
    }

    /**
     * Determine if the user can update another user's role.
     */
    public function updateRole(User $currentUser, User $targetUser): Response
    {
        // Users cannot edit their own role
        if ($currentUser->id === $targetUser->id) {
            return Response::deny('You cannot edit your own role.');
        }

        // Super admins can update any role
        if ($currentUser->is_super_admin) {
            return Response::allow();
        }

        // Must belong to same organization
        if ($currentUser->organization_id !== $targetUser->organization_id) {
            return Response::deny('You can only manage roles within your organization.');
        }

        // Only owners and admins can update roles
        if (!$currentUser->isOwner() && !$currentUser->isAdmin()) {
            return Response::deny('You do not have permission to manage user roles.');
        }

        // Cannot demote organization owners (unless super admin)
        if ($targetUser->isOwner() && !$currentUser->is_super_admin) {
            return Response::deny('You cannot change the role of an organization owner.');
        }

        // Organization admins cannot promote users to owner
        if ($currentUser->isAdmin() && !$currentUser->isOwner() && request()->input('role') === 'owner') {
            return Response::deny('Only organization owners can promote users to owner role.');
        }

        return Response::allow();
    }
}
