<?php

namespace App\Services\VPS;

use App\Models\Tenant;
use App\Models\VpsServer;
use Illuminate\Support\Facades\Log;

/**
 * VPS Allocation Service
 *
 * Handles VPS server allocation and selection logic for tenants.
 * Determines which VPS server should host a new site based on
 * allocation strategy, capacity, and health status.
 */
class VpsAllocationService
{
    /**
     * Find an available VPS server for a tenant.
     *
     * Strategy:
     * 1. Check if tenant has an existing allocation
     * 2. If allocated VPS is available, use it
     * 3. Otherwise, find a shared VPS with capacity
     *
     * @param Tenant $tenant The tenant needing VPS allocation
     * @return VpsServer|null
     */
    public function findAvailableVps(Tenant $tenant): ?VpsServer
    {
        // First, check if tenant has existing allocation
        $allocation = $tenant->vpsAllocations()
            ->with('vpsServer')
            ->first();

        if ($allocation && $this->isVpsAvailable($allocation->vpsServer)) {
            Log::info('Using existing VPS allocation', [
                'tenant_id' => $tenant->id,
                'vps_id' => $allocation->vpsServer->id,
            ]);

            return $allocation->vpsServer;
        }

        // Find shared VPS with capacity, ordered by current load
        $vps = $this->findSharedVpsWithCapacity();

        if ($vps) {
            Log::info('Allocated shared VPS', [
                'tenant_id' => $tenant->id,
                'vps_id' => $vps->id,
                'current_sites' => $vps->getSiteCount(),
            ]);
        } else {
            Log::warning('No available VPS found', [
                'tenant_id' => $tenant->id,
            ]);
        }

        return $vps;
    }

    /**
     * Find a shared VPS server with available capacity.
     *
     * @return VpsServer|null
     */
    public function findSharedVpsWithCapacity(): ?VpsServer
    {
        return VpsServer::active()
            ->shared()
            ->healthy()
            ->orderByRaw('(SELECT COUNT(*) FROM sites WHERE vps_id = vps_servers.id) ASC')
            ->first();
    }

    /**
     * Check if a VPS server is available for new sites.
     *
     * @param VpsServer $vps The VPS to check
     * @return bool
     */
    public function isVpsAvailable(VpsServer $vps): bool
    {
        return $vps->isAvailable();
    }

    /**
     * Get VPS allocation information for a tenant.
     *
     * @param Tenant $tenant The tenant
     * @return array{has_allocation: bool, vps?: array, shared_vps_available: int}
     */
    public function getAllocationInfo(Tenant $tenant): array
    {
        $allocation = $tenant->vpsAllocations()->with('vpsServer')->first();

        $info = [
            'has_allocation' => (bool) $allocation,
            'shared_vps_available' => $this->getAvailableSharedVpsCount(),
        ];

        if ($allocation && $allocation->vpsServer) {
            $vps = $allocation->vpsServer;
            $info['vps'] = [
                'id' => $vps->id,
                'hostname' => $vps->hostname,
                'ip_address' => $vps->ip_address,
                'allocation_type' => $vps->allocation_type,
                'status' => $vps->status,
                'health_status' => $vps->health_status,
                'site_count' => $vps->getSiteCount(),
            ];
        }

        return $info;
    }

    /**
     * Get the count of available shared VPS servers.
     *
     * @return int
     */
    public function getAvailableSharedVpsCount(): int
    {
        return VpsServer::active()
            ->shared()
            ->healthy()
            ->count();
    }

    /**
     * Recommend a VPS server for a tenant based on their needs.
     *
     * This method can be extended to include more sophisticated
     * allocation logic based on tenant tier, expected load, etc.
     *
     * @param Tenant $tenant The tenant
     * @param array<string, mixed> $requirements Optional requirements
     * @return VpsServer|null
     */
    public function recommendVps(Tenant $tenant, array $requirements = []): ?VpsServer
    {
        // For now, use the same logic as findAvailableVps
        // Future enhancement: consider requirements like:
        // - Minimum memory
        // - Specific region
        // - Performance tier
        // - Isolation requirements

        return $this->findAvailableVps($tenant);
    }

    /**
     * Check if VPS server has capacity for additional sites.
     *
     * @param VpsServer $vps The VPS server
     * @param int $additionalSites Number of additional sites
     * @return bool
     */
    public function hasCapacity(VpsServer $vps, int $additionalSites = 1): bool
    {
        if (!$vps->isAvailable()) {
            return false;
        }

        // For shared VPS, implement a soft limit
        // This can be made configurable via tier limits
        $maxSitesPerVps = config('vps.max_sites_per_shared_vps', 50);
        $currentSites = $vps->getSiteCount();

        return ($currentSites + $additionalSites) <= $maxSitesPerVps;
    }
}
