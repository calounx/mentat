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
        'last_health_check_at',
        'health_status',
    ];

    protected $casts = [
        'observability_configured' => 'boolean',
        'last_health_check_at' => 'datetime',
    ];

    protected $hidden = [
        'ssh_key_id',
        'provider_id',
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
