<?php

namespace App\Jobs;

use App\Models\Site;
use App\Models\SiteBackup;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

class CreateBackupJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    /**
     * The number of times the job may be attempted.
     */
    public int $tries = 3;

    /**
     * The number of seconds to wait before retrying the job.
     */
    public int $backoff = 120;

    /**
     * Create a new job instance.
     */
    public function __construct(
        public Site $site,
        public string $backupType = 'full',
        public ?int $retentionDays = null
    ) {}

    /**
     * Execute the job.
     */
    public function handle(VPSManagerBridge $vpsManager): void
    {
        $site = $this->site;
        $vps = $site->vpsServer;

        if (! $vps) {
            Log::error('CreateBackupJob: No VPS server associated with site', [
                'site_id' => $site->id,
                'domain' => $site->domain,
            ]);

            return;
        }

        Log::info('CreateBackupJob: Starting backup creation', [
            'site_id' => $site->id,
            'domain' => $site->domain,
            'backup_type' => $this->backupType,
        ]);

        // Track backup duration for metrics
        $startTime = microtime(true);

        // Create backup record first with pending status
        $backup = SiteBackup::create([
            'site_id' => $site->id,
            'backup_type' => $this->backupType,
            'status' => 'pending',
            'storage_path' => null,
            'size_bytes' => 0,
            'checksum' => null,
            'retention_days' => $this->retentionDays ?? $site->tenant?->tierLimits?->backup_retention_days ?? 7,
            'expires_at' => now()->addDays($this->retentionDays ?? $site->tenant?->tierLimits?->backup_retention_days ?? 7),
        ]);

        // Emit BackupCreated event
        \App\Events\Backup\BackupCreated::dispatch($backup, $site);

        try {
            // Determine backup components
            $components = match ($this->backupType) {
                'full' => ['files', 'database'],
                'files' => ['files'],
                'database' => ['database'],
                default => ['files', 'database'],
            };

            $result = $vpsManager->createBackup($vps, $site->domain, $components);

            if ($result['success']) {
                $duration = (int) round(microtime(true) - $startTime);

                // Update backup record with actual data
                $backup->update([
                    'status' => 'completed',
                    'storage_path' => $result['data']['path'] ?? $backup->storage_path,
                    'size_bytes' => $result['data']['size'] ?? 0,
                    'checksum' => $result['data']['checksum'] ?? null,
                    'completed_at' => now(),
                ]);

                // Emit BackupCompleted event
                \App\Events\Backup\BackupCompleted::dispatch(
                    $backup->fresh(),
                    $backup->size_bytes,
                    $duration
                );

                Log::info('CreateBackupJob: Backup created successfully', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'backup_id' => $backup->id,
                    'size' => $backup->getSizeFormatted(),
                    'duration_seconds' => $duration,
                ]);
            } else {
                // Capture data before deletion (for event)
                $siteId = $site->id;
                $backupType = $this->backupType;
                $errorMessage = $result['output'] ?? 'Backup creation failed with no output';

                // Delete the pending backup record on failure
                $backup->delete();

                // Emit BackupFailed event
                \App\Events\Backup\BackupFailed::dispatch($siteId, $backupType, $errorMessage);

                Log::error('CreateBackupJob: Backup creation failed', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'output' => $result['output'] ?? 'No output',
                ]);
            }
        } catch (\Exception $e) {
            // Capture data before deletion (for event)
            $siteId = $site->id;
            $backupType = $this->backupType;

            // Delete the pending backup record on exception
            $backup->delete();

            // Emit BackupFailed event
            \App\Events\Backup\BackupFailed::dispatch($siteId, $backupType, $e->getMessage());

            Log::error('CreateBackupJob: Exception during backup creation', [
                'site_id' => $site->id,
                'domain' => $site->domain,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            throw $e; // Re-throw to trigger retry
        }
    }

    /**
     * Handle a job failure.
     */
    public function failed(?\Throwable $exception): void
    {
        Log::error('CreateBackupJob: Job failed after all retries', [
            'site_id' => $this->site->id,
            'domain' => $this->site->domain,
            'backup_type' => $this->backupType,
            'error' => $exception?->getMessage(),
        ]);

        // Emit BackupFailed event (if not already emitted)
        \App\Events\Backup\BackupFailed::dispatch(
            $this->site->id,
            $this->backupType,
            $exception?->getMessage() ?? 'Job failed after all retries'
        );
    }
}
