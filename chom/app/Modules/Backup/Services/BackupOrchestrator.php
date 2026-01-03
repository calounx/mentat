<?php

declare(strict_types=1);

namespace App\Modules\Backup\Services;

use App\Models\SiteBackup;
use App\Modules\Backup\ValueObjects\BackupConfiguration;
use App\Modules\Backup\ValueObjects\RetentionPolicy;
use App\Services\BackupService;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\Log;

/**
 * Backup Orchestrator Service
 *
 * Orchestrates backup operations by wrapping the existing BackupService
 * with module-specific context and value objects.
 */
class BackupOrchestrator
{
    public function __construct(
        private readonly BackupService $backupService
    ) {
    }

    /**
     * Create a backup with configuration.
     *
     * @param string $siteId Site ID
     * @param BackupConfiguration $config Backup configuration
     * @return SiteBackup Created backup
     * @throws \RuntimeException
     */
    public function createBackup(string $siteId, BackupConfiguration $config): SiteBackup
    {
        Log::info('Backup module: Creating backup', [
            'site_id' => $siteId,
            'type' => $config->getType(),
            'retention_days' => $config->getRetentionDays(),
        ]);

        return $this->backupService->createBackup(
            $siteId,
            $config->getType(),
            $config->getRetentionDays()
        );
    }

    /**
     * Restore a backup.
     *
     * @param string $backupId Backup ID
     * @param string|null $targetSiteId Target site ID
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function restoreBackup(string $backupId, ?string $targetSiteId = null): bool
    {
        Log::info('Backup module: Restoring backup', [
            'backup_id' => $backupId,
            'target_site_id' => $targetSiteId ?? 'original',
        ]);

        return $this->backupService->restoreBackup($backupId, $targetSiteId);
    }

    /**
     * Delete a backup.
     *
     * @param string $backupId Backup ID
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function deleteBackup(string $backupId): bool
    {
        Log::info('Backup module: Deleting backup', [
            'backup_id' => $backupId,
        ]);

        return $this->backupService->deleteBackup($backupId);
    }

    /**
     * Schedule automatic backups.
     *
     * @param string $siteId Site ID
     * @param string $frequency Backup frequency
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function scheduleAutomaticBackup(string $siteId, string $frequency): bool
    {
        Log::info('Backup module: Scheduling automatic backup', [
            'site_id' => $siteId,
            'frequency' => $frequency,
        ]);

        return $this->backupService->scheduleAutomaticBackup($siteId, $frequency);
    }

    /**
     * Apply retention policy and cleanup old backups.
     *
     * @param string $siteId Site ID
     * @param RetentionPolicy $policy Retention policy
     * @return int Number of backups deleted
     * @throws \RuntimeException
     */
    public function applyRetentionPolicy(string $siteId, RetentionPolicy $policy): int
    {
        Log::info('Backup module: Applying retention policy', [
            'site_id' => $siteId,
            'max_backups' => $policy->getMaxBackups(),
            'max_age_days' => $policy->getMaxAgeDays(),
        ]);

        return $this->backupService->cleanupExpiredBackups($siteId);
    }

    /**
     * Validate backup integrity.
     *
     * @param string $backupId Backup ID
     * @return array Validation results
     * @throws \RuntimeException
     */
    public function validateIntegrity(string $backupId): array
    {
        Log::info('Backup module: Validating backup integrity', [
            'backup_id' => $backupId,
        ]);

        return $this->backupService->validateBackupIntegrity($backupId);
    }

    /**
     * Get backups for a site.
     *
     * @param string $siteId Site ID
     * @return Collection Backups collection
     * @throws \RuntimeException
     */
    public function getBackupsForSite(string $siteId): Collection
    {
        return $this->backupService->getBackupsBySchedule($siteId);
    }

    /**
     * Get backup statistics for a site.
     *
     * @param string $siteId Site ID
     * @return array Backup statistics
     */
    public function getStatistics(string $siteId): array
    {
        $backups = $this->getBackupsForSite($siteId);

        $totalSize = $backups->sum('size_bytes');
        $completedBackups = $backups->where('status', 'completed')->count();
        $failedBackups = $backups->where('status', 'failed')->count();
        $lastBackup = $backups->sortByDesc('created_at')->first();

        return [
            'total_backups' => $backups->count(),
            'completed_backups' => $completedBackups,
            'failed_backups' => $failedBackups,
            'total_size_bytes' => $totalSize,
            'total_size_mb' => round($totalSize / 1024 / 1024, 2),
            'total_size_gb' => round($totalSize / 1024 / 1024 / 1024, 2),
            'last_backup_at' => $lastBackup?->created_at?->toIso8601String(),
            'last_backup_status' => $lastBackup?->status,
        ];
    }
}
