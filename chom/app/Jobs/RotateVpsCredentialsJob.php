<?php

namespace App\Jobs;

use App\Models\VpsServer;
use App\Services\Secrets\SecretsRotationService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

/**
 * SECURITY: Async VPS Credentials Rotation Job
 *
 * Handles asynchronous rotation of VPS credentials. Used for both scheduled
 * rotations and cleanup of old keys after overlap period.
 *
 * Queue: high (security-critical operations)
 * Retry: 3 times with exponential backoff
 * Timeout: 5 minutes per server
 *
 * Actions:
 * - 'rotate': Full credential rotation process
 * - 'cleanup_old_key': Remove old key after 24h overlap
 */
class RotateVpsCredentialsJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    /**
     * Maximum retry attempts
     */
    public $tries = 3;

    /**
     * Timeout in seconds (5 minutes)
     */
    public $timeout = 300;

    /**
     * Queue name (high priority for security operations)
     */
    public $queue = 'high';

    /**
     * Create a new job instance.
     */
    public function __construct(
        public VpsServer $vps,
        public string $action = 'rotate'
    ) {}

    /**
     * Execute the job.
     */
    public function handle(SecretsRotationService $rotationService): void
    {
        Log::info('VPS credentials rotation job started', [
            'vps_id' => $this->vps->id,
            'vps_name' => $this->vps->name,
            'action' => $this->action,
        ]);

        try {
            if ($this->action === 'rotate') {
                $result = $rotationService->rotateVpsCredentials($this->vps);

                Log::info('VPS credentials rotated successfully', [
                    'vps_id' => $this->vps->id,
                    'result' => $result,
                ]);
            } elseif ($this->action === 'cleanup_old_key') {
                $rotationService->cleanupOldKey($this->vps);

                Log::info('Old VPS key cleaned up successfully', [
                    'vps_id' => $this->vps->id,
                ]);
            }

        } catch (\Exception $e) {
            Log::error('VPS credentials rotation job failed', [
                'vps_id' => $this->vps->id,
                'action' => $this->action,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            throw $e;
        }
    }

    /**
     * Handle job failure.
     */
    public function failed(\Throwable $exception): void
    {
        Log::critical('VPS credentials rotation job failed permanently', [
            'vps_id' => $this->vps->id,
            'action' => $this->action,
            'error' => $exception->getMessage(),
            'attempts' => $this->attempts(),
        ]);

        // TODO: Send alert to security team
        // \App\Notifications\SecurityAlertNotification::dispatch($exception);
    }
}
