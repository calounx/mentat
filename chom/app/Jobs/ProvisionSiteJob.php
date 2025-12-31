<?php

namespace App\Jobs;

use App\Models\Site;
use App\Services\Sites\Provisioners\ProvisionerFactory;
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
    public function handle(ProvisionerFactory $provisionerFactory): void
    {
        $site = $this->site;
        $vps = $site->vpsServer;

        if (!$vps) {
            Log::error('ProvisionSiteJob: No VPS server associated with site', [
                'site_id' => $site->id,
                'domain' => $site->domain,
            ]);
            $site->update(['status' => 'failed']);

            // Emit provisioning failed event
            \App\Events\Site\SiteProvisioningFailed::dispatch(
                $site->fresh(),
                'No VPS server associated with site'
            );

            return;
        }

        Log::info('ProvisionSiteJob: Starting site provisioning', [
            'site_id' => $site->id,
            'domain' => $site->domain,
            'site_type' => $site->site_type,
            'vps' => $vps->hostname,
        ]);

        // Track provisioning duration for metrics
        $startTime = microtime(true);

        try {
            // Get appropriate provisioner using Strategy pattern
            $provisioner = $provisionerFactory->make($site->site_type);

            // Validate site configuration
            if (!$provisioner->validate($site)) {
                throw new \InvalidArgumentException(
                    "Site configuration is invalid for type: {$site->site_type}"
                );
            }

            // Provision the site using the strategy
            $result = $provisioner->provision($site, $vps);

            if ($result['success']) {
                $duration = microtime(true) - $startTime;

                $site->update(['status' => 'active']);

                // Emit successful provisioning event
                \App\Events\Site\SiteProvisioned::dispatch(
                    $site->fresh(),
                    ['duration' => $duration]
                );

                Log::info('ProvisionSiteJob: Site provisioned successfully', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'site_type' => $site->site_type,
                    'duration_seconds' => round($duration, 2),
                ]);

                // Issue SSL if enabled
                if ($site->ssl_enabled) {
                    IssueSslCertificateJob::dispatch($site);
                }
            } else {
                $site->update(['status' => 'failed']);

                // Emit provisioning failed event
                \App\Events\Site\SiteProvisioningFailed::dispatch(
                    $site->fresh(),
                    $result['output'] ?? 'Provisioning failed with no output'
                );

                Log::error('ProvisionSiteJob: Site provisioning failed', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'site_type' => $site->site_type,
                    'output' => $result['output'] ?? 'No output',
                ]);
            }
        } catch (\Exception $e) {
            $site->update(['status' => 'failed']);

            // Emit provisioning failed event with exception details
            \App\Events\Site\SiteProvisioningFailed::dispatch(
                $site->fresh(),
                $e->getMessage(),
                $e->getTraceAsString()
            );

            Log::error('ProvisionSiteJob: Exception during provisioning', [
                'site_id' => $site->id,
                'domain' => $site->domain,
                'site_type' => $site->site_type,
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

        // Emit provisioning failed event (if not already emitted)
        \App\Events\Site\SiteProvisioningFailed::dispatch(
            $this->site->fresh(),
            $exception?->getMessage() ?? 'Job failed after all retries',
            $exception?->getTraceAsString()
        );
    }
}
