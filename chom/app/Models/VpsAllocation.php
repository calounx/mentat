<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class VpsAllocation extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'vps_id',
        'tenant_id',
        'sites_allocated',
        'storage_mb_allocated',
        'memory_mb_allocated',
    ];

    /**
     * Get the VPS server for this allocation.
     */
    public function vpsServer(): BelongsTo
    {
        return $this->belongsTo(VpsServer::class, 'vps_id');
    }

    /**
     * Get the tenant for this allocation.
     */
    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    /**
     * Increment site allocation.
     */
    public function incrementSites(int $count = 1): void
    {
        $this->increment('sites_allocated', $count);
    }

    /**
     * Decrement site allocation.
     */
    public function decrementSites(int $count = 1): void
    {
        $this->decrement('sites_allocated', $count);
    }

    /**
     * Update storage allocation.
     */
    public function updateStorageAllocation(int $mb): void
    {
        $this->update(['storage_mb_allocated' => $mb]);
    }
}
