<?php

declare(strict_types=1);

namespace App\Services;

use App\Events\SiteDeleted;
use App\Events\SiteDisabled;
use App\Events\SiteEnabled;
use App\Events\SiteProvisioned;
use App\Events\SiteUpdated;
use App\Jobs\DeleteSiteJob;
use App\Jobs\IssueSslCertificateJob;
use App\Jobs\ProvisionSiteJob;
use App\Jobs\UpdatePHPVersionJob;
use App\Models\Site;
use App\Repositories\SiteRepository;
use App\Repositories\TenantRepository;
use App\Repositories\VpsServerRepository;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

/**
 * Site Management Service
 *
 * Handles all business logic related to site provisioning, configuration,
 * and lifecycle management.
 */
class SiteManagementService
{
    public function __construct(
        private readonly SiteRepository $siteRepository,
        private readonly TenantRepository $tenantRepository,
        private readonly VpsServerRepository $vpsServerRepository,
        private readonly QuotaService $quotaService
    ) {
    }

    /**
     * Provision a new site for a tenant.
     *
     * @param array $data Site configuration data
     * @param string $tenantId The tenant ID
     * @return Site The newly created site
     * @throws ValidationException
     * @throws \RuntimeException
     */
    public function provisionSite(array $data, string $tenantId): Site
    {
        try {
            // Validate tenant exists and is active
            $tenant = $this->tenantRepository->findById($tenantId);
            if (!$tenant || !$tenant->isActive()) {
                throw new \RuntimeException('Tenant not found or inactive');
            }

            // Check quota limits
            if (!$this->quotaService->canCreateSite($tenantId)) {
                $quota = $this->quotaService->checkSiteQuota($tenantId);
                throw new \RuntimeException(
                    "Site quota exceeded. Current: {$quota['current']}, Limit: {$quota['limit']}"
                );
            }

            // Validate input data
            $validated = $this->validateSiteData($data);

            // Find available VPS server
            $vpsServer = $this->findAvailableVpsServer($tenant->tier);
            if (!$vpsServer) {
                throw new \RuntimeException('No available VPS servers for provisioning');
            }

            // Create site record with 'creating' status
            $siteData = [
                'tenant_id' => $tenantId,
                'vps_id' => $vpsServer->id,
                'domain' => $validated['domain'],
                'site_type' => $validated['site_type'] ?? 'wordpress',
                'php_version' => $validated['php_version'] ?? '8.2',
                'ssl_enabled' => false,
                'status' => 'creating',
                'storage_used_mb' => 0,
                'settings' => $validated['settings'] ?? [],
            ];

            $site = $this->siteRepository->create($siteData);

            Log::info('Site provisioning initiated', [
                'site_id' => $site->id,
                'tenant_id' => $tenantId,
                'domain' => $site->domain,
            ]);

            // Dispatch async provisioning job
            ProvisionSiteJob::dispatch($site);

            // Fire domain event
            Event::dispatch(new SiteProvisioned($site));

            return $site;
        } catch (ValidationException $e) {
            Log::error('Site provisioning validation failed', [
                'tenant_id' => $tenantId,
                'errors' => $e->errors(),
            ]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Site provisioning failed', [
                'tenant_id' => $tenantId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to provision site: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Update site configuration.
     *
     * @param string $siteId The site ID
     * @param array $config Configuration updates
     * @return Site The updated site
     * @throws \RuntimeException
     */
    public function updateSiteConfiguration(string $siteId, array $config): Site
    {
        try {
            $site = $this->siteRepository->findById($siteId);
            if (!$site) {
                throw new \RuntimeException('Site not found');
            }

            // Validate configuration
            $validated = $this->validateConfigurationUpdate($config);

            // Merge existing settings with new config
            $settings = array_merge($site->settings ?? [], $validated['settings'] ?? []);

            $updateData = array_filter([
                'settings' => $settings,
                'document_root' => $validated['document_root'] ?? null,
            ], fn($value) => $value !== null);

            $updatedSite = $this->siteRepository->update($siteId, $updateData);

            Log::info('Site configuration updated', [
                'site_id' => $siteId,
                'updated_fields' => array_keys($updateData),
            ]);

            Event::dispatch(new SiteUpdated($updatedSite, $updateData));

            return $updatedSite;
        } catch (\Exception $e) {
            Log::error('Site configuration update failed', [
                'site_id' => $siteId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to update site configuration: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Change PHP version for a site.
     *
     * @param string $siteId The site ID
     * @param string $version PHP version (e.g., '8.2', '8.3')
     * @return Site The updated site
     * @throws \RuntimeException
     */
    public function changePHPVersion(string $siteId, string $version): Site
    {
        try {
            $site = $this->siteRepository->findById($siteId);
            if (!$site) {
                throw new \RuntimeException('Site not found');
            }

            // Validate PHP version
            $supportedVersions = ['7.4', '8.0', '8.1', '8.2', '8.3'];
            if (!in_array($version, $supportedVersions)) {
                throw new \RuntimeException(
                    'Unsupported PHP version. Supported: ' . implode(', ', $supportedVersions)
                );
            }

            if ($site->php_version === $version) {
                Log::info('PHP version already set', [
                    'site_id' => $siteId,
                    'version' => $version,
                ]);
                return $site;
            }

            // Update to 'updating' status
            $this->siteRepository->update($siteId, ['status' => 'updating']);

            Log::info('PHP version change initiated', [
                'site_id' => $siteId,
                'from_version' => $site->php_version,
                'to_version' => $version,
            ]);

            // Dispatch async job to update PHP version
            UpdatePHPVersionJob::dispatch($site, $version);

            // Return refreshed site
            return $this->siteRepository->findById($siteId);
        } catch (\Exception $e) {
            Log::error('PHP version change failed', [
                'site_id' => $siteId,
                'version' => $version,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to change PHP version: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Enable SSL for a site.
     *
     * @param string $siteId The site ID
     * @return Site The updated site
     * @throws \RuntimeException
     */
    public function enableSSL(string $siteId): Site
    {
        try {
            $site = $this->siteRepository->findById($siteId);
            if (!$site) {
                throw new \RuntimeException('Site not found');
            }

            if ($site->ssl_enabled) {
                Log::info('SSL already enabled', ['site_id' => $siteId]);
                return $site;
            }

            Log::info('SSL enablement initiated', [
                'site_id' => $siteId,
                'domain' => $site->domain,
            ]);

            // Dispatch async job to issue SSL certificate
            IssueSslCertificateJob::dispatch($site);

            return $this->siteRepository->findById($siteId);
        } catch (\Exception $e) {
            Log::error('SSL enablement failed', [
                'site_id' => $siteId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to enable SSL: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Disable a site.
     *
     * @param string $siteId The site ID
     * @param string $reason Reason for disabling
     * @return Site The disabled site
     * @throws \RuntimeException
     */
    public function disableSite(string $siteId, string $reason = ''): Site
    {
        try {
            $site = $this->siteRepository->findById($siteId);
            if (!$site) {
                throw new \RuntimeException('Site not found');
            }

            if ($site->status === 'disabled') {
                Log::info('Site already disabled', ['site_id' => $siteId]);
                return $site;
            }

            $updatedSite = $this->siteRepository->update($siteId, [
                'status' => 'disabled',
            ]);

            Log::warning('Site disabled', [
                'site_id' => $siteId,
                'domain' => $site->domain,
                'reason' => $reason ?: 'No reason provided',
            ]);

            Event::dispatch(new SiteDisabled($updatedSite, $reason));

            return $updatedSite;
        } catch (\Exception $e) {
            Log::error('Site disable failed', [
                'site_id' => $siteId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to disable site: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Enable a previously disabled site.
     *
     * @param string $siteId The site ID
     * @return Site The enabled site
     * @throws \RuntimeException
     */
    public function enableSite(string $siteId): Site
    {
        try {
            $site = $this->siteRepository->findById($siteId);
            if (!$site) {
                throw new \RuntimeException('Site not found');
            }

            if ($site->status === 'active') {
                Log::info('Site already active', ['site_id' => $siteId]);
                return $site;
            }

            $updatedSite = $this->siteRepository->update($siteId, [
                'status' => 'active',
            ]);

            Log::info('Site enabled', [
                'site_id' => $siteId,
                'domain' => $site->domain,
            ]);

            Event::dispatch(new SiteEnabled($updatedSite));

            return $updatedSite;
        } catch (\Exception $e) {
            Log::error('Site enable failed', [
                'site_id' => $siteId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to enable site: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Delete a site.
     *
     * @param string $siteId The site ID
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function deleteSite(string $siteId): bool
    {
        try {
            $site = $this->siteRepository->findById($siteId);
            if (!$site) {
                throw new \RuntimeException('Site not found');
            }

            // Update to 'deleting' status
            $this->siteRepository->update($siteId, ['status' => 'deleting']);

            Log::warning('Site deletion initiated', [
                'site_id' => $siteId,
                'domain' => $site->domain,
                'tenant_id' => $site->tenant_id,
            ]);

            // Dispatch async job to delete site resources
            DeleteSiteJob::dispatch($site);

            Event::dispatch(new SiteDeleted($site));

            return true;
        } catch (\Exception $e) {
            Log::error('Site deletion failed', [
                'site_id' => $siteId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to delete site: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Get site metrics and statistics.
     *
     * @param string $siteId The site ID
     * @return array Site metrics
     * @throws \RuntimeException
     */
    public function getSiteMetrics(string $siteId): array
    {
        try {
            $site = $this->siteRepository->findById($siteId);
            if (!$site) {
                throw new \RuntimeException('Site not found');
            }

            $backupsCount = $site->backups()->count();
            $lastBackup = $site->backups()->latest()->first();
            $storageUsedMb = $site->storage_used_mb ?? 0;

            $metrics = [
                'site_id' => $site->id,
                'domain' => $site->domain,
                'status' => $site->status,
                'php_version' => $site->php_version,
                'ssl_enabled' => $site->ssl_enabled,
                'ssl_expires_at' => $site->ssl_expires_at?->toIso8601String(),
                'ssl_expiring_soon' => $site->isSslExpiringSoon(),
                'storage_used_mb' => $storageUsedMb,
                'storage_used_gb' => round($storageUsedMb / 1024, 2),
                'backups_count' => $backupsCount,
                'last_backup_at' => $lastBackup?->created_at?->toIso8601String(),
                'created_at' => $site->created_at->toIso8601String(),
                'uptime_days' => $site->created_at->diffInDays(now()),
            ];

            Log::debug('Site metrics retrieved', ['site_id' => $siteId]);

            return $metrics;
        } catch (\Exception $e) {
            Log::error('Failed to retrieve site metrics', [
                'site_id' => $siteId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to get site metrics: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Validate site data for creation.
     *
     * @param array $data Site data
     * @return array Validated data
     * @throws ValidationException
     */
    private function validateSiteData(array $data): array
    {
        $validator = Validator::make($data, [
            'domain' => 'required|string|max:255|regex:/^[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,}$/i',
            'site_type' => 'nullable|string|in:wordpress,laravel,static',
            'php_version' => 'nullable|string|in:7.4,8.0,8.1,8.2,8.3',
            'settings' => 'nullable|array',
        ]);

        if ($validator->fails()) {
            throw new ValidationException($validator);
        }

        return $validator->validated();
    }

    /**
     * Validate configuration update data.
     *
     * @param array $config Configuration data
     * @return array Validated data
     * @throws ValidationException
     */
    private function validateConfigurationUpdate(array $config): array
    {
        $validator = Validator::make($config, [
            'settings' => 'nullable|array',
            'document_root' => 'nullable|string|max:255',
        ]);

        if ($validator->fails()) {
            throw new ValidationException($validator);
        }

        return $validator->validated();
    }

    /**
     * Find an available VPS server for site provisioning.
     *
     * @param string $tier Tenant tier
     * @return \App\Models\VpsServer|null
     */
    private function findAvailableVpsServer(string $tier): ?\App\Models\VpsServer
    {
        // For enterprise tier, prefer dedicated VPS
        if ($tier === 'enterprise') {
            $vps = $this->vpsServerRepository->findAvailableVps(minMemoryMb: 8192);
            if ($vps) {
                return $vps;
            }
        }

        // For professional tier, prefer VPS with good resources
        if ($tier === 'professional') {
            $vps = $this->vpsServerRepository->findAvailableVps(minMemoryMb: 4096);
            if ($vps) {
                return $vps;
            }
        }

        // Default: find any available VPS
        return $this->vpsServerRepository->findAvailableVps();
    }
}
