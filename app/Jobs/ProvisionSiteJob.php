<?php

namespace App\Jobs;

use App\Models\Site;
use App\Models\User;
use App\Models\VpsServer;
use App\Notifications\SiteProvisioningFailed;
use App\Services\Integration\VPSManagerBridge;
use App\Services\Reliability\Correlation\CorrelationId;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Notification;

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
     * Healing attempts made during this job run.
     */
    private array $healingAttempts = [];

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
        // Generate correlation ID for tracking this provisioning operation
        $correlationId = CorrelationId::generate();

        $site = $this->site->fresh();
        $this->healingAttempts = $site->healing_attempts ?? [];

        // Increment provision attempts
        $site->update([
            'provision_attempts' => $site->provision_attempts + 1,
            'last_healing_at' => now(),
        ]);

        Log::withContext([
            'correlation_id' => $correlationId,
            'site_id' => $site->id,
            'domain' => $site->domain,
        ]);

        Log::info('ProvisionSiteJob: Starting site provisioning', [
            'site_id' => $site->id,
            'domain' => $site->domain,
            'attempt' => $site->provision_attempts,
            'correlation_id' => $correlationId,
        ]);

        // Self-healing: Check if VPS is available
        $vps = $this->ensureValidVps($site, $vpsManager);
        if (!$vps) {
            $this->failWithReason($site, 'No healthy VPS server available for provisioning');
            return;
        }

        // Self-healing: If VPS changed, update the site
        if ($vps->id !== $site->vps_id) {
            $site->update(['vps_id' => $vps->id]);
            $site->refresh();
        }

        try {
            // Self-healing: Check VPS connectivity before provisioning
            if (!$this->checkVpsConnectivity($vps, $vpsManager)) {
                throw new \RuntimeException("VPS {$vps->hostname} is not responding");
            }

            // Self-healing: Try to clean up any partial site before provisioning
            $this->cleanupPartialSite($site, $vps, $vpsManager);

            // Create site on VPS based on type
            $result = $this->provisionSite($site, $vps, $vpsManager);

            if ($result['success']) {
                $site->update([
                    'status' => 'active',
                    'failure_reason' => null,
                    'healing_attempts' => $this->healingAttempts,
                ]);

                Log::info('ProvisionSiteJob: Site provisioned successfully', [
                    'site_id' => $site->id,
                    'domain' => $site->domain,
                    'healing_attempts' => count($this->healingAttempts),
                ]);

                // Issue SSL if enabled
                if ($site->ssl_enabled) {
                    IssueSslCertificateJob::dispatch($site);
                }
            } else {
                $errorOutput = $result['output'] ?? $result['error'] ?? 'Unknown error';
                throw new \RuntimeException("Provisioning command failed: {$errorOutput}");
            }
        } catch (\Exception $e) {
            $this->recordHealingAttempt('provision_site', false, $e->getMessage());
            $site->update([
                'healing_attempts' => $this->healingAttempts,
            ]);

            Log::error('ProvisionSiteJob: Exception during provisioning', [
                'site_id' => $site->id,
                'domain' => $site->domain,
                'error' => $e->getMessage(),
                'attempt' => $this->attempts(),
            ]);

            throw $e; // Re-throw to trigger retry
        }
    }

    /**
     * Ensure we have a valid, healthy VPS for provisioning.
     */
    private function ensureValidVps(Site $site, VPSManagerBridge $vpsManager): ?VpsServer
    {
        $currentVps = $site->vpsServer;

        // Check if current VPS is healthy
        if ($currentVps && $currentVps->status === 'active') {
            $healthCheck = $vpsManager->healthCheck($currentVps);
            if ($healthCheck['success']) {
                $this->recordHealingAttempt('check_current_vps', true, "Current VPS {$currentVps->hostname} is healthy");
                return $currentVps;
            }

            $this->recordHealingAttempt('check_current_vps', false, "Current VPS {$currentVps->hostname} health check failed");

            // Mark VPS as unhealthy
            $currentVps->update([
                'health_status' => 'unhealthy',
                'last_health_check_at' => now(),
            ]);
        }

        // Try to find an alternative VPS
        $this->recordHealingAttempt('find_alternative_vps', true, 'Searching for alternative healthy VPS');

        $alternativeVps = VpsServer::active()
            ->shared()
            ->healthy()
            ->where('id', '!=', $currentVps?->id)
            ->orderByRaw('(SELECT COUNT(*) FROM sites WHERE vps_id = vps_servers.id) ASC')
            ->first();

        if ($alternativeVps) {
            $this->recordHealingAttempt('switch_vps', true, "Switching to alternative VPS: {$alternativeVps->hostname}");
            return $alternativeVps;
        }

        $this->recordHealingAttempt('find_alternative_vps', false, 'No alternative healthy VPS available');
        return null;
    }

    /**
     * Check VPS connectivity.
     */
    private function checkVpsConnectivity(VpsServer $vps, VPSManagerBridge $vpsManager): bool
    {
        try {
            $result = $vpsManager->testConnection($vps);
            $this->recordHealingAttempt('test_connectivity', $result, $result ? 'VPS is reachable' : 'VPS not reachable');
            return $result;
        } catch (\Exception $e) {
            $this->recordHealingAttempt('test_connectivity', false, "Connection test failed: {$e->getMessage()}");
            return false;
        }
    }

    /**
     * Clean up any partial site configuration.
     */
    private function cleanupPartialSite(Site $site, VpsServer $vps, VPSManagerBridge $vpsManager): void
    {
        // Only cleanup on retry attempts
        if ($this->attempts() <= 1) {
            return;
        }

        try {
            // Check if site partially exists
            $siteInfo = $vpsManager->getSiteInfo($vps, $site->domain);

            if ($siteInfo['success'] && isset($siteInfo['data'])) {
                $this->recordHealingAttempt('cleanup_partial', true, 'Found partial site configuration, cleaning up');

                // Delete the partial site
                $vpsManager->deleteSite($vps, $site->domain, force: true);
                sleep(2); // Wait for cleanup to complete

                $this->recordHealingAttempt('cleanup_complete', true, 'Partial site configuration removed');
            }
        } catch (\Exception $e) {
            // Ignore cleanup errors - site might not exist
            $this->recordHealingAttempt('cleanup_partial', false, "Cleanup skipped: {$e->getMessage()}");
        }
    }

    /**
     * Provision the site on VPS.
     */
    private function provisionSite(Site $site, VpsServer $vps, VPSManagerBridge $vpsManager): array
    {
        return match ($site->site_type) {
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
    }

    /**
     * Record a healing attempt.
     */
    private function recordHealingAttempt(string $action, bool $success, string $result): void
    {
        $this->healingAttempts[] = [
            'action' => $action,
            'success' => $success,
            'result' => $result,
            'timestamp' => now()->toIso8601String(),
            'attempt' => $this->attempts(),
        ];
    }

    /**
     * Mark site as failed with reason.
     */
    private function failWithReason(Site $site, string $reason): void
    {
        $site->update([
            'status' => 'failed',
            'failure_reason' => $reason,
            'healing_attempts' => $this->healingAttempts,
        ]);

        Log::error('ProvisionSiteJob: Site provisioning failed', [
            'site_id' => $site->id,
            'domain' => $site->domain,
            'reason' => $reason,
        ]);

        // Notify super admins
        $this->notifySuperAdmins($site, $reason);
    }

    /**
     * Handle a job failure after all retries.
     */
    public function failed(?\Throwable $exception): void
    {
        $site = $this->site->fresh();
        $reason = $exception?->getMessage() ?? 'Unknown error after all retry attempts';

        $site->update([
            'status' => 'failed',
            'failure_reason' => $reason,
            'healing_attempts' => $this->healingAttempts,
        ]);

        Log::error('ProvisionSiteJob: Job failed after all retries', [
            'site_id' => $site->id,
            'domain' => $site->domain,
            'error' => $reason,
            'healing_attempts' => $this->healingAttempts,
        ]);

        // Notify super admins
        $this->notifySuperAdmins($site, $reason);
    }

    /**
     * Notify super admins about the failure.
     */
    private function notifySuperAdmins(Site $site, string $reason): void
    {
        try {
            $superAdmins = User::where('is_super_admin', true)->get();

            if ($superAdmins->isEmpty()) {
                Log::warning('ProvisionSiteJob: No super admins to notify about failure', [
                    'site_id' => $site->id,
                ]);
                return;
            }

            Notification::send(
                $superAdmins,
                new SiteProvisioningFailed($site, $reason, $this->healingAttempts)
            );

            Log::info('ProvisionSiteJob: Notified super admins about failure', [
                'site_id' => $site->id,
                'admin_count' => $superAdmins->count(),
            ]);
        } catch (\Exception $e) {
            Log::error('ProvisionSiteJob: Failed to notify super admins', [
                'site_id' => $site->id,
                'error' => $e->getMessage(),
            ]);
        }
    }
}
