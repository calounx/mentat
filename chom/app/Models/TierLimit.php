<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Facades\Cache;

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
        ];
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

    /**
     * Get cached tier limits for a specific tier.
     * Caches for 1 hour to reduce database queries.
     *
     * @param string $tier The tier name (starter, pro, enterprise)
     * @return TierLimit|null
     */
    public static function getCached(string $tier): ?TierLimit
    {
        $cacheKey = "tier_limit:{$tier}";

        return Cache::remember($cacheKey, 3600, function () use ($tier) {
            return static::find($tier);
        });
    }

    /**
     * Get all cached tier limits.
     * Caches for 1 hour to reduce database queries.
     *
     * @return \Illuminate\Support\Collection
     */
    public static function getAllCached(): \Illuminate\Support\Collection
    {
        $cacheKey = "tier_limits:all";

        return Cache::remember($cacheKey, 3600, function () {
            return static::all();
        });
    }

    /**
     * Invalidate cache for a specific tier.
     * Call this when tier limits are updated.
     *
     * @param string $tier
     */
    public static function invalidateCache(string $tier): void
    {
        Cache::forget("tier_limit:{$tier}");
        Cache::forget("tier_limits:all");
    }

    /**
     * Boot method to automatically invalidate cache on updates.
     */
    protected static function booted(): void
    {
        static::saved(function (TierLimit $tierLimit) {
            static::invalidateCache($tierLimit->tier);
        });

        static::deleted(function (TierLimit $tierLimit) {
            static::invalidateCache($tierLimit->tier);
        });
    }
}
