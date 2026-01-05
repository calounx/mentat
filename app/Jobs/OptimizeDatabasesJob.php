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

class OptimizeDatabasesJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    /**
     * The number of times the job may be attempted.
     */
    public int $tries = 2;

    /**
     * The number of seconds to wait before retrying the job.
     */
    public int $backoff = 300;

    /**
     * The number of seconds the job can run before timing out.
     */
    public int $timeout = 1800; // 30 minutes

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
        Log::info('OptimizeDatabasesJob: Starting database optimization');

        $optimizedCount = 0;
        $failedCount = 0;
        $skippedCount = 0;

        // Get all active sites with databases (WordPress, Laravel, PHP sites typically have databases)
        $sites = Site::active()
            ->whereNotNull('db_name')
            ->with('vpsServer')
            ->get();

        Log::info('OptimizeDatabasesJob: Found sites with databases', [
            'count' => $sites->count(),
        ]);

        // Group sites by VPS to optimize connection reuse
        $sitesByVps = $sites->groupBy('vps_id');

        foreach ($sitesByVps as $vpsId => $vpsSites) {
            $vps = $vpsSites->first()->vpsServer;

            if (!$vps) {
                Log::warning('OptimizeDatabasesJob: VPS server not found', [
                    'vps_id' => $vpsId,
                ]);
                $skippedCount += $vpsSites->count();
                continue;
            }

            if (!$vps->isAvailable()) {
                Log::warning('OptimizeDatabasesJob: VPS server is not available', [
                    'vps_id' => $vps->id,
                    'hostname' => $vps->hostname,
                    'vps_status' => $vps->status,
                    'health_status' => $vps->health_status,
                ]);
                $skippedCount += $vpsSites->count();
                continue;
            }

            foreach ($vpsSites as $site) {
                try {
                    Log::info('OptimizeDatabasesJob: Optimizing database', [
                        'site_id' => $site->id,
                        'domain' => $site->domain,
                        'db_name' => $site->db_name,
                    ]);

                    $result = $vpsManager->optimizeDatabase($vps, $site->domain);

                    if ($result['success']) {
                        Log::info('OptimizeDatabasesJob: Database optimized successfully', [
                            'site_id' => $site->id,
                            'domain' => $site->domain,
                            'data' => $result['data'],
                        ]);
                        $optimizedCount++;
                    } else {
                        Log::error('OptimizeDatabasesJob: Database optimization failed', [
                            'site_id' => $site->id,
                            'domain' => $site->domain,
                            'output' => $result['output'] ?? 'No output',
                        ]);
                        $failedCount++;
                    }
                } catch (\Exception $e) {
                    Log::error('OptimizeDatabasesJob: Exception during database optimization', [
                        'site_id' => $site->id,
                        'domain' => $site->domain,
                        'error' => $e->getMessage(),
                    ]);
                    $failedCount++;
                }
            }
        }

        Log::info('OptimizeDatabasesJob: Database optimization completed', [
            'total_sites' => $sites->count(),
            'optimized' => $optimizedCount,
            'failed' => $failedCount,
            'skipped' => $skippedCount,
        ]);
    }

    /**
     * Handle a job failure.
     */
    public function failed(?\Throwable $exception): void
    {
        Log::error('OptimizeDatabasesJob: Job failed after all retries', [
            'error' => $exception?->getMessage(),
        ]);
    }
}
