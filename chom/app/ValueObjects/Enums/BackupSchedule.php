<?php

declare(strict_types=1);

namespace App\ValueObjects\Enums;

/**
 * Backup schedule enumeration
 *
 * Defines the available backup schedule frequencies.
 */
enum BackupSchedule: string
{
    case HOURLY = 'hourly';
    case DAILY = 'daily';
    case WEEKLY = 'weekly';
    case MONTHLY = 'monthly';

    /**
     * Get a human-readable label for the schedule
     */
    public function label(): string
    {
        return match ($this) {
            self::HOURLY => 'Hourly',
            self::DAILY => 'Daily',
            self::WEEKLY => 'Weekly',
            self::MONTHLY => 'Monthly',
        };
    }

    /**
     * Get the description of the schedule
     */
    public function description(): string
    {
        return match ($this) {
            self::HOURLY => 'Every hour',
            self::DAILY => 'Once per day at midnight',
            self::WEEKLY => 'Once per week on Sunday',
            self::MONTHLY => 'Once per month on the 1st',
        };
    }

    /**
     * Get the cron expression for this schedule
     */
    public function cronExpression(): string
    {
        return match ($this) {
            self::HOURLY => '0 * * * *',
            self::DAILY => '0 0 * * *',
            self::WEEKLY => '0 0 * * 0',
            self::MONTHLY => '0 0 1 * *',
        };
    }

    /**
     * Get the interval in hours
     */
    public function intervalHours(): int
    {
        return match ($this) {
            self::HOURLY => 1,
            self::DAILY => 24,
            self::WEEKLY => 168,
            self::MONTHLY => 720,
        };
    }

    /**
     * Get the recommended retention days for this schedule
     */
    public function recommendedRetentionDays(): int
    {
        return match ($this) {
            self::HOURLY => 7,
            self::DAILY => 30,
            self::WEEKLY => 90,
            self::MONTHLY => 365,
        };
    }

    /**
     * Calculate the estimated number of backups per retention period
     */
    public function estimatedBackupCount(int $retentionDays): int
    {
        $backupsPerDay = 24 / $this->intervalHours();
        return (int)ceil($backupsPerDay * $retentionDays);
    }
}
