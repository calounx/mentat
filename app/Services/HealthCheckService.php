<?php

declare(strict_types=1);

namespace App\Services;

use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\VpsServer;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Health Check Service
 *
 * Detects and reports data inconsistencies in the database.
 * Provides comprehensive system health monitoring and coherency validation.
 *
 * Note: This version focuses on database-level checks. Disk-level checks
 * require SSH infrastructure and are implemented in the full CHOM version.
 *
 * @package App\Services
 */
class HealthCheckService
{
    /**
     * Detect all incoherencies in the system
     *
     * Main detection method that runs all health checks and returns a comprehensive report.
     *
     * @param bool $quickCheck If true, runs only lightweight checks (currently all checks are lightweight)
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
            // Database-level checks (always run)
            $results['orphaned_backups'] = $this->findOrphanedBackups();
            $results['incorrect_vps_counts'] = $this->validateVpsSiteCounts();
            $results['ssl_expiring_soon'] = $this->findSslExpiringSoon();
            $results['orphaned_database_sites'] = $this->findSitesWithInvalidVps();

            // Disk checks require SSH infrastructure (not available in this version)
            // $results['orphaned_disk_sites'] remains empty

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
     * Find sites with invalid or missing VPS references
     *
     * Detects sites that reference VPS servers that don't exist or are terminated.
     *
     * @return Collection<int, array{site: Site, vps_id: string}>
     */
    public function findSitesWithInvalidVps(): Collection
    {
        Log::info('Checking for sites with invalid VPS references');

        try {
            // Find sites with null vps_id or vps_id that doesn't exist
            $sites = Site::whereNotNull('vps_id')
                ->whereIn('status', ['active', 'creating', 'updating'])
                ->whereNotIn('vps_id', function ($query) {
                    $query->select('id')->from('vps_servers');
                })
                ->get();

            $results = $sites->map(function (Site $site) {
                Log::warning('Site with invalid VPS reference detected', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'vps_id' => $site->vps_id,
                ]);

                return [
                    'site' => $site,
                    'vps_id' => $site->vps_id,
                ];
            });

            Log::info('Invalid VPS references check completed', [
                'issues_found' => $results->count(),
            ]);

            return $results;
        } catch (\Exception $e) {
            Log::error('Failed to find sites with invalid VPS', [
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to find sites with invalid VPS: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Find sites in database but not on disk (stub)
     *
     * Note: This requires SSH infrastructure. Returns empty collection in this version.
     *
     * @return Collection<int, array>
     */
    public function findOrphanedDatabaseSites(): Collection
    {
        // Requires SSH infrastructure - not available in this version
        return collect();
    }

    /**
     * Find sites on disk but not in database (stub)
     *
     * Note: This requires SSH infrastructure. Returns empty collection in this version.
     *
     * @return Collection<int, array>
     */
    public function findOrphanedDiskSites(): Collection
    {
        // Requires SSH infrastructure - not available in this version
        return collect();
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
}
