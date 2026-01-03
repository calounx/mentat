<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

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
            'type' => $this->type,
            'size' => $this->size,
            'size_formatted' => $this->when(
                isset($this->size),
                fn() => $this->formatBytes($this->size)
            ),
            'status' => $this->status,
            'created_at' => $this->created_at?->toISOString(),
            'completed_at' => $this->completed_at?->toISOString(),

            // Download URL (conditionally shown based on status)
            'download_url' => $this->when(
                $this->status === 'completed' && $this->file_path,
                fn() => route('backups.download', ['backup' => $this->id])
            ),

            // Conditional relationships
            'site' => $this->when(
                $this->relationLoaded('site'),
                fn() => new SiteResource($this->site)
            ),

            // Additional metadata
            'meta' => [
                'backup_method' => $this->backup_method ?? 'automated',
                'retention_days' => $this->retention_days ?? 30,
                'compression_type' => $this->compression_type ?? 'gzip',
                'encrypted' => $this->encrypted ?? false,
                'duration_seconds' => $this->when(
                    isset($this->started_at) && isset($this->completed_at),
                    fn() => $this->completed_at->diffInSeconds($this->started_at)
                ),
            ],

            // Error information if failed
            'error' => $this->when(
                $this->status === 'failed',
                fn() => [
                    'message' => $this->error_message,
                    'code' => $this->error_code,
                    'occurred_at' => $this->failed_at?->toISOString(),
                ]
            ),
        ];
    }

    /**
     * Format bytes to human-readable format.
     *
     * @param int $bytes
     * @param int $precision
     * @return string
     */
    protected function formatBytes(int $bytes, int $precision = 2): string
    {
        $units = ['B', 'KB', 'MB', 'GB', 'TB'];

        for ($i = 0; $bytes > 1024 && $i < count($units) - 1; $i++) {
            $bytes /= 1024;
        }

        return round($bytes, $precision) . ' ' . $units[$i];
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
