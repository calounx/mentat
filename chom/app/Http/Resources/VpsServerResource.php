<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class VpsServerResource extends JsonResource
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
            'status' => $this->status,
            'region' => $this->region,
            'provider' => $this->provider ?? 'custom',
            'created_at' => $this->created_at?->toISOString(),
            'updated_at' => $this->updated_at?->toISOString(),

            // Server specifications
            'specifications' => [
                'cpu_cores' => $this->cpu_cores ?? null,
                'ram_mb' => $this->ram_mb ?? null,
                'disk_gb' => $this->disk_gb ?? null,
                'os_version' => $this->os_version ?? null,
            ],

            // Site allocation
            'allocated_sites' => $this->when(
                $this->relationLoaded('sites'),
                fn() => $this->sites->count()
            ),
            'max_sites' => $this->max_sites ?? 10,

            // Sites relationship (conditionally loaded)
            'sites' => $this->when(
                $request->query('include') === 'sites' && $this->relationLoaded('sites'),
                fn() => SiteResource::collection($this->sites)
            ),

            // Health metrics (conditionally loaded)
            'health_metrics' => $this->when(
                $this->relationLoaded('latestHealthMetric') && $this->latestHealthMetric,
                fn() => [
                    'cpu_usage' => $this->latestHealthMetric->cpu_usage,
                    'ram_usage' => $this->latestHealthMetric->ram_usage,
                    'disk_usage' => $this->latestHealthMetric->disk_usage,
                    'load_average' => $this->latestHealthMetric->load_average ?? null,
                    'uptime_seconds' => $this->latestHealthMetric->uptime_seconds ?? null,
                    'checked_at' => $this->latestHealthMetric->created_at?->toISOString(),
                ]
            ),

            // Connection status
            'connection' => [
                'ssh_port' => $this->ssh_port ?? 22,
                'last_connected_at' => $this->last_connected_at?->toISOString(),
                'connection_status' => $this->getConnectionStatus(),
            ],

            // Status flags
            'is_active' => $this->status === 'active',
            'is_maintenance' => $this->status === 'maintenance',
            'is_provisioning' => $this->status === 'provisioning',
        ];
    }

    /**
     * Get connection status based on last connection time.
     *
     * @return string
     */
    protected function getConnectionStatus(): string
    {
        if (!$this->last_connected_at) {
            return 'never_connected';
        }

        $minutesSinceLastConnection = $this->last_connected_at->diffInMinutes(now());

        if ($minutesSinceLastConnection < 5) {
            return 'online';
        } elseif ($minutesSinceLastConnection < 15) {
            return 'warning';
        }

        return 'offline';
    }

    /**
     * Get additional data that should be returned with the resource array.
     *
     * @return array<string, mixed>
     */
    public function with(Request $request): array
    {
        return [
            'version' => '1.0',
        ];
    }
}
