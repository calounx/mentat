<?php

namespace App\Jobs;

use App\Events\Backup\RestoreCompleted;
use App\Events\Backup\RestoreFailed;
use App\Events\Backup\RestoreStarted;
use App\Models\SiteBackup;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

class RestoreBackupJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    /**
     * The number of times the job may be attempted.
     */
    public int $tries = 2;

    /**
     * The number of seconds to wait before retrying the job.
     */
    public int $backoff = 180;

    /**
     * The number of seconds the job can run before timing out.
     */
    public int $timeout = 1800; // 30 minutes for large restores

    /**
     * Create a new job instance.
     */
    public function __construct(
        public SiteBackup $backup,
        public string $restoreType = 'full',
        public bool $force = false,
        public bool $skipVerify = false,
        public ?string $actorId = null
    ) {}

    /**
     * Execute the job.
     */
    public function handle(VPSManagerBridge $vpsManager): void
    {
        $backup = $this->backup;
        $site = $backup->site;

        if (! $site) {
            Log::error('RestoreBackupJob: No site associated with backup', [
                'backup_id' => $backup->id,
            ]);

            return;
        }

        $vps = $site->vpsServer;

        if (! $vps) {
            Log::error('RestoreBackupJob: No VPS server associated with site', [
                'backup_id' => $backup->id,
                'site_id' => $site->id,
                'domain' => $site->domain,
            ]);

            return;
        }

        // Emit RestoreStarted event
        RestoreStarted::dispatch($backup, $site, $this->restoreType, $this->actorId);

        Log::info('RestoreBackupJob: Starting restore operation', [
            'backup_id' => $backup->id,
            'site_id' => $site->id,
            'domain' => $site->domain,
            'restore_type' => $this->restoreType,
            'force' => $this->force,
        ]);

        // Track restore duration for metrics
        $startTime = microtime(true);

        try {
            // Update site status to 'restoring'
            $previousStatus = $site->status;
            $site->update(['status' => 'restoring']);

            // Verify backup is valid and ready
            if (! $this->skipVerify) {
                if (! $backup->storage_path) {
                    throw new \RuntimeException('Backup storage path is not available');
                }

                if ($backup->isExpired()) {
                    throw new \RuntimeException('Backup has expired and cannot be restored');
                }

                if ($backup->status !== 'completed') {
                    throw new \RuntimeException('Backup is not in completed state');
                }
            }

            // Execute restore via VPS Manager Bridge
            $result = $vpsManager->restoreBackup($vps, $site, $backup->storage_path);

            if ($result['success']) {
                $duration = (int) round(microtime(true) - $startTime);

                // Restore site to previous status (or active if it was restoring)
                $site->update([
                    'status' => $previousStatus === 'restoring' ? 'active' : $previousStatus,
                ]);

                // Emit RestoreCompleted event
                RestoreCompleted::dispatch($backup, $site, $duration, $this->actorId);

                Log::info('RestoreBackupJob: Restore completed successfully', [
                    'backup_id' => $backup->id,
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'duration_seconds' => $duration,
                ]);
            } else {
                $errorMessage = $result['output'] ?? 'Restore failed with no output';

                // Set site status to failed
                $site->update(['status' => 'failed']);

                // Emit RestoreFailed event
                RestoreFailed::dispatch($site->id, $backup->id, $errorMessage, $this->actorId);

                Log::error('RestoreBackupJob: Restore failed', [
                    'backup_id' => $backup->id,
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'output' => $result['output'] ?? 'No output',
                ]);

                throw new \RuntimeException($errorMessage);
            }
        } catch (\Exception $e) {
            // Set site status to failed
            $site->update(['status' => 'failed']);

            // Emit RestoreFailed event
            RestoreFailed::dispatch($site->id, $backup->id, $e->getMessage(), $this->actorId);

            Log::error('RestoreBackupJob: Exception during restore', [
                'backup_id' => $backup->id,
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
        Log::error('RestoreBackupJob: Job failed after all retries', [
            'backup_id' => $this->backup->id,
            'site_id' => $this->backup->site_id,
            'restore_type' => $this->restoreType,
            'error' => $exception?->getMessage(),
        ]);

        // Ensure site is marked as failed
        $site = $this->backup->site;
        if ($site) {
            $site->update(['status' => 'failed']);
        }

        // Emit RestoreFailed event (if not already emitted)
        RestoreFailed::dispatch(
            $this->backup->site_id,
            $this->backup->id,
            $exception?->getMessage() ?? 'Job failed after all retries',
            $this->actorId
        );
    }

    /**
     * Get tags for queue monitoring.
     *
     * @return array<string>
     */
    public function tags(): array
    {
        return [
            'restore',
            'backup:'.$this->backup->id,
            'site:'.$this->backup->site_id,
        ];
    }
}
