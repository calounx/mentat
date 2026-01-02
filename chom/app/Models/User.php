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
    use HasApiTokens, HasFactory, HasUuids, Notifiable;

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
        if (! $this->organization) {
            return null;
        }

        // Load the relationship if not already loaded
        if (! $this->organization->relationLoaded('defaultTenant')) {
            $this->organization->load('defaultTenant');
        }

        return $this->organization->defaultTenant;
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
        if (! config('auth.two_factor_authentication.enabled', false)) {
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
        if (! $this->requires2FA()) {
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
        if (! $this->password_confirmed_at) {
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
        if (! $this->ssh_key_rotated_at) {
            return true;
        }

        return $this->ssh_key_rotated_at->addDays(90)->isPast();
    }

    /**
     * SECURITY: Enable two-factor authentication for this user.
     *
     * Generates a new 2FA secret using Google2FA.
     * Secret is encrypted at rest via model cast.
     * Does not confirm 2FA - user must verify with code first.
     *
     * @return array Contains 'secret' and 'qr_code'
     */
    public function enableTwoFactorAuthentication(): array
    {
        $google2fa = new \PragmaRX\Google2FA\Google2FA;

        // Generate cryptographically secure secret (160-bit)
        $secret = $google2fa->generateSecretKey(32);

        // Generate QR code URL for authenticator apps
        $qrCodeUrl = $google2fa->getQRCodeUrl(
            config('app.name'),
            $this->email,
            $secret
        );

        // Generate SVG QR code
        $qrCode = $this->generateQrCodeSvg($qrCodeUrl);

        // Generate recovery codes (8 codes, 10 characters each)
        $recoveryCodes = $this->generateRecoveryCodes();

        // Store secret (but don't enable yet - wait for confirmation)
        $this->two_factor_secret = $secret;
        $this->two_factor_backup_codes = array_map(
            fn($code) => \Illuminate\Support\Facades\Hash::make($code),
            $recoveryCodes
        );
        $this->save();

        return [
            'secret' => $secret,
            'qr_code' => $qrCode,
            'recovery_codes' => $recoveryCodes, // Plain text - show only once!
        ];
    }

    /**
     * SECURITY: Confirm two-factor authentication setup.
     *
     * Called after user successfully verifies their first TOTP code.
     * Marks 2FA as enabled and confirmed.
     */
    public function confirmTwoFactorAuthentication(): void
    {
        $this->update([
            'two_factor_enabled' => true,
            'two_factor_confirmed_at' => now(),
        ]);
    }

    /**
     * SECURITY: Disable two-factor authentication.
     *
     * Clears all 2FA data from user account.
     * Should only be called after password confirmation.
     */
    public function disableTwoFactorAuthentication(): void
    {
        $this->update([
            'two_factor_enabled' => false,
            'two_factor_secret' => null,
            'two_factor_backup_codes' => null,
            'two_factor_confirmed_at' => null,
        ]);
    }

    /**
     * SECURITY: Generate new recovery codes.
     *
     * Returns plain text codes - must be shown to user immediately.
     * Codes are hashed before storage.
     *
     * @return array Plain text recovery codes
     */
    public function generateRecoveryCodes(int $count = 8): array
    {
        $codes = [];
        for ($i = 0; $i < $count; $i++) {
            // Generate 10-character alphanumeric code
            $codes[] = strtoupper(\Illuminate\Support\Str::random(10));
        }

        // Hash and store the codes
        $hashedCodes = array_map(
            fn($code) => \Illuminate\Support\Facades\Hash::make($code),
            $codes
        );

        $this->update(['two_factor_backup_codes' => $hashedCodes]);

        return $codes; // Return plain text for user
    }

    /**
     * SECURITY: Verify a TOTP or recovery code.
     *
     * @param string $code TOTP code (6 digits) or recovery code (10 chars)
     * @return bool True if code is valid
     */
    public function verifyTwoFactorCode(string $code): bool
    {
        if (! $this->two_factor_enabled || ! $this->two_factor_secret) {
            return false;
        }

        $google2fa = new \PragmaRX\Google2FA\Google2FA;

        // Try TOTP code first (6 digits)
        if (strlen($code) === 6 && ctype_digit($code)) {
            return $google2fa->verifyKey($this->two_factor_secret, $code, 1);
        }

        // Try recovery codes (10 characters)
        if (strlen($code) === 10) {
            $backupCodes = $this->two_factor_backup_codes ?? [];

            foreach ($backupCodes as $index => $hashedCode) {
                if (\Illuminate\Support\Facades\Hash::check($code, $hashedCode)) {
                    // Remove used recovery code (single-use)
                    unset($backupCodes[$index]);
                    $this->update(['two_factor_backup_codes' => array_values($backupCodes)]);
                    return true;
                }
            }
        }

        return false;
    }

    /**
     * Generate SVG QR code for 2FA setup.
     */
    protected function generateQrCodeSvg(string $url): string
    {
        $renderer = new \BaconQrCode\Renderer\ImageRenderer(
            new \BaconQrCode\Renderer\RendererStyle\RendererStyle(200),
            new \BaconQrCode\Renderer\Image\SvgImageBackEnd
        );

        $writer = new \BaconQrCode\Writer($renderer);

        return $writer->writeString($url);
    }
}
