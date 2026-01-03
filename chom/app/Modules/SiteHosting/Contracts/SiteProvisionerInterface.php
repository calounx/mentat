<?php

declare(strict_types=1);

namespace App\Modules\SiteHosting\Contracts;

use App\Models\Site;
use App\Modules\SiteHosting\ValueObjects\PhpVersion;
use App\Modules\SiteHosting\ValueObjects\SslCertificate;

/**
 * Site Provisioner Service Contract
 *
 * Defines the contract for site provisioning and management operations.
 */
interface SiteProvisionerInterface
{
    /**
     * Provision a new site.
     *
     * @param array $data Site configuration
     * @param string $tenantId Tenant ID
     * @return Site Provisioned site
     * @throws \RuntimeException
     */
    public function provision(array $data, string $tenantId): Site;

    /**
     * Update site configuration.
     *
     * @param string $siteId Site ID
     * @param array $config Configuration updates
     * @return Site Updated site
     * @throws \RuntimeException
     */
    public function updateConfiguration(string $siteId, array $config): Site;

    /**
     * Change PHP version for a site.
     *
     * @param string $siteId Site ID
     * @param PhpVersion $version PHP version
     * @return Site Updated site
     * @throws \RuntimeException
     */
    public function changePhpVersion(string $siteId, PhpVersion $version): Site;

    /**
     * Enable SSL for a site.
     *
     * @param string $siteId Site ID
     * @return SslCertificate SSL certificate details
     * @throws \RuntimeException
     */
    public function enableSsl(string $siteId): SslCertificate;

    /**
     * Renew SSL certificate for a site.
     *
     * @param string $siteId Site ID
     * @return SslCertificate Renewed certificate
     * @throws \RuntimeException
     */
    public function renewSsl(string $siteId): SslCertificate;

    /**
     * Enable a site.
     *
     * @param string $siteId Site ID
     * @return Site Enabled site
     * @throws \RuntimeException
     */
    public function enable(string $siteId): Site;

    /**
     * Disable a site.
     *
     * @param string $siteId Site ID
     * @param string $reason Reason for disabling
     * @return Site Disabled site
     * @throws \RuntimeException
     */
    public function disable(string $siteId, string $reason = ''): Site;

    /**
     * Delete a site.
     *
     * @param string $siteId Site ID
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function delete(string $siteId): bool;

    /**
     * Get site metrics.
     *
     * @param string $siteId Site ID
     * @return array Site metrics
     * @throws \RuntimeException
     */
    public function getMetrics(string $siteId): array;
}
