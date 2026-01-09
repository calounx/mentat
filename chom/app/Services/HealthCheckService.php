<?php

declare(strict_types=1);

namespace App\Services;

use App\Contracts\Infrastructure\VpsProviderInterface;
use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\VpsServer;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Health Check Service
 *
 * Detects and reports data inconsistencies between database state and actual VPS disk state.
 * Provides comprehensive system health monitoring and coherency validation.
 *
 * @package App\Services
 */
class HealthCheckService
{
    /**
     * Base directory for sites on VPS servers
     */
    private const SITES_BASE_DIR = '/var/www';

    public function __construct(
        private readonly VpsProviderInterface $vpsProvider
    ) {
    }

    /**
     * Detect all incoherencies in the system
     *
     * Main detection method that runs all health checks and returns a comprehensive report.
     *
     * @param bool $quickCheck If true, runs only lightweight checks
     * @return array{
     *     orphaned_database_sites: Collection,
     *     orphaned_disk_sites: Collection,
     *     orphaned_backups: Collection,
     *     incorrect_vps_counts: Collection,
     *     ssl_expiring_soon: Collection,
     *     summary: array
     * }
     */
    public function detectIncoherencies(bool $quickCheck = false): array
    {
        Log::info('Starting coherency detection', [
            'quick_check' => $quickCheck,
            'timestamp' => now()->toIso8601String(),
        ]);

        $startTime = microtime(true);

        $results = [
            'orphaned_database_sites' => collect(),
            'orphaned_disk_sites' => collect(),
            'orphaned_backups' => collect(),
            'incorrect_vps_counts' => collect(),
            'ssl_expiring_soon' => collect(),
        ];

        try {
            // Always check database-level incoherencies (lightweight)
            $results['orphaned_backups'] = $this->findOrphanedBackups();
            $results['incorrect_vps_counts'] = $this->validateVpsSiteCounts();
            $results['ssl_expiring_soon'] = $this->findSslExpiringSoon();

            // Skip disk checks for quick checks (require SSH connections)
            if (!$quickCheck) {
                $results['orphaned_database_sites'] = $this->findOrphanedDatabaseSites();
                $results['orphaned_disk_sites'] = $this->findOrphanedDiskSites();
            }

            $executionTime = round((microtime(true) - $startTime) * 1000, 2);

            $summary = [
                'total_issues' => array_sum(array_map(fn($collection) => $collection->count(), $results)),
                'orphaned_database_sites_count' => $results['orphaned_database_sites']->count(),
                'orphaned_disk_sites_count' => $results['orphaned_disk_sites']->count(),
                'orphaned_backups_count' => $results['orphaned_backups']->count(),
                'incorrect_vps_counts_count' => $results['incorrect_vps_counts']->count(),
                'ssl_expiring_soon_count' => $results['ssl_expiring_soon']->count(),
                'execution_time_ms' => $executionTime,
                'check_type' => $quickCheck ? 'quick' : 'full',
                'timestamp' => now()->toIso8601String(),
            ];

            Log::info('Coherency detection completed', $summary);

            $results['summary'] = $summary;

            return $results;
        } catch (\Exception $e) {
            Log::error('Coherency detection failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            throw new \RuntimeException('Failed to detect incoherencies: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Find sites in database but not on disk
     *
     * Detects "orphaned database sites" - sites that exist in the database with 'active' status
     * but whose directories don't exist on their assigned VPS servers.
     *
     * @return Collection<int, array{site: Site, vps: VpsServer, expected_path: string}>
     */
    public function findOrphanedDatabaseSites(): Collection
    {
        Log::info('Checking for orphaned database sites');

        $orphans = collect();

        try {
            // Get all active sites with their VPS servers
            $sites = Site::with('vpsServer')
                ->whereIn('status', ['active', 'creating'])
                ->whereNotNull('vps_id')
                ->get();

            foreach ($sites as $site) {
                if (!$site->vpsServer) {
                    Log::warning('Site has no VPS server assigned', [
                        'site_id' => $site->id,
                        'domain' => $site->domain,
                    ]);
                    continue;
                }

                try {
                    $expectedPath = $this->getSiteDirectoryPath($site->domain);
                    $exists = $this->checkDirectoryExistsOnVps($site->vpsServer, $expectedPath);

                    if (!$exists) {
                        Log::warning('Orphaned database site detected', [
                            'site_id' => $site->id,
                            'domain' => $site->domain,
                            'vps_id' => $site->vpsServer->id,
                            'expected_path' => $expectedPath,
                        ]);

                        $orphans->push([
                            'site' => $site,
                            'vps' => $site->vpsServer,
                            'expected_path' => $expectedPath,
                        ]);
                    }
                } catch (\Exception $e) {
                    Log::error('Failed to check site directory on VPS', [
                        'site_id' => $site->id,
                        'domain' => $site->domain,
                        'vps_id' => $site->vpsServer->id,
                        'error' => $e->getMessage(),
                    ]);
                }
            }

            Log::info('Orphaned database sites check completed', [
                'total_sites_checked' => $sites->count(),
                'orphans_found' => $orphans->count(),
            ]);

            return $orphans;
        } catch (\Exception $e) {
            Log::error('Failed to find orphaned database sites', [
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to find orphaned database sites: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Find sites on disk but not in database
     *
     * Detects "orphaned disk sites" - site directories that exist on VPS servers
     * but have no corresponding database records.
     *
     * @return Collection<int, array{vps: VpsServer, path: string, domain: string}>
     */
    public function findOrphanedDiskSites(): Collection
    {
        Log::info('Checking for orphaned disk sites');

        $orphans = collect();

        try {
            // Get all active VPS servers
            $vpsServers = VpsServer::where('status', 'active')->get();

            foreach ($vpsServers as $vps) {
                try {
                    $diskSites = $this->listSitesOnVps($vps);
                    $dbDomains = Site::where('vps_id', $vps->id)
                        ->whereNotNull('domain')
                        ->pluck('domain')
                        ->toArray();

                    foreach ($diskSites as $diskSite) {
                        $domain = $diskSite['domain'];

                        if (!in_array($domain, $dbDomains, true)) {
                            Log::warning('Orphaned disk site detected', [
                                'vps_id' => $vps->id,
                                'domain' => $domain,
                                'path' => $diskSite['path'],
                            ]);

                            $orphans->push([
                                'vps' => $vps,
                                'path' => $diskSite['path'],
                                'domain' => $domain,
                            ]);
                        }
                    }
                } catch (\Exception $e) {
                    Log::error('Failed to check disk sites on VPS', [
                        'vps_id' => $vps->id,
                        'error' => $e->getMessage(),
                    ]);
                }
            }

            Log::info('Orphaned disk sites check completed', [
                'total_vps_checked' => $vpsServers->count(),
                'orphans_found' => $orphans->count(),
            ]);

            return $orphans;
        } catch (\Exception $e) {
            Log::error('Failed to find orphaned disk sites', [
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to find orphaned disk sites: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Find backups referencing deleted sites
     *
     * Detects orphaned backups - backup records that reference sites that no longer exist
     * (soft-deleted or hard-deleted from the database).
     *
     * @return Collection<int, array{backup: SiteBackup, site_id: string}>
     */
    public function findOrphanedBackups(): Collection
    {
        Log::info('Checking for orphaned backups');

        try {
            $orphanedBackups = SiteBackup::whereNotIn('site_id', function ($query) {
                $query->select('id')->from('sites');
            })->get();

            $orphans = $orphanedBackups->map(function (SiteBackup $backup) {
                Log::warning('Orphaned backup detected', [
                    'backup_id' => $backup->id,
                    'site_id' => $backup->site_id,
                    'created_at' => $backup->created_at?->toIso8601String(),
                ]);

                return [
                    'backup' => $backup,
                    'site_id' => $backup->site_id,
                ];
            });

            Log::info('Orphaned backups check completed', [
                'orphans_found' => $orphans->count(),
            ]);

            return $orphans;
        } catch (\Exception $e) {
            Log::error('Failed to find orphaned backups', [
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to find orphaned backups: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Validate VPS site_count accuracy
     *
     * Verifies that the site_count field on VPS servers matches the actual number
     * of active sites assigned to each VPS in the database.
     *
     * @return Collection<int, array{vps: VpsServer, recorded_count: int, actual_count: int, difference: int}>
     */
    public function validateVpsSiteCounts(): Collection
    {
        Log::info('Validating VPS site counts');

        try {
            $vpsServers = VpsServer::withCount([
                'sites' => function ($query) {
                    $query->whereIn('status', ['active', 'creating', 'updating']);
                }
            ])->get();

            $incoherent = collect();

            foreach ($vpsServers as $vps) {
                $recordedCount = $vps->site_count ?? 0;
                $actualCount = $vps->sites_count ?? 0;

                if ($recordedCount !== $actualCount) {
                    Log::warning('VPS site count mismatch detected', [
                        'vps_id' => $vps->id,
                        'hostname' => $vps->hostname,
                        'recorded_count' => $recordedCount,
                        'actual_count' => $actualCount,
                        'difference' => $actualCount - $recordedCount,
                    ]);

                    $incoherent->push([
                        'vps' => $vps,
                        'recorded_count' => $recordedCount,
                        'actual_count' => $actualCount,
                        'difference' => $actualCount - $recordedCount,
                    ]);
                }
            }

            Log::info('VPS site counts validation completed', [
                'total_vps_checked' => $vpsServers->count(),
                'incoherent_counts' => $incoherent->count(),
            ]);

            return $incoherent;
        } catch (\Exception $e) {
            Log::error('Failed to validate VPS site counts', [
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to validate VPS site counts: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Find SSL certificates expiring soon
     *
     * Detects sites with SSL certificates that will expire within the next 30 days.
     *
     * @param int $daysThreshold Number of days before expiration to warn (default: 30)
     * @return Collection<int, array{site: Site, days_until_expiry: int}>
     */
    public function findSslExpiringSoon(int $daysThreshold = 30): Collection
    {
        Log::info('Checking for SSL certificates expiring soon', [
            'days_threshold' => $daysThreshold,
        ]);

        try {
            $expiryThreshold = now()->addDays($daysThreshold);

            $expiringSites = Site::where('ssl_enabled', true)
                ->whereNotNull('ssl_expires_at')
                ->where('ssl_expires_at', '<=', $expiryThreshold)
                ->where('ssl_expires_at', '>', now())
                ->get();

            $results = $expiringSites->map(function (Site $site) {
                $daysUntilExpiry = now()->diffInDays($site->ssl_expires_at, false);

                Log::warning('SSL certificate expiring soon', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'expires_at' => $site->ssl_expires_at?->toIso8601String(),
                    'days_until_expiry' => (int)$daysUntilExpiry,
                ]);

                return [
                    'site' => $site,
                    'days_until_expiry' => (int)$daysUntilExpiry,
                ];
            });

            Log::info('SSL expiration check completed', [
                'expiring_soon_count' => $results->count(),
            ]);

            return $results;
        } catch (\Exception $e) {
            Log::error('Failed to check SSL expiration', [
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to check SSL expiration: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Check if a directory exists on a VPS server
     *
     * @param VpsServer $vps The VPS server to check
     * @param string $path The directory path to verify
     * @return bool True if directory exists, false otherwise
     */
    private function checkDirectoryExistsOnVps(VpsServer $vps, string $path): bool
    {
        try {
            $result = $this->vpsProvider->executeCommand(
                $vps->id,
                "test -d '{$path}' && echo 'EXISTS' || echo 'NOT_FOUND'",
                30
            );

            return $result->isSuccessful() && str_contains($result->output, 'EXISTS');
        } catch (\Exception $e) {
            Log::error('Failed to check directory on VPS', [
                'vps_id' => $vps->id,
                'path' => $path,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * List all site directories on a VPS server
     *
     * @param VpsServer $vps The VPS server to scan
     * @return array<int, array{domain: string, path: string}>
     */
    private function listSitesOnVps(VpsServer $vps): array
    {
        try {
            $result = $this->vpsProvider->executeCommand(
                $vps->id,
                "find " . self::SITES_BASE_DIR . " -maxdepth 1 -type d -not -name 'www' | tail -n +2",
                60
            );

            if (!$result->isSuccessful()) {
                Log::warning('Failed to list sites on VPS', [
                    'vps_id' => $vps->id,
                    'exit_code' => $result->exitCode,
                    'error' => $result->error,
                ]);

                return [];
            }

            $directories = array_filter(explode("\n", trim($result->output)));
            $sites = [];

            foreach ($directories as $dir) {
                $domain = basename($dir);

                // Skip system directories
                if (in_array($domain, ['html', 'default', 'localhost'], true)) {
                    continue;
                }

                $sites[] = [
                    'domain' => $domain,
                    'path' => $dir,
                ];
            }

            return $sites;
        } catch (\Exception $e) {
            Log::error('Failed to list sites on VPS', [
                'vps_id' => $vps->id,
                'error' => $e->getMessage(),
            ]);

            return [];
        }
    }

    /**
     * Get the expected directory path for a site
     *
     * @param string $domain The site domain
     * @return string The expected directory path
     */
    private function getSiteDirectoryPath(string $domain): string
    {
        return self::SITES_BASE_DIR . '/' . $domain;
    }
}
