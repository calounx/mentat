<?php

declare(strict_types=1);

namespace App\Modules\Backup\ValueObjects;

/**
 * Retention Policy Value Object
 *
 * Encapsulates backup retention policy rules.
 */
final readonly class RetentionPolicy
{
    public function __construct(
        private int $maxBackups,
        private int $maxAgeDays,
        private bool $keepMinimumOne = true
    ) {
        $this->validate();
    }

    /**
     * Create default retention policy.
     *
     * @return self
     */
    public static function default(): self
    {
        return new self(
            maxBackups: 10,
            maxAgeDays: 30,
            keepMinimumOne: true
        );
    }

    /**
     * Create aggressive cleanup policy.
     *
     * @return self
     */
    public static function aggressive(): self
    {
        return new self(
            maxBackups: 5,
            maxAgeDays: 7,
            keepMinimumOne: true
        );
    }

    /**
     * Create conservative retention policy.
     *
     * @return self
     */
    public static function conservative(): self
    {
        return new self(
            maxBackups: 30,
            maxAgeDays: 90,
            keepMinimumOne: true
        );
    }

    /**
     * Create compliance-oriented policy (long retention).
     *
     * @return self
     */
    public static function compliance(): self
    {
        return new self(
            maxBackups: 100,
            maxAgeDays: 365,
            keepMinimumOne: true
        );
    }

    /**
     * Get maximum number of backups to retain.
     *
     * @return int
     */
    public function getMaxBackups(): int
    {
        return $this->maxBackups;
    }

    /**
     * Get maximum age in days.
     *
     * @return int
     */
    public function getMaxAgeDays(): int
    {
        return $this->maxAgeDays;
    }

    /**
     * Check if at least one backup should always be kept.
     *
     * @return bool
     */
    public function shouldKeepMinimumOne(): bool
    {
        return $this->keepMinimumOne;
    }

    /**
     * Check if a backup should be deleted based on age.
     *
     * @param \DateTime $backupDate Backup creation date
     * @return bool Should delete
     */
    public function shouldDeleteByAge(\DateTime $backupDate): bool
    {
        $now = new \DateTime();
        $daysDiff = $now->diff($backupDate)->days;

        return $daysDiff > $this->maxAgeDays;
    }

    /**
     * Validate policy configuration.
     *
     * @return void
     * @throws \InvalidArgumentException
     */
    private function validate(): void
    {
        if ($this->maxBackups < 1) {
            throw new \InvalidArgumentException('Maximum backups must be at least 1');
        }

        if ($this->maxAgeDays < 1) {
            throw new \InvalidArgumentException('Maximum age must be at least 1 day');
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
            'max_backups' => $this->maxBackups,
            'max_age_days' => $this->maxAgeDays,
            'keep_minimum_one' => $this->keepMinimumOne,
        ];
    }
}
