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

class ProvisionSiteJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    /**
     * The number of times the job may be attempted.
     */
    public int $tries = 3;

    /**
     * The number of seconds to wait before retrying the job.
     */
    public int $backoff = 60;

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

        if (!$vps) {
            Log::error('ProvisionSiteJob: No VPS server associated with site', [
                'site_id' => $site->id,
                'domain' => $site->domain,
            ]);
            $site->update(['status' => 'failed']);
            return;
        }

        Log::info('ProvisionSiteJob: Starting site provisioning', [
            'site_id' => $site->id,
            'domain' => $site->domain,
            'vps' => $vps->hostname,
        ]);

        try {
            // Create site on VPS based on type
            $result = match ($site->site_type) {
                'wordpress' => $vpsManager->createWordPressSite($vps, $site->domain, [
                    'php_version' => $site->php_version,
                ]),
                'laravel' => $vpsManager->createLaravelSite($vps, $site->domain, [
                    'php_version' => $site->php_version,
                ]),
                'php' => $vpsManager->createPhpSite($vps, $site->domain, [
                    'php_version' => $site->php_version,
                ]),
                'html' => $vpsManager->createHtmlSite($vps, $site->domain),
                default => throw new \InvalidArgumentException("Unsupported site type: {$site->site_type}"),
            };

            if ($result['success']) {
                $site->update(['status' => 'active']);

                Log::info('ProvisionSiteJob: Site provisioned successfully', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                ]);

                // Issue SSL if enabled
                if ($site->ssl_enabled) {
                    IssueSslCertificateJob::dispatch($site);
                }
            } else {
                $site->update(['status' => 'failed']);

                Log::error('ProvisionSiteJob: Site provisioning failed', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'output' => $result['output'] ?? 'No output',
                ]);
            }
        } catch (\Exception $e) {
            $site->update(['status' => 'failed']);

            Log::error('ProvisionSiteJob: Exception during provisioning', [
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
        Log::error('ProvisionSiteJob: Job failed after all retries', [
            'site_id' => $this->site->id,
            'domain' => $this->site->domain,
            'error' => $exception?->getMessage(),
        ]);

        $this->site->update(['status' => 'failed']);
    }
}
