<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasManyThrough;

class VpsServer extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'hostname',
        'ip_address',
        'provider',
        'provider_id',
        'region',
        'spec_cpu',
        'spec_memory_mb',
        'spec_disk_gb',
        'status',
        'allocation_type',
        'vpsmanager_version',
        'observability_configured',
        'ssh_key_id',
        'ssh_private_key',
        'ssh_public_key',
        'key_rotated_at',
        'last_health_check_at',
        'health_status',
    ];

    /**
     * SECURITY: Encrypted casts for SSH keys.
     *
     * Laravel automatically encrypts these fields using APP_KEY (AES-256-CBC + HMAC-SHA-256)
     * when writing to database and decrypts when reading from database.
     *
     * OWASP Reference: A02:2021 – Cryptographic Failures
     * Protection: Keys encrypted at rest, never stored in plain text
     */
    protected $casts = [
        'observability_configured' => 'boolean',
        'last_health_check_at' => 'datetime',
        'key_rotated_at' => 'datetime',
        'ssh_private_key' => 'encrypted',
        'ssh_public_key' => 'encrypted',
    ];

    /**
     * SECURITY: Hide sensitive fields from JSON serialization.
     *
     * These fields should never be exposed in API responses or logs.
     * Even though keys are encrypted in database, we prevent accidental exposure.
     */
    protected $hidden = [
        'ssh_key_id',
        'provider_id',
        'ssh_private_key',
        'ssh_public_key',
    ];

    /**
     * Get all sites on this VPS.
     */
    public function sites(): HasMany
    {
        return $this->hasMany(Site::class, 'vps_id');
    }

    /**
     * Get all allocations for this VPS.
     */
    public function allocations(): HasMany
    {
        return $this->hasMany(VpsAllocation::class, 'vps_id');
    }

    /**
     * Get all tenants using this VPS.
     */
    public function tenants(): HasManyThrough
    {
        return $this->hasManyThrough(
            Tenant::class,
            VpsAllocation::class,
            'vps_id',
            'id',
            'id',
            'tenant_id'
        );
    }

    /**
     * Check if VPS is active and can accept new sites.
     */
    public function isAvailable(): bool
    {
        return $this->status === 'active' && $this->health_status !== 'unhealthy';
    }

    /**
     * Get available memory in MB.
     */
    public function getAvailableMemoryMb(): int
    {
        $allocated = $this->allocations()->sum('memory_mb_allocated');
        return max(0, $this->spec_memory_mb - $allocated);
    }

    /**
     * Get current site count.
     */
    public function getSiteCount(): int
    {
        return $this->sites()->count();
    }

    /**
     * Get utilization percentage.
     */
    public function getUtilizationPercent(): float
    {
        if ($this->spec_memory_mb === 0) {
            return 0;
        }
        $allocated = $this->allocations()->sum('memory_mb_allocated');
        return round(($allocated / $this->spec_memory_mb) * 100, 2);
    }

    /**
     * Check if VPS is shared or dedicated.
     */
    public function isShared(): bool
    {
        return $this->allocation_type === 'shared';
    }

    /**
     * Scope for active VPS servers.
     */
    public function scopeActive($query)
    {
        return $query->where('status', 'active');
    }

    /**
     * Scope for shared VPS servers.
     */
    public function scopeShared($query)
    {
        return $query->where('allocation_type', 'shared');
    }

    /**
     * Scope for healthy VPS servers.
     */
    public function scopeHealthy($query)
    {
        return $query->whereIn('health_status', ['healthy', 'unknown']);
    }
}
