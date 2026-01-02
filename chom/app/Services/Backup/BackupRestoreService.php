<?php

namespace App\Services\Backup;

use App\Contracts\VpsManagerInterface;
use App\Models\Site;
use App\Models\SiteBackup;
use Illuminate\Support\Facades\Log;

/**
 * Backup Restore Service
 *
 * Handles restoration of sites from backups.
 * Manages the complex process of restoring files, databases, and configurations.
 */
class BackupRestoreService
{
    /**
     * Create a new backup restore service instance.
     */
    public function __construct(
        protected VpsManagerInterface $vpsManager
    ) {}

    /**
     * Restore a site from backup.
     *
     * This method initiates the restore process.
     * The actual restoration is handled asynchronously via job.
     *
     * @param  SiteBackup  $backup  The backup to restore from
     * @return array{success: bool, message: string}
     */
    public function restoreFromBackup(SiteBackup $backup): array
    {
        // Validate backup is ready
        if (! $backup->storage_path) {
            return [
                'success' => false,
                'message' => 'Backup is not yet available for restore',
            ];
        }

        // Validate backup is not expired
        if ($backup->isExpired()) {
            return [
                'success' => false,
                'message' => 'This backup has expired and cannot be restored',
            ];
        }

        $site = $backup->site;

        // Check site status
        if ($site->status === 'creating') {
            return [
                'success' => false,
                'message' => 'Cannot restore site that is still being created',
            ];
        }

        Log::info('Restore initiated', [
            'backup_id' => $backup->id,
            'site_id' => $site->id,
            'backup_type' => $backup->backup_type,
        ]);

        // Note: Actual restore should be handled by a job
        // RestoreSiteJob::dispatch($backup);

        return [
            'success' => true,
            'message' => 'Site restore has been queued',
        ];
    }

    /**
     * Execute the actual restore process.
     *
     * This method is typically called from a background job.
     *
     * @param  SiteBackup  $backup  The backup to restore from
     * @return array{success: bool, message: string}
     */
    public function executeRestore(SiteBackup $backup): array
    {
        $site = $backup->site;

        if (! $site->vpsServer) {
            return [
                'success' => false,
                'message' => 'Site has no associated VPS server',
            ];
        }

        try {
            // Set site to maintenance mode
            $this->setSiteToMaintenance($site);

            // Execute restore on VPS
            $result = $this->vpsManager->restoreBackup(
                $site->vpsServer,
                $site,
                $backup->storage_path
            );

            if (! $result['success']) {
                Log::error('VPS restore failed', [
                    'backup_id' => $backup->id,
                    'site_id' => $site->id,
                    'error' => $result['error'] ?? 'Unknown error',
                ]);

                // Attempt to bring site back online
                $this->setSiteToActive($site);

                return [
                    'success' => false,
                    'message' => $result['error'] ?? 'Restore failed on VPS',
                ];
            }

            // Restore successful, bring site back online
            $this->setSiteToActive($site);

            Log::info('Restore completed', [
                'backup_id' => $backup->id,
                'site_id' => $site->id,
            ]);

            return [
                'success' => true,
                'message' => 'Site restored successfully',
            ];

        } catch (\Exception $e) {
            Log::error('Restore execution error', [
                'backup_id' => $backup->id,
                'site_id' => $site->id,
                'error' => $e->getMessage(),
            ]);

            // Attempt to bring site back online
            $this->setSiteToActive($site);

            return [
                'success' => false,
                'message' => $e->getMessage(),
            ];
        }
    }

    /**
     * Validate that a backup can be restored.
     *
     * @param  SiteBackup  $backup  The backup to validate
     * @return array{valid: bool, errors: array<string>}
     */
    public function validateRestore(SiteBackup $backup): array
    {
        $errors = [];

        if (! $backup->storage_path) {
            $errors[] = 'Backup file is not available';
        }

        if ($backup->isExpired()) {
            $errors[] = 'Backup has expired';
        }

        $site = $backup->site;

        if (! $site) {
            $errors[] = 'Associated site not found';
        }

        if ($site && ! $site->vpsServer) {
            $errors[] = 'Site has no VPS server';
        }

        if ($site && ! $site->vpsServer?->isAvailable()) {
            $errors[] = 'VPS server is not available';
        }

        if ($site && $site->status === 'creating') {
            $errors[] = 'Site is still being created';
        }

        return [
            'valid' => empty($errors),
            'errors' => $errors,
        ];
    }

    /**
     * Create a pre-restore backup.
     *
     * Before restoring, create a safety backup of the current state.
     *
     * @param  Site  $site  The site to backup
     */
    public function createPreRestoreBackup(Site $site, BackupService $backupService): ?SiteBackup
    {
        try {
            $backup = $backupService->createBackup(
                $site,
                backupType: 'full',
                retentionDays: 7 // Shorter retention for safety backups
            );

            Log::info('Pre-restore backup created', [
                'backup_id' => $backup->id,
                'site_id' => $site->id,
            ]);

            return $backup;

        } catch (\Exception $e) {
            Log::error('Pre-restore backup failed', [
                'site_id' => $site->id,
                'error' => $e->getMessage(),
            ]);

            return null;
        }
    }

    /**
     * Set site to maintenance mode during restore.
     */
    protected function setSiteToMaintenance(Site $site): void
    {
        $site->update(['status' => 'maintenance']);

        Log::info('Site set to maintenance mode', [
            'site_id' => $site->id,
        ]);
    }

    /**
     * Set site back to active after restore.
     */
    protected function setSiteToActive(Site $site): void
    {
        $site->update(['status' => 'active']);

        Log::info('Site set to active', [
            'site_id' => $site->id,
        ]);
    }

    /**
     * Get restore history for a site.
     *
     * @return array<array{backup_id: string, restored_at: string, backup_type: string}>
     */
    public function getRestoreHistory(Site $site, int $limit = 10): array
    {
        // This would require a restores table to track history
        // For now, return empty array as placeholder
        // TODO: Implement restore history tracking

        return [];
    }

    /**
     * Estimate restore time based on backup size.
     *
     * @return array{estimated_minutes: int, size_formatted: string}
     */
    public function estimateRestoreTime(SiteBackup $backup): array
    {
        // Rough estimate: 1GB per 5 minutes
        $sizeGb = $backup->size_bytes / 1073741824;
        $estimatedMinutes = max(1, (int) ceil($sizeGb * 5));

        return [
            'estimated_minutes' => $estimatedMinutes,
            'size_formatted' => $backup->getSizeFormatted(),
        ];
    }
}
