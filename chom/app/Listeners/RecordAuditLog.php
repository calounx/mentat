<?php

namespace App\Listeners;

use App\Events\AbstractDomainEvent;
use App\Models\AuditLog;
use App\Models\Organization;
use App\Models\User;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\Log;

/**
 * Automatically records audit logs for all domain events.
 *
 * QUEUED: Yes (non-blocking, audit logs can be slightly delayed)
 * REPLACES: Manual AuditLog::log() calls scattered throughout controllers/services
 *
 * This listener provides centralized, automatic audit logging for all domain events.
 * Instead of manually calling AuditLog::log() in every controller/service, we capture
 * the event and log it automatically with proper context and severity.
 *
 * @package App\Listeners
 */
class RecordAuditLog implements ShouldQueue
{
    /**
     * The name of the queue the job should be sent to.
     *
     * @var string
     */
    public $queue = 'default';

    /**
     * The number of times the queued listener may be attempted.
     *
     * @var int
     */
    public $tries = 3;

    /**
     * The number of seconds to wait before retrying.
     *
     * @var int
     */
    public $backoff = 30;

    /**
     * Handle any domain event and create audit log entry.
     *
     * @param AbstractDomainEvent $event
     * @return void
     */
    public function handle(AbstractDomainEvent $event): void
    {
        $user = $event->actorId ? User::find($event->actorId) : null;
        $organization = $user?->organization;

        $metadata = $event->getMetadata();

        AuditLog::log(
            action: $this->mapEventToAction($event),
            organization: $organization,
            user: $user,
            resourceType: $this->extractResourceType($metadata),
            resourceId: $this->extractResourceId($metadata),
            metadata: $metadata,
            severity: $this->determineSeverity($event)
        );

        Log::debug('Audit log created for event', [
            'event' => $event->getEventName(),
            'action' => $this->mapEventToAction($event),
            'severity' => $this->determineSeverity($event),
        ]);
    }

    /**
     * Map event class to audit action string.
     *
     * @param AbstractDomainEvent $event
     * @return string
     */
    private function mapEventToAction(AbstractDomainEvent $event): string
    {
        return match (true) {
            $event instanceof \App\Events\Site\SiteCreated => 'site.created',
            $event instanceof \App\Events\Site\SiteProvisioned => 'site.provisioned',
            $event instanceof \App\Events\Site\SiteProvisioningFailed => 'site.provisioning_failed',
            $event instanceof \App\Events\Site\SiteDeleted => 'site.deleted',
            $event instanceof \App\Events\Backup\BackupCreated => 'backup.created',
            $event instanceof \App\Events\Backup\BackupCompleted => 'backup.completed',
            $event instanceof \App\Events\Backup\BackupFailed => 'backup.failed',
            default => 'unknown.event',
        };
    }

    /**
     * Extract resource type from event metadata.
     *
     * @param array<string, mixed> $metadata
     * @return string|null
     */
    private function extractResourceType(array $metadata): ?string
    {
        if (isset($metadata['site_id'])) {
            return 'site';
        }
        if (isset($metadata['backup_id'])) {
            return 'backup';
        }
        return null;
    }

    /**
     * Extract resource ID from event metadata.
     *
     * @param array<string, mixed> $metadata
     * @return string|null
     */
    private function extractResourceId(array $metadata): ?string
    {
        return $metadata['site_id']
            ?? $metadata['backup_id']
            ?? null;
    }

    /**
     * Determine audit log severity based on event type.
     *
     * @param AbstractDomainEvent $event
     * @return string
     */
    private function determineSeverity(AbstractDomainEvent $event): string
    {
        return match (true) {
            // High severity: failures and errors
            $event instanceof \App\Events\Site\SiteProvisioningFailed,
            $event instanceof \App\Events\Backup\BackupFailed => 'high',

            // Medium severity: normal operations
            default => 'medium',
        };
    }

    /**
     * Handle a job failure.
     *
     * @param AbstractDomainEvent $event
     * @param \Throwable $exception
     * @return void
     */
    public function failed(AbstractDomainEvent $event, \Throwable $exception): void
    {
        Log::error('RecordAuditLog listener failed', [
            'event' => $event->getEventName(),
            'error' => $exception->getMessage(),
            'trace' => $exception->getTraceAsString(),
        ]);
    }
}
