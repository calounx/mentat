<?php

namespace App\Events\Backup;

use App\Events\AbstractDomainEvent;
use App\Models\Site;
use App\Models\SiteBackup;

/**
 * Fired when a backup restore operation begins.
 *
 * TIMING: Emitted BEFORE the restore process starts in RestoreBackupJob
 * LISTENERS:
 * - RecordAuditLog: Creates audit trail for restore initiation
 * - SendNotification: Notifies administrators of restore start
 * - RecordMetrics: Records restore start counter
 */
class RestoreStarted extends AbstractDomainEvent
{
    /**
     * Create a new RestoreStarted event instance.
     *
     * @param  SiteBackup  $backup  The backup being restored
     * @param  Site  $site  The site being restored to
     * @param  string  $restoreType  Type of restore (full|database|files)
     * @param  string|null  $actorId  The ID of the actor (user who initiated restore)
     */
    public function __construct(
        public readonly SiteBackup $backup,
        public readonly Site $site,
        public readonly string $restoreType = 'full',
        ?string $actorId = null
    ) {
        parent::__construct($actorId, 'user');
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
            'site_id' => $this->site->id,
            'domain' => $this->site->domain,
            'restore_type' => $this->restoreType,
            'backup_type' => $this->backup->backup_type,
            'backup_created_at' => $this->backup->created_at->toIso8601String(),
        ]);
    }
}
