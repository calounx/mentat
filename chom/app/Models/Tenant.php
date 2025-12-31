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
        'cached_storage_mb',
        'cached_sites_count',
        'cached_at',
    ];

    protected $casts = [
        'settings' => 'array',
        'cached_at' => 'datetime',
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
     * Get current site count (uses cached value with 5-minute freshness).
     *
     * This method uses a cached aggregate to avoid expensive COUNT queries.
     * Cache is automatically invalidated when sites are created/updated/deleted.
     * If cache is stale (>5 minutes), it will be refreshed automatically.
     *
     * @return int Number of sites belonging to this tenant
     */
    public function getSiteCount(): int
    {
        // Check if cache is stale or missing
        if ($this->isCacheStale()) {
            $this->updateCachedStats();
        }

        return $this->cached_sites_count;
    }

    /**
     * Get total storage used in MB (uses cached value with 5-minute freshness).
     *
     * This method uses a cached aggregate to avoid expensive SUM queries.
     * Cache is automatically invalidated when sites are created/updated/deleted.
     * If cache is stale (>5 minutes), it will be refreshed automatically.
     *
     * @return int Total storage used in MB across all sites
     */
    public function getStorageUsedMb(): int
    {
        // Check if cache is stale or missing
        if ($this->isCacheStale()) {
            $this->updateCachedStats();
        }

        return $this->cached_storage_mb;
    }

    /**
     * Update cached aggregate statistics.
     *
     * This method recalculates and stores aggregate values for:
     * - Total site count
     * - Total storage usage
     *
     * Called automatically when:
     * - Sites are created, updated, or deleted (via model events)
     * - Cache is older than 5 minutes (staleness check)
     *
     * @return void
     */
    public function updateCachedStats(): void
    {
        // Use single query with both aggregates for efficiency
        $stats = $this->sites()
            ->selectRaw('COUNT(*) as site_count, COALESCE(SUM(storage_used_mb), 0) as total_storage')
            ->first();

        $this->update([
            'cached_sites_count' => $stats->site_count ?? 0,
            'cached_storage_mb' => $stats->total_storage ?? 0,
            'cached_at' => now(),
        ]);
    }

    /**
     * Check if cached statistics are stale (older than 5 minutes).
     *
     * @return bool True if cache needs refresh, false if cache is fresh
     */
    private function isCacheStale(): bool
    {
        // Cache is stale if it doesn't exist or is older than 5 minutes
        return !$this->cached_at || $this->cached_at->diffInMinutes(now()) > 5;
    }
}
