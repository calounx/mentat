<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class Site extends Model
{
    use HasFactory, HasUuids, SoftDeletes;

    protected $fillable = [
        'tenant_id',
        'vps_id',
        'domain',
        'site_type',
        'php_version',
        'ssl_enabled',
        'ssl_expires_at',
        'status',
        'failure_reason',
        'healing_attempts',
        'last_healing_at',
        'provision_attempts',
        'document_root',
        'db_name',
        'db_user',
        'storage_used_mb',
        'settings',
    ];

    protected $casts = [
        'ssl_enabled' => 'boolean',
        'ssl_expires_at' => 'datetime',
        'settings' => 'array',
        'healing_attempts' => 'array',
        'last_healing_at' => 'datetime',
    ];

    protected $hidden = [
        'db_user',
        'db_name',
        'document_root',
    ];

    /**
     * Get the tenant that owns this site.
     */
    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    /**
     * Get the VPS server hosting this site.
     */
    public function vpsServer(): BelongsTo
    {
        return $this->belongsTo(VpsServer::class, 'vps_id');
    }

    /**
     * Get all backups for this site.
     */
    public function backups(): HasMany
    {
        return $this->hasMany(SiteBackup::class);
    }

    /**
     * Check if site is active.
     */
    public function isActive(): bool
    {
        return $this->status === 'active';
    }

    /**
     * Check if SSL certificate is expiring soon (within 14 days).
     */
    public function isSslExpiringSoon(): bool
    {
        if (!$this->ssl_enabled || !$this->ssl_expires_at) {
            return false;
        }
        return $this->ssl_expires_at->diffInDays(now()) <= 14;
    }

    /**
     * Check if SSL certificate has expired.
     */
    public function isSslExpired(): bool
    {
        if (!$this->ssl_enabled || !$this->ssl_expires_at) {
            return false;
        }
        return $this->ssl_expires_at->isPast();
    }

    /**
     * Get the full URL for this site.
     */
    public function getUrl(): string
    {
        $protocol = $this->ssl_enabled ? 'https' : 'http';
        return "{$protocol}://{$this->domain}";
    }

    /**
     * Scope for active sites.
     */
    public function scopeActive($query)
    {
        return $query->where('status', 'active');
    }

    /**
     * Scope for WordPress sites.
     */
    public function scopeWordpress($query)
    {
        return $query->where('site_type', 'wordpress');
    }

    /**
     * Scope for sites with expiring SSL.
     */
    public function scopeSslExpiringSoon($query, int $days = 14)
    {
        return $query->where('ssl_enabled', true)
            ->whereNotNull('ssl_expires_at')
            ->where('ssl_expires_at', '<=', now()->addDays($days));
    }
}
