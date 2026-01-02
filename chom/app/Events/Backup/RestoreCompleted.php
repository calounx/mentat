<?php

namespace App\Events\Backup;

use App\Events\AbstractDomainEvent;
use App\Models\Site;
use App\Models\SiteBackup;

/**
 * Fired when a backup restore operation completes successfully.
 *
 * TIMING: Emitted AFTER restore completes successfully in RestoreBackupJob
 * LISTENERS:
 * - RecordAuditLog: Creates audit trail for successful restore
 * - SendNotification: Notifies administrators/users of restore completion
 * - RecordMetrics: Records restore duration and success counter
 */
class RestoreCompleted extends AbstractDomainEvent
{
    /**
     * Create a new RestoreCompleted event instance.
     *
     * @param  SiteBackup  $backup  The backup that was restored
     * @param  Site  $site  The site that was restored
     * @param  int  $durationSeconds  How long the restore took to complete
     * @param  string|null  $actorId  The ID of the actor (defaults to system)
     */
    public function __construct(
        public readonly SiteBackup $backup,
        public readonly Site $site,
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
            'site_id' => $this->site->id,
            'domain' => $this->site->domain,
            'backup_type' => $this->backup->backup_type,
            'duration_seconds' => $this->durationSeconds,
            'restore_completed_at' => now()->toIso8601String(),
        ]);
    }
}
