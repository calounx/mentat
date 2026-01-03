<?php

declare(strict_types=1);

namespace App\Modules\Infrastructure\Services;

use App\Models\VpsServer;
use App\Modules\Infrastructure\Contracts\VpsProviderInterface;
use App\Modules\Infrastructure\ValueObjects\VpsSpecification;
use App\Repositories\VpsServerRepository;
use Illuminate\Support\Facades\Log;

/**
 * VPS Manager Service
 *
 * Manages VPS server operations including provisioning, health checks,
 * and resource allocation.
 */
class VpsManager implements VpsProviderInterface
{
    public function __construct(
        private readonly VpsServerRepository $vpsRepository
    ) {
    }

    /**
     * Provision a new VPS server.
     *
     * @param VpsSpecification $spec VPS specifications
     * @return VpsServer Provisioned VPS
     * @throws \RuntimeException
     */
    public function provision(VpsSpecification $spec): VpsServer
    {
        try {
            Log::info('Infrastructure module: Provisioning VPS', [
                'provider' => $spec->getProvider(),
                'region' => $spec->getRegion(),
                'memory_mb' => $spec->getMemoryMb(),
            ]);

            $vps = $this->vpsRepository->create([
                'provider' => $spec->getProvider(),
                'region' => $spec->getRegion(),
                'ip_address' => $spec->getIpAddress() ?? $this->generateIpAddress(),
                'memory_mb' => $spec->getMemoryMb(),
                'disk_gb' => $spec->getDiskGb(),
                'cpu_cores' => $spec->getCpuCores(),
                'status' => 'provisioning',
                'is_active' => true,
            ]);

            Log::info('VPS provisioned successfully', [
                'vps_id' => $vps->id,
                'ip_address' => $vps->ip_address,
            ]);

            return $vps;
        } catch (\Exception $e) {
            Log::error('VPS provisioning failed', [
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to provision VPS: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Deprovision a VPS server.
     *
     * @param string $vpsId VPS ID
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function deprovision(string $vpsId): bool
    {
        try {
            $vps = $this->vpsRepository->findById($vpsId);

            if (!$vps) {
                throw new \RuntimeException('VPS not found');
            }

            Log::info('Infrastructure module: Deprovisioning VPS', [
                'vps_id' => $vpsId,
                'ip_address' => $vps->ip_address,
            ]);

            $this->vpsRepository->update($vpsId, [
                'status' => 'deprovisioning',
                'is_active' => false,
            ]);

            return true;
        } catch (\Exception $e) {
            Log::error('VPS deprovisioning failed', [
                'vps_id' => $vpsId,
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to deprovision VPS: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Get VPS server details.
     *
     * @param string $vpsId VPS ID
     * @return VpsServer VPS details
     * @throws \RuntimeException
     */
    public function getDetails(string $vpsId): VpsServer
    {
        $vps = $this->vpsRepository->findById($vpsId);

        if (!$vps) {
            throw new \RuntimeException('VPS not found');
        }

        return $vps;
    }

    /**
     * Check VPS server health.
     *
     * @param string $vpsId VPS ID
     * @return array Health status
     */
    public function checkHealth(string $vpsId): array
    {
        try {
            $vps = $this->getDetails($vpsId);

            $siteCount = $vps->sites()->count();
            $activeSites = $vps->sites()->where('status', 'active')->count();

            return [
                'vps_id' => $vpsId,
                'status' => $vps->status,
                'is_active' => $vps->is_active,
                'healthy' => $vps->is_active && $vps->status === 'active',
                'site_count' => $siteCount,
                'active_sites' => $activeSites,
                'load_percentage' => $siteCount > 0 ? round(($siteCount / 100) * 100, 2) : 0,
            ];
        } catch (\Exception $e) {
            Log::error('VPS health check failed', [
                'vps_id' => $vpsId,
                'error' => $e->getMessage(),
            ]);

            return [
                'vps_id' => $vpsId,
                'healthy' => false,
                'error' => $e->getMessage(),
            ];
        }
    }

    /**
     * Find available VPS for site provisioning.
     *
     * @param int $minMemoryMb Minimum memory requirement
     * @param int $minDiskGb Minimum disk requirement
     * @return VpsServer|null Available VPS
     */
    public function findAvailable(int $minMemoryMb = 2048, int $minDiskGb = 20): ?VpsServer
    {
        return $this->vpsRepository->findAvailableVps($minMemoryMb, $minDiskGb);
    }

    /**
     * Get VPS resource usage.
     *
     * @param string $vpsId VPS ID
     * @return array Resource usage metrics
     */
    public function getResourceUsage(string $vpsId): array
    {
        try {
            $vps = $this->getDetails($vpsId);

            $sites = $vps->sites;
            $totalStorageMb = $sites->sum('storage_used_mb');

            return [
                'vps_id' => $vpsId,
                'memory_mb' => $vps->memory_mb,
                'disk_gb' => $vps->disk_gb,
                'cpu_cores' => $vps->cpu_cores,
                'sites_count' => $sites->count(),
                'storage_used_mb' => $totalStorageMb,
                'storage_used_gb' => round($totalStorageMb / 1024, 2),
                'disk_usage_percentage' => round(($totalStorageMb / 1024 / $vps->disk_gb) * 100, 2),
            ];
        } catch (\Exception $e) {
            Log::error('Failed to get VPS resource usage', [
                'vps_id' => $vpsId,
                'error' => $e->getMessage(),
            ]);

            return [
                'vps_id' => $vpsId,
                'error' => $e->getMessage(),
            ];
        }
    }

    /**
     * Generate a mock IP address for development.
     *
     * @return string
     */
    private function generateIpAddress(): string
    {
        return sprintf(
            '192.168.%d.%d',
            rand(1, 254),
            rand(1, 254)
        );
    }
}
