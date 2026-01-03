<?php

declare(strict_types=1);

namespace App\Modules\SiteHosting\Services;

use App\Models\Site;
use App\Modules\SiteHosting\Contracts\SiteProvisionerInterface;
use App\Modules\SiteHosting\ValueObjects\PhpVersion;
use App\Modules\SiteHosting\ValueObjects\SslCertificate;
use App\Services\SiteManagementService;
use Illuminate\Support\Facades\Log;

/**
 * Site Provisioning Service
 *
 * Orchestrator service that wraps the existing SiteManagementService
 * with module-specific context and implements the module contract.
 */
class SiteProvisioningService implements SiteProvisionerInterface
{
    public function __construct(
        private readonly SiteManagementService $siteManagementService
    ) {
    }

    /**
     * Provision a new site.
     *
     * @param array $data Site configuration
     * @param string $tenantId Tenant ID
     * @return Site Provisioned site
     * @throws \RuntimeException
     */
    public function provision(array $data, string $tenantId): Site
    {
        Log::info('SiteHosting module: Provisioning site', [
            'tenant_id' => $tenantId,
            'domain' => $data['domain'] ?? 'unknown',
        ]);

        return $this->siteManagementService->provisionSite($data, $tenantId);
    }

    /**
     * Update site configuration.
     *
     * @param string $siteId Site ID
     * @param array $config Configuration updates
     * @return Site Updated site
     * @throws \RuntimeException
     */
    public function updateConfiguration(string $siteId, array $config): Site
    {
        Log::info('SiteHosting module: Updating site configuration', [
            'site_id' => $siteId,
        ]);

        return $this->siteManagementService->updateSiteConfiguration($siteId, $config);
    }

    /**
     * Change PHP version for a site.
     *
     * @param string $siteId Site ID
     * @param PhpVersion $version PHP version
     * @return Site Updated site
     * @throws \RuntimeException
     */
    public function changePhpVersion(string $siteId, PhpVersion $version): Site
    {
        Log::info('SiteHosting module: Changing PHP version', [
            'site_id' => $siteId,
            'version' => $version->toString(),
        ]);

        return $this->siteManagementService->changePHPVersion($siteId, $version->toString());
    }

    /**
     * Enable SSL for a site.
     *
     * @param string $siteId Site ID
     * @return SslCertificate SSL certificate details
     * @throws \RuntimeException
     */
    public function enableSsl(string $siteId): SslCertificate
    {
        Log::info('SiteHosting module: Enabling SSL', [
            'site_id' => $siteId,
        ]);

        $site = $this->siteManagementService->enableSSL($siteId);

        return SslCertificate::fromSite($site);
    }

    /**
     * Renew SSL certificate for a site.
     *
     * @param string $siteId Site ID
     * @return SslCertificate Renewed certificate
     * @throws \RuntimeException
     */
    public function renewSsl(string $siteId): SslCertificate
    {
        Log::info('SiteHosting module: Renewing SSL certificate', [
            'site_id' => $siteId,
        ]);

        // For now, re-enable SSL which will renew the certificate
        $site = $this->siteManagementService->enableSSL($siteId);

        return SslCertificate::fromSite($site);
    }

    /**
     * Enable a site.
     *
     * @param string $siteId Site ID
     * @return Site Enabled site
     * @throws \RuntimeException
     */
    public function enable(string $siteId): Site
    {
        Log::info('SiteHosting module: Enabling site', [
            'site_id' => $siteId,
        ]);

        return $this->siteManagementService->enableSite($siteId);
    }

    /**
     * Disable a site.
     *
     * @param string $siteId Site ID
     * @param string $reason Reason for disabling
     * @return Site Disabled site
     * @throws \RuntimeException
     */
    public function disable(string $siteId, string $reason = ''): Site
    {
        Log::info('SiteHosting module: Disabling site', [
            'site_id' => $siteId,
            'reason' => $reason,
        ]);

        return $this->siteManagementService->disableSite($siteId, $reason);
    }

    /**
     * Delete a site.
     *
     * @param string $siteId Site ID
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function delete(string $siteId): bool
    {
        Log::info('SiteHosting module: Deleting site', [
            'site_id' => $siteId,
        ]);

        return $this->siteManagementService->deleteSite($siteId);
    }

    /**
     * Get site metrics.
     *
     * @param string $siteId Site ID
     * @return array Site metrics
     * @throws \RuntimeException
     */
    public function getMetrics(string $siteId): array
    {
        return $this->siteManagementService->getSiteMetrics($siteId);
    }
}
