<?php

namespace App\Services\Sites\Provisioners;

use App\Contracts\SiteProvisionerInterface;
use App\Models\Site;
use App\Models\VpsServer;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Support\Facades\Log;

/**
 * WordPress Site Provisioner.
 *
 * Handles provisioning of WordPress sites on VPS servers.
 * Implements the Strategy pattern for extensible site provisioning.
 */
class WordPressSiteProvisioner implements SiteProvisionerInterface
{
    public function __construct(
        private VPSManagerBridge $vpsManager
    ) {}

    /**
     * {@inheritdoc}
     */
    public function provision(Site $site, VpsServer $vps): array
    {
        Log::info('Provisioning WordPress site', [
            'site_id' => $site->id,
            'domain' => $site->domain,
            'vps' => $vps->hostname,
        ]);

        $options = $this->buildProvisioningOptions($site);

        return $this->vpsManager->createWordPressSite($vps, $site->domain, $options);
    }

    /**
     * {@inheritdoc}
     */
    public function getSiteType(): string
    {
        return 'wordpress';
    }

    /**
     * {@inheritdoc}
     */
    public function validate(Site $site): bool
    {
        // Validate WordPress-specific requirements
        if ($site->site_type !== $this->getSiteType()) {
            return false;
        }

        // PHP version must be specified for WordPress
        if (empty($site->php_version)) {
            Log::warning('WordPress site missing PHP version', [
                'site_id' => $site->id,
                'domain' => $site->domain,
            ]);

            return false;
        }

        // Validate PHP version is supported
        $supportedVersions = ['8.2', '8.4'];
        if (! in_array($site->php_version, $supportedVersions, true)) {
            Log::warning('WordPress site has unsupported PHP version', [
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
     */
    private function buildProvisioningOptions(Site $site): array
    {
        $options = [
            'php_version' => $site->php_version ?? '8.2',
        ];

        // Extract WordPress-specific settings from site settings
        $settings = $site->settings ?? [];

        if (! empty($settings['admin_email'])) {
            $options['admin_email'] = $settings['admin_email'];
        }

        if (! empty($settings['admin_user'])) {
            $options['admin_user'] = $settings['admin_user'];
        }

        return $options;
    }
}
