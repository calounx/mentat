<?php

namespace App\Services\Sites\Provisioners;

use App\Contracts\SiteProvisionerInterface;
use App\Models\Site;
use App\Models\VpsServer;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Support\Facades\Log;

/**
 * Laravel Site Provisioner.
 *
 * Handles provisioning of Laravel sites on VPS servers.
 * Implements the Strategy pattern for extensible site provisioning.
 */
class LaravelSiteProvisioner implements SiteProvisionerInterface
{
    public function __construct(
        private VPSManagerBridge $vpsManager
    ) {}

    /**
     * {@inheritdoc}
     */
    public function provision(Site $site, VpsServer $vps): array
    {
        Log::info('Provisioning Laravel site', [
            'site_id' => $site->id,
            'domain' => $site->domain,
            'vps' => $vps->hostname,
        ]);

        $options = $this->buildProvisioningOptions($site);

        // Use the generic site:create command with Laravel type
        return $this->vpsManager->execute($vps, 'site:create', [
            $site->domain,
            'type' => 'laravel',
            'php-version' => $options['php_version'],
        ]);
    }

    /**
     * {@inheritdoc}
     */
    public function getSiteType(): string
    {
        return 'laravel';
    }

    /**
     * {@inheritdoc}
     */
    public function validate(Site $site): bool
    {
        // Validate Laravel-specific requirements
        if ($site->site_type !== $this->getSiteType()) {
            return false;
        }

        // PHP version must be specified for Laravel
        if (empty($site->php_version)) {
            Log::warning('Laravel site missing PHP version', [
                'site_id' => $site->id,
                'domain' => $site->domain,
            ]);
            return false;
        }

        // Validate PHP version is supported (Laravel requires 8.2+)
        $supportedVersions = ['8.2', '8.4'];
        if (!in_array($site->php_version, $supportedVersions, true)) {
            Log::warning('Laravel site has unsupported PHP version', [
                'site_id' => $site->id,
                'domain' => $site->domain,
                'php_version' => $site->php_version,
                'supported' => $supportedVersions,
            ]);
            return false;
        }

        return true;
    }

    /**
     * Build provisioning options from site configuration.
     *
     * @param Site $site
     * @return array
     */
    private function buildProvisioningOptions(Site $site): array
    {
        $options = [
            'php_version' => $site->php_version ?? '8.2',
        ];

        // Extract Laravel-specific settings from site settings
        $settings = $site->settings ?? [];

        // Add any Laravel-specific configuration options here
        // e.g., database type, queue worker setup, etc.

        return $options;
    }
}
