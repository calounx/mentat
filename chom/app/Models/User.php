<?php

namespace App\Models;

use Illuminate\Contracts\Auth\MustVerifyEmail;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
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
        'two_factor_enabled',
        'two_factor_secret',
        'two_factor_backup_codes',
        'two_factor_confirmed_at',
        'password_confirmed_at',
        'ssh_key_rotated_at',
    ];

    protected $hidden = [
        'password',
        'remember_token',
        'two_factor_secret',
        'two_factor_backup_codes',
    ];

    /**
     * SECURITY: Cast configuration including encrypted fields.
     *
     * two_factor_secret: Encrypted to protect 2FA recovery
     * - Uses Laravel's encrypted cast (AES-256-CBC + HMAC-SHA-256)
     * - Prevents unauthorized 2FA bypass if database compromised
     *
     * OWASP Reference: A02:2021 – Cryptographic Failures
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'two_factor_enabled' => 'boolean',
            'two_factor_secret' => 'encrypted',  // SECURITY: Encrypt 2FA secrets at rest
            'two_factor_backup_codes' => 'encrypted:array',  // SECURITY: Encrypt backup codes
            'two_factor_confirmed_at' => 'datetime',
            'password_confirmed_at' => 'datetime',
            'ssh_key_rotated_at' => 'datetime',
        ];
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
     * Get all operations initiated by this user.
     */
    public function operations(): HasMany
    {
        return $this->hasMany(Operation::class);
    }

    /**
     * SECURITY: Check if 2FA is required for this user's role.
     *
     * OWASP Reference: A07:2021 – Identification and Authentication Failures
     * Two-factor authentication MUST be enforced for privileged accounts.
     *
     * Configuration-based: Checks config('auth.two_factor_authentication')
     * to determine which roles require 2FA.
     */
    public function requires2FA(): bool
    {
        // Check if 2FA is globally enabled
        if (!config('auth.two_factor_authentication.enabled', false)) {
            return false;
        }

        // Get roles that require 2FA from configuration
        $requiredRoles = config('auth.two_factor_authentication.required_for_roles', []);

        return in_array($this->role, $requiredRoles);
    }

    /**
     * SECURITY: Check if user is within 2FA setup grace period.
     *
     * Grace period: Configurable days from account creation
     * After grace period, 2FA is mandatory for configured roles.
     *
     * Configuration-based: Uses config('auth.two_factor_authentication.grace_period_days')
     */
    public function isIn2FAGracePeriod(): bool
    {
        if (!$this->requires2FA()) {
            return false;
        }

        $gracePeriodDays = config('auth.two_factor_authentication.grace_period_days', 7);

        return $this->created_at->addDays($gracePeriodDays)->isFuture();
    }

    /**
     * SECURITY: Check if password confirmation is still valid.
     *
     * Password confirmation expires after 10 minutes.
     * Used for step-up authentication on sensitive operations.
     */
    public function hasRecentPasswordConfirmation(): bool
    {
        if (!$this->password_confirmed_at) {
            return false;
        }

        return $this->password_confirmed_at->addMinutes(10)->isFuture();
    }

    /**
     * SECURITY: Record password confirmation timestamp.
     */
    public function confirmPassword(): void
    {
        $this->update(['password_confirmed_at' => now()]);
    }

    /**
     * SECURITY: Check if SSH keys need rotation.
     *
     * Keys should be rotated every 90 days per security policy.
     * OWASP Reference: A02:2021 – Cryptographic Failures
     */
    public function needsKeyRotation(): bool
    {
        if (!$this->ssh_key_rotated_at) {
            return true;
        }

        return $this->ssh_key_rotated_at->addDays(90)->isPast();
    }
}
