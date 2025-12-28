<?php

namespace App\Jobs;

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
    public int $backoff = 60;

    /**
     * Create a new job instance.
     */
    public function __construct(
        public SiteBackup $backup
    ) {}

    /**
     * Execute the job.
     */
    public function handle(VPSManagerBridge $vpsManager): void
    {
        $backup = $this->backup;
        $site = $backup->site;

        if (!$site) {
            Log::error('RestoreBackupJob: No site associated with backup', [
                'backup_id' => $backup->id,
            ]);
            return;
        }

        $vps = $site->vpsServer;

        if (!$vps) {
            Log::error('RestoreBackupJob: No VPS server associated with site', [
                'backup_id' => $backup->id,
                'site_id' => $site->id,
                'domain' => $site->domain,
            ]);
            return;
        }

        Log::info('RestoreBackupJob: Starting backup restore', [
            'backup_id' => $backup->id,
            'site_id' => $site->id,
            'domain' => $site->domain,
            'backup_type' => $backup->backup_type,
            'storage_path' => $backup->storage_path,
        ]);

        try {
            // Set site to maintenance mode during restore
            $previousStatus = $site->status;
            $site->update(['status' => 'restoring']);

            $result = $vpsManager->restoreBackup($vps, $backup->storage_path);

            if ($result['success']) {
                // Restore site to previous status
                $site->update(['status' => $previousStatus]);

                Log::info('RestoreBackupJob: Backup restored successfully', [
                    'backup_id' => $backup->id,
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                ]);
            } else {
                // Restore site to previous status even on failure
                $site->update(['status' => $previousStatus]);

                Log::error('RestoreBackupJob: Backup restore failed', [
                    'backup_id' => $backup->id,
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'output' => $result['output'] ?? 'No output',
                ]);
            }
        } catch (\Exception $e) {
            // Attempt to restore site status
            $site->update(['status' => 'active']);

            Log::error('RestoreBackupJob: Exception during backup restore', [
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
            'error' => $exception?->getMessage(),
        ]);

        // Ensure site is not left in 'restoring' status
        if ($this->backup->site && $this->backup->site->status === 'restoring') {
            $this->backup->site->update(['status' => 'active']);
        }
    }
}
