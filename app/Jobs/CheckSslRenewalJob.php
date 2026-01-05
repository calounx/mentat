<?php

namespace App\Jobs;

use App\Models\Site;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

class CheckSslRenewalJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    /**
     * The number of times the job may be attempted.
     */
    public int $tries = 3;

    /**
     * The number of seconds to wait before retrying the job.
     */
    public int $backoff = 300;

    /**
     * Number of days before expiration to trigger renewal.
     */
    private const RENEWAL_THRESHOLD_DAYS = 14;

    /**
     * Create a new job instance.
     */
    public function __construct()
    {
    }

    /**
     * Execute the job.
     */
    public function handle(VPSManagerBridge $vpsManager): void
    {
        Log::info('CheckSslRenewalJob: Starting SSL renewal check');

        $renewedCount = 0;
        $failedCount = 0;
        $skippedCount = 0;

        // Get all sites with SSL enabled that are expiring within the threshold
        $sites = Site::active()
            ->sslExpiringSoon(self::RENEWAL_THRESHOLD_DAYS)
            ->with('vpsServer')
            ->get();

        Log::info('CheckSslRenewalJob: Found sites with expiring SSL', [
            'count' => $sites->count(),
            'threshold_days' => self::RENEWAL_THRESHOLD_DAYS,
        ]);

        foreach ($sites as $site) {
            $vps = $site->vpsServer;

            if (!$vps) {
                Log::warning('CheckSslRenewalJob: Site has no VPS server', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                ]);
                $skippedCount++;
                continue;
            }

            if (!$vps->isAvailable()) {
                Log::warning('CheckSslRenewalJob: VPS server is not available', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'vps' => $vps->hostname,
                    'vps_status' => $vps->status,
                ]);
                $skippedCount++;
                continue;
            }

            try {
                Log::info('CheckSslRenewalJob: Renewing SSL certificate', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'expires_at' => $site->ssl_expires_at?->toIso8601String(),
                    'days_until_expiry' => $site->ssl_expires_at?->diffInDays(now()),
                ]);

                $result = $vpsManager->renewSSL($vps, $site->domain);

                if ($result['success']) {
                    // Let's Encrypt certificates are valid for 90 days
                    $newExpiresAt = now()->addDays(90);

                    // Check if result contains expiry date
                    if (isset($result['data']['expires_at'])) {
                        $newExpiresAt = \Carbon\Carbon::parse($result['data']['expires_at']);
                    }

                    $site->update([
                        'ssl_expires_at' => $newExpiresAt,
                    ]);

                    Log::info('CheckSslRenewalJob: SSL certificate renewed successfully', [
                        'site_id' => $site->id,
                        'domain' => $site->domain,
                        'new_expires_at' => $newExpiresAt->toIso8601String(),
                    ]);

                    $renewedCount++;
                } else {
                    Log::error('CheckSslRenewalJob: SSL renewal failed', [
                        'site_id' => $site->id,
                        'domain' => $site->domain,
                        'output' => $result['output'] ?? 'No output',
                    ]);
                    $failedCount++;
                }
            } catch (\Exception $e) {
                Log::error('CheckSslRenewalJob: Exception during SSL renewal', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'error' => $e->getMessage(),
                ]);
                $failedCount++;
            }
        }

        Log::info('CheckSslRenewalJob: SSL renewal check completed', [
            'total_checked' => $sites->count(),
            'renewed' => $renewedCount,
            'failed' => $failedCount,
            'skipped' => $skippedCount,
        ]);
    }

    /**
     * Handle a job failure.
     */
    public function failed(?\Throwable $exception): void
    {
        Log::error('CheckSslRenewalJob: Job failed after all retries', [
            'error' => $exception?->getMessage(),
        ]);
    }
}
