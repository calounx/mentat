<?php

namespace App\Listeners;

use App\Events\Backup\BackupCompleted;
use App\Events\Backup\BackupFailed;
use App\Events\Site\SiteProvisioned;
use App\Events\Site\SiteProvisioningFailed;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\Log;

/**
 * Sends user notifications for significant events.
 *
 * QUEUED: Yes (email sending is slow and should be async)
 *
 * This listener handles all user-facing notifications for important events
 * like successful site provisioning, provisioning failures, backup completion, etc.
 *
 * TODO: Integrate with actual email/notification service when available.
 * For now, this logs notification events for tracking.
 *
 * @package App\Listeners
 */
class SendNotification implements ShouldQueue
{
    /**
     * The name of the queue the job should be sent to.
     *
     * @var string
     */
    public $queue = 'notifications';

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
    public $backoff = 60;

    /**
     * Handle site provisioned event.
     *
     * Sends success notification when a site is fully provisioned.
     *
     * @param SiteProvisioned $event
     * @return void
     */
    public function handleSiteProvisioned(SiteProvisioned $event): void
    {
        // TODO: Send actual email notification when mail service is configured
        Log::info('Notification: Site provisioned successfully', [
            'site_id' => $event->site->id,
            'domain' => $event->site->domain,
            'site_type' => $event->site->site_type,
            'tenant_id' => $event->site->tenant_id,
            'duration' => $event->provisioningDetails['duration'] ?? null,
        ]);

        // Future implementation:
        // Mail::to($event->site->tenant->owner)->send(
        //     new SiteProvisionedMail($event->site)
        // );
    }

    /**
     * Handle site provisioning failed event.
     *
     * Sends error notification when site provisioning fails.
     *
     * @param SiteProvisioningFailed $event
     * @return void
     */
    public function handleSiteProvisioningFailed(SiteProvisioningFailed $event): void
    {
        // TODO: Send error notification to user and ops team
        Log::warning('Notification: Site provisioning failed', [
            'site_id' => $event->site->id,
            'domain' => $event->site->domain,
            'error' => $event->errorMessage,
            'tenant_id' => $event->site->tenant_id,
        ]);

        // Future implementation:
        // Mail::to($event->site->tenant->owner)->send(
        //     new SiteProvisioningFailedMail($event->site, $event->errorMessage)
        // );
        //
        // // Also alert ops team
        // Mail::to(config('mail.ops_team'))->send(
        //     new OpsAlertMail('Site Provisioning Failed', $event->getMetadata())
        // );
    }

    /**
     * Handle backup completed event.
     *
     * Sends confirmation when a backup completes successfully.
     *
     * @param BackupCompleted $event
     * @return void
     */
    public function handleBackupCompleted(BackupCompleted $event): void
    {
        Log::info('Notification: Backup completed', [
            'backup_id' => $event->backup->id,
            'site_id' => $event->backup->site_id,
            'backup_type' => $event->backup->backup_type,
            'size' => $event->backup->getSizeFormatted(),
            'duration_seconds' => $event->durationSeconds,
        ]);

        // Future implementation:
        // Mail::to($event->backup->site->tenant->owner)->send(
        //     new BackupCompletedMail($event->backup)
        // );
    }

    /**
     * Handle backup failed event.
     *
     * Sends error notification when backup fails.
     *
     * @param BackupFailed $event
     * @return void
     */
    public function handleBackupFailed(BackupFailed $event): void
    {
        Log::warning('Notification: Backup failed', [
            'site_id' => $event->siteId,
            'backup_type' => $event->backupType,
            'error' => $event->errorMessage,
        ]);

        // Future implementation:
        // $site = Site::find($event->siteId);
        // if ($site) {
        //     Mail::to($site->tenant->owner)->send(
        //         new BackupFailedMail($site, $event->errorMessage)
        //     );
        // }
    }

    /**
     * Handle a job failure.
     *
     * @param mixed $event
     * @param \Throwable $exception
     * @return void
     */
    public function failed($event, \Throwable $exception): void
    {
        Log::error('SendNotification listener failed', [
            'event' => get_class($event),
            'error' => $exception->getMessage(),
            'trace' => $exception->getTraceAsString(),
        ]);
    }
}
