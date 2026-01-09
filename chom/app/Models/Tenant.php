<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Tenant Model
 *
 * Represents a tenant within an organization.
 *
 * @property string $id
 * @property string $organization_id
 * @property string $name
 * @property string $slug
 * @property string $tier
 * @property string $status
 * @property array|null $settings
 * @property int $metrics_retention_days
 */
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
        'metrics_retention_days' => 'integer',
    ];

    /**
     * Get the organization that owns this tenant.
     */
    public function organization(): BelongsTo
    {
        return $this->belongsTo(Organization::class);
    }

    /**
     * Get the sites for this tenant.
     */
    public function sites(): HasMany
    {
        return $this->hasMany(Site::class);
    }

    /**
     * Check if tenant is active.
     */
    public function isActive(): bool
    {
        return $this->status === 'active';
    }
}
