<?php

namespace App\Services\Backup;

use App\Contracts\VpsManagerInterface;
use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\Tenant;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

/**
 * Backup Service
 *
 * Handles backup creation, management, and deletion operations.
 * Orchestrates VPS backup operations and local storage management.
 */
class BackupService
{
    /**
     * Create a new backup service instance.
     */
    public function __construct(
        protected VpsManagerInterface $vpsManager
    ) {}

    /**
     * Create a new backup for a site.
     *
     * This creates the backup record and initiates the actual backup process.
     * The actual backup is handled asynchronously via job.
     *
     * @param  Site  $site  The site to backup
     * @param  string  $backupType  Type of backup (full, database, files)
     * @param  int  $retentionDays  How long to keep the backup
     */
    public function createBackup(
        Site $site,
        string $backupType = 'full',
        int $retentionDays = 30
    ): SiteBackup {
        // Validate backup type
        $this->validateBackupType($backupType);

        // Create backup record
        $backup = SiteBackup::create([
            'site_id' => $site->id,
            'backup_type' => $backupType,
            'storage_path' => null, // Will be set when backup completes
            'size_bytes' => 0,
            'retention_days' => $retentionDays,
            'expires_at' => now()->addDays($retentionDays),
        ]);

        Log::info('Backup record created', [
            'backup_id' => $backup->id,
            'site_id' => $site->id,
            'backup_type' => $backupType,
        ]);

        // Note: Actual backup execution should be handled by a job
        // BackupSiteJob::dispatch($backup);

        return $backup;
    }

    /**
     * Execute the actual backup process.
     *
     * This method is typically called from a background job.
     *
     * @param  SiteBackup  $backup  The backup record
     * @return array{success: bool, message: string, path?: string, size?: int}
     */
    public function executeBackup(SiteBackup $backup): array
    {
        $site = $backup->site;

        if (! $site->vpsServer) {
            return [
                'success' => false,
                'message' => 'Site has no associated VPS server',
            ];
        }

        try {
            // Create backup on VPS
            $result = $this->vpsManager->createBackup(
                $site->vpsServer,
                $site,
                $backup->backup_type
            );

            if (! $result['success']) {
                Log::error('VPS backup failed', [
                    'backup_id' => $backup->id,
                    'site_id' => $site->id,
                    'error' => $result['error'] ?? 'Unknown error',
                ]);

                return [
                    'success' => false,
                    'message' => $result['error'] ?? 'Backup failed on VPS',
                ];
            }

            // Update backup record with results
            $backup->update([
                'storage_path' => $result['path'],
                'size_bytes' => $result['size'] ?? 0,
                'checksum' => $result['checksum'] ?? null,
            ]);

            // Update site storage metrics
            $this->updateSiteStorageMetrics($site);

            Log::info('Backup completed', [
                'backup_id' => $backup->id,
                'site_id' => $site->id,
                'size' => $backup->getSizeFormatted(),
            ]);

            return [
                'success' => true,
                'message' => 'Backup completed successfully',
                'path' => $result['path'],
                'size' => $result['size'] ?? 0,
            ];

        } catch (\Exception $e) {
            Log::error('Backup execution error', [
                'backup_id' => $backup->id,
                'error' => $e->getMessage(),
            ]);

            return [
                'success' => false,
                'message' => $e->getMessage(),
            ];
        }
    }

    /**
     * Delete a backup.
     *
     * @param  SiteBackup  $backup  The backup to delete
     * @return array{success: bool, message: string}
     */
    public function deleteBackup(SiteBackup $backup): array
    {
        try {
            // Delete from storage if exists
            if ($backup->storage_path && Storage::exists($backup->storage_path)) {
                Storage::delete($backup->storage_path);
            }

            // Delete database record
            $backup->delete();

            Log::info('Backup deleted', [
                'backup_id' => $backup->id,
                'site_id' => $backup->site_id,
            ]);

            return [
                'success' => true,
                'message' => 'Backup deleted successfully',
            ];

        } catch (\Exception $e) {
            Log::error('Backup deletion error', [
                'backup_id' => $backup->id,
                'error' => $e->getMessage(),
            ]);

            return [
                'success' => false,
                'message' => $e->getMessage(),
            ];
        }
    }

    /**
     * Generate a temporary download URL for a backup.
     *
     * @param  SiteBackup  $backup  The backup
     * @param  int  $expiryMinutes  URL expiry time in minutes
     * @return array{success: bool, url?: string, expires_at?: string, message?: string}
     */
    public function getDownloadUrl(SiteBackup $backup, int $expiryMinutes = 15): array
    {
        if (! $backup->storage_path) {
            return [
                'success' => false,
                'message' => 'Backup is not yet available for download',
            ];
        }

        if ($backup->isExpired()) {
            return [
                'success' => false,
                'message' => 'Backup has expired and is no longer available',
            ];
        }

        try {
            $expiresAt = now()->addMinutes($expiryMinutes);
            $url = Storage::temporaryUrl($backup->storage_path, $expiresAt);

            return [
                'success' => true,
                'url' => $url,
                'expires_at' => $expiresAt->toIso8601String(),
            ];

        } catch (\Exception $e) {
            Log::error('Failed to generate download URL', [
                'backup_id' => $backup->id,
                'error' => $e->getMessage(),
            ]);

            return [
                'success' => false,
                'message' => 'Failed to generate download URL',
            ];
        }
    }

    /**
     * Clean up expired backups for a site or tenant.
     *
     * @param  Site|Tenant  $entity  The site or tenant
     * @return int Number of backups cleaned up
     */
    public function cleanupExpiredBackups(Site|Tenant $entity): int
    {
        $query = $entity instanceof Site
            ? $entity->backups()
            : SiteBackup::whereHas('site', fn ($q) => $q->where('tenant_id', $entity->id));

        $expiredBackups = $query->where('expires_at', '<=', now())->get();

        $count = 0;
        foreach ($expiredBackups as $backup) {
            $result = $this->deleteBackup($backup);
            if ($result['success']) {
                $count++;
            }
        }

        if ($count > 0) {
            Log::info('Expired backups cleaned up', [
                'entity_type' => $entity instanceof Site ? 'site' : 'tenant',
                'entity_id' => $entity->id,
                'count' => $count,
            ]);
        }

        return $count;
    }

    /**
     * Validate backup type.
     *
     * @throws \InvalidArgumentException
     */
    protected function validateBackupType(string $backupType): void
    {
        $validTypes = ['full', 'database', 'files'];

        if (! in_array($backupType, $validTypes)) {
            throw new \InvalidArgumentException(
                "Invalid backup type: {$backupType}. Must be one of: ".implode(', ', $validTypes)
            );
        }
    }

    /**
     * Update site storage metrics after backup operations.
     */
    protected function updateSiteStorageMetrics(Site $site): void
    {
        // This could query VPS for actual storage usage
        // For now, we'll sum up backup sizes
        $totalBackupSize = $site->backups()->sum('size_bytes');
        $storageMb = round($totalBackupSize / 1048576);

        $site->update(['storage_used_mb' => $storageMb]);
    }

    /**
     * Get backup statistics for a tenant.
     *
     * @return array{total_backups: int, total_size_bytes: int, total_size_formatted: string, oldest?: string, newest?: string}
     */
    public function getBackupStats(Tenant $tenant): array
    {
        $backups = SiteBackup::whereHas('site', fn ($q) => $q->where('tenant_id', $tenant->id));

        $totalSize = $backups->sum('size_bytes');
        $oldest = $backups->orderBy('created_at', 'asc')->first();
        $newest = $backups->orderBy('created_at', 'desc')->first();

        return [
            'total_backups' => $backups->count(),
            'total_size_bytes' => $totalSize,
            'total_size_formatted' => $this->formatBytes($totalSize),
            'oldest' => $oldest?->created_at->toIso8601String(),
            'newest' => $newest?->created_at->toIso8601String(),
        ];
    }

    /**
     * Format bytes to human-readable size.
     */
    protected function formatBytes(int $bytes): string
    {
        if ($bytes >= 1073741824) {
            return round($bytes / 1073741824, 2).' GB';
        }
        if ($bytes >= 1048576) {
            return round($bytes / 1048576, 2).' MB';
        }

        return round($bytes / 1024, 2).' KB';
    }
}
