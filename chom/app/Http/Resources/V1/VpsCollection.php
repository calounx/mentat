<?php

namespace App\Http\Resources\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\ResourceCollection;

/**
 * VPS Server Collection Resource
 *
 * Transforms paginated VpsServer collection into consistent JSON API response format.
 * Includes pagination metadata and summary statistics.
 *
 * @package App\Http\Resources\V1
 */
class VpsCollection extends ResourceCollection
{
    /**
     * The resource that this resource collects.
     *
     * @var string
     */
    public $collects = VpsResource::class;

    /**
     * Transform the resource collection into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'data' => $this->collection,
            'meta' => [
                'pagination' => [
                    'current_page' => $this->currentPage(),
                    'per_page' => $this->perPage(),
                    'total' => $this->total(),
                    'total_pages' => $this->lastPage(),
                    'from' => $this->firstItem(),
                    'to' => $this->lastItem(),
                ],
                'summary' => $this->getSummary(),
            ],
        ];
    }

    /**
     * Get collection summary statistics.
     *
     * @return array<string, mixed>
     */
    private function getSummary(): array
    {
        $items = $this->collection;

        $totalServers = $items->count();
        $activeServers = $items->where('status', 'active')->count();
        $totalSites = $items->sum('sites_count');

        // Calculate total resources
        $totalCpu = $items->sum('spec_cpu');
        $totalMemoryMb = $items->sum('spec_memory_mb');
        $totalDiskGb = $items->sum('spec_disk_gb');

        // Count by provider
        $providerCounts = $items->groupBy('provider')->map->count();

        // Count by allocation type
        $allocationCounts = $items->groupBy('allocation_type')->map->count();

        // Health status distribution
        $healthCounts = $items->groupBy('health_status')->map->count();

        return [
            'servers' => [
                'total' => $totalServers,
                'active' => $activeServers,
                'inactive' => $items->where('status', 'inactive')->count(),
                'maintenance' => $items->where('status', 'maintenance')->count(),
            ],
            'sites' => [
                'total' => $totalSites,
                'average_per_server' => $totalServers > 0 ? round($totalSites / $totalServers, 2) : 0,
            ],
            'resources' => [
                'total_cpu_cores' => $totalCpu,
                'total_memory_gb' => round($totalMemoryMb / 1024, 2),
                'total_disk_gb' => $totalDiskGb,
            ],
            'providers' => $providerCounts->toArray(),
            'allocation_types' => $allocationCounts->toArray(),
            'health_status' => $healthCounts->toArray(),
        ];
    }

    /**
     * Get additional data that should be returned with the resource array.
     *
     * @return array<string, mixed>
     */
    public function with(Request $request): array
    {
        return [
            'success' => true,
        ];
    }
}
