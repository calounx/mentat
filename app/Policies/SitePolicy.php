<?php

namespace App\Policies;

use App\Models\Site;
use App\Models\User;
use Illuminate\Auth\Access\Response;

class SitePolicy
{
    /**
     * Determine whether the user can view any sites.
     * All authenticated users in the tenant can view sites.
     */
    public function viewAny(User $user): Response
    {
        return Response::allow();
    }

    /**
     * Determine whether the user can view a specific site.
     * User must belong to the same tenant as the site.
     */
    public function view(User $user, Site $site): Response
    {
        return $this->belongsToTenant($user, $site)
            ? Response::allow()
            : Response::deny('You do not have access to this site.');
    }

    /**
     * Determine whether the user can create sites.
     * Requires user approval, organization approval, tenant approval,
     * plan selection, active tenant status, and proper role permissions.
     */
    public function create(User $user): Response
    {
        $tenant = $user->currentTenant();

        if (! $tenant) {
            return Response::deny('You must be associated with a tenant to create sites.');
        }

        // Check user approval
        if (! $user->isApproved()) {
            return Response::deny('Your account is pending approval.');
        }

        // Check organization approval
        if ($user->organization && ! $user->organization->isApproved()) {
            return Response::deny('Your organization is pending approval.');
        }

        // Check tenant approval
        if (! $tenant->isApproved()) {
            return Response::deny('Your tenant account is pending approval.');
        }

        // Check plan selection
        if (! $tenant->hasPlanSelected()) {
            return Response::deny('You must select a plan before creating sites.');
        }

        // Check tenant status
        if (! $tenant->isActive()) {
            return Response::deny('Your account is currently suspended.');
        }

        // Check role permission
        if (! $user->canManageSites()) {
            return Response::deny('You do not have permission to create sites.');
        }

        // Check quota
        if (! $tenant->canCreateSite()) {
            return Response::deny("You have reached your plan's site limit.");
        }

        return Response::allow();
    }

    /**
     * Determine whether the user can update the site.
     * Only owner, admin, and member roles can update sites they have access to.
     */
    public function update(User $user, Site $site): Response
    {
        if (!$this->belongsToTenant($user, $site)) {
            return Response::deny('You do not have access to this site.');
        }

        if ($user->canManageSites()) {
            return Response::allow();
        }

        return Response::deny('You do not have permission to update sites.');
    }

    /**
     * Determine whether the user can delete the site.
     * Only owner and admin roles can delete sites.
     */
    public function delete(User $user, Site $site): Response
    {
        if (!$this->belongsToTenant($user, $site)) {
            return Response::deny('You do not have access to this site.');
        }

        if ($user->isAdmin()) {
            return Response::allow();
        }

        return Response::deny('You do not have permission to delete sites.');
    }

    /**
     * Determine whether the user can enable the site.
     * Only owner, admin, and member roles can enable sites.
     */
    public function enable(User $user, Site $site): Response
    {
        if (!$this->belongsToTenant($user, $site)) {
            return Response::deny('You do not have access to this site.');
        }

        if ($user->canManageSites()) {
            return Response::allow();
        }

        return Response::deny('You do not have permission to enable sites.');
    }

    /**
     * Determine whether the user can disable the site.
     * Only owner, admin, and member roles can disable sites.
     */
    public function disable(User $user, Site $site): Response
    {
        if (!$this->belongsToTenant($user, $site)) {
            return Response::deny('You do not have access to this site.');
        }

        if ($user->canManageSites()) {
            return Response::allow();
        }

        return Response::deny('You do not have permission to disable sites.');
    }

    /**
     * Determine whether the user can issue SSL for the site.
     * Only owner, admin, and member roles can issue SSL.
     */
    public function issueSSL(User $user, Site $site): Response
    {
        if (!$this->belongsToTenant($user, $site)) {
            return Response::deny('You do not have access to this site.');
        }

        if ($user->canManageSites()) {
            return Response::allow();
        }

        return Response::deny('You do not have permission to issue SSL certificates.');
    }

    /**
     * Check if user belongs to the same tenant as the site.
     */
    private function belongsToTenant(User $user, Site $site): bool
    {
        $userTenant = $user->currentTenant();

        return $userTenant && $site->tenant_id === $userTenant->id;
    }
}
