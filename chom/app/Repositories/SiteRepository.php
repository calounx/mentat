<?php

namespace App\Repositories;

use App\Models\Site;
use App\Models\Tenant;
use App\Models\VpsServer;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Site Repository.
 *
 * Handles complex site queries and data access logic.
 * Implements Repository pattern to separate data access from business logic.
 */
class SiteRepository
{
    /**
     * Get active sites for a tenant.
     *
     * @param Tenant $tenant
     * @return Collection
     */
    public function getActiveForTenant(Tenant $tenant): Collection
    {
        return Site::where('tenant_id', $tenant->id)
            ->where('status', 'active')
            ->with('vpsServer:id,hostname,ip_address')
            ->orderBy('created_at', 'desc')
            ->get();
    }

    /**
     * Get storage statistics by tenant.
     *
     * @param Tenant $tenant
     * @return array
     */
    public function getStorageStatsByTenant(Tenant $tenant): array
    {
        $stats = Site::where('tenant_id', $tenant->id)
            ->select([
                DB::raw('COUNT(*) as total_sites'),
                DB::raw('SUM(storage_used_mb) as total_storage_mb'),
                DB::raw('AVG(storage_used_mb) as average_storage_mb'),
                DB::raw('MAX(storage_used_mb) as max_storage_mb'),
            ])
            ->first();

        return [
            'total_sites' => $stats->total_sites ?? 0,
            'total_storage_mb' => $stats->total_storage_mb ?? 0,
            'total_storage_gb' => round(($stats->total_storage_mb ?? 0) / 1024, 2),
            'average_storage_mb' => round($stats->average_storage_mb ?? 0, 2),
            'max_storage_mb' => $stats->max_storage_mb ?? 0,
        ];
    }

    /**
     * Find available VPS servers with capacity.
     *
     * @param Tenant|null $tenant Tenant to find VPS for (optional)
     * @param int $minimumSites Minimum number of sites the VPS should handle
     * @return Collection
     */
    public function findAvailableVpsServers(?Tenant $tenant = null, int $minimumSites = 1): Collection
    {
        $query = VpsServer::active()
            ->shared()
            ->healthy()
            ->withCount('sites')
            ->having('sites_count', '>=', $minimumSites)
            ->orderBy('sites_count', 'asc');

        // If tenant specified, check for existing allocations
        if ($tenant) {
            $query->whereHas('allocations', function ($q) use ($tenant) {
                $q->where('tenant_id', $tenant->id);
            });
        }

        return $query->get();
    }

    /**
     * Get sites with expiring SSL certificates.
     *
     * @param int $days Number of days until expiry
     * @return Collection
     */
    public function getSitesWithExpiringSsl(int $days = 14): Collection
    {
        return Site::sslExpiringSoon($days)
            ->active()
            ->with(['tenant', 'vpsServer'])
            ->orderBy('ssl_expires_at', 'asc')
            ->get();
    }

    /**
     * Get sites by type for a tenant.
     *
     * @param Tenant $tenant
     * @param string $siteType
     * @return Collection
     */
    public function getByTypeForTenant(Tenant $tenant, string $siteType): Collection
    {
        return Site::where('tenant_id', $tenant->id)
            ->where('site_type', $siteType)
            ->with('vpsServer:id,hostname,ip_address')
            ->orderBy('created_at', 'desc')
            ->get();
    }

    /**
     * Get sites on a specific VPS server.
     *
     * @param VpsServer $vps
     * @return Collection
     */
    public function getBySiteServer(VpsServer $vps): Collection
    {
        return Site::where('vps_id', $vps->id)
            ->with('tenant:id,name')
            ->orderBy('created_at', 'desc')
            ->get();
    }

    /**
     * Count sites by status for a tenant.
     *
     * @param Tenant $tenant
     * @return array
     */
    public function countByStatusForTenant(Tenant $tenant): array
    {
        $counts = Site::where('tenant_id', $tenant->id)
            ->select('status', DB::raw('COUNT(*) as count'))
            ->groupBy('status')
            ->get()
            ->pluck('count', 'status')
            ->toArray();

        return [
            'active' => $counts['active'] ?? 0,
            'creating' => $counts['creating'] ?? 0,
            'disabled' => $counts['disabled'] ?? 0,
            'failed' => $counts['failed'] ?? 0,
            'total' => array_sum($counts),
        ];
    }

    /**
     * Count sites by type for a tenant.
     *
     * @param Tenant $tenant
     * @return array
     */
    public function countByTypeForTenant(Tenant $tenant): array
    {
        return Site::where('tenant_id', $tenant->id)
            ->select('site_type', DB::raw('COUNT(*) as count'))
            ->groupBy('site_type')
            ->get()
            ->pluck('count', 'site_type')
            ->toArray();
    }

    /**
     * Get most recent sites for a tenant.
     *
     * @param Tenant $tenant
     * @param int $limit
     * @return Collection
     */
    public function getRecentForTenant(Tenant $tenant, int $limit = 10): Collection
    {
        return Site::where('tenant_id', $tenant->id)
            ->with('vpsServer:id,hostname')
            ->orderBy('created_at', 'desc')
            ->limit($limit)
            ->get();
    }

    /**
     * Search sites by domain for a tenant.
     *
     * @param Tenant $tenant
     * @param string $search
     * @return Collection
     */
    public function searchByDomain(Tenant $tenant, string $search): Collection
    {
        return Site::where('tenant_id', $tenant->id)
            ->where('domain', 'like', '%' . $search . '%')
            ->with('vpsServer:id,hostname')
            ->orderBy('domain', 'asc')
            ->get();
    }

    /**
     * Get VPS utilization statistics.
     *
     * @return Collection
     */
    public function getVpsUtilizationStats(): Collection
    {
        return DB::table('vps_servers')
            ->select([
                'vps_servers.id',
                'vps_servers.hostname',
                'vps_servers.ip_address',
                'vps_servers.allocation_type',
                DB::raw('COUNT(sites.id) as site_count'),
                DB::raw('SUM(sites.storage_used_mb) as total_storage_mb'),
            ])
            ->leftJoin('sites', 'vps_servers.id', '=', 'sites.vps_id')
            ->where('vps_servers.status', 'active')
            ->groupBy('vps_servers.id', 'vps_servers.hostname', 'vps_servers.ip_address', 'vps_servers.allocation_type')
            ->orderBy('site_count', 'desc')
            ->get();
    }

    /**
     * Create a new site.
     *
     * @param array $data
     * @return Site
     */
    public function create(array $data): Site
    {
        return Site::create($data);
    }

    /**
     * Update a site.
     *
     * @param Site $site
     * @param array $data
     * @return bool
     */
    public function update(Site $site, array $data): bool
    {
        return $site->update($data);
    }

    /**
     * Delete a site.
     *
     * @param Site $site
     * @return bool
     */
    public function delete(Site $site): bool
    {
        return $site->delete();
    }

    /**
     * Find site by ID.
     *
     * @param string $id
     * @return Site|null
     */
    public function findById(string $id): ?Site
    {
        return Site::find($id);
    }

    /**
     * Find site by domain for tenant.
     *
     * @param Tenant $tenant
     * @param string $domain
     * @return Site|null
     */
    public function findByDomain(Tenant $tenant, string $domain): ?Site
    {
        return Site::where('tenant_id', $tenant->id)
            ->where('domain', $domain)
            ->first();
    }
}
