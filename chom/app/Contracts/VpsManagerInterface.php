<?php

namespace App\Contracts;

use App\Models\Site;
use App\Models\VpsServer;

/**
 * Interface for VPS management operations.
 *
 * This interface defines the contract for managing sites on VPS servers,
 * allowing for different implementations (e.g., SSH-based, API-based).
 */
interface VpsManagerInterface
{
    /**
     * Provision a new site on the VPS server.
     *
     * @param  VpsServer  $vps  The VPS server to provision on
     * @param  Site  $site  The site to provision
     * @return array{success: bool, output?: string, error?: string}
     */
    public function provisionSite(VpsServer $vps, Site $site): array;

    /**
     * Enable a site on the VPS server.
     *
     * @param  VpsServer  $vps  The VPS server
     * @param  string  $domain  The site domain
     * @return array{success: bool, output?: string, error?: string}
     */
    public function enableSite(VpsServer $vps, string $domain): array;

    /**
     * Disable a site on the VPS server.
     *
     * @param  VpsServer  $vps  The VPS server
     * @param  string  $domain  The site domain
     * @return array{success: bool, output?: string, error?: string}
     */
    public function disableSite(VpsServer $vps, string $domain): array;

    /**
     * Delete a site from the VPS server.
     *
     * @param  VpsServer  $vps  The VPS server
     * @param  string  $domain  The site domain
     * @param  bool  $force  Force deletion even if errors occur
     * @return array{success: bool, output?: string, error?: string}
     */
    public function deleteSite(VpsServer $vps, string $domain, bool $force = false): array;

    /**
     * Issue SSL certificate for a site.
     *
     * @param  VpsServer  $vps  The VPS server
     * @param  string  $domain  The site domain
     * @return array{success: bool, output?: string, error?: string}
     */
    public function issueSslCertificate(VpsServer $vps, string $domain): array;

    /**
     * Create a backup of a site.
     *
     * @param  VpsServer  $vps  The VPS server
     * @param  Site  $site  The site to backup
     * @param  string  $backupType  The type of backup (full, database, files)
     * @return array{success: bool, path?: string, size?: int, output?: string, error?: string}
     */
    public function createBackup(VpsServer $vps, Site $site, string $backupType = 'full'): array;

    /**
     * Restore a site from backup.
     *
     * @param  VpsServer  $vps  The VPS server
     * @param  Site  $site  The site to restore
     * @param  string  $backupPath  The path to the backup file
     * @return array{success: bool, output?: string, error?: string}
     */
    public function restoreBackup(VpsServer $vps, Site $site, string $backupPath): array;

    /**
     * Check VPS server health status.
     *
     * @param  VpsServer  $vps  The VPS server to check
     * @return array{healthy: bool, load?: float, memory_used?: int, disk_used?: int, error?: string}
     */
    public function checkHealth(VpsServer $vps): array;

    /**
     * Get site metrics from the VPS.
     *
     * @param  VpsServer  $vps  The VPS server
     * @param  Site  $site  The site to get metrics for
     * @return array{storage_mb?: int, bandwidth_mb?: int, requests?: int, error?: string}
     */
    public function getSiteMetrics(VpsServer $vps, Site $site): array;
}
