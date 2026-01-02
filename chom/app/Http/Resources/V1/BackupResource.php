<?php

namespace App\Http\Resources\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Backup API Resource
 *
 * Transforms SiteBackup model into standardized JSON response.
 */
class BackupResource extends JsonResource
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
            'site_id' => $this->site_id,
            'filename' => $this->filename,
            'backup_type' => $this->backup_type,
            'status' => $this->status,

            // Size information
            'size_bytes' => $this->size_bytes,
            'size_mb' => $this->size_mb,
            'size_formatted' => $this->getSizeFormatted(),

            // Status flags
            'is_ready' => $this->status === 'completed' && !empty($this->storage_path),
            'is_expired' => $this->isExpired(),
            'can_restore' => $this->status === 'completed' && !$this->isExpired(),
            'can_download' => $this->status === 'completed' && !empty($this->storage_path),

            // Dates
            'retention_days' => $this->retention_days,
            'expires_at' => $this->expires_at?->toIso8601String(),
            'completed_at' => $this->completed_at?->toIso8601String(),
            'created_at' => $this->created_at->toIso8601String(),
            'updated_at' => $this->updated_at->toIso8601String(),

            // Error information (if any)
            'error_message' => $this->when($this->status === 'failed', $this->error_message),

            // Related site information
            'site' => $this->when(
                $this->relationLoaded('site') && $this->site,
                fn () => [
                    'id' => $this->site->id,
                    'domain' => $this->site->domain,
                    'site_type' => $this->site->site_type,
                ]
            ),
        ];
    }
}
