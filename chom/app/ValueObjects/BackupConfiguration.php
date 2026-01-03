<?php

declare(strict_types=1);

namespace App\ValueObjects;

use App\ValueObjects\Enums\BackupSchedule;
use App\ValueObjects\Enums\BackupType;
use DateTimeImmutable;
use InvalidArgumentException;
use JsonSerializable;

/**
 * Backup configuration value object
 *
 * Encapsulates backup configuration with validation.
 */
final class BackupConfiguration implements JsonSerializable
{
    private const MIN_RETENTION_DAYS = 1;
    private const MAX_RETENTION_DAYS = 365;
    private const DEFAULT_COMPRESSION_RATIO = 0.7;
    private const ENCRYPTION_OVERHEAD = 1.05;

    /**
     * Create a new BackupConfiguration instance
     *
     * @param BackupType $type Backup type
     * @param int $retentionDays Number of days to retain backups
     * @param bool $compressed Whether to compress backups
     * @param bool $encrypted Whether to encrypt backups
     * @param BackupSchedule|null $schedule Backup schedule
     * @param array<int, string> $excludePaths Paths to exclude from backup
     * @throws InvalidArgumentException If configuration is invalid
     */
    public function __construct(
        public readonly BackupType $type,
        public readonly int $retentionDays,
        public readonly bool $compressed = true,
        public readonly bool $encrypted = true,
        public readonly ?BackupSchedule $schedule = null,
        public readonly array $excludePaths = []
    ) {
        $this->validate();
    }

    /**
     * Validate the configuration
     *
     * @throws InvalidArgumentException If configuration is invalid
     */
    private function validate(): void
    {
        if ($this->retentionDays < self::MIN_RETENTION_DAYS || $this->retentionDays > self::MAX_RETENTION_DAYS) {
            throw new InvalidArgumentException(
                "Retention days must be between " . self::MIN_RETENTION_DAYS . " and " . self::MAX_RETENTION_DAYS
            );
        }

        foreach ($this->excludePaths as $path) {
            if (!is_string($path) || empty($path)) {
                throw new InvalidArgumentException('Exclude paths must be non-empty strings');
            }
        }
    }

    /**
     * Create a full backup configuration
     *
     * @param int $retentionDays
     * @return self
     */
    public static function fullBackup(int $retentionDays = 30): self
    {
        return new self(
            type: BackupType::FULL,
            retentionDays: $retentionDays,
            compressed: true,
            encrypted: true,
            schedule: BackupSchedule::DAILY
        );
    }

    /**
     * Create a files-only backup configuration
     *
     * @param int $retentionDays
     * @return self
     */
    public static function filesOnly(int $retentionDays = 7): self
    {
        return new self(
            type: BackupType::FILES,
            retentionDays: $retentionDays,
            compressed: true,
            encrypted: false,
            schedule: BackupSchedule::DAILY
        );
    }

    /**
     * Create a database-only backup configuration
     *
     * @param int $retentionDays
     * @return self
     */
    public static function databaseOnly(int $retentionDays = 14): self
    {
        return new self(
            type: BackupType::DATABASE,
            retentionDays: $retentionDays,
            compressed: true,
            encrypted: true,
            schedule: BackupSchedule::HOURLY
        );
    }

    /**
     * Create a configuration-only backup configuration
     *
     * @param int $retentionDays
     * @return self
     */
    public static function configOnly(int $retentionDays = 30): self
    {
        return new self(
            type: BackupType::CONFIG,
            retentionDays: $retentionDays,
            compressed: false,
            encrypted: true,
            schedule: BackupSchedule::DAILY
        );
    }

    /**
     * Create a manual backup configuration
     *
     * @param int $retentionDays
     * @return self
     */
    public static function manual(int $retentionDays = 90): self
    {
        return new self(
            type: BackupType::MANUAL,
            retentionDays: $retentionDays,
            compressed: true,
            encrypted: true,
            schedule: null
        );
    }

    /**
     * Create a new configuration with a schedule
     *
     * @param BackupSchedule $schedule
     * @return self
     */
    public function withSchedule(BackupSchedule $schedule): self
    {
        return new self(
            type: $this->type,
            retentionDays: $this->retentionDays,
            compressed: $this->compressed,
            encrypted: $this->encrypted,
            schedule: $schedule,
            excludePaths: $this->excludePaths
        );
    }

    /**
     * Create a new configuration with exclusions
     *
     * @param array<int, string> $paths
     * @return self
     */
    public function withExclusions(array $paths): self
    {
        return new self(
            type: $this->type,
            retentionDays: $this->retentionDays,
            compressed: $this->compressed,
            encrypted: $this->encrypted,
            schedule: $this->schedule,
            excludePaths: array_merge($this->excludePaths, $paths)
        );
    }

    /**
     * Create a new configuration with different retention
     *
     * @param int $retentionDays
     * @return self
     */
    public function withRetention(int $retentionDays): self
    {
        return new self(
            type: $this->type,
            retentionDays: $retentionDays,
            compressed: $this->compressed,
            encrypted: $this->encrypted,
            schedule: $this->schedule,
            excludePaths: $this->excludePaths
        );
    }

    /**
     * Estimate backup size
     *
     * @param int $siteSize Original site size in bytes
     * @return int Estimated backup size in bytes
     */
    public function estimatedSize(int $siteSize): int
    {
        $size = (int)($siteSize * $this->type->sizeFactor());

        if ($this->compressed) {
            $size = (int)($size * self::DEFAULT_COMPRESSION_RATIO);
        }

        if ($this->encrypted) {
            $size = (int)($size * self::ENCRYPTION_OVERHEAD);
        }

        return $size;
    }

    /**
     * Get the expiration date for backups
     *
     * @return DateTimeImmutable
     */
    public function getExpirationDate(): DateTimeImmutable
    {
        return (new DateTimeImmutable())->modify("+{$this->retentionDays} days");
    }

    /**
     * Check if backup is scheduled
     *
     * @return bool
     */
    public function isScheduled(): bool
    {
        return $this->schedule !== null;
    }

    /**
     * Check if backup is manual
     *
     * @return bool
     */
    public function isManual(): bool
    {
        return $this->type === BackupType::MANUAL;
    }

    /**
     * Get estimated number of backups that will be retained
     *
     * @return int
     */
    public function estimatedBackupCount(): int
    {
        if (!$this->isScheduled()) {
            return 1;
        }

        return $this->schedule->estimatedBackupCount($this->retentionDays);
    }

    /**
     * Get estimated total storage needed
     *
     * @param int $siteSize Original site size in bytes
     * @return int Total estimated storage in bytes
     */
    public function estimatedTotalStorage(int $siteSize): int
    {
        $backupSize = $this->estimatedSize($siteSize);
        return $backupSize * $this->estimatedBackupCount();
    }

    /**
     * Check if this configuration equals another
     *
     * @param BackupConfiguration $other
     * @return bool
     */
    public function equals(BackupConfiguration $other): bool
    {
        return $this->type === $other->type
            && $this->retentionDays === $other->retentionDays
            && $this->compressed === $other->compressed
            && $this->encrypted === $other->encrypted
            && $this->schedule === $other->schedule
            && $this->excludePaths === $other->excludePaths;
    }

    /**
     * Convert to array
     *
     * @return array<string, mixed>
     */
    public function toArray(): array
    {
        return [
            'type' => $this->type->value,
            'retention_days' => $this->retentionDays,
            'compressed' => $this->compressed,
            'encrypted' => $this->encrypted,
            'schedule' => $this->schedule?->value,
            'exclude_paths' => $this->excludePaths,
        ];
    }

    /**
     * Convert to string
     *
     * @return string
     */
    public function __toString(): string
    {
        $schedule = $this->isScheduled() ? $this->schedule->label() : 'Manual';
        return sprintf(
            '%s backup (%s, %d days retention)',
            $this->type->label(),
            $schedule,
            $this->retentionDays
        );
    }

    /**
     * Serialize to JSON
     *
     * @return array<string, mixed>
     */
    public function jsonSerialize(): array
    {
        return array_merge($this->toArray(), [
            'type_label' => $this->type->label(),
            'schedule_label' => $this->schedule?->label(),
            'is_scheduled' => $this->isScheduled(),
            'is_manual' => $this->isManual(),
            'estimated_backup_count' => $this->estimatedBackupCount(),
            'expiration_date' => $this->getExpirationDate()->format('Y-m-d H:i:s'),
        ]);
    }
}
