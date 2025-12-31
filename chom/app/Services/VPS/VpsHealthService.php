<?php

namespace App\Services\VPS;

use App\Contracts\VpsManagerInterface;
use App\Models\VpsServer;
use Illuminate\Support\Facades\Log;

/**
 * VPS Health Service
 *
 * Monitors and manages VPS server health status.
 * Performs health checks and updates server status accordingly.
 */
class VpsHealthService
{
    /**
     * Create a new VPS health service instance.
     *
     * @param VpsManagerInterface $vpsManager
     */
    public function __construct(
        protected VpsManagerInterface $vpsManager
    ) {}

    /**
     * Perform health check on a VPS server.
     *
     * @param VpsServer $vps The VPS to check
     * @return array{healthy: bool, load?: float, memory_used?: int, disk_used?: int, issues: array<string>}
     */
    public function checkHealth(VpsServer $vps): array
    {
        try {
            $result = $this->vpsManager->checkHealth($vps);

            $issues = [];

            if (!$result['healthy']) {
                $issues[] = 'VPS health check failed';
            }

            // Update health status in database
            $healthStatus = $result['healthy'] ? 'healthy' : 'unhealthy';
            $vps->update([
                'health_status' => $healthStatus,
                'last_health_check_at' => now(),
            ]);

            Log::info('VPS health check completed', [
                'vps_id' => $vps->id,
                'healthy' => $result['healthy'],
                'health_status' => $healthStatus,
            ]);

            return [
                'healthy' => $result['healthy'],
                'load' => $result['load'] ?? null,
                'memory_used' => $result['memory_used'] ?? null,
                'disk_used' => $result['disk_used'] ?? null,
                'issues' => $issues,
            ];

        } catch (\Exception $e) {
            Log::error('VPS health check failed', [
                'vps_id' => $vps->id,
                'error' => $e->getMessage(),
            ]);

            // Mark as unhealthy if check fails
            $vps->update([
                'health_status' => 'unknown',
                'last_health_check_at' => now(),
            ]);

            return [
                'healthy' => false,
                'issues' => ['Health check failed: ' . $e->getMessage()],
            ];
        }
    }

    /**
     * Perform health checks on all active VPS servers.
     *
     * @return array{total: int, healthy: int, unhealthy: int, unknown: int}
     */
    public function checkAllVpsHealth(): array
    {
        $vpsServers = VpsServer::active()->get();

        $stats = [
            'total' => $vpsServers->count(),
            'healthy' => 0,
            'unhealthy' => 0,
            'unknown' => 0,
        ];

        foreach ($vpsServers as $vps) {
            $result = $this->checkHealth($vps);

            if ($result['healthy']) {
                $stats['healthy']++;
            } elseif (!empty($result['issues'])) {
                $stats['unhealthy']++;
            } else {
                $stats['unknown']++;
            }
        }

        Log::info('All VPS health checks completed', $stats);

        return $stats;
    }

    /**
     * Get VPS servers that need attention.
     *
     * @return \Illuminate\Database\Eloquent\Collection
     */
    public function getUnhealthyServers()
    {
        return VpsServer::where('health_status', 'unhealthy')
            ->orWhere(function ($query) {
                $query->whereNull('last_health_check_at')
                    ->orWhere('last_health_check_at', '<', now()->subHours(24));
            })
            ->get();
    }

    /**
     * Get health status summary.
     *
     * @return array{total_servers: int, healthy: int, unhealthy: int, unknown: int, stale_checks: int}
     */
    public function getHealthSummary(): array
    {
        $allVps = VpsServer::all();

        return [
            'total_servers' => $allVps->count(),
            'healthy' => $allVps->where('health_status', 'healthy')->count(),
            'unhealthy' => $allVps->where('health_status', 'unhealthy')->count(),
            'unknown' => $allVps->where('health_status', 'unknown')->count(),
            'stale_checks' => $allVps->where(function ($vps) {
                return !$vps->last_health_check_at ||
                       $vps->last_health_check_at < now()->subHours(24);
            })->count(),
        ];
    }

    /**
     * Mark VPS as healthy.
     *
     * @param VpsServer $vps
     * @return void
     */
    public function markHealthy(VpsServer $vps): void
    {
        $vps->update([
            'health_status' => 'healthy',
            'last_health_check_at' => now(),
        ]);

        Log::info('VPS marked as healthy', [
            'vps_id' => $vps->id,
        ]);
    }

    /**
     * Mark VPS as unhealthy.
     *
     * @param VpsServer $vps
     * @param string|null $reason
     * @return void
     */
    public function markUnhealthy(VpsServer $vps, ?string $reason = null): void
    {
        $vps->update([
            'health_status' => 'unhealthy',
            'last_health_check_at' => now(),
        ]);

        Log::warning('VPS marked as unhealthy', [
            'vps_id' => $vps->id,
            'reason' => $reason,
        ]);
    }
}
