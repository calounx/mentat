<?php

namespace App\Jobs;

use App\Models\VpsServer;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

class VpsHealthCheckJob implements ShouldQueue
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
    public function __construct()
    {
    }

    /**
     * Execute the job.
     */
    public function handle(VPSManagerBridge $vpsManager): void
    {
        Log::info('VpsHealthCheckJob: Starting VPS health checks');

        $healthyCount = 0;
        $unhealthyCount = 0;
        $unreachableCount = 0;

        // Get all active VPS servers
        $servers = VpsServer::active()->get();

        Log::info('VpsHealthCheckJob: Checking active VPS servers', [
            'count' => $servers->count(),
        ]);

        foreach ($servers as $vps) {
            try {
                Log::debug('VpsHealthCheckJob: Checking VPS health', [
                    'vps_id' => $vps->id,
                    'hostname' => $vps->hostname,
                    'ip_address' => $vps->ip_address,
                ]);

                $result = $vpsManager->healthCheck($vps);

                if ($result['success']) {
                    $healthStatus = $this->determineHealthStatus($result['data']);

                    $vps->update([
                        'last_health_check_at' => now(),
                        'health_status' => $healthStatus,
                    ]);

                    if ($healthStatus === 'healthy') {
                        $healthyCount++;
                        Log::info('VpsHealthCheckJob: VPS is healthy', [
                            'vps_id' => $vps->id,
                            'hostname' => $vps->hostname,
                            'data' => $result['data'],
                        ]);
                    } else {
                        $unhealthyCount++;
                        Log::warning('VpsHealthCheckJob: VPS has health issues', [
                            'vps_id' => $vps->id,
                            'hostname' => $vps->hostname,
                            'health_status' => $healthStatus,
                            'data' => $result['data'],
                        ]);
                    }
                } else {
                    $vps->update([
                        'last_health_check_at' => now(),
                        'health_status' => 'unhealthy',
                    ]);

                    $unhealthyCount++;
                    Log::error('VpsHealthCheckJob: Health check command failed', [
                        'vps_id' => $vps->id,
                        'hostname' => $vps->hostname,
                        'output' => $result['output'] ?? 'No output',
                    ]);
                }
            } catch (\Exception $e) {
                $vps->update([
                    'last_health_check_at' => now(),
                    'health_status' => 'unreachable',
                ]);

                $unreachableCount++;
                Log::error('VpsHealthCheckJob: Exception during health check', [
                    'vps_id' => $vps->id,
                    'hostname' => $vps->hostname,
                    'error' => $e->getMessage(),
                ]);
            }
        }

        Log::info('VpsHealthCheckJob: Health check completed', [
            'total_checked' => $servers->count(),
            'healthy' => $healthyCount,
            'unhealthy' => $unhealthyCount,
            'unreachable' => $unreachableCount,
        ]);

        // Log critical alert if any servers are unhealthy or unreachable
        if ($unhealthyCount > 0 || $unreachableCount > 0) {
            Log::critical('VpsHealthCheckJob: VPS servers require attention', [
                'unhealthy_count' => $unhealthyCount,
                'unreachable_count' => $unreachableCount,
            ]);
        }
    }

    /**
     * Determine the overall health status based on check data.
     */
    private function determineHealthStatus(?array $data): string
    {
        if ($data === null) {
            return 'unknown';
        }

        // Check for critical issues
        $status = $data['status'] ?? null;
        if ($status === 'critical' || $status === 'unhealthy') {
            return 'unhealthy';
        }

        // Check resource thresholds
        $cpuUsage = $data['cpu_usage'] ?? 0;
        $memoryUsage = $data['memory_usage'] ?? 0;
        $diskUsage = $data['disk_usage'] ?? 0;

        // Critical thresholds
        if ($cpuUsage > 95 || $memoryUsage > 95 || $diskUsage > 95) {
            return 'unhealthy';
        }

        // Warning thresholds
        if ($cpuUsage > 80 || $memoryUsage > 85 || $diskUsage > 85) {
            return 'degraded';
        }

        // Check for any reported issues
        $issues = $data['issues'] ?? [];
        if (!empty($issues)) {
            $criticalIssues = array_filter($issues, fn($issue) =>
                ($issue['severity'] ?? 'info') === 'critical'
            );

            if (!empty($criticalIssues)) {
                return 'unhealthy';
            }

            $warningIssues = array_filter($issues, fn($issue) =>
                ($issue['severity'] ?? 'info') === 'warning'
            );

            if (!empty($warningIssues)) {
                return 'degraded';
            }
        }

        return 'healthy';
    }

    /**
     * Handle a job failure.
     */
    public function failed(?\Throwable $exception): void
    {
        Log::error('VpsHealthCheckJob: Job failed after all retries', [
            'error' => $exception?->getMessage(),
        ]);
    }
}
