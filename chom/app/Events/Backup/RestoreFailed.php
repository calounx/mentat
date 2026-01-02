<?php

namespace App\Events\Backup;

use App\Events\AbstractDomainEvent;

/**
 * Fired when a backup restore operation fails.
 *
 * TIMING: Emitted when restore fails or throws exception in RestoreBackupJob
 * LISTENERS:
 * - RecordAuditLog: Creates audit trail for failed restore
 * - SendNotification: Notifies administrators of restore failure
 * - RecordMetrics: Records restore failure counter
 */
class RestoreFailed extends AbstractDomainEvent
{
    /**
     * Create a new RestoreFailed event instance.
     *
     * @param  string  $siteId  The ID of the site being restored
     * @param  string  $backupId  The ID of the backup being restored
     * @param  string  $errorMessage  The error that occurred
     * @param  string|null  $actorId  The ID of the actor (defaults to system)
     */
    public function __construct(
        public readonly string $siteId,
        public readonly string $backupId,
        public readonly string $errorMessage,
        ?string $actorId = null
    ) {
        parent::__construct($actorId, 'system');
    }

    /**
     * Get event metadata for logging and auditing.
     *
     * @return array<string, mixed>
     */
    public function getMetadata(): array
    {
        return array_merge(parent::getMetadata(), [
            'site_id' => $this->siteId,
            'backup_id' => $this->backupId,
            'error_message' => $this->errorMessage,
            'restore_failed_at' => now()->toIso8601String(),
        ]);
    }
}
