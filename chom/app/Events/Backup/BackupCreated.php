<?php

namespace App\Events\Backup;

use App\Events\AbstractDomainEvent;
use App\Models\SiteBackup;

/**
 * Fired when a backup record is created (before actual backup execution).
 *
 * TIMING: Emitted AFTER SiteBackup::create() in CreateBackupJob
 * LISTENERS:
 * - RecordAuditLog: Creates audit trail for backup initiation
 * - RecordMetrics: Records backup_initiated_total counter
 *
 * NOTE: This is fired when the backup JOB starts, not when it completes.
 * See BackupCompleted for the completion event.
 *
 * @package App\Events\Backup
 */
class BackupCreated extends AbstractDomainEvent
{
    /**
     * Create a new BackupCreated event instance.
     *
     * @param SiteBackup $backup The newly created backup record
     * @param string|null $actorId The ID of the user who initiated the backup
     */
    public function __construct(
        public readonly SiteBackup $backup,
        ?string $actorId = null
    ) {
        parent::__construct($actorId);
    }

    /**
     * Get event metadata for logging and auditing.
     *
     * @return array<string, mixed>
     */
    public function getMetadata(): array
    {
        return array_merge(parent::getMetadata(), [
            'backup_id' => $this->backup->id,
            'site_id' => $this->backup->site_id,
            'backup_type' => $this->backup->backup_type,
            'retention_days' => $this->backup->retention_days,
        ]);
    }
}
