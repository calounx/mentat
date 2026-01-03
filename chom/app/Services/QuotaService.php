<?php

declare(strict_types=1);

namespace App\Services;

use App\Events\QuotaExceeded;
use App\Events\QuotaWarning;
use App\Repositories\BackupRepository;
use App\Repositories\SiteRepository;
use App\Repositories\TenantRepository;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Log;

/**
 * Quota Service
 *
 * Handles all business logic related to resource quotas, usage tracking,
 * and tier-based limitations.
 */
class QuotaService
{
    private const CACHE_TTL = 300; // 5 minutes
    private const QUOTA_WARNING_THRESHOLD = 80; // 80%

    private const TIER_LIMITS = [
        'free' => [
            'max_sites' => 1,
            'max_storage_gb' => 1,
            'max_backups_per_site' => 3,
            'max_bandwidth_gb' => 10,
        ],
        'starter' => [
            'max_sites' => 5,
            'max_storage_gb' => 10,
            'max_backups_per_site' => 5,
            'max_bandwidth_gb' => 100,
        ],
        'professional' => [
            'max_sites' => 20,
            'max_storage_gb' => 100,
            'max_backups_per_site' => 20,
            'max_bandwidth_gb' => 500,
        ],
        'enterprise' => [
            'max_sites' => -1, // Unlimited
            'max_storage_gb' => -1, // Unlimited
            'max_backups_per_site' => -1, // Unlimited
            'max_bandwidth_gb' => -1, // Unlimited
        ],
    ];

    public function __construct(
        private readonly TenantRepository $tenantRepository,
        private readonly SiteRepository $siteRepository,
        private readonly BackupRepository $backupRepository
    ) {
    }

    /**
     * Check site quota for a tenant.
     *
     * @param string $tenantId The tenant ID
     * @return array Quota information ['current' => int, 'limit' => int, 'available' => bool]
     * @throws \RuntimeException
     */
    public function checkSiteQuota(string $tenantId): array
    {
        try {
            $tenant = $this->tenantRepository->findById($tenantId);
            if (!$tenant) {
                throw new \RuntimeException('Tenant not found');
            }

            $cacheKey = "quota:sites:{$tenantId}";

            return Cache::remember($cacheKey, self::CACHE_TTL, function () use ($tenant) {
                $limits = $this->getQuotaLimitsByTier($tenant->tier);
                $current = $this->siteRepository->countByTenantId($tenant->id);
                $limit = $limits['max_sites'];

                $available = $limit === -1 || $current < $limit;

                $quota = [
                    'current' => $current,
                    'limit' => $limit,
                    'limit_display' => $limit === -1 ? 'Unlimited' : $limit,
                    'available' => $available,
                    'percentage' => $limit > 0 ? round(($current / $limit) * 100, 2) : 0,
                ];

                // Log warning if approaching limit
                if ($quota['percentage'] >= self::QUOTA_WARNING_THRESHOLD && $limit > 0) {
                    Log::warning('Site quota warning', [
                        'tenant_id' => $tenant->id,
                        'current' => $current,
                        'limit' => $limit,
                        'percentage' => $quota['percentage'],
                    ]);

                    Event::dispatch(new QuotaWarning($tenant, 'sites', $quota));
                }

                // Fire event if quota exceeded
                if (!$available && $limit > 0) {
                    Event::dispatch(new QuotaExceeded($tenant, 'sites', $quota));
                }

                return $quota;
            });
        } catch (\Exception $e) {
            Log::error('Failed to check site quota', [
                'tenant_id' => $tenantId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to check site quota: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Check storage quota for a tenant.
     *
     * @param string $tenantId The tenant ID
     * @return array Storage quota information
     * @throws \RuntimeException
     */
    public function checkStorageQuota(string $tenantId): array
    {
        try {
            $tenant = $this->tenantRepository->findById($tenantId);
            if (!$tenant) {
                throw new \RuntimeException('Tenant not found');
            }

            $cacheKey = "quota:storage:{$tenantId}";

            return Cache::remember($cacheKey, self::CACHE_TTL, function () use ($tenant) {
                $limits = $this->getQuotaLimitsByTier($tenant->tier);
                $usedMb = $this->siteRepository->getTotalStorageByTenantId($tenant->id);
                $limitMb = $limits['max_storage_gb'] * 1024;

                $available = $limits['max_storage_gb'] === -1 || $usedMb < $limitMb;

                $quota = [
                    'used_mb' => $usedMb,
                    'used_gb' => round($usedMb / 1024, 2),
                    'limit_mb' => $limitMb,
                    'limit_gb' => $limits['max_storage_gb'],
                    'limit_display' => $limits['max_storage_gb'] === -1 ? 'Unlimited' : "{$limits['max_storage_gb']} GB",
                    'available' => $available,
                    'percentage' => $limitMb > 0 ? round(($usedMb / $limitMb) * 100, 2) : 0,
                    'remaining_mb' => $limitMb > 0 ? max(0, $limitMb - $usedMb) : -1,
                    'remaining_gb' => $limitMb > 0 ? round(max(0, $limitMb - $usedMb) / 1024, 2) : -1,
                ];

                // Log warning if approaching limit
                if ($quota['percentage'] >= self::QUOTA_WARNING_THRESHOLD && $limitMb > 0) {
                    Log::warning('Storage quota warning', [
                        'tenant_id' => $tenant->id,
                        'used_mb' => $usedMb,
                        'limit_mb' => $limitMb,
                        'percentage' => $quota['percentage'],
                    ]);

                    Event::dispatch(new QuotaWarning($tenant, 'storage', $quota));
                }

                // Fire event if quota exceeded
                if (!$available && $limitMb > 0) {
                    Event::dispatch(new QuotaExceeded($tenant, 'storage', $quota));
                }

                return $quota;
            });
        } catch (\Exception $e) {
            Log::error('Failed to check storage quota', [
                'tenant_id' => $tenantId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to check storage quota: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Check backup quota for a site.
     *
     * @param string $siteId The site ID
     * @return array Backup quota information
     * @throws \RuntimeException
     */
    public function checkBackupQuota(string $siteId): array
    {
        try {
            $site = $this->siteRepository->findById($siteId);
            if (!$site) {
                throw new \RuntimeException('Site not found');
            }

            $tenant = $this->tenantRepository->findById($site->tenant_id);
            if (!$tenant) {
                throw new \RuntimeException('Tenant not found');
            }

            $cacheKey = "quota:backups:{$siteId}";

            return Cache::remember($cacheKey, self::CACHE_TTL, function () use ($site, $tenant) {
                $limits = $this->getQuotaLimitsByTier($tenant->tier);
                $current = $this->backupRepository->countBySiteId($site->id);
                $limit = $limits['max_backups_per_site'];

                $available = $limit === -1 || $current < $limit;

                $quota = [
                    'current' => $current,
                    'limit' => $limit,
                    'limit_display' => $limit === -1 ? 'Unlimited' : $limit,
                    'available' => $available,
                    'percentage' => $limit > 0 ? round(($current / $limit) * 100, 2) : 0,
                ];

                // Log warning if approaching limit
                if ($quota['percentage'] >= self::QUOTA_WARNING_THRESHOLD && $limit > 0) {
                    Log::warning('Backup quota warning', [
                        'site_id' => $site->id,
                        'current' => $current,
                        'limit' => $limit,
                        'percentage' => $quota['percentage'],
                    ]);

                    Event::dispatch(new QuotaWarning($tenant, 'backups', $quota));
                }

                return $quota;
            });
        } catch (\Exception $e) {
            Log::error('Failed to check backup quota', [
                'site_id' => $siteId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to check backup quota: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Update storage usage for a site.
     *
     * @param string $siteId The site ID
     * @param int $usedMb Storage used in megabytes
     * @return void
     * @throws \RuntimeException
     */
    public function updateStorageUsage(string $siteId, int $usedMb): void
    {
        try {
            $site = $this->siteRepository->findById($siteId);
            if (!$site) {
                throw new \RuntimeException('Site not found');
            }

            $this->siteRepository->update($siteId, [
                'storage_used_mb' => $usedMb,
            ]);

            // Clear storage quota cache for tenant
            Cache::forget("quota:storage:{$site->tenant_id}");

            Log::info('Storage usage updated', [
                'site_id' => $siteId,
                'storage_used_mb' => $usedMb,
            ]);

            // Check if storage quota is now exceeded
            $this->checkStorageQuota($site->tenant_id);
        } catch (\Exception $e) {
            Log::error('Failed to update storage usage', [
                'site_id' => $siteId,
                'used_mb' => $usedMb,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to update storage usage: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Get comprehensive tenant usage statistics.
     *
     * @param string $tenantId The tenant ID
     * @return array Usage statistics
     * @throws \RuntimeException
     */
    public function getTenantUsage(string $tenantId): array
    {
        try {
            $tenant = $this->tenantRepository->findById($tenantId);
            if (!$tenant) {
                throw new \RuntimeException('Tenant not found');
            }

            $siteQuota = $this->checkSiteQuota($tenantId);
            $storageQuota = $this->checkStorageQuota($tenantId);

            // Get total backups across all sites
            $sites = $this->siteRepository->findByTenantId($tenantId);
            $totalBackups = 0;

            foreach ($sites as $site) {
                $totalBackups += $this->backupRepository->countBySiteId($site->id);
            }

            $usage = [
                'tenant_id' => $tenantId,
                'tier' => $tenant->tier,
                'sites' => $siteQuota,
                'storage' => $storageQuota,
                'backups' => [
                    'total' => $totalBackups,
                ],
                'limits' => $this->getQuotaLimitsByTier($tenant->tier),
            ];

            Log::debug('Tenant usage retrieved', [
                'tenant_id' => $tenantId,
                'sites_used' => $siteQuota['current'],
                'storage_used_gb' => $storageQuota['used_gb'],
                'total_backups' => $totalBackups,
            ]);

            return $usage;
        } catch (\Exception $e) {
            Log::error('Failed to get tenant usage', [
                'tenant_id' => $tenantId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to get tenant usage: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Check if tenant can create a new site.
     *
     * @param string $tenantId The tenant ID
     * @return bool True if site can be created
     */
    public function canCreateSite(string $tenantId): bool
    {
        try {
            $quota = $this->checkSiteQuota($tenantId);
            return $quota['available'];
        } catch (\Exception $e) {
            Log::error('Failed to check if site can be created', [
                'tenant_id' => $tenantId,
                'error' => $e->getMessage(),
            ]);
            return false;
        }
    }

    /**
     * Check if a backup can be created for a site.
     *
     * @param string $siteId The site ID
     * @return bool True if backup can be created
     */
    public function canCreateBackup(string $siteId): bool
    {
        try {
            $quota = $this->checkBackupQuota($siteId);
            return $quota['available'];
        } catch (\Exception $e) {
            Log::error('Failed to check if backup can be created', [
                'site_id' => $siteId,
                'error' => $e->getMessage(),
            ]);
            return false;
        }
    }

    /**
     * Get quota limits for a specific tier.
     *
     * @param string $tier The tier name
     * @return array Tier limits
     * @throws \RuntimeException
     */
    public function getQuotaLimitsByTier(string $tier): array
    {
        if (!isset(self::TIER_LIMITS[$tier])) {
            Log::warning('Unknown tier, using starter limits', ['tier' => $tier]);
            return self::TIER_LIMITS['starter'];
        }

        return self::TIER_LIMITS[$tier];
    }

    /**
     * Clear all quota caches for a tenant.
     *
     * @param string $tenantId The tenant ID
     * @return void
     */
    public function clearQuotaCache(string $tenantId): void
    {
        Cache::forget("quota:sites:{$tenantId}");
        Cache::forget("quota:storage:{$tenantId}");

        // Also clear backup caches for all sites
        $sites = $this->siteRepository->findByTenantId($tenantId);
        foreach ($sites as $site) {
            Cache::forget("quota:backups:{$site->id}");
        }

        Log::debug('Quota cache cleared', ['tenant_id' => $tenantId]);
    }
}
