<?php

namespace App\Policies;

use App\Models\User;
use App\Models\VpsServer;
use Illuminate\Auth\Access\Response;

/**
 * VPS Server Policy
 *
 * Defines authorization rules for VPS server management.
 *
 * Access Control:
 * - View: All authenticated users in tenant
 * - Create: Admin and Owner roles only
 * - Update: Admin and Owner roles only
 * - Delete: Owner role only (critical operation)
 *
 * Tenant Isolation:
 * - Shared VPS: Accessible by all tenants
 * - Dedicated VPS: Only accessible by allocated tenant
 *
 * @package App\Policies
 */
class VpsPolicy
{
    /**
     * Determine whether the user can view any VPS servers.
     *
     * All authenticated users can view VPS servers allocated to their tenant.
     */
    public function viewAny(User $user): Response
    {
        return Response::allow();
    }

    /**
     * Determine whether the user can view a specific VPS server.
     *
     * Users can view:
     * - Shared VPS servers
     * - Dedicated VPS servers allocated to their tenant
     */
    public function view(User $user, VpsServer $vps): Response
    {
        // Shared VPS are visible to all
        if ($vps->isShared()) {
            return Response::allow();
        }

        // Dedicated VPS: Check tenant allocation
        if ($this->hasAccess($user, $vps)) {
            return Response::allow();
        }

        return Response::deny('You do not have access to this VPS server.');
    }

    /**
     * Determine whether the user can create VPS servers.
     *
     * Only admin and owner roles can create VPS servers.
     * This is a sensitive operation that affects infrastructure.
     */
    public function create(User $user): Response
    {
        if ($user->isAdmin()) {
            return Response::allow();
        }

        return Response::deny('Only administrators can create VPS servers.');
    }

    /**
     * Determine whether the user can update the VPS server.
     *
     * Only admin and owner roles can update VPS configuration.
     * User must have access to the VPS (tenant check).
     */
    public function update(User $user, VpsServer $vps): Response
    {
        if (!$this->hasAccess($user, $vps)) {
            return Response::deny('You do not have access to this VPS server.');
        }

        if ($user->isAdmin()) {
            return Response::allow();
        }

        return Response::deny('Only administrators can update VPS servers.');
    }

    /**
     * Determine whether the user can delete the VPS server.
     *
     * CRITICAL OPERATION: Only owner role can delete VPS servers.
     * Deletion protection enforced in controller (prevents deletion with active sites).
     */
    public function delete(User $user, VpsServer $vps): Response
    {
        if (!$this->hasAccess($user, $vps)) {
            return Response::deny('You do not have access to this VPS server.');
        }

        if ($user->isOwner()) {
            return Response::allow();
        }

        return Response::deny('Only account owners can delete VPS servers.');
    }

    /**
     * Determine whether the user can rotate SSH keys for the VPS.
     *
     * SECURITY OPERATION: Only admin and owner roles.
     */
    public function rotateKeys(User $user, VpsServer $vps): Response
    {
        if (!$this->hasAccess($user, $vps)) {
            return Response::deny('You do not have access to this VPS server.');
        }

        if ($user->isAdmin()) {
            return Response::allow();
        }

        return Response::deny('Only administrators can rotate SSH keys.');
    }

    /**
     * Determine whether the user can manage allocations.
     *
     * Only admin and owner roles can modify VPS allocations.
     */
    public function manageAllocations(User $user, VpsServer $vps): Response
    {
        if ($user->isAdmin()) {
            return Response::allow();
        }

        return Response::deny('Only administrators can manage VPS allocations.');
    }

    // =========================================================================
    // PRIVATE HELPERS
    // =========================================================================

    /**
     * Check if user has access to the VPS server.
     *
     * Access rules:
     * - Shared VPS: All users have access
     * - Dedicated VPS: Only users in allocated tenant
     *
     * @param User $user
     * @param VpsServer $vps
     * @return bool
     */
    private function hasAccess(User $user, VpsServer $vps): bool
    {
        // Shared VPS accessible to all
        if ($vps->isShared()) {
            return true;
        }

        // Dedicated VPS: Check tenant allocation
        $userTenant = $user->currentTenant();
        if (!$userTenant) {
            return false;
        }

        // Check if VPS has allocation for user's tenant
        return $vps->allocations()
            ->where('tenant_id', $userTenant->id)
            ->exists();
    }
}
