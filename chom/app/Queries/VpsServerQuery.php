<?php

declare(strict_types=1);

namespace App\Queries;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

/**
 * VPS server query object with load balancing support.
 *
 * Encapsulates VPS server queries with support for:
 * - Status filtering
 * - Resource availability filtering
 * - Site count filtering
 * - Load balancing queries
 * - Health check aggregation
 * - Regional filtering
 *
 * @example
 * $availableServers = VpsServerQuery::make()
 *     ->available()
 *     ->withMinimumMemory(2048)
 *     ->byRegion('us-east')
 *     ->get();
 */
class VpsServerQuery extends BaseQuery
{
    /**
     * Create a new VPS server query instance.
     *
     * @param string|null $status Status filter
     * @param int|null $maxSiteCount Maximum site count filter
     * @param int|null $minCpuAvailable Minimum CPU cores available
     * @param int|null $minMemoryAvailable Minimum memory in MB available
     * @param string|null $region Region filter
     * @param string|null $provider Provider filter
     * @param string|null $allocationType Allocation type filter (shared, dedicated)
     * @param string|null $healthStatus Health status filter
     * @param string $sortBy Sort field
     * @param string $sortDirection Sort direction (asc or desc)
     * @param array $eagerLoad Relationships to eager load
     */
    public function __construct(
        private readonly ?string $status = null,
        private readonly ?int $maxSiteCount = null,
        private readonly ?int $minCpuAvailable = null,
        private readonly ?int $minMemoryAvailable = null,
        private readonly ?string $region = null,
        private readonly ?string $provider = null,
        private readonly ?string $allocationType = null,
        private readonly ?string $healthStatus = null,
        private readonly string $sortBy = 'created_at',
        private readonly string $sortDirection = 'desc',
        private readonly array $eagerLoad = []
    ) {}

    /**
     * Create a new query instance using fluent builder pattern.
     *
     * @return static
     */
    public static function make(): static
    {
        return new static();
    }

    /**
     * Filter by status.
     *
     * @param string $status Status value (provisioning, active, maintenance, failed, decommissioned)
     * @return static
     */
    public function withStatus(string $status): static
    {
        return new static(
            status: $status,
            maxSiteCount: $this->maxSiteCount,
            minCpuAvailable: $this->minCpuAvailable,
            minMemoryAvailable: $this->minMemoryAvailable,
            region: $this->region,
            provider: $this->provider,
            allocationType: $this->allocationType,
            healthStatus: $this->healthStatus,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter servers with maximum site count.
     *
     * @param int $count Maximum number of sites
     * @return static
     */
    public function withMaxSiteCount(int $count): static
    {
        return new static(
            status: $this->status,
            maxSiteCount: $count,
            minCpuAvailable: $this->minCpuAvailable,
            minMemoryAvailable: $this->minMemoryAvailable,
            region: $this->region,
            provider: $this->provider,
            allocationType: $this->allocationType,
            healthStatus: $this->healthStatus,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter servers with minimum CPU cores available.
     *
     * @param int $cores Minimum CPU cores
     * @return static
     */
    public function withMinimumCpu(int $cores): static
    {
        return new static(
            status: $this->status,
            maxSiteCount: $this->maxSiteCount,
            minCpuAvailable: $cores,
            minMemoryAvailable: $this->minMemoryAvailable,
            region: $this->region,
            provider: $this->provider,
            allocationType: $this->allocationType,
            healthStatus: $this->healthStatus,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter servers with minimum memory available in MB.
     *
     * @param int $memoryMb Minimum memory in MB
     * @return static
     */
    public function withMinimumMemory(int $memoryMb): static
    {
        return new static(
            status: $this->status,
            maxSiteCount: $this->maxSiteCount,
            minCpuAvailable: $this->minCpuAvailable,
            minMemoryAvailable: $memoryMb,
            region: $this->region,
            provider: $this->provider,
            allocationType: $this->allocationType,
            healthStatus: $this->healthStatus,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter by region.
     *
     * @param string $region Region identifier
     * @return static
     */
    public function byRegion(string $region): static
    {
        return new static(
            status: $this->status,
            maxSiteCount: $this->maxSiteCount,
            minCpuAvailable: $this->minCpuAvailable,
            minMemoryAvailable: $this->minMemoryAvailable,
            region: $region,
            provider: $this->provider,
            allocationType: $this->allocationType,
            healthStatus: $this->healthStatus,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter by provider.
     *
     * @param string $provider Provider name
     * @return static
     */
    public function byProvider(string $provider): static
    {
        return new static(
            status: $this->status,
            maxSiteCount: $this->maxSiteCount,
            minCpuAvailable: $this->minCpuAvailable,
            minMemoryAvailable: $this->minMemoryAvailable,
            region: $this->region,
            provider: $provider,
            allocationType: $this->allocationType,
            healthStatus: $this->healthStatus,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter by allocation type.
     *
     * @param string $type Allocation type (shared, dedicated)
     * @return static
     */
    public function withAllocationType(string $type): static
    {
        return new static(
            status: $this->status,
            maxSiteCount: $this->maxSiteCount,
            minCpuAvailable: $this->minCpuAvailable,
            minMemoryAvailable: $this->minMemoryAvailable,
            region: $this->region,
            provider: $this->provider,
            allocationType: $type,
            healthStatus: $this->healthStatus,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Filter by health status.
     *
     * @param string $status Health status (healthy, degraded, unhealthy, unknown)
     * @return static
     */
    public function withHealthStatus(string $status): static
    {
        return new static(
            status: $this->status,
            maxSiteCount: $this->maxSiteCount,
            minCpuAvailable: $this->minCpuAvailable,
            minMemoryAvailable: $this->minMemoryAvailable,
            region: $this->region,
            provider: $this->provider,
            allocationType: $this->allocationType,
            healthStatus: $status,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Sort by specified field and direction.
     *
     * @param string $field Field to sort by
     * @param string $direction Sort direction (asc or desc)
     * @return static
     */
    public function sortBy(string $field, string $direction = 'desc'): static
    {
        return new static(
            status: $this->status,
            maxSiteCount: $this->maxSiteCount,
            minCpuAvailable: $this->minCpuAvailable,
            minMemoryAvailable: $this->minMemoryAvailable,
            region: $this->region,
            provider: $this->provider,
            allocationType: $this->allocationType,
            healthStatus: $this->healthStatus,
            sortBy: $field,
            sortDirection: $direction,
            eagerLoad: $this->eagerLoad
        );
    }

    /**
     * Specify relationships to eager load.
     *
     * @param array $relations
     * @return static
     */
    public function with(array $relations): static
    {
        return new static(
            status: $this->status,
            maxSiteCount: $this->maxSiteCount,
            minCpuAvailable: $this->minCpuAvailable,
            minMemoryAvailable: $this->minMemoryAvailable,
            region: $this->region,
            provider: $this->provider,
            allocationType: $this->allocationType,
            healthStatus: $this->healthStatus,
            sortBy: $this->sortBy,
            sortDirection: $this->sortDirection,
            eagerLoad: $relations
        );
    }

    /**
     * Get available servers (active status with healthy or degraded health).
     *
     * @return \Illuminate\Support\Collection
     */
    public function available(): \Illuminate\Support\Collection
    {
        return DB::table('vps_servers')
            ->where('status', 'active')
            ->whereIn('health_status', ['healthy', 'degraded'])
            ->when($this->region, fn($q) => $q->where('region', $this->region))
            ->when($this->provider, fn($q) => $q->where('provider', $this->provider))
            ->when($this->allocationType, fn($q) => $q->where('allocation_type', $this->allocationType))
            ->when($this->minCpuAvailable, fn($q) => $q->where('spec_cpu', '>=', $this->minCpuAvailable))
            ->when($this->minMemoryAvailable, fn($q) => $q->where('spec_memory_mb', '>=', $this->minMemoryAvailable))
            ->get();
    }

    /**
     * Get the least loaded server (server with fewest sites).
     *
     * @return mixed
     */
    public function leastLoaded(): mixed
    {
        return DB::table('vps_servers')
            ->leftJoin('sites', 'vps_servers.id', '=', 'sites.vps_id')
            ->select('vps_servers.*', DB::raw('COUNT(sites.id) as site_count'))
            ->where('vps_servers.status', 'active')
            ->whereIn('vps_servers.health_status', ['healthy', 'degraded'])
            ->when($this->region, fn($q) => $q->where('vps_servers.region', $this->region))
            ->when($this->provider, fn($q) => $q->where('vps_servers.provider', $this->provider))
            ->when($this->allocationType, fn($q) => $q->where('vps_servers.allocation_type', $this->allocationType))
            ->when($this->minCpuAvailable, fn($q) => $q->where('vps_servers.spec_cpu', '>=', $this->minCpuAvailable))
            ->when($this->minMemoryAvailable, fn($q) => $q->where('vps_servers.spec_memory_mb', '>=', $this->minMemoryAvailable))
            ->groupBy('vps_servers.id')
            ->orderBy('site_count', 'asc')
            ->first();
    }

    /**
     * Get the most loaded server (server with most sites).
     *
     * @return mixed
     */
    public function mostLoaded(): mixed
    {
        return DB::table('vps_servers')
            ->leftJoin('sites', 'vps_servers.id', '=', 'sites.vps_id')
            ->select('vps_servers.*', DB::raw('COUNT(sites.id) as site_count'))
            ->where('vps_servers.status', 'active')
            ->when($this->region, fn($q) => $q->where('vps_servers.region', $this->region))
            ->when($this->provider, fn($q) => $q->where('vps_servers.provider', $this->provider))
            ->groupBy('vps_servers.id')
            ->orderBy('site_count', 'desc')
            ->first();
    }

    /**
     * Get health check summary for all matching servers.
     *
     * @return array
     */
    public function healthCheck(): array
    {
        $query = $this->buildQuery();

        $total = $query->count();
        $byStatus = DB::table('vps_servers')
            ->select('health_status', DB::raw('count(*) as count'))
            ->when($this->status, fn($q) => $q->where('status', $this->status))
            ->when($this->region, fn($q) => $q->where('region', $this->region))
            ->when($this->provider, fn($q) => $q->where('provider', $this->provider))
            ->groupBy('health_status')
            ->pluck('count', 'health_status')
            ->toArray();

        return [
            'total' => $total,
            'by_health_status' => $byStatus,
            'healthy_percentage' => $total > 0 ? round(($byStatus['healthy'] ?? 0) / $total * 100, 2) : 0,
        ];
    }

    /**
     * Get servers with observability configured.
     *
     * @return \Illuminate\Support\Collection
     */
    public function withObservability(): \Illuminate\Support\Collection
    {
        return $this->buildQuery()
            ->where('observability_configured', true)
            ->get();
    }

    /**
     * Get servers without observability configured.
     *
     * @return \Illuminate\Support\Collection
     */
    public function withoutObservability(): \Illuminate\Support\Collection
    {
        return $this->buildQuery()
            ->where('observability_configured', false)
            ->get();
    }

    /**
     * Get servers grouped by provider with counts.
     *
     * @return array
     */
    public function countByProvider(): array
    {
        $query = DB::table('vps_servers')
            ->select('provider', DB::raw('count(*) as count'))
            ->groupBy('provider');

        if ($this->status) {
            $query->where('status', $this->status);
        }

        return $query->pluck('count', 'provider')->toArray();
    }

    /**
     * Get servers grouped by region with counts.
     *
     * @return array
     */
    public function countByRegion(): array
    {
        $query = DB::table('vps_servers')
            ->select('region', DB::raw('count(*) as count'))
            ->whereNotNull('region')
            ->groupBy('region');

        if ($this->status) {
            $query->where('status', $this->status);
        }

        return $query->pluck('count', 'region')->toArray();
    }

    /**
     * Get total CPU capacity across all matching servers.
     *
     * @return int
     */
    public function totalCpuCapacity(): int
    {
        return (int) $this->buildQuery()->sum('spec_cpu');
    }

    /**
     * Get total memory capacity in MB across all matching servers.
     *
     * @return int
     */
    public function totalMemoryCapacity(): int
    {
        return (int) $this->buildQuery()->sum('spec_memory_mb');
    }

    /**
     * Get total disk capacity in GB across all matching servers.
     *
     * @return int
     */
    public function totalDiskCapacity(): int
    {
        return (int) $this->buildQuery()->sum('spec_disk_gb');
    }

    /**
     * Build the query with all filters applied.
     *
     * @return Builder
     */
    protected function buildQuery(): Builder
    {
        $query = DB::table('vps_servers');

        if ($this->status !== null) {
            $query->where('status', $this->status);
        }

        if ($this->healthStatus !== null) {
            $query->where('health_status', $this->healthStatus);
        }

        if ($this->region !== null) {
            $query->where('region', $this->region);
        }

        if ($this->provider !== null) {
            $query->where('provider', $this->provider);
        }

        if ($this->allocationType !== null) {
            $query->where('allocation_type', $this->allocationType);
        }

        if ($this->minCpuAvailable !== null) {
            $query->where('spec_cpu', '>=', $this->minCpuAvailable);
        }

        if ($this->minMemoryAvailable !== null) {
            $query->where('spec_memory_mb', '>=', $this->minMemoryAvailable);
        }

        if ($this->maxSiteCount !== null) {
            $query->leftJoin('sites', 'vps_servers.id', '=', 'sites.vps_id')
                ->select('vps_servers.*', DB::raw('COUNT(sites.id) as site_count'))
                ->groupBy('vps_servers.id')
                ->having('site_count', '<=', $this->maxSiteCount);
        }

        $this->applySort($query, $this->sortBy, $this->sortDirection);

        return $query;
    }
}
