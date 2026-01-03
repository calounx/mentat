<?php

namespace App\Policies;

use App\Models\Site;
use App\Models\User;
use Illuminate\Support\Facades\DB;

/**
 * Site Policy
 *
 * Authorization policy for Site model operations.
 * Controls access to site viewing, creation, updating, and deletion
 * based on user roles and tenant membership.
 *
 * @package App\Policies
 */
class SitePolicy extends BasePolicy
{
    /**
     * Determine whether the user can view any sites.
     *
     * Members and above can view the site list.
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
     * Determine whether the user can view the site.
     *
     * User must be a member or higher and site must belong to their tenant.
     *
     * @param User $user
     * @param Site $site
     * @return bool
     */
    public function view(User $user, Site $site): bool
    {
        if (!$this->isMember($user)) {
            return $this->deny($user, 'view', 'insufficient_role', [
                'required_role' => 'member',
                'site_id' => $site->id,
            ]);
        }

        if (!$this->belongsToTenant($user, $site)) {
            return $this->deny($user, 'view', 'tenant_mismatch', [
                'site_id' => $site->id,
            ]);
        }

        return $this->allow($user, 'view', 'belongs_to_tenant');
    }

    /**
     * Determine whether the user can create sites.
     *
     * User must be a member or higher and must not exceed quota limits.
     *
     * @param User $user
     * @return bool
     */
    public function create(User $user): bool
    {
        if (!$this->isMember($user)) {
            return $this->deny($user, 'create', 'insufficient_role', [
                'required_role' => 'member',
            ]);
        }

        if (!$this->withinQuota($user)) {
            return $this->deny($user, 'create', 'quota_exceeded', [
                'current_tenant_id' => $user->current_tenant_id,
            ]);
        }

        return $this->allow($user, 'create', 'within_quota');
    }

    /**
     * Determine whether the user can update the site.
     *
     * User must be a member or higher and site must belong to their tenant.
     *
     * @param User $user
     * @param Site $site
     * @return bool
     */
    public function update(User $user, Site $site): bool
    {
        if (!$this->isMember($user)) {
            return $this->deny($user, 'update', 'insufficient_role', [
                'required_role' => 'member',
                'site_id' => $site->id,
            ]);
        }

        if (!$this->belongsToTenant($user, $site)) {
            return $this->deny($user, 'update', 'tenant_mismatch', [
                'site_id' => $site->id,
            ]);
        }

        if ($this->isSoftDeleted($site)) {
            return $this->deny($user, 'update', 'site_deleted', [
                'site_id' => $site->id,
            ]);
        }

        return $this->allow($user, 'update', 'belongs_to_tenant');
    }

    /**
     * Determine whether the user can delete the site.
     *
     * User must be admin or higher and site must belong to their tenant.
     *
     * @param User $user
     * @param Site $site
     * @return bool
     */
    public function delete(User $user, Site $site): bool
    {
        if (!$this->canDeleteResource($user)) {
            return $this->deny($user, 'delete', 'insufficient_role', [
                'required_role' => 'admin',
                'site_id' => $site->id,
            ]);
        }

        if (!$this->belongsToTenant($user, $site)) {
            return $this->deny($user, 'delete', 'tenant_mismatch', [
                'site_id' => $site->id,
            ]);
        }

        return $this->allow($user, 'delete', 'admin_owns_tenant');
    }

    /**
     * Determine whether the user can permanently delete the site.
     *
     * Only owners can force delete sites.
     *
     * @param User $user
     * @param Site $site
     * @return bool
     */
    public function forceDelete(User $user, Site $site): bool
    {
        if (!$this->isOwner($user)) {
            return $this->deny($user, 'forceDelete', 'insufficient_role', [
                'required_role' => 'owner',
                'site_id' => $site->id,
            ]);
        }

        if (!$this->belongsToTenant($user, $site)) {
            return $this->deny($user, 'forceDelete', 'tenant_mismatch', [
                'site_id' => $site->id,
            ]);
        }

        return $this->allow($user, 'forceDelete', 'owner_owns_tenant');
    }

    /**
     * Determine whether the user can restore the site.
     *
     * Admins and above can restore soft-deleted sites.
     *
     * @param User $user
     * @param Site $site
     * @return bool
     */
    public function restore(User $user, Site $site): bool
    {
        if (!$this->isAdmin($user)) {
            return $this->deny($user, 'restore', 'insufficient_role', [
                'required_role' => 'admin',
                'site_id' => $site->id,
            ]);
        }

        if (!$this->belongsToTenant($user, $site)) {
            return $this->deny($user, 'restore', 'tenant_mismatch', [
                'site_id' => $site->id,
            ]);
        }

        if (!$this->isSoftDeleted($site)) {
            return $this->deny($user, 'restore', 'not_deleted', [
                'site_id' => $site->id,
            ]);
        }

        if (!$this->withinQuota($user)) {
            return $this->deny($user, 'restore', 'quota_exceeded', [
                'current_tenant_id' => $user->current_tenant_id,
            ]);
        }

        return $this->allow($user, 'restore', 'admin_can_restore');
    }

    /**
     * Check if user's tenant is within site quota.
     *
     * Queries tenant's current site count and tier limits.
     * Returns true if quota allows creation, false otherwise.
     *
     * @param User $user
     * @return bool
     */
    protected function withinQuota(User $user): bool
    {
        if (!$user->current_tenant_id) {
            $this->logAuthorizationFailure($user, 'withinQuota', 'no_current_tenant');
            return false;
        }

        $tenantData = DB::table('tenants')
            ->select('tier')
            ->where('id', $user->current_tenant_id)
            ->first();

        if (!$tenantData) {
            $this->logAuthorizationFailure($user, 'withinQuota', 'tenant_not_found', [
                'tenant_id' => $user->current_tenant_id,
            ]);
            return false;
        }

        $tierLimit = DB::table('tier_limits')
            ->select('max_sites')
            ->where('tier', $tenantData->tier)
            ->first();

        if (!$tierLimit) {
            $this->logAuthorizationFailure($user, 'withinQuota', 'tier_limit_not_found', [
                'tier' => $tenantData->tier,
            ]);
            return false;
        }

        if ($tierLimit->max_sites === -1) {
            return true;
        }

        $currentSiteCount = DB::table('sites')
            ->where('tenant_id', $user->current_tenant_id)
            ->whereNull('deleted_at')
            ->count();

        $withinLimit = $currentSiteCount < $tierLimit->max_sites;

        if (!$withinLimit) {
            $this->logAuthorizationFailure($user, 'withinQuota', 'quota_exceeded', [
                'tenant_id' => $user->current_tenant_id,
                'current_count' => $currentSiteCount,
                'max_sites' => $tierLimit->max_sites,
                'tier' => $tenantData->tier,
            ]);
        }

        return $withinLimit;
    }

    /**
     * Determine whether the user can enable/disable the site.
     *
     * User must be a member or higher and site must belong to their tenant.
     *
     * @param User $user
     * @param Site $site
     * @return bool
     */
    public function toggleStatus(User $user, Site $site): bool
    {
        if (!$this->isMember($user)) {
            return $this->deny($user, 'toggleStatus', 'insufficient_role', [
                'required_role' => 'member',
                'site_id' => $site->id,
            ]);
        }

        if (!$this->belongsToTenant($user, $site)) {
            return $this->deny($user, 'toggleStatus', 'tenant_mismatch', [
                'site_id' => $site->id,
            ]);
        }

        return $this->allow($user, 'toggleStatus', 'belongs_to_tenant');
    }

    /**
     * Determine whether the user can manage SSL certificates.
     *
     * User must be a member or higher and site must belong to their tenant.
     *
     * @param User $user
     * @param Site $site
     * @return bool
     */
    public function manageSSL(User $user, Site $site): bool
    {
        if (!$this->isMember($user)) {
            return $this->deny($user, 'manageSSL', 'insufficient_role', [
                'required_role' => 'member',
                'site_id' => $site->id,
            ]);
        }

        if (!$this->belongsToTenant($user, $site)) {
            return $this->deny($user, 'manageSSL', 'tenant_mismatch', [
                'site_id' => $site->id,
            ]);
        }

        return $this->allow($user, 'manageSSL', 'belongs_to_tenant');
    }

    /**
     * Determine whether the user can view site metrics.
     *
     * User must be a member or higher and site must belong to their tenant.
     *
     * @param User $user
     * @param Site $site
     * @return bool
     */
    public function viewMetrics(User $user, Site $site): bool
    {
        if (!$this->isMember($user)) {
            return $this->deny($user, 'viewMetrics', 'insufficient_role', [
                'required_role' => 'member',
                'site_id' => $site->id,
            ]);
        }

        if (!$this->belongsToTenant($user, $site)) {
            return $this->deny($user, 'viewMetrics', 'tenant_mismatch', [
                'site_id' => $site->id,
            ]);
        }

        return $this->allow($user, 'viewMetrics', 'belongs_to_tenant');
    }
}
