<?php

namespace App\Policies;

use App\Models\User;
use App\Models\VpsServer;

/**
 * VPS Server Policy
 *
 * Authorization policy for VPS Server model operations.
 * Controls access to VPS server viewing, monitoring, and management
 * based on user roles and tenant membership.
 *
 * @package App\Policies
 */
class VpsServerPolicy extends BasePolicy
{
    /**
     * Determine whether the user can view any VPS servers.
     *
     * Members and above can view the VPS server list.
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
     * User must be a member or higher.
     * VPS servers are shared resources, so no tenant check is needed here.
     * Access control is enforced at the site level.
     *
     * @param User $user
     * @param VpsServer $vpsServer
     * @return bool
     */
    public function view(User $user, VpsServer $vpsServer): bool
    {
        if (!$this->isMember($user)) {
            return $this->deny($user, 'view', 'insufficient_role', [
                'required_role' => 'member',
                'vps_id' => $vpsServer->id,
            ]);
        }

        return $this->allow($user, 'view', 'has_member_role');
    }

    /**
     * Determine whether the user can view VPS health monitoring.
     *
     * User must be a member or higher to view health metrics.
     *
     * @param User $user
     * @param VpsServer $vpsServer
     * @return bool
     */
    public function viewHealth(User $user, VpsServer $vpsServer): bool
    {
        if (!$this->isMember($user)) {
            return $this->deny($user, 'viewHealth', 'insufficient_role', [
                'required_role' => 'member',
                'vps_id' => $vpsServer->id,
            ]);
        }

        return $this->allow($user, 'viewHealth', 'has_member_role');
    }

    /**
     * Determine whether the user can view VPS statistics.
     *
     * User must be a member or higher to view statistics.
     *
     * @param User $user
     * @param VpsServer $vpsServer
     * @return bool
     */
    public function viewStats(User $user, VpsServer $vpsServer): bool
    {
        if (!$this->isMember($user)) {
            return $this->deny($user, 'viewStats', 'insufficient_role', [
                'required_role' => 'member',
                'vps_id' => $vpsServer->id,
            ]);
        }

        return $this->allow($user, 'viewStats', 'has_member_role');
    }

    /**
     * Determine whether the user can manage the VPS server.
     *
     * Only admins and above can manage VPS servers.
     *
     * @param User $user
     * @param VpsServer $vpsServer
     * @return bool
     */
    public function manage(User $user, VpsServer $vpsServer): bool
    {
        if (!$this->isAdmin($user)) {
            return $this->deny($user, 'manage', 'insufficient_role', [
                'required_role' => 'admin',
                'vps_id' => $vpsServer->id,
            ]);
        }

        return $this->allow($user, 'manage', 'is_admin');
    }
}
