<?php

namespace App\Models;

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
        'name',
        'email',
        'password',
        'organization_id',
        'role',
        'is_super_admin',
        'two_factor_enabled',
        'two_factor_secret',
        'settings',
        'must_reset_password',
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
}
