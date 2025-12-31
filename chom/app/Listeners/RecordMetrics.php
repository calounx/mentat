<?php

namespace App\Listeners;

use App\Contracts\ObservabilityInterface;
use App\Events\Backup\BackupCompleted;
use App\Events\Backup\BackupFailed;
use App\Events\Site\SiteCreated;
use App\Events\Site\SiteDeleted;
use App\Events\Site\SiteProvisioned;
use App\Events\Site\SiteProvisioningFailed;
use Illuminate\Support\Facades\Log;

/**
 * Records Prometheus metrics for all domain events.
 *
 * QUEUED: No (metrics should be recorded immediately for accurate monitoring)
 *
 * This listener integrates with the observability stack (Prometheus) to record
 * metrics counters and histograms for all significant business events.
 *
 * @package App\Listeners
 */
class RecordMetrics
{
    /**
     * Create a new RecordMetrics listener instance.
     *
     * @param ObservabilityInterface $observability
     */
    public function __construct(
        private ObservabilityInterface $observability
    ) {}

    /**
     * Handle site created event.
     *
     * Increments the sites_created_total counter.
     *
     * @param SiteCreated $event
     * @return void
     */
    public function handleSiteCreated(SiteCreated $event): void
    {
        $this->observability->incrementCounter('sites_created_total', 1, [
            'tenant_id' => $event->tenant->id,
            'site_type' => $event->site->site_type,
            'php_version' => $event->site->php_version,
        ]);

        Log::debug('Metric recorded: sites_created_total', [
            'site_id' => $event->site->id,
            'site_type' => $event->site->site_type,
        ]);
    }

    /**
     * Handle site provisioned event.
     *
     * Increments success counter and records provisioning duration.
     *
     * @param SiteProvisioned $event
     * @return void
     */
    public function handleSiteProvisioned(SiteProvisioned $event): void
    {
        $this->observability->incrementCounter('sites_provisioned_total', 1, [
            'tenant_id' => $event->site->tenant_id,
            'site_type' => $event->site->site_type,
        ]);

        if (isset($event->provisioningDetails['duration'])) {
            $this->observability->recordHistogram(
                'site_provisioning_duration_seconds',
                $event->provisioningDetails['duration'],
                ['site_type' => $event->site->site_type]
            );
        }

        Log::debug('Metrics recorded: sites_provisioned_total + duration', [
            'site_id' => $event->site->id,
            'duration' => $event->provisioningDetails['duration'] ?? null,
        ]);
    }

    /**
     * Handle site provisioning failed event.
     *
     * Increments the failure counter for monitoring.
     *
     * @param SiteProvisioningFailed $event
     * @return void
     */
    public function handleSiteProvisioningFailed(SiteProvisioningFailed $event): void
    {
        $this->observability->incrementCounter('sites_provisioning_failed_total', 1, [
            'tenant_id' => $event->site->tenant_id,
            'site_type' => $event->site->site_type,
        ]);

        Log::debug('Metric recorded: sites_provisioning_failed_total', [
            'site_id' => $event->site->id,
            'error' => substr($event->errorMessage, 0, 100),
        ]);
    }

    /**
     * Handle site deleted event.
     *
     * Increments the sites_deleted_total counter.
     *
     * @param SiteDeleted $event
     * @return void
     */
    public function handleSiteDeleted(SiteDeleted $event): void
    {
        $this->observability->incrementCounter('sites_deleted_total', 1, [
            'tenant_id' => $event->tenantId,
        ]);

        Log::debug('Metric recorded: sites_deleted_total', [
            'site_id' => $event->siteId,
            'domain' => $event->domain,
        ]);
    }

    /**
     * Handle backup completed event.
     *
     * Records backup metrics including duration and size.
     *
     * @param BackupCompleted $event
     * @return void
     */
    public function handleBackupCompleted(BackupCompleted $event): void
    {
        $this->observability->incrementCounter('backups_completed_total', 1, [
            'backup_type' => $event->backup->backup_type,
        ]);

        $this->observability->recordHistogram(
            'backup_duration_seconds',
            $event->durationSeconds,
            ['backup_type' => $event->backup->backup_type]
        );

        $this->observability->recordHistogram(
            'backup_size_bytes',
            $event->sizeBytes,
            ['backup_type' => $event->backup->backup_type]
        );

        Log::debug('Metrics recorded: backups_completed_total + duration + size', [
            'backup_id' => $event->backup->id,
            'duration' => $event->durationSeconds,
            'size' => $event->sizeBytes,
        ]);
    }

    /**
     * Handle backup failed event.
     *
     * Increments the backup failure counter.
     *
     * @param BackupFailed $event
     * @return void
     */
    public function handleBackupFailed(BackupFailed $event): void
    {
        $this->observability->incrementCounter('backups_failed_total', 1, [
            'backup_type' => $event->backupType,
        ]);

        Log::debug('Metric recorded: backups_failed_total', [
            'site_id' => $event->siteId,
            'backup_type' => $event->backupType,
        ]);
    }
}
