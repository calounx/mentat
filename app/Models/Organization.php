<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Laravel\Cashier\Billable;

class Organization extends Model
{
    use HasFactory, HasUuids, Billable;

    protected $fillable = [
        'name',
        'slug',
        'billing_email',
        'stripe_customer_id',
    ];

    protected $hidden = [
        'stripe_customer_id',
    ];

    /**
     * Get the email address for Stripe billing.
     */
    public function stripeEmail(): string
    {
        return $this->billing_email;
    }

    /**
     * Get all tenants belonging to this organization.
     */
    public function tenants(): HasMany
    {
        return $this->hasMany(Tenant::class);
    }

    /**
     * Get the default/primary tenant (oldest by created_at).
     * Note: Cannot use oldestOfMany() because PostgreSQL doesn't support MIN/MAX on UUID columns.
     */
    public function defaultTenant(): HasOne
    {
        return $this->hasOne(Tenant::class)->orderBy('created_at');
    }

    /**
     * Get all users in this organization.
     */
    public function users(): HasMany
    {
        return $this->hasMany(User::class);
    }

    /**
     * Get the owner of this organization.
     */
    public function owner(): HasOne
    {
        return $this->hasOne(User::class)->where('role', 'owner');
    }

    /**
     * Get the subscription for this organization.
     */
    public function subscription(): HasOne
    {
        return $this->hasOne(Subscription::class);
    }

    /**
     * Get all invoices for this organization.
     */
    public function invoices(): HasMany
    {
        return $this->hasMany(Invoice::class);
    }

    /**
     * Get all audit logs for this organization.
     */
    public function auditLogs(): HasMany
    {
        return $this->hasMany(AuditLog::class);
    }

    /**
     * Check if organization has an active subscription.
     */
    public function hasActiveSubscription(): bool
    {
        return $this->subscription?->status === 'active'
            || $this->subscription?->status === 'trialing';
    }

    /**
     * Get the current tier for this organization.
     */
    public function getCurrentTier(): string
    {
        return $this->subscription?->tier ?? 'starter';
    }
}
