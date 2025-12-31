<?php

namespace App\Events\Backup;

use App\Events\AbstractDomainEvent;

/**
 * Fired when backup execution fails.
 *
 * TIMING: Emitted in CreateBackupJob catch block BEFORE backup->delete()
 * LISTENERS:
 * - RecordAuditLog: Creates high-severity audit trail for failure
 * - SendNotification: Notifies user of backup failure
 * - RecordMetrics: Records backup_failed_total counter
 *
 * NOTE: We don't pass the SiteBackup model because it will be deleted
 * after this event is fired. We pass primitive data instead.
 *
 * @package App\Events\Backup
 */
class BackupFailed extends AbstractDomainEvent
{
    /**
     * Create a new BackupFailed event instance.
     *
     * @param string $siteId The UUID of the site
     * @param string $backupType The type of backup that failed ('full', 'database', 'files')
     * @param string $errorMessage The error message describing what went wrong
     * @param string|null $actorId The ID of the actor (defaults to 'system')
     */
    public function __construct(
        public readonly string $siteId,
        public readonly string $backupType,
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
            'backup_type' => $this->backupType,
            'error' => $this->errorMessage,
        ]);
    }
}
