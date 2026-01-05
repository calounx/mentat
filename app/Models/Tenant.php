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
        'is_approved',
        'approved_at',
        'approved_by',
        'settings',
        'metrics_retention_days',
    ];

    protected $casts = [
        'settings' => 'array',
        'is_approved' => 'boolean',
        'approved_at' => 'datetime',
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
     * Boot the model.
     */
    protected static function boot(): void
    {
        parent::boot();

        // When tenant status changes, update all associated sites
        static::updating(function (Tenant $tenant) {
            if ($tenant->isDirty('status')) {
                $oldStatus = $tenant->getOriginal('status');
                $newStatus = $tenant->status;

                if ($newStatus === 'suspended') {
                    // Suspend all active sites when tenant is suspended
                    $tenant->sites()
                        ->where('status', 'active')
                        ->update(['status' => 'disabled']);
                } elseif ($newStatus === 'cancelled') {
                    // Mark all sites as disabled when tenant is cancelled
                    $tenant->sites()
                        ->whereNotIn('status', ['failed', 'deleting'])
                        ->update(['status' => 'disabled']);
                } elseif ($newStatus === 'active' && $oldStatus === 'suspended') {
                    // Reactivate disabled sites when tenant is unsuspended
                    $tenant->sites()
                        ->where('status', 'disabled')
                        ->update(['status' => 'active']);
                }
            }
        });
    }

    /**
     * Get the user who approved this tenant.
     */
    public function approver(): BelongsTo
    {
        return $this->belongsTo(User::class, 'approved_by');
    }

    /**
     * Check if tenant is approved.
     */
    public function isApproved(): bool
    {
        return $this->is_approved === true;
    }

    /**
     * Approve this tenant.
     */
    public function approve(User $approver): void
    {
        $this->update([
            'is_approved' => true,
            'approved_at' => now(),
            'approved_by' => $approver->id,
        ]);
    }

    /**
     * Revoke approval for this tenant.
     */
    public function revokeApproval(): void
    {
        $this->update([
            'is_approved' => false,
            'approved_at' => null,
            'approved_by' => null,
        ]);
    }

    /**
     * Check if tenant is active.
     */
    public function isActive(): bool
    {
        return $this->status === 'active';
    }

    /**
     * Check if tenant can have sites created.
     * Tenant must be both active and approved.
     */
    public function canHaveSites(): bool
    {
        return $this->isActive() && $this->isApproved();
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
