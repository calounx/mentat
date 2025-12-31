<?php

namespace App\Services\VPS;

use App\Models\VpsServer;

/**
 * VPS Site Manager.
 *
 * Manages site operations on VPS servers.
 * Follows Single Responsibility Principle - only handles site management.
 */
class VpsSiteManager
{
    public function __construct(
        private VpsCommandExecutor $commandExecutor
    ) {}

    /**
     * Create a WordPress site.
     *
     * @param VpsServer $vps
     * @param string $domain
     * @param array $options Configuration options
     * @return array
     */
    public function createWordPressSite(VpsServer $vps, string $domain, array $options = []): array
    {
        $args = [
            $domain,
            'type' => 'wordpress',
            'php-version' => $options['php_version'] ?? '8.2',
        ];

        if (!empty($options['admin_email'])) {
            $args['admin-email'] = $options['admin_email'];
        }

        if (!empty($options['admin_user'])) {
            $args['admin-user'] = $options['admin_user'];
        }

        return $this->commandExecutor->execute($vps, 'site:create', $args);
    }

    /**
     * Create an HTML site.
     *
     * @param VpsServer $vps
     * @param string $domain
     * @return array
     */
    public function createHtmlSite(VpsServer $vps, string $domain): array
    {
        return $this->commandExecutor->execute($vps, 'site:create', [
            $domain,
            'type' => 'html',
        ]);
    }

    /**
     * Create a Laravel site.
     *
     * @param VpsServer $vps
     * @param string $domain
     * @param array $options Configuration options
     * @return array
     */
    public function createLaravelSite(VpsServer $vps, string $domain, array $options = []): array
    {
        return $this->commandExecutor->execute($vps, 'site:create', [
            $domain,
            'type' => 'laravel',
            'php-version' => $options['php_version'] ?? '8.2',
        ]);
    }

    /**
     * Delete a site.
     *
     * @param VpsServer $vps
     * @param string $domain
     * @param bool $force Force deletion without confirmation
     * @return array
     */
    public function deleteSite(VpsServer $vps, string $domain, bool $force = false): array
    {
        $args = [$domain];
        if ($force) {
            $args['force'] = true;
        }

        return $this->commandExecutor->execute($vps, 'site:delete', $args);
    }

    /**
     * Enable a site.
     *
     * @param VpsServer $vps
     * @param string $domain
     * @return array
     */
    public function enableSite(VpsServer $vps, string $domain): array
    {
        return $this->commandExecutor->execute($vps, 'site:enable', [$domain]);
    }

    /**
     * Disable a site.
     *
     * @param VpsServer $vps
     * @param string $domain
     * @return array
     */
    public function disableSite(VpsServer $vps, string $domain): array
    {
        return $this->commandExecutor->execute($vps, 'site:disable', [$domain]);
    }

    /**
     * List all sites on a VPS.
     *
     * @param VpsServer $vps
     * @return array
     */
    public function listSites(VpsServer $vps): array
    {
        return $this->commandExecutor->execute($vps, 'site:list');
    }

    /**
     * Get site info.
     *
     * @param VpsServer $vps
     * @param string $domain
     * @return array
     */
    public function getSiteInfo(VpsServer $vps, string $domain): array
    {
        return $this->commandExecutor->execute($vps, 'site:info', [$domain]);
    }

    /**
     * Clear cache for a site.
     *
     * @param VpsServer $vps
     * @param string $domain
     * @return array
     */
    public function clearCache(VpsServer $vps, string $domain): array
    {
        return $this->commandExecutor->execute($vps, 'cache:clear', ['site' => $domain]);
    }
}
