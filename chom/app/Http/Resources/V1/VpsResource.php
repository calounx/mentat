<?php

namespace App\Http\Resources\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * VPS Server API Resource
 *
 * Transforms VpsServer model into consistent JSON API response format.
 *
 * SECURITY:
 * - Hides sensitive SSH keys (handled by Model $hidden attribute)
 * - Hides provider_id for security
 * - Conditionally shows detailed information based on route
 *
 * @package App\Http\Resources\V1
 */
class VpsResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'hostname' => $this->hostname,
            'ip_address' => $this->ip_address,
            'provider' => $this->provider,
            'region' => $this->region,
            'status' => $this->status,
            'health_status' => $this->health_status,
            'allocation_type' => $this->allocation_type,

            // Specifications
            'specs' => [
                'cpu_cores' => $this->spec_cpu,
                'memory_mb' => $this->spec_memory_mb,
                'memory_gb' => $this->spec_memory_mb ? round($this->spec_memory_mb / 1024, 2) : null,
                'disk_gb' => $this->spec_disk_gb,
            ],

            // Resource utilization
            'utilization' => $this->when($this->spec_memory_mb > 0, function () {
                return [
                    'percent' => $this->getUtilizationPercent(),
                    'available_memory_mb' => $this->getAvailableMemoryMb(),
                ];
            }),

            // Configuration
            'vpsmanager_version' => $this->vpsmanager_version,
            'observability_configured' => $this->observability_configured,

            // SSH key status (not the keys themselves)
            'ssh_configured' => !empty($this->ssh_private_key) && !empty($this->ssh_public_key),
            'key_rotated_at' => $this->key_rotated_at?->toIso8601String(),

            // Health monitoring
            'last_health_check_at' => $this->last_health_check_at?->toIso8601String(),

            // Timestamps
            'created_at' => $this->created_at->toIso8601String(),
            'updated_at' => $this->updated_at->toIso8601String(),

            // Relationships (conditionally loaded)

            // Sites count
            'sites_count' => $this->when($this->relationLoaded('sites'), function () {
                return $this->sites->count();
            }),

            // Sites list (for detailed view)
            'sites' => $this->when($this->relationLoaded('sites'), function () {
                return $this->sites->map(function ($site) {
                    return [
                        'id' => $site->id,
                        'domain' => $site->domain,
                        'site_type' => $site->site_type,
                        'status' => $site->status,
                        'storage_used_mb' => $site->storage_used_mb,
                        'created_at' => $site->created_at->toIso8601String(),
                    ];
                });
            }),

            // Allocations (for detailed view)
            'allocations' => $this->when($this->relationLoaded('allocations'), function () {
                return $this->allocations->map(function ($allocation) {
                    return [
                        'id' => $allocation->id,
                        'tenant_id' => $allocation->tenant_id,
                        'sites_allocated' => $allocation->sites_allocated,
                        'storage_mb_allocated' => $allocation->storage_mb_allocated,
                        'memory_mb_allocated' => $allocation->memory_mb_allocated,
                        'created_at' => $allocation->created_at->toIso8601String(),
                    ];
                });
            }),

            // Capacity summary
            'capacity' => $this->when($this->spec_memory_mb > 0 && $this->spec_disk_gb > 0, function () {
                $totalAllocatedMemory = $this->allocations->sum('memory_mb_allocated') ?? 0;
                $totalAllocatedStorage = $this->allocations->sum('storage_mb_allocated') ?? 0;
                $sitesCount = $this->relationLoaded('sites') ? $this->sites->count() : $this->getSiteCount();

                return [
                    'sites' => [
                        'current' => $sitesCount,
                        'max_recommended' => $this->getRecommendedSiteLimit(),
                    ],
                    'memory' => [
                        'allocated_mb' => $totalAllocatedMemory,
                        'total_mb' => $this->spec_memory_mb,
                        'available_mb' => max(0, $this->spec_memory_mb - $totalAllocatedMemory),
                        'percent_used' => round(($totalAllocatedMemory / $this->spec_memory_mb) * 100, 2),
                    ],
                    'storage' => [
                        'allocated_mb' => $totalAllocatedStorage,
                        'allocated_gb' => round($totalAllocatedStorage / 1024, 2),
                        'total_gb' => $this->spec_disk_gb,
                        'available_gb' => round(max(0, ($this->spec_disk_gb * 1024) - $totalAllocatedStorage) / 1024, 2),
                        'percent_used' => round(($totalAllocatedStorage / ($this->spec_disk_gb * 1024)) * 100, 2),
                    ],
                ];
            }),
        ];
    }

    /**
     * Calculate recommended site limit based on VPS specs.
     *
     * @return int
     */
    private function getRecommendedSiteLimit(): int
    {
        if (!$this->spec_memory_mb || !$this->spec_cpu) {
            return 0;
        }

        // Rough estimation: 1GB RAM per 5 sites, 1 CPU core per 10 sites
        $memoryBasedLimit = (int) floor($this->spec_memory_mb / 1024) * 5;
        $cpuBasedLimit = $this->spec_cpu * 10;

        // Return the lower of the two limits
        return min($memoryBasedLimit, $cpuBasedLimit);
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
