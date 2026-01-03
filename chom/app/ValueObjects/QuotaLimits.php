<?php

declare(strict_types=1);

namespace App\ValueObjects;

use InvalidArgumentException;
use JsonSerializable;

/**
 * Quota limits value object
 *
 * Represents subscription tier limits for resources and features.
 */
final class QuotaLimits implements JsonSerializable
{
    private const UNLIMITED = -1;

    /**
     * Create a new QuotaLimits instance
     *
     * @param int $maxSites Maximum number of sites (-1 for unlimited)
     * @param int $maxStorageMb Maximum storage in MB (-1 for unlimited)
     * @param int $maxBackupsPerSite Maximum backups per site
     * @param int $maxTeamMembers Maximum team members (-1 for unlimited)
     * @param bool $sslIncluded Whether SSL certificates are included
     * @param bool $automaticBackups Whether automatic backups are enabled
     * @throws InvalidArgumentException If limits are invalid
     */
    public function __construct(
        public readonly int $maxSites,
        public readonly int $maxStorageMb,
        public readonly int $maxBackupsPerSite,
        public readonly int $maxTeamMembers,
        public readonly bool $sslIncluded,
        public readonly bool $automaticBackups
    ) {
        $this->validate();
    }

    /**
     * Validate limits
     *
     * @throws InvalidArgumentException If limits are invalid
     */
    private function validate(): void
    {
        if ($this->maxSites < self::UNLIMITED || $this->maxSites === 0) {
            throw new InvalidArgumentException('Max sites must be -1 (unlimited) or positive');
        }

        if ($this->maxStorageMb < self::UNLIMITED || $this->maxStorageMb === 0) {
            throw new InvalidArgumentException('Max storage must be -1 (unlimited) or positive');
        }

        if ($this->maxBackupsPerSite < 0) {
            throw new InvalidArgumentException('Max backups per site must be non-negative');
        }

        if ($this->maxTeamMembers < self::UNLIMITED || $this->maxTeamMembers === 0) {
            throw new InvalidArgumentException('Max team members must be -1 (unlimited) or positive');
        }
    }

    /**
     * Create free tier limits
     *
     * @return self
     */
    public static function free(): self
    {
        return new self(
            maxSites: 1,
            maxStorageMb: 1024,
            maxBackupsPerSite: 3,
            maxTeamMembers: 1,
            sslIncluded: true,
            automaticBackups: false
        );
    }

    /**
     * Create starter tier limits
     *
     * @return self
     */
    public static function starter(): self
    {
        return new self(
            maxSites: 3,
            maxStorageMb: 10240,
            maxBackupsPerSite: 10,
            maxTeamMembers: 3,
            sslIncluded: true,
            automaticBackups: true
        );
    }

    /**
     * Create professional tier limits
     *
     * @return self
     */
    public static function professional(): self
    {
        return new self(
            maxSites: 10,
            maxStorageMb: 51200,
            maxBackupsPerSite: 30,
            maxTeamMembers: 10,
            sslIncluded: true,
            automaticBackups: true
        );
    }

    /**
     * Create enterprise tier limits
     *
     * @return self
     */
    public static function enterprise(): self
    {
        return new self(
            maxSites: self::UNLIMITED,
            maxStorageMb: self::UNLIMITED,
            maxBackupsPerSite: 90,
            maxTeamMembers: self::UNLIMITED,
            sslIncluded: true,
            automaticBackups: true
        );
    }

    /**
     * Check if unlimited sites are allowed
     *
     * @return bool
     */
    public function allowsUnlimitedSites(): bool
    {
        return $this->maxSites === self::UNLIMITED;
    }

    /**
     * Check if unlimited storage is allowed
     *
     * @return bool
     */
    public function allowsUnlimitedStorage(): bool
    {
        return $this->maxStorageMb === self::UNLIMITED;
    }

    /**
     * Check if unlimited team members are allowed
     *
     * @return bool
     */
    public function allowsUnlimitedTeamMembers(): bool
    {
        return $this->maxTeamMembers === self::UNLIMITED;
    }

    /**
     * Check if a new site can be created
     *
     * @param int $currentCount Current number of sites
     * @return bool
     */
    public function canCreateSite(int $currentCount): bool
    {
        if ($this->allowsUnlimitedSites()) {
            return true;
        }

        return $currentCount < $this->maxSites;
    }

    /**
     * Check if storage can be used
     *
     * @param int $currentUsageMb Current storage usage in MB
     * @return bool
     */
    public function canUseStorage(int $currentUsageMb): bool
    {
        if ($this->allowsUnlimitedStorage()) {
            return true;
        }

        return $currentUsageMb < $this->maxStorageMb;
    }

    /**
     * Check if a new backup can be created
     *
     * @param int $currentCount Current number of backups for the site
     * @return bool
     */
    public function canCreateBackup(int $currentCount): bool
    {
        return $currentCount < $this->maxBackupsPerSite;
    }

    /**
     * Check if a new team member can be invited
     *
     * @param int $currentCount Current number of team members
     * @return bool
     */
    public function canInviteMember(int $currentCount): bool
    {
        if ($this->allowsUnlimitedTeamMembers()) {
            return true;
        }

        return $currentCount < $this->maxTeamMembers;
    }

    /**
     * Get usage percentage for various metrics
     *
     * @param UsageStats $usage Current usage statistics
     * @return array<string, float>
     */
    public function getUsagePercentage(UsageStats $usage): array
    {
        return [
            'sites' => $this->calculatePercentage($usage->siteCount, $this->maxSites),
            'storage' => $this->calculatePercentage($usage->storageUsedMb, $this->maxStorageMb),
            'team_members' => $this->calculatePercentage($usage->teamMemberCount, $this->maxTeamMembers),
        ];
    }

    /**
     * Calculate percentage of usage
     *
     * @param int $current Current usage
     * @param int $max Maximum allowed
     * @return float Percentage (0-100), or 0 if unlimited
     */
    private function calculatePercentage(int $current, int $max): float
    {
        if ($max === self::UNLIMITED) {
            return 0.0;
        }

        if ($max === 0) {
            return 100.0;
        }

        return min(100.0, ($current / $max) * 100);
    }

    /**
     * Get remaining capacity
     *
     * @param UsageStats $usage Current usage statistics
     * @return array<string, int|string>
     */
    public function getRemainingCapacity(UsageStats $usage): array
    {
        return [
            'sites' => $this->allowsUnlimitedSites() ? 'unlimited' : max(0, $this->maxSites - $usage->siteCount),
            'storage_mb' => $this->allowsUnlimitedStorage() ? 'unlimited' : max(0, $this->maxStorageMb - $usage->storageUsedMb),
            'team_members' => $this->allowsUnlimitedTeamMembers() ? 'unlimited' : max(0, $this->maxTeamMembers - $usage->teamMemberCount),
        ];
    }

    /**
     * Check if this quota equals another
     *
     * @param QuotaLimits $other
     * @return bool
     */
    public function equals(QuotaLimits $other): bool
    {
        return $this->maxSites === $other->maxSites
            && $this->maxStorageMb === $other->maxStorageMb
            && $this->maxBackupsPerSite === $other->maxBackupsPerSite
            && $this->maxTeamMembers === $other->maxTeamMembers
            && $this->sslIncluded === $other->sslIncluded
            && $this->automaticBackups === $other->automaticBackups;
    }

    /**
     * Check if this quota is more permissive than another
     *
     * @param QuotaLimits $other
     * @return bool
     */
    public function isMorePermissiveThan(QuotaLimits $other): bool
    {
        return $this->isAtLeast($this->maxSites, $other->maxSites)
            && $this->isAtLeast($this->maxStorageMb, $other->maxStorageMb)
            && $this->maxBackupsPerSite >= $other->maxBackupsPerSite
            && $this->isAtLeast($this->maxTeamMembers, $other->maxTeamMembers);
    }

    /**
     * Check if a value is at least the minimum (considering unlimited)
     *
     * @param int $value
     * @param int $minimum
     * @return bool
     */
    private function isAtLeast(int $value, int $minimum): bool
    {
        if ($value === self::UNLIMITED) {
            return true;
        }

        if ($minimum === self::UNLIMITED) {
            return false;
        }

        return $value >= $minimum;
    }

    /**
     * Convert to array
     *
     * @return array<string, mixed>
     */
    public function toArray(): array
    {
        return [
            'max_sites' => $this->maxSites,
            'max_storage_mb' => $this->maxStorageMb,
            'max_storage_gb' => $this->allowsUnlimitedStorage() ? -1 : (int)($this->maxStorageMb / 1024),
            'max_backups_per_site' => $this->maxBackupsPerSite,
            'max_team_members' => $this->maxTeamMembers,
            'ssl_included' => $this->sslIncluded,
            'automatic_backups' => $this->automaticBackups,
        ];
    }

    /**
     * Convert to string
     *
     * @return string
     */
    public function __toString(): string
    {
        $sites = $this->allowsUnlimitedSites() ? 'unlimited' : $this->maxSites;
        $storage = $this->allowsUnlimitedStorage() ? 'unlimited' : (int)($this->maxStorageMb / 1024) . 'GB';

        return sprintf('%s sites, %s storage', $sites, $storage);
    }

    /**
     * Serialize to JSON
     *
     * @return array<string, mixed>
     */
    public function jsonSerialize(): array
    {
        return array_merge($this->toArray(), [
            'allows_unlimited_sites' => $this->allowsUnlimitedSites(),
            'allows_unlimited_storage' => $this->allowsUnlimitedStorage(),
            'allows_unlimited_team_members' => $this->allowsUnlimitedTeamMembers(),
        ]);
    }
}
