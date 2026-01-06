<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\SoftDeletes;
use Laravel\Cashier\Billable;

class Organization extends Model
{
    use HasFactory, HasUuids, Billable, SoftDeletes;

    protected $fillable = [
        'name',
        'slug',
        'billing_email',
        'stripe_customer_id',
        'status',
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

    /**
     * Check if organization can be deleted.
     * Organizations with active resources cannot be deleted.
     */
    public function canBeDeleted(): bool
    {
        // Cannot delete if has active tenants
        if ($this->tenants()->where('status', 'active')->exists()) {
            return false;
        }

        // Cannot delete if has active sites
        if (Site::whereHas('tenant', fn($q) => $q->where('organization_id', $this->id))->exists()) {
            return false;
        }

        // Cannot delete if has active subscription
        if ($this->subscribed()) {
            return false;
        }

        return true;
    }

    /**
     * Get list of blockers preventing deletion.
     */
    public function getDeletionBlockers(): array
    {
        $blockers = [];

        $activeTenants = $this->tenants()->where('status', 'active')->count();
        if ($activeTenants > 0) {
            $blockers[] = "{$activeTenants} active tenant(s)";
        }

        $activeSites = Site::whereHas('tenant', fn($q) => $q->where('organization_id', $this->id))->count();
        if ($activeSites > 0) {
            $blockers[] = "{$activeSites} active site(s)";
        }

        if ($this->subscribed()) {
            $blockers[] = "Active subscription";
        }

        return $blockers;
    }

    /**
     * Suspend the organization and all its tenants.
     */
    public function suspend(): void
    {
        $this->update(['status' => 'suspended']);

        // Suspend all tenants
        $this->tenants()->update(['status' => 'suspended']);
    }

    /**
     * Activate the organization.
     */
    public function activate(): void
    {
        $this->update(['status' => 'active']);
    }
}
