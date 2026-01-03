<?php

declare(strict_types=1);

namespace App\ValueObjects;

use InvalidArgumentException;
use JsonSerializable;

/**
 * Usage statistics value object
 *
 * Represents current resource usage for a tenant.
 */
final class UsageStats implements JsonSerializable
{
    /**
     * Create a new UsageStats instance
     *
     * @param int $siteCount Number of sites
     * @param int $storageUsedMb Storage used in megabytes
     * @param int $backupCount Total number of backups
     * @param int $teamMemberCount Number of team members
     * @throws InvalidArgumentException If any value is negative
     */
    public function __construct(
        public readonly int $siteCount,
        public readonly int $storageUsedMb,
        public readonly int $backupCount,
        public readonly int $teamMemberCount
    ) {
        $this->validate();
    }

    /**
     * Validate usage statistics
     *
     * @throws InvalidArgumentException If any value is negative
     */
    private function validate(): void
    {
        if ($this->siteCount < 0) {
            throw new InvalidArgumentException('Site count cannot be negative');
        }

        if ($this->storageUsedMb < 0) {
            throw new InvalidArgumentException('Storage used cannot be negative');
        }

        if ($this->backupCount < 0) {
            throw new InvalidArgumentException('Backup count cannot be negative');
        }

        if ($this->teamMemberCount < 0) {
            throw new InvalidArgumentException('Team member count cannot be negative');
        }
    }

    /**
     * Create empty usage stats
     *
     * @return self
     */
    public static function empty(): self
    {
        return new self(
            siteCount: 0,
            storageUsedMb: 0,
            backupCount: 0,
            teamMemberCount: 1
        );
    }

    /**
     * Create usage stats for a tenant
     *
     * This would typically fetch from database in a real implementation
     *
     * @param string $tenantId
     * @return self
     */
    public static function forTenant(string $tenantId): self
    {
        return self::empty();
    }

    /**
     * Get storage used in gigabytes
     *
     * @return float
     */
    public function getStorageUsedGb(): float
    {
        return $this->storageUsedMb / 1024;
    }

    /**
     * Get usage percentage against quota limits
     *
     * @param QuotaLimits $limits
     * @return array<string, float>
     */
    public function getUsagePercentage(QuotaLimits $limits): array
    {
        return $limits->getUsagePercentage($this);
    }

    /**
     * Check if usage is within limits
     *
     * @param QuotaLimits $limits
     * @return bool
     */
    public function isWithinLimits(QuotaLimits $limits): bool
    {
        if (!$limits->allowsUnlimitedSites() && $this->siteCount > $limits->maxSites) {
            return false;
        }

        if (!$limits->allowsUnlimitedStorage() && $this->storageUsedMb > $limits->maxStorageMb) {
            return false;
        }

        if (!$limits->allowsUnlimitedTeamMembers() && $this->teamMemberCount > $limits->maxTeamMembers) {
            return false;
        }

        return true;
    }

    /**
     * Get overages compared to quota limits
     *
     * @param QuotaLimits $limits
     * @return array<string, int>
     */
    public function getOverages(QuotaLimits $limits): array
    {
        $overages = [];

        if (!$limits->allowsUnlimitedSites() && $this->siteCount > $limits->maxSites) {
            $overages['sites'] = $this->siteCount - $limits->maxSites;
        }

        if (!$limits->allowsUnlimitedStorage() && $this->storageUsedMb > $limits->maxStorageMb) {
            $overages['storage_mb'] = $this->storageUsedMb - $limits->maxStorageMb;
        }

        if (!$limits->allowsUnlimitedTeamMembers() && $this->teamMemberCount > $limits->maxTeamMembers) {
            $overages['team_members'] = $this->teamMemberCount - $limits->maxTeamMembers;
        }

        return $overages;
    }

    /**
     * Check if there are any overages
     *
     * @param QuotaLimits $limits
     * @return bool
     */
    public function hasOverages(QuotaLimits $limits): bool
    {
        return !empty($this->getOverages($limits));
    }

    /**
     * Create a new instance with updated site count
     *
     * @param int $siteCount
     * @return self
     */
    public function withSiteCount(int $siteCount): self
    {
        return new self(
            siteCount: $siteCount,
            storageUsedMb: $this->storageUsedMb,
            backupCount: $this->backupCount,
            teamMemberCount: $this->teamMemberCount
        );
    }

    /**
     * Create a new instance with updated storage
     *
     * @param int $storageUsedMb
     * @return self
     */
    public function withStorageUsed(int $storageUsedMb): self
    {
        return new self(
            siteCount: $this->siteCount,
            storageUsedMb: $storageUsedMb,
            backupCount: $this->backupCount,
            teamMemberCount: $this->teamMemberCount
        );
    }

    /**
     * Create a new instance with updated backup count
     *
     * @param int $backupCount
     * @return self
     */
    public function withBackupCount(int $backupCount): self
    {
        return new self(
            siteCount: $this->siteCount,
            storageUsedMb: $this->storageUsedMb,
            backupCount: $backupCount,
            teamMemberCount: $this->teamMemberCount
        );
    }

    /**
     * Create a new instance with updated team member count
     *
     * @param int $teamMemberCount
     * @return self
     */
    public function withTeamMemberCount(int $teamMemberCount): self
    {
        return new self(
            siteCount: $this->siteCount,
            storageUsedMb: $this->storageUsedMb,
            backupCount: $this->backupCount,
            teamMemberCount: $teamMemberCount
        );
    }

    /**
     * Increment site count
     *
     * @return self
     */
    public function incrementSiteCount(): self
    {
        return $this->withSiteCount($this->siteCount + 1);
    }

    /**
     * Decrement site count
     *
     * @return self
     */
    public function decrementSiteCount(): self
    {
        return $this->withSiteCount(max(0, $this->siteCount - 1));
    }

    /**
     * Add storage usage
     *
     * @param int $megabytes
     * @return self
     */
    public function addStorageUsage(int $megabytes): self
    {
        return $this->withStorageUsed($this->storageUsedMb + $megabytes);
    }

    /**
     * Subtract storage usage
     *
     * @param int $megabytes
     * @return self
     */
    public function subtractStorageUsage(int $megabytes): self
    {
        return $this->withStorageUsed(max(0, $this->storageUsedMb - $megabytes));
    }

    /**
     * Check if this usage equals another
     *
     * @param UsageStats $other
     * @return bool
     */
    public function equals(UsageStats $other): bool
    {
        return $this->siteCount === $other->siteCount
            && $this->storageUsedMb === $other->storageUsedMb
            && $this->backupCount === $other->backupCount
            && $this->teamMemberCount === $other->teamMemberCount;
    }

    /**
     * Convert to array
     *
     * @return array<string, mixed>
     */
    public function toArray(): array
    {
        return [
            'site_count' => $this->siteCount,
            'storage_used_mb' => $this->storageUsedMb,
            'storage_used_gb' => $this->getStorageUsedGb(),
            'backup_count' => $this->backupCount,
            'team_member_count' => $this->teamMemberCount,
        ];
    }

    /**
     * Convert to string
     *
     * @return string
     */
    public function __toString(): string
    {
        return sprintf(
            '%d sites, %.2fGB storage, %d backups, %d team members',
            $this->siteCount,
            $this->getStorageUsedGb(),
            $this->backupCount,
            $this->teamMemberCount
        );
    }

    /**
     * Serialize to JSON
     *
     * @return array<string, mixed>
     */
    public function jsonSerialize(): array
    {
        return $this->toArray();
    }
}
