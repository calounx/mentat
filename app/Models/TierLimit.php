<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class TierLimit extends Model
{
    use HasFactory;

    /**
     * The primary key for the model.
     */
    protected $primaryKey = 'tier';

    /**
     * The "type" of the primary key ID.
     */
    protected $keyType = 'string';

    /**
     * Indicates if the IDs are auto-incrementing.
     */
    public $incrementing = false;

    protected $fillable = [
        'tier',
        'name',
        'description',
        'max_sites',
        'max_storage_gb',
        'max_bandwidth_gb',
        'backup_retention_days',
        'support_level',
        'dedicated_ip',
        'staging_environments',
        'white_label',
        'api_rate_limit_per_hour',
        'price_monthly_cents',
        'start_date',
        'end_date',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'max_sites' => 'integer',
            'max_storage_gb' => 'integer',
            'max_bandwidth_gb' => 'integer',
            'backup_retention_days' => 'integer',
            'dedicated_ip' => 'boolean',
            'staging_environments' => 'boolean',
            'white_label' => 'boolean',
            'api_rate_limit_per_hour' => 'integer',
            'price_monthly_cents' => 'integer',
            'start_date' => 'date',
            'end_date' => 'date',
            'is_active' => 'boolean',
        ];
    }

    /**
     * Scope for active plans.
     */
    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }

    /**
     * Scope for currently valid plans (within date range).
     */
    public function scopeCurrentlyValid($query)
    {
        $today = now()->toDateString();

        return $query->where('is_active', true)
            ->where(function ($q) use ($today) {
                $q->whereNull('start_date')
                    ->orWhere('start_date', '<=', $today);
            })
            ->where(function ($q) use ($today) {
                $q->whereNull('end_date')
                    ->orWhere('end_date', '>=', $today);
            });
    }

    /**
     * Check if plan is currently valid.
     */
    public function isCurrentlyValid(): bool
    {
        if (!$this->is_active) {
            return false;
        }

        $today = now()->toDateString();

        if ($this->start_date && $this->start_date->toDateString() > $today) {
            return false;
        }

        if ($this->end_date && $this->end_date->toDateString() < $today) {
            return false;
        }

        return true;
    }

    /**
     * Get all tenants with this tier.
     */
    public function tenants(): HasMany
    {
        return $this->hasMany(Tenant::class, 'tier', 'tier');
    }

    /**
     * Check if this tier has unlimited sites.
     */
    public function hasUnlimitedSites(): bool
    {
        return $this->max_sites === -1;
    }

    /**
     * Check if this tier has unlimited storage.
     */
    public function hasUnlimitedStorage(): bool
    {
        return $this->max_storage_gb === -1;
    }

    /**
     * Check if this tier has unlimited bandwidth.
     */
    public function hasUnlimitedBandwidth(): bool
    {
        return $this->max_bandwidth_gb === -1;
    }

    /**
     * Check if this tier has unlimited API rate limit.
     */
    public function hasUnlimitedApiRateLimit(): bool
    {
        return $this->api_rate_limit_per_hour === -1;
    }

    /**
     * Get the monthly price in dollars.
     */
    public function getPriceMonthlyInDollars(): float
    {
        return $this->price_monthly_cents / 100;
    }

    /**
     * Get formatted monthly price.
     */
    public function getFormattedMonthlyPrice(): string
    {
        return '$' . number_format($this->getPriceMonthlyInDollars(), 2);
    }

    /**
     * Get the display value for a limit (shows "Unlimited" for -1).
     */
    public function getDisplayValue(string $attribute): string
    {
        $value = $this->$attribute;

        if ($value === -1) {
            return 'Unlimited';
        }

        return (string) $value;
    }
}
