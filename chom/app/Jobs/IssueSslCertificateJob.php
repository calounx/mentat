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

class IssueSslCertificateJob implements ShouldQueue
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
        public Site $site
    ) {}

    /**
     * Execute the job.
     */
    public function handle(VPSManagerBridge $vpsManager): void
    {
        $site = $this->site;
        $vps = $site->vpsServer;

        if (! $vps) {
            Log::error('IssueSslCertificateJob: No VPS server associated with site', [
                'site_id' => $site->id,
                'domain' => $site->domain,
            ]);

            return;
        }

        Log::info('IssueSslCertificateJob: Starting SSL certificate issuance', [
            'site_id' => $site->id,
            'domain' => $site->domain,
            'vps' => $vps->hostname,
        ]);

        try {
            $result = $vpsManager->issueSSL($vps, $site->domain);

            if ($result['success']) {
                // Let's Encrypt certificates are valid for 90 days
                $expiresAt = now()->addDays(90);

                // Check if result contains expiry date
                if (isset($result['data']['expires_at'])) {
                    $expiresAt = \Carbon\Carbon::parse($result['data']['expires_at']);
                }

                $site->update([
                    'ssl_enabled' => true,
                    'ssl_expires_at' => $expiresAt,
                ]);

                Log::info('IssueSslCertificateJob: SSL certificate issued successfully', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'expires_at' => $expiresAt->toIso8601String(),
                ]);
            } else {
                Log::error('IssueSslCertificateJob: SSL issuance failed', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'output' => $result['output'] ?? 'No output',
                ]);

                // Don't throw - SSL failure shouldn't block site creation
                // Just log and the site remains without SSL
            }
        } catch (\Exception $e) {
            Log::error('IssueSslCertificateJob: Exception during SSL issuance', [
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
        Log::error('IssueSslCertificateJob: Job failed after all retries', [
            'site_id' => $this->site->id,
            'domain' => $this->site->domain,
            'error' => $exception?->getMessage(),
        ]);

        // Site remains active but without SSL - this is acceptable
        // The user can retry SSL issuance later
    }
}
