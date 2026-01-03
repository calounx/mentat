<?php

declare(strict_types=1);

namespace App\Modules\Backup\ValueObjects;

/**
 * Backup Configuration Value Object
 *
 * Encapsulates backup configuration settings.
 */
final readonly class BackupConfiguration
{
    private const ALLOWED_TYPES = ['full', 'files', 'database'];
    private const MIN_RETENTION_DAYS = 1;
    private const MAX_RETENTION_DAYS = 365;

    public function __construct(
        private string $type,
        private int $retentionDays,
        private bool $compressed = true,
        private bool $encrypted = false
    ) {
        $this->validate();
    }

    /**
     * Create default full backup configuration.
     *
     * @param int $retentionDays Retention period in days
     * @return self
     */
    public static function full(int $retentionDays = 30): self
    {
        return new self('full', $retentionDays);
    }

    /**
     * Create files-only backup configuration.
     *
     * @param int $retentionDays Retention period in days
     * @return self
     */
    public static function filesOnly(int $retentionDays = 30): self
    {
        return new self('files', $retentionDays);
    }

    /**
     * Create database-only backup configuration.
     *
     * @param int $retentionDays Retention period in days
     * @return self
     */
    public static function databaseOnly(int $retentionDays = 30): self
    {
        return new self('database', $retentionDays);
    }

    /**
     * Get backup type.
     *
     * @return string
     */
    public function getType(): string
    {
        return $this->type;
    }

    /**
     * Get retention period in days.
     *
     * @return int
     */
    public function getRetentionDays(): int
    {
        return $this->retentionDays;
    }

    /**
     * Check if backup should be compressed.
     *
     * @return bool
     */
    public function isCompressed(): bool
    {
        return $this->compressed;
    }

    /**
     * Check if backup should be encrypted.
     *
     * @return bool
     */
    public function isEncrypted(): bool
    {
        return $this->encrypted;
    }

    /**
     * Create with encryption enabled.
     *
     * @return self
     */
    public function withEncryption(): self
    {
        return new self($this->type, $this->retentionDays, $this->compressed, true);
    }

    /**
     * Create without compression.
     *
     * @return self
     */
    public function withoutCompression(): self
    {
        return new self($this->type, $this->retentionDays, false, $this->encrypted);
    }

    /**
     * Validate configuration.
     *
     * @return void
     * @throws \InvalidArgumentException
     */
    private function validate(): void
    {
        if (!in_array($this->type, self::ALLOWED_TYPES, true)) {
            throw new \InvalidArgumentException(
                sprintf(
                    'Invalid backup type: %s. Allowed types: %s',
                    $this->type,
                    implode(', ', self::ALLOWED_TYPES)
                )
            );
        }

        if ($this->retentionDays < self::MIN_RETENTION_DAYS) {
            throw new \InvalidArgumentException(
                sprintf(
                    'Retention period must be at least %d day(s)',
                    self::MIN_RETENTION_DAYS
                )
            );
        }

        if ($this->retentionDays > self::MAX_RETENTION_DAYS) {
            throw new \InvalidArgumentException(
                sprintf(
                    'Retention period cannot exceed %d days',
                    self::MAX_RETENTION_DAYS
                )
            );
        }
    }

    /**
     * Convert to array.
     *
     * @return array
     */
    public function toArray(): array
    {
        return [
            'type' => $this->type,
            'retention_days' => $this->retentionDays,
            'compressed' => $this->compressed,
            'encrypted' => $this->encrypted,
        ];
    }
}
