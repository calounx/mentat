<?php

declare(strict_types=1);

namespace App\ValueObjects\Enums;

/**
 * SSL certificate provider enumeration
 *
 * Defines the available SSL certificate providers.
 */
enum SslProvider: string
{
    case LETS_ENCRYPT = 'letsencrypt';
    case CUSTOM = 'custom';
    case CLOUDFLARE = 'cloudflare';

    /**
     * Get a human-readable label for the SSL provider
     */
    public function label(): string
    {
        return match ($this) {
            self::LETS_ENCRYPT => "Let's Encrypt",
            self::CUSTOM => 'Custom Certificate',
            self::CLOUDFLARE => 'Cloudflare',
        };
    }

    /**
     * Get the description of the SSL provider
     */
    public function description(): string
    {
        return match ($this) {
            self::LETS_ENCRYPT => 'Free automated SSL certificates from Let\'s Encrypt',
            self::CUSTOM => 'User-provided SSL certificate',
            self::CLOUDFLARE => 'SSL certificate managed by Cloudflare',
        };
    }

    /**
     * Check if the provider supports automatic renewal
     */
    public function supportsAutoRenewal(): bool
    {
        return match ($this) {
            self::LETS_ENCRYPT, self::CLOUDFLARE => true,
            self::CUSTOM => false,
        };
    }

    /**
     * Get the typical certificate validity period in days
     */
    public function validityPeriodDays(): int
    {
        return match ($this) {
            self::LETS_ENCRYPT => 90,
            self::CLOUDFLARE => 90,
            self::CUSTOM => 365,
        };
    }

    /**
     * Check if the provider is free
     */
    public function isFree(): bool
    {
        return match ($this) {
            self::LETS_ENCRYPT => true,
            self::CLOUDFLARE, self::CUSTOM => false,
        };
    }
}
