<?php

namespace App\Events\Backup;

use App\Events\AbstractDomainEvent;
use App\Models\SiteBackup;

/**
 * Fired when backup execution completes successfully.
 *
 * TIMING: Emitted AFTER backup->update() with size/path in CreateBackupJob
 * LISTENERS:
 * - RecordAuditLog: Creates audit trail for successful backup
 * - SendNotification: Notifies user of backup completion
 * - RecordMetrics: Records backup duration, size, and success counter
 */
class BackupCompleted extends AbstractDomainEvent
{
    /**
     * Create a new BackupCompleted event instance.
     *
     * @param  SiteBackup  $backup  The completed backup record
     * @param  int  $sizeBytes  The actual size of the backup in bytes
     * @param  int  $durationSeconds  How long the backup took to complete
     * @param  string|null  $actorId  The ID of the actor (defaults to 'system')
     */
    public function __construct(
        public readonly SiteBackup $backup,
        public readonly int $sizeBytes,
        public readonly int $durationSeconds,
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
            'backup_id' => $this->backup->id,
            'site_id' => $this->backup->site_id,
            'backup_type' => $this->backup->backup_type,
            'size_bytes' => $this->sizeBytes,
            'size_formatted' => $this->backup->getSizeFormatted(),
            'duration_seconds' => $this->durationSeconds,
        ]);
    }
}
