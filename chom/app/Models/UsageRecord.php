<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class UsageRecord extends Model
{
    use HasFactory, HasUuids;

    /**
     * Boot the model and register global scopes for tenant isolation.
     */
    protected static function booted(): void
    {
        // Apply tenant scope automatically to all queries
        static::addGlobalScope('tenant', function ($builder) {
            if (auth()->check() && auth()->user()->currentTenant()) {
                $builder->where('tenant_id', auth()->user()->currentTenant()->id);
            }
        });
    }

    protected $fillable = [
        'tenant_id',
        'metric_type',
        'quantity',
        'unit_price',
        'period_start',
        'period_end',
        'stripe_usage_record_id',
    ];

    protected $hidden = [
        'stripe_usage_record_id',
    ];

    protected function casts(): array
    {
        return [
            'quantity' => 'decimal:2',
            'unit_price' => 'decimal:4',
            'period_start' => 'date',
            'period_end' => 'date',
        ];
    }

    /**
     * Get the tenant this usage record belongs to.
     */
    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    /**
     * Scope to filter by metric type.
     */
    public function scopeForMetric($query, string $metricType)
    {
        return $query->where('metric_type', $metricType);
    }

    /**
     * Scope to filter by period.
     */
    public function scopeForPeriod($query, $periodStart, $periodEnd)
    {
        return $query->where('period_start', '>=', $periodStart)
            ->where('period_end', '<=', $periodEnd);
    }

    /**
     * Scope to get records for the current month.
     */
    public function scopeCurrentMonth($query)
    {
        $now = now();
        return $query->whereMonth('period_start', $now->month)
            ->whereYear('period_start', $now->year);
    }

    /**
     * Calculate the total cost for this usage record.
     */
    public function getTotalCost(): float
    {
        if ($this->unit_price === null) {
            return 0.0;
        }

        return (float) $this->quantity * (float) $this->unit_price;
    }

    /**
     * Get the formatted total cost.
     */
    public function getFormattedTotalCost(): string
    {
        return '$' . number_format($this->getTotalCost(), 2);
    }

    /**
     * Check if this record is for the current billing period.
     */
    public function isCurrentPeriod(): bool
    {
        $now = now()->toDateString();
        return $this->period_start <= $now && $this->period_end >= $now;
    }
}
