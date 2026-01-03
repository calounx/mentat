<?php

declare(strict_types=1);

namespace App\Services;

use App\Events\BackupCreated;
use App\Events\BackupDeleted;
use App\Events\BackupFailed;
use App\Events\BackupRestored;
use App\Jobs\CreateBackupJob;
use App\Jobs\RestoreBackupJob;
use App\Models\SiteBackup;
use App\Repositories\BackupRepository;
use App\Repositories\SiteRepository;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

/**
 * Backup Service
 *
 * Handles all business logic related to site backups, restoration,
 * and retention management.
 */
class BackupService
{
    public function __construct(
        private readonly BackupRepository $backupRepository,
        private readonly SiteRepository $siteRepository,
        private readonly QuotaService $quotaService
    ) {
    }

    /**
     * Create a backup for a site.
     *
     * @param string $siteId The site ID
     * @param string $type Backup type (full, files, database)
     * @param int $retentionDays Number of days to retain the backup
     * @return SiteBackup The created backup
     * @throws ValidationException
     * @throws \RuntimeException
     */
    public function createBackup(string $siteId, string $type = 'full', int $retentionDays = 30): SiteBackup
    {
        try {
            // Validate site exists
            $site = $this->siteRepository->findById($siteId);
            if (!$site) {
                throw new \RuntimeException('Site not found');
            }

            // Validate backup type
            $this->validateBackupType($type);

            // Check backup quota
            if (!$this->quotaService->canCreateBackup($siteId)) {
                $quota = $this->quotaService->checkBackupQuota($siteId);
                throw new \RuntimeException(
                    "Backup quota exceeded. Current: {$quota['current']}, Limit: {$quota['limit']}"
                );
            }

            // Check storage quota (estimate backup size as 50% of current storage)
            $estimatedBackupSizeMb = (int) ceil(($site->storage_used_mb ?? 100) * 0.5);
            $storageQuota = $this->quotaService->checkStorageQuota($site->tenant_id);

            if (!$storageQuota['available']) {
                throw new \RuntimeException(
                    'Storage quota exceeded. Cannot create backup.'
                );
            }

            // Create backup record with 'pending' status
            $expiresAt = now()->addDays($retentionDays);

            $backupData = [
                'site_id' => $siteId,
                'backup_type' => $type,
                'storage_path' => $this->generateStoragePath($site, $type),
                'size_bytes' => 0,
                'checksum' => '',
                'retention_days' => $retentionDays,
                'expires_at' => $expiresAt,
                'status' => 'pending',
            ];

            $backup = $this->backupRepository->create($backupData);

            Log::info('Backup creation initiated', [
                'backup_id' => $backup->id,
                'site_id' => $siteId,
                'type' => $type,
                'retention_days' => $retentionDays,
            ]);

            // Dispatch async backup job
            CreateBackupJob::dispatch($backup);

            Event::dispatch(new BackupCreated($backup));

            return $backup;
        } catch (ValidationException $e) {
            Log::error('Backup creation validation failed', [
                'site_id' => $siteId,
                'errors' => $e->errors(),
            ]);
            throw $e;
        } catch (\Exception $e) {
            Log::error('Backup creation failed', [
                'site_id' => $siteId,
                'type' => $type,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to create backup: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Restore a backup to a site.
     *
     * @param string $backupId The backup ID
     * @param string|null $targetSiteId Target site ID (null = restore to original site)
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function restoreBackup(string $backupId, string $targetSiteId = null): bool
    {
        try {
            $backup = $this->backupRepository->findById($backupId);
            if (!$backup) {
                throw new \RuntimeException('Backup not found');
            }

            if ($backup->status !== 'completed') {
                throw new \RuntimeException(
                    "Cannot restore backup with status: {$backup->status}"
                );
            }

            // Determine target site
            $targetSite = $targetSiteId
                ? $this->siteRepository->findById($targetSiteId)
                : $backup->site;

            if (!$targetSite) {
                throw new \RuntimeException('Target site not found');
            }

            // Validate target site status
            if ($targetSite->status === 'deleting') {
                throw new \RuntimeException('Cannot restore to a site being deleted');
            }

            // Update site status to 'restoring'
            $this->siteRepository->update($targetSite->id, ['status' => 'restoring']);

            Log::info('Backup restoration initiated', [
                'backup_id' => $backupId,
                'source_site_id' => $backup->site_id,
                'target_site_id' => $targetSite->id,
                'backup_type' => $backup->backup_type,
            ]);

            // Dispatch async restoration job
            RestoreBackupJob::dispatch($backup, $targetSite);

            Event::dispatch(new BackupRestored($backup, $targetSite));

            return true;
        } catch (\Exception $e) {
            Log::error('Backup restoration failed', [
                'backup_id' => $backupId,
                'target_site_id' => $targetSiteId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to restore backup: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Delete a backup.
     *
     * @param string $backupId The backup ID
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function deleteBackup(string $backupId): bool
    {
        try {
            $backup = $this->backupRepository->findById($backupId);
            if (!$backup) {
                throw new \RuntimeException('Backup not found');
            }

            // Delete backup file from storage
            if ($backup->storage_path && Storage::disk('backups')->exists($backup->storage_path)) {
                Storage::disk('backups')->delete($backup->storage_path);

                Log::info('Backup file deleted from storage', [
                    'backup_id' => $backupId,
                    'storage_path' => $backup->storage_path,
                ]);
            }

            // Delete backup record
            $this->backupRepository->delete($backupId);

            Log::info('Backup deleted', [
                'backup_id' => $backupId,
                'site_id' => $backup->site_id,
            ]);

            Event::dispatch(new BackupDeleted($backup));

            return true;
        } catch (\Exception $e) {
            Log::error('Backup deletion failed', [
                'backup_id' => $backupId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to delete backup: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Schedule automatic backup for a site.
     *
     * @param string $siteId The site ID
     * @param string $frequency Backup frequency (daily, weekly, monthly)
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function scheduleAutomaticBackup(string $siteId, string $frequency): bool
    {
        try {
            $site = $this->siteRepository->findById($siteId);
            if (!$site) {
                throw new \RuntimeException('Site not found');
            }

            // Validate frequency
            $allowedFrequencies = ['daily', 'weekly', 'monthly'];
            if (!in_array($frequency, $allowedFrequencies)) {
                throw new \RuntimeException(
                    'Invalid frequency. Allowed: ' . implode(', ', $allowedFrequencies)
                );
            }

            // Update site settings with backup schedule
            $settings = $site->settings ?? [];
            $settings['backup_schedule'] = [
                'enabled' => true,
                'frequency' => $frequency,
                'last_run' => null,
                'next_run' => $this->calculateNextBackupTime($frequency),
            ];

            $this->siteRepository->update($siteId, ['settings' => $settings]);

            Log::info('Automatic backup scheduled', [
                'site_id' => $siteId,
                'frequency' => $frequency,
                'next_run' => $settings['backup_schedule']['next_run'],
            ]);

            return true;
        } catch (\Exception $e) {
            Log::error('Automatic backup scheduling failed', [
                'site_id' => $siteId,
                'frequency' => $frequency,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to schedule automatic backup: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Get backups for a site that have a schedule.
     *
     * @param string $siteId The site ID
     * @return Collection Collection of backups
     * @throws \RuntimeException
     */
    public function getBackupsBySchedule(string $siteId): Collection
    {
        try {
            $site = $this->siteRepository->findById($siteId);
            if (!$site) {
                throw new \RuntimeException('Site not found');
            }

            $backups = $this->backupRepository->findBySiteId($siteId);

            Log::debug('Retrieved scheduled backups', [
                'site_id' => $siteId,
                'count' => $backups->count(),
            ]);

            return $backups;
        } catch (\Exception $e) {
            Log::error('Failed to retrieve scheduled backups', [
                'site_id' => $siteId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to get scheduled backups: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Cleanup expired backups for a site or all sites.
     *
     * @param string|null $siteId Optional site ID (null = all sites)
     * @return int Number of backups deleted
     * @throws \RuntimeException
     */
    public function cleanupExpiredBackups(string $siteId = null): int
    {
        try {
            $query = $siteId
                ? $this->backupRepository->findBySiteId($siteId)
                : $this->backupRepository->all();

            $expiredBackups = $query->filter(function ($backup) {
                return $backup->isExpired();
            });

            $deletedCount = 0;

            foreach ($expiredBackups as $backup) {
                try {
                    $this->deleteBackup($backup->id);
                    $deletedCount++;
                } catch (\Exception $e) {
                    Log::warning('Failed to delete expired backup', [
                        'backup_id' => $backup->id,
                        'error' => $e->getMessage(),
                    ]);
                }
            }

            Log::info('Expired backups cleaned up', [
                'site_id' => $siteId ?? 'all',
                'deleted_count' => $deletedCount,
            ]);

            return $deletedCount;
        } catch (\Exception $e) {
            Log::error('Expired backup cleanup failed', [
                'site_id' => $siteId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to cleanup expired backups: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Validate backup integrity.
     *
     * @param string $backupId The backup ID
     * @return array Validation results
     * @throws \RuntimeException
     */
    public function validateBackupIntegrity(string $backupId): array
    {
        try {
            $backup = $this->backupRepository->findById($backupId);
            if (!$backup) {
                throw new \RuntimeException('Backup not found');
            }

            $results = [
                'backup_id' => $backupId,
                'valid' => true,
                'checks' => [],
            ];

            // Check if backup file exists
            $fileExists = Storage::disk('backups')->exists($backup->storage_path);
            $results['checks']['file_exists'] = $fileExists;

            if (!$fileExists) {
                $results['valid'] = false;
                Log::warning('Backup file not found', [
                    'backup_id' => $backupId,
                    'storage_path' => $backup->storage_path,
                ]);
            } else {
                // Verify file size matches
                $actualSize = Storage::disk('backups')->size($backup->storage_path);
                $results['checks']['size_match'] = abs($actualSize - $backup->size_bytes) < 1024; // Allow 1KB variance

                if (!$results['checks']['size_match']) {
                    $results['valid'] = false;
                    Log::warning('Backup size mismatch', [
                        'backup_id' => $backupId,
                        'expected' => $backup->size_bytes,
                        'actual' => $actualSize,
                    ]);
                }

                // Verify checksum if available
                if ($backup->checksum) {
                    $actualChecksum = md5_file(Storage::disk('backups')->path($backup->storage_path));
                    $results['checks']['checksum_match'] = $actualChecksum === $backup->checksum;

                    if (!$results['checks']['checksum_match']) {
                        $results['valid'] = false;
                        Log::warning('Backup checksum mismatch', [
                            'backup_id' => $backupId,
                        ]);
                    }
                } else {
                    $results['checks']['checksum_match'] = null;
                }
            }

            // Check if backup has expired
            $results['checks']['not_expired'] = !$backup->isExpired();
            if ($backup->isExpired()) {
                Log::info('Backup has expired', [
                    'backup_id' => $backupId,
                    'expires_at' => $backup->expires_at,
                ]);
            }

            Log::info('Backup integrity validated', [
                'backup_id' => $backupId,
                'valid' => $results['valid'],
            ]);

            return $results;
        } catch (\Exception $e) {
            Log::error('Backup integrity validation failed', [
                'backup_id' => $backupId,
                'error' => $e->getMessage(),
            ]);
            throw new \RuntimeException('Failed to validate backup integrity: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Validate backup type.
     *
     * @param string $type Backup type
     * @throws \RuntimeException
     */
    private function validateBackupType(string $type): void
    {
        $allowedTypes = ['full', 'files', 'database'];
        if (!in_array($type, $allowedTypes)) {
            throw new \RuntimeException(
                'Invalid backup type. Allowed: ' . implode(', ', $allowedTypes)
            );
        }
    }

    /**
     * Generate storage path for backup file.
     *
     * @param \App\Models\Site $site
     * @param string $type
     * @return string Storage path
     */
    private function generateStoragePath(\App\Models\Site $site, string $type): string
    {
        $timestamp = now()->format('Y-m-d_H-i-s');
        $filename = "{$site->domain}_{$type}_{$timestamp}.tar.gz";

        return "backups/{$site->tenant_id}/{$site->id}/{$filename}";
    }

    /**
     * Calculate next backup time based on frequency.
     *
     * @param string $frequency
     * @return string ISO8601 datetime
     */
    private function calculateNextBackupTime(string $frequency): string
    {
        return match ($frequency) {
            'daily' => now()->addDay()->startOfDay()->toIso8601String(),
            'weekly' => now()->addWeek()->startOfWeek()->toIso8601String(),
            'monthly' => now()->addMonth()->startOfMonth()->toIso8601String(),
            default => now()->addDay()->toIso8601String(),
        };
    }
}
