<?php

namespace App\Services\Sites\Provisioners;

use App\Contracts\SiteProvisionerInterface;
use App\Models\Site;
use App\Models\VpsServer;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Support\Facades\Log;

/**
 * HTML/Static Site Provisioner.
 *
 * Handles provisioning of static HTML sites on VPS servers.
 * Implements the Strategy pattern for extensible site provisioning.
 */
class HtmlSiteProvisioner implements SiteProvisionerInterface
{
    public function __construct(
        private VPSManagerBridge $vpsManager
    ) {}

    /**
     * {@inheritdoc}
     */
    public function provision(Site $site, VpsServer $vps): array
    {
        Log::info('Provisioning HTML site', [
            'site_id' => $site->id,
            'domain' => $site->domain,
            'vps' => $vps->hostname,
        ]);

        return $this->vpsManager->createHtmlSite($vps, $site->domain);
    }

    /**
     * {@inheritdoc}
     */
    public function getSiteType(): string
    {
        return 'html';
    }

    /**
     * {@inheritdoc}
     */
    public function validate(Site $site): bool
    {
        // Validate HTML site requirements
        if ($site->site_type !== $this->getSiteType()) {
            return false;
        }

        // HTML sites don't have specific validation requirements
        // beyond the basic domain validation
        return true;
    }
}
