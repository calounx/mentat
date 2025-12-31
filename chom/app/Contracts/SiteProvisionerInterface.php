<?php

namespace App\Contracts;

use App\Models\Site;
use App\Models\VpsServer;

/**
 * Interface for site provisioning strategies.
 *
 * Each implementation handles provisioning for a specific site type
 * following the Strategy pattern for extensibility and SOLID principles.
 */
interface SiteProvisionerInterface
{
    /**
     * Provision a site on a VPS server.
     *
     * @param Site $site The site to provision
     * @param VpsServer $vps The VPS server to provision on
     * @return array Result with 'success', 'exit_code', 'output', and optional 'data'
     * @throws \RuntimeException If provisioning fails critically
     */
    public function provision(Site $site, VpsServer $vps): array;

    /**
     * Get the site type this provisioner handles.
     *
     * @return string The site type (e.g., 'wordpress', 'html', 'laravel')
     */
    public function getSiteType(): string;

    /**
     * Validate site-specific requirements before provisioning.
     *
     * @param Site $site The site to validate
     * @return bool True if site is valid for this provisioner
     */
    public function validate(Site $site): bool;
}
