<?php

namespace App\Models;

use App\Notifications\ResetPasswordNotification;
use Illuminate\Contracts\Auth\MustVerifyEmail;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Illuminate\Support\Facades\Cache;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable implements MustVerifyEmail
{
    use HasFactory, Notifiable, HasApiTokens, HasUuids;

    protected $fillable = [
        'username',
        'first_name',
        'last_name',
        'email',
        'password',
        'organization_id',
        'role',
        'is_super_admin',
        'two_factor_enabled',
        'two_factor_secret',
        'settings',
        'must_reset_password',
        'approval_status',
        'approved_at',
        'approved_by',
        'rejected_at',
        'rejected_by',
        'rejection_reason',
    ];

    protected $hidden = [
        'password',
        'remember_token',
        'two_factor_secret',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'is_super_admin' => 'boolean',
            'two_factor_enabled' => 'boolean',
            'settings' => 'array',
            'must_reset_password' => 'boolean',
            'approval_status' => 'string',
            'approved_at' => 'datetime',
            'rejected_at' => 'datetime',
        ];
    }

    /**
     * Check if user must reset their password on next login.
     */
    public function mustResetPassword(): bool
    {
        return $this->must_reset_password === true;
    }

    /**
     * Get the organization this user belongs to.
     */
    public function organization(): BelongsTo
    {
        return $this->belongsTo(Organization::class);
    }

    /**
     * Get the current tenant for this user.
     */
    public function currentTenant(): ?Tenant
    {
        return $this->organization?->defaultTenant;
    }

    /**
     * Check if user is organization owner.
     */
    public function isOwner(): bool
    {
        return $this->role === 'owner';
    }

    /**
     * Check if user is admin or owner.
     */
    public function isAdmin(): bool
    {
        return in_array($this->role, ['owner', 'admin']);
    }

    /**
     * Check if user can manage sites.
     */
    public function canManageSites(): bool
    {
        return in_array($this->role, ['owner', 'admin', 'member']);
    }

    /**
     * Check if user is viewer only.
     */
    public function isViewer(): bool
    {
        return $this->role === 'viewer';
    }

    /**
     * Check if user is a super admin (system-wide admin access).
     * Super admins can access the admin panel and manage all tenants, VPS servers, etc.
     */
    public function isSuperAdmin(): bool
    {
        return $this->is_super_admin === true;
    }

    /**
     * Check if user approval is pending.
     */
    public function isPending(): bool
    {
        return $this->approval_status === 'pending';
    }

    /**
     * Check if user is approved.
     */
    public function isApproved(): bool
    {
        return $this->approval_status === 'approved';
    }

    /**
     * Check if user was rejected.
     */
    public function isRejected(): bool
    {
        return $this->approval_status === 'rejected';
    }

    /**
     * Approve this user.
     */
    public function approve(User $approver): void
    {
        $this->update([
            'approval_status' => 'approved',
            'approved_at' => now(),
            'approved_by' => $approver->id,
        ]);
    }

    /**
     * Reject this user with reason and track in spam database.
     */
    public function reject(User $rejector, string $reason): void
    {
        \DB::transaction(function () use ($rejector, $reason) {
            $this->update([
                'approval_status' => 'rejected',
                'rejected_at' => now(),
                'rejected_by' => $rejector->id,
                'rejection_reason' => $reason,
            ]);

            // Track in spam database
            RejectedEmail::trackRejection($this->email, $this->id, $reason, $rejector->id);
        });
    }

    /**
     * Get user's full name.
     */
    public function fullName(): string
    {
        return trim("{$this->first_name} {$this->last_name}");
    }

    /**
     * Get the user who approved this user.
     */
    public function approver(): BelongsTo
    {
        return $this->belongsTo(User::class, 'approved_by');
    }

    /**
     * Get the user who rejected this user.
     */
    public function rejector(): BelongsTo
    {
        return $this->belongsTo(User::class, 'rejected_by');
    }

    /**
     * Get all operations initiated by this user.
     */
    public function operations(): HasMany
    {
        return $this->hasMany(Operation::class);
    }

    /**
     * Get all tenants this user has access to.
     */
    public function tenants(): BelongsToMany
    {
        return $this->belongsToMany(Tenant::class, 'tenant_user')
                    ->withTimestamps();
    }

    /**
     * Check if user has access to a specific tenant.
     */
    public function hasAccessToTenant(Tenant $tenant): bool
    {
        if ($this->is_super_admin) {
            return true;
        }

        if ($this->organization_id !== $tenant->organization_id) {
            return false;
        }

        return $this->tenants()->where('tenants.id', $tenant->id)->exists();
    }

    /**
     * Get cached tenant IDs for performance.
     */
    public function getCachedTenantIds(): array
    {
        return Cache::remember(
            "user:{$this->id}:tenant_ids",
            now()->addHour(),
            fn() => $this->tenants()->pluck('tenants.id')->toArray()
        );
    }

    /**
     * Record user login timestamp.
     */
    public function recordLogin(): void
    {
        $this->update(['last_login_at' => now()]);
    }

    /**
     * Check if current user can manage the target user based on hierarchy.
     * Hierarchy: Self → Tenant owner/manager → Org owner/manager → Super admin
     */
    public function canManageUser(User $target): bool
    {
        // Cannot manage yourself through admin functions
        if ($this->id === $target->id) {
            return false;
        }

        // Super admins can manage all users
        if ($this->is_super_admin) {
            return true;
        }

        // Must be in same organization
        if ($this->organization_id !== $target->organization_id) {
            return false;
        }

        // Organization owners can manage everyone in their org except other owners
        if ($this->isOwner()) {
            return !$target->isOwner() || $target->id === $this->id;
        }

        // Organization admins can manage members and viewers, but not owners or other admins
        if ($this->isAdmin()) {
            return !$target->isOwner() && !$target->isAdmin();
        }

        // Regular users cannot manage other users
        return false;
    }

    /**
     * Check if current user is a tenant owner/manager of the target user.
     * This checks if they share tenants and current user has management role in that tenant.
     *
     * Note: Currently uses organization-level roles. Future enhancement will use
     * per-tenant roles from the tenant_user.role column.
     */
    public function isTenantOwnerOf(User $target): bool
    {
        // Super admins own everything
        if ($this->is_super_admin) {
            return true;
        }

        // Must be in same organization
        if ($this->organization_id !== $target->organization_id) {
            return false;
        }

        // Organization owners and admins are considered tenant owners
        if ($this->isOwner() || $this->isAdmin()) {
            return true;
        }

        // Future: Check tenant_user.role column for per-tenant ownership
        // Example: $this->tenants()->wherePivot('role', 'owner')->exists()

        return false;
    }

    /**
     * Check if current user is an organization owner of the target user.
     */
    public function isOrgOwnerOf(User $target): bool
    {
        // Super admins can manage all organizations
        if ($this->is_super_admin) {
            return true;
        }

        // Must be in same organization and be an owner
        return $this->organization_id === $target->organization_id && $this->isOwner();
    }

    /**
     * Get the role of this user within a specific tenant.
     *
     * Note: Currently returns organization-level role. Future enhancement will
     * return per-tenant role from tenant_user.role column if set.
     */
    public function getTenantRole(Tenant $tenant): ?string
    {
        // Check if user has access to this tenant
        if (!$this->hasAccessToTenant($tenant)) {
            return null;
        }

        // Future: Return per-tenant role if set in tenant_user pivot table
        // $pivotRole = $this->tenants()
        //     ->where('tenants.id', $tenant->id)
        //     ->first()?->pivot->role;
        //
        // if ($pivotRole) {
        //     return $pivotRole;
        // }

        // For now, return organization-level role
        return $this->role;
    }

    /**
     * Send the password reset notification.
     *
     * @param  string  $token
     * @return void
     */
    public function sendPasswordResetNotification($token)
    {
        $this->notify(new ResetPasswordNotification($token));
    }
}
