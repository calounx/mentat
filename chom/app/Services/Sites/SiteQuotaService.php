<?php

namespace App\Services\Sites;

use App\Models\Tenant;

/**
 * Site Quota Service
 *
 * Handles quota checking and management for site creation.
 * Encapsulates all business logic related to site limits and quotas.
 */
class SiteQuotaService
{
    /**
     * Check if tenant can create a new site.
     *
     * @param Tenant $tenant The tenant to check
     * @return bool
     */
    public function canCreateSite(Tenant $tenant): bool
    {
        $maxSites = $this->getMaxSites($tenant);

        // -1 indicates unlimited sites
        if ($maxSites === -1) {
            return true;
        }

        return $tenant->sites()->count() < $maxSites;
    }

    /**
     * Ensure tenant can create a site or throw an exception.
     *
     * @param Tenant $tenant The tenant to check
     * @return void
     * @throws \App\Exceptions\QuotaExceededException
     */
    public function ensureCanCreateSite(Tenant $tenant): void
    {
        if (!$this->canCreateSite($tenant)) {
            throw new \App\Exceptions\QuotaExceededException(
                'Site limit exceeded',
                [
                    'current_sites' => $this->getCurrentSiteCount($tenant),
                    'limit' => $this->getMaxSites($tenant),
                ]
            );
        }
    }

    /**
     * Get the maximum number of sites allowed for the tenant.
     *
     * @param Tenant $tenant The tenant
     * @return int Returns -1 for unlimited
     */
    public function getMaxSites(Tenant $tenant): int
    {
        return $tenant->tierLimits?->max_sites ?? 5;
    }

    /**
     * Get the current site count for the tenant.
     *
     * @param Tenant $tenant The tenant
     * @return int
     */
    public function getCurrentSiteCount(Tenant $tenant): int
    {
        return $tenant->sites()->count();
    }

    /**
     * Get the remaining site quota for the tenant.
     *
     * @param Tenant $tenant The tenant
     * @return int|string Returns 'unlimited' or the remaining count
     */
    public function getRemainingQuota(Tenant $tenant): int|string
    {
        $maxSites = $this->getMaxSites($tenant);

        if ($maxSites === -1) {
            return 'unlimited';
        }

        $currentCount = $this->getCurrentSiteCount($tenant);
        return max(0, $maxSites - $currentCount);
    }

    /**
     * Get quota information for the tenant.
     *
     * @param Tenant $tenant The tenant
     * @return array{current: int, limit: int, remaining: int|string, can_create: bool}
     */
    public function getQuotaInfo(Tenant $tenant): array
    {
        return [
            'current' => $this->getCurrentSiteCount($tenant),
            'limit' => $this->getMaxSites($tenant),
            'remaining' => $this->getRemainingQuota($tenant),
            'can_create' => $this->canCreateSite($tenant),
        ];
    }

    /**
     * Check if tenant can create multiple sites.
     *
     * @param Tenant $tenant The tenant
     * @param int $count Number of sites to create
     * @return bool
     */
    public function canCreateMultipleSites(Tenant $tenant, int $count): bool
    {
        $maxSites = $this->getMaxSites($tenant);

        if ($maxSites === -1) {
            return true;
        }

        $currentCount = $this->getCurrentSiteCount($tenant);
        return ($currentCount + $count) <= $maxSites;
    }
}
