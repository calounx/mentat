<?php

namespace App\Http\Resources\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Site API Resource
 *
 * Transforms Site model into consistent JSON API response format.
 */
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
            'domain' => $this->domain,
            'url' => $this->getUrl(),
            'site_type' => $this->site_type,
            'php_version' => $this->php_version,
            'ssl_enabled' => $this->ssl_enabled,
            'ssl_expires_at' => $this->ssl_expires_at?->toIso8601String(),
            'status' => $this->status,
            'storage_used_mb' => $this->storage_used_mb,
            'created_at' => $this->created_at->toIso8601String(),
            'updated_at' => $this->updated_at->toIso8601String(),

            // VPS Server relationship
            'vps' => $this->when($this->relationLoaded('vpsServer') && $this->vpsServer, function () {
                return [
                    'id' => $this->vpsServer->id,
                    'hostname' => $this->vpsServer->hostname,
                    'ip_address' => $this->vpsServer->ip_address ?? null,
                ];
            }),

            // Backups count
            'backups_count' => $this->when($this->relationLoaded('backups'), function () {
                return $this->backups->count();
            }),

            // Recent backups (for detailed view)
            'recent_backups' => $this->when($this->relationLoaded('backups'), function () {
                return $this->backups->take(5)->map(function ($backup) {
                    return [
                        'id' => $backup->id,
                        'type' => $backup->backup_type,
                        'size' => $backup->getSizeFormatted(),
                        'status' => $backup->status,
                        'created_at' => $backup->created_at->toIso8601String(),
                    ];
                });
            }),

            // Detailed information (only for show endpoint)
            'db_name' => $this->when($request->routeIs('sites.show'), $this->db_name),
            'document_root' => $this->when($request->routeIs('sites.show'), $this->document_root),
            'settings' => $this->when($request->routeIs('sites.show'), $this->settings),

            // SSL certificate status
            'ssl_status' => $this->when($this->ssl_enabled, function () {
                if (!$this->ssl_expires_at) {
                    return 'pending';
                }
                if ($this->isSslExpired()) {
                    return 'expired';
                }
                if ($this->isSslExpiringSoon()) {
                    return 'expiring_soon';
                }
                return 'valid';
            }),
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
