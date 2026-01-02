<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Invoice extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'organization_id',
        'stripe_invoice_id',
        'amount_cents',
        'currency',
        'status',
        'paid_at',
        'period_start',
        'period_end',
    ];

    protected $hidden = [
        'stripe_invoice_id',
    ];

    protected function casts(): array
    {
        return [
            'amount_cents' => 'integer',
            'paid_at' => 'datetime',
            'period_start' => 'date',
            'period_end' => 'date',
        ];
    }

    /**
     * Get the organization that owns this invoice.
     */
    public function organization(): BelongsTo
    {
        return $this->belongsTo(Organization::class);
    }

    /**
     * Check if the invoice is paid.
     */
    public function isPaid(): bool
    {
        return $this->status === 'paid';
    }

    /**
     * Check if the invoice is open (awaiting payment).
     */
    public function isOpen(): bool
    {
        return $this->status === 'open';
    }

    /**
     * Get the amount in dollars.
     */
    public function getAmountInDollars(): float
    {
        return $this->amount_cents / 100;
    }

    /**
     * Get formatted amount with currency symbol.
     */
    public function getFormattedAmount(): string
    {
        $symbol = match ($this->currency) {
            'usd' => '$',
            'eur' => '€',
            'gbp' => '£',
            default => strtoupper($this->currency).' ',
        };

        return $symbol.number_format($this->getAmountInDollars(), 2);
    }
}
