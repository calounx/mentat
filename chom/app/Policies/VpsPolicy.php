<?php

namespace App\Policies;

use App\Models\User;
use App\Models\VpsServer;

/**
 * VPS Server Policy
 *
 * Authorization policy for VpsServer model operations.
 * Controls access to VPS viewing and management operations.
 *
 * Note: VPS servers are not tenant-scoped directly, but access is controlled
 * through the sites they host. Only users with sites on a VPS can access it.
 *
 * @package App\Policies
 */
class VpsPolicy extends BasePolicy
{
    /**
     * Determine whether the user can view any VPS servers.
     *
     * Members and above can view VPS servers they have sites on.
     *
     * @param User $user
     * @return bool
     */
    public function viewAny(User $user): bool
    {
        if (!$this->isMember($user)) {
            return $this->deny($user, 'viewAny', 'insufficient_role', [
                'required_role' => 'member',
            ]);
        }

        return $this->allow($user, 'viewAny', 'has_member_role');
    }

    /**
     * Determine whether the user can view the VPS server.
     *
     * User must have at least one site on this VPS server.
     *
     * @param User $user
     * @param VpsServer $vps
     * @return bool
     */
    public function view(User $user, VpsServer $vps): bool
    {
        if (!$this->isMember($user)) {
            return $this->deny($user, 'view', 'insufficient_role', [
                'required_role' => 'member',
                'vps_id' => $vps->id,
            ]);
        }

        // Check if user's current tenant has any sites on this VPS
        if (!$this->userHasSiteOnVps($user, $vps)) {
            return $this->deny($user, 'view', 'no_sites_on_vps', [
                'vps_id' => $vps->id,
                'tenant_id' => $user->current_tenant_id,
            ]);
        }

        return $this->allow($user, 'view', 'has_site_on_vps');
    }

    /**
     * Determine whether the user can create VPS servers.
     *
     * Only owners can create VPS servers.
     *
     * @param User $user
     * @return bool
     */
    public function create(User $user): bool
    {
        if (!$this->isOwner($user)) {
            return $this->deny($user, 'create', 'insufficient_role', [
                'required_role' => 'owner',
            ]);
        }

        return $this->allow($user, 'create', 'is_owner');
    }

    /**
     * Determine whether the user can update the VPS server.
     *
     * Only owners can update VPS servers.
     *
     * @param User $user
     * @param VpsServer $vps
     * @return bool
     */
    public function update(User $user, VpsServer $vps): bool
    {
        if (!$this->isOwner($user)) {
            return $this->deny($user, 'update', 'insufficient_role', [
                'required_role' => 'owner',
                'vps_id' => $vps->id,
            ]);
        }

        return $this->allow($user, 'update', 'is_owner');
    }

    /**
     * Determine whether the user can delete the VPS server.
     *
     * Only owners can delete VPS servers.
     *
     * @param User $user
     * @param VpsServer $vps
     * @return bool
     */
    public function delete(User $user, VpsServer $vps): bool
    {
        if (!$this->isOwner($user)) {
            return $this->deny($user, 'delete', 'insufficient_role', [
                'required_role' => 'owner',
                'vps_id' => $vps->id,
            ]);
        }

        return $this->allow($user, 'delete', 'is_owner');
    }

    /**
     * Determine whether the user can view VPS health and stats.
     *
     * User must have at least one site on this VPS server.
     *
     * @param User $user
     * @param VpsServer $vps
     * @return bool
     */
    public function viewMetrics(User $user, VpsServer $vps): bool
    {
        if (!$this->isMember($user)) {
            return $this->deny($user, 'viewMetrics', 'insufficient_role', [
                'required_role' => 'member',
                'vps_id' => $vps->id,
            ]);
        }

        // Check if user's current tenant has any sites on this VPS
        if (!$this->userHasSiteOnVps($user, $vps)) {
            return $this->deny($user, 'viewMetrics', 'no_sites_on_vps', [
                'vps_id' => $vps->id,
                'tenant_id' => $user->current_tenant_id,
            ]);
        }

        return $this->allow($user, 'viewMetrics', 'has_site_on_vps');
    }

    /**
     * Check if user's tenant has any sites on this VPS.
     *
     * @param User $user
     * @param VpsServer $vps
     * @return bool
     */
    private function userHasSiteOnVps(User $user, VpsServer $vps): bool
    {
        if (!$user->current_tenant_id) {
            $this->logAuthorizationFailure($user, 'userHasSiteOnVps', 'no_current_tenant', [
                'vps_id' => $vps->id,
            ]);
            return false;
        }

        // Check if any sites exist for this tenant on this VPS
        $hasSites = \App\Models\Site::where('tenant_id', $user->current_tenant_id)
            ->where('vps_id', $vps->id)
            ->whereNull('deleted_at')
            ->exists();

        if (!$hasSites) {
            $this->logAuthorizationFailure($user, 'userHasSiteOnVps', 'no_sites_found', [
                'vps_id' => $vps->id,
                'tenant_id' => $user->current_tenant_id,
            ]);
        }

        return $hasSites;
    }
}
