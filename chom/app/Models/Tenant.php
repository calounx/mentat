<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasManyThrough;

class Tenant extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'organization_id',
        'name',
        'slug',
        'tier',
        'status',
        'settings',
        'metrics_retention_days',
    ];

    protected $casts = [
        'settings' => 'array',
    ];

    /**
     * Get the organization that owns this tenant.
     */
    public function organization(): BelongsTo
    {
        return $this->belongsTo(Organization::class);
    }

    /**
     * Get all sites belonging to this tenant.
     */
    public function sites(): HasMany
    {
        return $this->hasMany(Site::class);
    }

    /**
     * Get all VPS allocations for this tenant.
     */
    public function vpsAllocations(): HasMany
    {
        return $this->hasMany(VpsAllocation::class);
    }

    /**
     * Get all VPS servers allocated to this tenant.
     */
    public function vpsServers(): HasManyThrough
    {
        return $this->hasManyThrough(
            VpsServer::class,
            VpsAllocation::class,
            'tenant_id',
            'id',
            'id',
            'vps_id'
        );
    }

    /**
     * Get all usage records for this tenant.
     */
    public function usageRecords(): HasMany
    {
        return $this->hasMany(UsageRecord::class);
    }

    /**
     * Get all operations for this tenant.
     */
    public function operations(): HasMany
    {
        return $this->hasMany(Operation::class);
    }

    /**
     * Get the tier limits for this tenant.
     */
    public function tierLimits()
    {
        return $this->hasOne(TierLimit::class, 'tier', 'tier');
    }

    /**
     * Check if tenant is active.
     */
    public function isActive(): bool
    {
        return $this->status === 'active';
    }

    /**
     * Get the maximum number of sites allowed.
     */
    public function getMaxSites(): int
    {
        return $this->tierLimits?->max_sites ?? 5;
    }

    /**
     * Check if tenant can create more sites.
     */
    public function canCreateSite(): bool
    {
        $maxSites = $this->getMaxSites();
        if ($maxSites === -1) {
            return true; // Unlimited
        }
        return $this->sites()->count() < $maxSites;
    }

    /**
     * Get current site count.
     */
    public function getSiteCount(): int
    {
        return $this->sites()->count();
    }

    /**
     * Get total storage used in MB.
     */
    public function getStorageUsedMb(): int
    {
        return $this->sites()->sum('storage_used_mb');
    }
}
