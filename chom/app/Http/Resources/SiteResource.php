<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class SiteResource extends JsonResource
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
            'name' => $this->name,
            'domain' => $this->domain,
            'status' => $this->status,
            'php_version' => $this->php_version,
            'created_at' => $this->created_at?->toISOString(),
            'updated_at' => $this->updated_at?->toISOString(),

            // Conditional relationships
            'vps_server' => $this->when(
                $this->relationLoaded('vpsServer'),
                fn() => new VpsServerResource($this->vpsServer)
            ),

            // Conditional counts
            'backups_count' => $this->when(
                $this->relationLoaded('backups'),
                fn() => $this->backups->count()
            ),

            // Latest backup
            'latest_backup' => $this->when(
                $this->relationLoaded('latestBackup') && $this->latestBackup,
                fn() => new BackupResource($this->latestBackup)
            ),

            // Additional metadata
            'meta' => [
                'storage_used' => $this->when(
                    isset($this->storage_used),
                    fn() => $this->storage_used
                ),
                'bandwidth_used' => $this->when(
                    isset($this->bandwidth_used),
                    fn() => $this->bandwidth_used
                ),
                'ssl_enabled' => $this->ssl_enabled ?? false,
                'auto_backup_enabled' => $this->auto_backup_enabled ?? false,
            ],
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
            'version' => '1.0',
        ];
    }
}
