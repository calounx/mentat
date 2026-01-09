<?php

namespace App\Policies;

use App\Models\User;
use Illuminate\Auth\Access\Response;

class UserPolicy
{
    /**
     * Determine if the user can view another user's profile.
     * Hierarchy: Self → Tenant owner/manager → Org owner/manager → Super admin
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

        // Organization owners and admins can view profiles in their organization
        if ($currentUser->organization_id === $targetUser->organization_id &&
            ($currentUser->isOwner() || $currentUser->isAdmin())) {
            return Response::allow();
        }

        // Tenant-level access: Users can view profiles of users in their shared tenants
        $sharedTenantIds = $currentUser->tenants()->pluck('tenants.id')->toArray();
        $targetTenantIds = $targetUser->tenants()->pluck('tenants.id')->toArray();

        if (!empty(array_intersect($sharedTenantIds, $targetTenantIds))) {
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

    /**
     * Determine if the user can view any users (admin panel).
     * Super admins can view all users system-wide.
     * Organization owners/admins can view their organization's users.
     */
    public function viewAny(User $currentUser): Response
    {
        // Super admins can view all users
        if ($currentUser->is_super_admin) {
            return Response::allow();
        }

        // Organization owners and admins can view their organization's users
        if ($currentUser->isOwner() || $currentUser->isAdmin()) {
            return Response::allow();
        }

        return Response::deny('You do not have permission to view users.');
    }

    /**
     * Determine if the user can create new users.
     */
    public function create(User $currentUser): Response
    {
        // Super admins can create users in any organization
        if ($currentUser->is_super_admin) {
            return Response::allow();
        }

        // Organization owners and admins can create users in their organization
        if ($currentUser->isOwner() || $currentUser->isAdmin()) {
            return Response::allow();
        }

        return Response::deny('You do not have permission to create users.');
    }

    /**
     * Determine if the user can update another user's profile.
     * Hierarchy: Self → Org owner/admin → Super admin
     */
    public function update(User $currentUser, User $targetUser): Response
    {
        // Users cannot update their own profile through admin functions
        // (they use profile settings for that)
        if ($currentUser->id === $targetUser->id) {
            return Response::allow();
        }

        // Super admins can update any profile
        if ($currentUser->is_super_admin) {
            return Response::allow();
        }

        // Must belong to same organization
        if ($currentUser->organization_id !== $targetUser->organization_id) {
            return Response::deny('You can only manage users within your organization.');
        }

        // Organization owners and admins can update profiles in their organization
        if ($currentUser->isOwner() || $currentUser->isAdmin()) {
            return Response::allow();
        }

        return Response::deny('You do not have permission to update this profile.');
    }

    /**
     * Determine if the user can delete another user.
     */
    public function delete(User $currentUser, User $targetUser): Response
    {
        if ($currentUser->id === $targetUser->id) {
            return Response::deny('You cannot delete yourself.');
        }

        if ($currentUser->is_super_admin) {
            return Response::allow();
        }

        if ($currentUser->organization_id !== $targetUser->organization_id) {
            return Response::deny('You can only delete users within your organization.');
        }

        if (!$currentUser->isOwner()) {
            return Response::deny('Only organization owners can delete users.');
        }

        if ($targetUser->isOwner()) {
            return Response::deny('Cannot delete another organization owner.');
        }

        return Response::allow();
    }

    /**
     * Determine if the user can manage tenant assignments for another user.
     */
    public function manageTenantAssignments(User $currentUser, User $targetUser): Response
    {
        return ($currentUser->is_super_admin ||
               ($currentUser->organization_id === $targetUser->organization_id &&
                $currentUser->isAdmin()))
            ? Response::allow()
            : Response::deny('You do not have permission to manage tenant assignments.');
    }

    /**
     * Determine if the user can manage users within a specific tenant.
     * This allows tenant-level user management (future feature).
     */
    public function manageTenantUsers(User $currentUser): Response
    {
        // Super admins can manage all tenant users
        if ($currentUser->is_super_admin) {
            return Response::allow();
        }

        // Organization owners and admins can manage tenant users in their organization
        if ($currentUser->isOwner() || $currentUser->isAdmin()) {
            return Response::allow();
        }

        // Future: Check if user has tenant-level management role
        // This would use the 'role' column in tenant_user pivot table

        return Response::deny('You do not have permission to manage tenant users.');
    }

    /**
     * Determine if the user can manage users within their organization.
     */
    public function manageOrgUsers(User $currentUser): Response
    {
        // Super admins can manage all users
        if ($currentUser->is_super_admin) {
            return Response::allow();
        }

        // Organization owners and admins can manage users in their organization
        if ($currentUser->isOwner() || $currentUser->isAdmin()) {
            return Response::allow();
        }

        return Response::deny('You do not have permission to manage organization users.');
    }
}
