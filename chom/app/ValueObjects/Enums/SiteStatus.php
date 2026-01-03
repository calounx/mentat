<?php

declare(strict_types=1);

namespace App\ValueObjects\Enums;

/**
 * Site status enumeration
 *
 * Defines the available site statuses.
 */
enum SiteStatus: string
{
    case PENDING = 'pending';
    case PROVISIONING = 'provisioning';
    case ACTIVE = 'active';
    case SUSPENDED = 'suspended';
    case MAINTENANCE = 'maintenance';
    case FAILED = 'failed';
    case DELETING = 'deleting';
    case DELETED = 'deleted';

    /**
     * Get a human-readable label for the status
     */
    public function label(): string
    {
        return match ($this) {
            self::PENDING => 'Pending',
            self::PROVISIONING => 'Provisioning',
            self::ACTIVE => 'Active',
            self::SUSPENDED => 'Suspended',
            self::MAINTENANCE => 'Maintenance Mode',
            self::FAILED => 'Failed',
            self::DELETING => 'Deleting',
            self::DELETED => 'Deleted',
        };
    }

    /**
     * Get the description of the status
     */
    public function description(): string
    {
        return match ($this) {
            self::PENDING => 'Site is queued for provisioning',
            self::PROVISIONING => 'Site is being set up',
            self::ACTIVE => 'Site is active and accessible',
            self::SUSPENDED => 'Site is suspended and not accessible',
            self::MAINTENANCE => 'Site is in maintenance mode',
            self::FAILED => 'Site provisioning or operation failed',
            self::DELETING => 'Site is being deleted',
            self::DELETED => 'Site has been deleted',
        };
    }

    /**
     * Check if the site is accessible
     */
    public function isAccessible(): bool
    {
        return match ($this) {
            self::ACTIVE, self::MAINTENANCE => true,
            self::PENDING, self::PROVISIONING, self::SUSPENDED, self::FAILED, self::DELETING, self::DELETED => false,
        };
    }

    /**
     * Check if the site can be modified
     */
    public function isModifiable(): bool
    {
        return match ($this) {
            self::ACTIVE, self::MAINTENANCE, self::SUSPENDED => true,
            self::PENDING, self::PROVISIONING, self::FAILED, self::DELETING, self::DELETED => false,
        };
    }

    /**
     * Check if the site is in a transitional state
     */
    public function isTransitional(): bool
    {
        return match ($this) {
            self::PENDING, self::PROVISIONING, self::DELETING => true,
            self::ACTIVE, self::SUSPENDED, self::MAINTENANCE, self::FAILED, self::DELETED => false,
        };
    }

    /**
     * Check if the site is in a terminal state
     */
    public function isTerminal(): bool
    {
        return match ($this) {
            self::DELETED, self::FAILED => true,
            self::PENDING, self::PROVISIONING, self::ACTIVE, self::SUSPENDED, self::MAINTENANCE, self::DELETING => false,
        };
    }

    /**
     * Get the badge color for UI display
     */
    public function badgeColor(): string
    {
        return match ($this) {
            self::ACTIVE => 'green',
            self::PENDING, self::PROVISIONING => 'blue',
            self::SUSPENDED, self::MAINTENANCE => 'yellow',
            self::FAILED => 'red',
            self::DELETING, self::DELETED => 'gray',
        };
    }
}
