<?php

declare(strict_types=1);

namespace App\ValueObjects\Enums;

/**
 * Backup type enumeration
 *
 * Defines the available backup types for sites.
 */
enum BackupType: string
{
    case FULL = 'full';
    case FILES = 'files';
    case DATABASE = 'database';
    case CONFIG = 'config';
    case MANUAL = 'manual';

    /**
     * Get a human-readable label for the backup type
     */
    public function label(): string
    {
        return match ($this) {
            self::FULL => 'Full Backup',
            self::FILES => 'Files Only',
            self::DATABASE => 'Database Only',
            self::CONFIG => 'Configuration Only',
            self::MANUAL => 'Manual Backup',
        };
    }

    /**
     * Get the description of what is included in this backup type
     */
    public function description(): string
    {
        return match ($this) {
            self::FULL => 'Complete backup including files, database, and configuration',
            self::FILES => 'Website files and uploads only',
            self::DATABASE => 'Database content only',
            self::CONFIG => 'Configuration files and settings only',
            self::MANUAL => 'User-initiated manual backup',
        };
    }

    /**
     * Get the relative backup size factor (1.0 = full backup size)
     */
    public function sizeFactor(): float
    {
        return match ($this) {
            self::FULL => 1.0,
            self::FILES => 0.7,
            self::DATABASE => 0.2,
            self::CONFIG => 0.01,
            self::MANUAL => 1.0,
        };
    }

    /**
     * Check if this backup type includes files
     */
    public function includesFiles(): bool
    {
        return match ($this) {
            self::FULL, self::FILES, self::MANUAL => true,
            self::DATABASE, self::CONFIG => false,
        };
    }

    /**
     * Check if this backup type includes database
     */
    public function includesDatabase(): bool
    {
        return match ($this) {
            self::FULL, self::DATABASE, self::MANUAL => true,
            self::FILES, self::CONFIG => false,
        };
    }

    /**
     * Check if this backup type includes configuration
     */
    public function includesConfig(): bool
    {
        return match ($this) {
            self::FULL, self::CONFIG, self::MANUAL => true,
            self::FILES, self::DATABASE => false,
        };
    }
}
