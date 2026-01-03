<?php

declare(strict_types=1);

namespace App\ValueObjects;

use InvalidArgumentException;
use JsonSerializable;

/**
 * Team role value object
 *
 * Represents a team member's role with hierarchical permissions.
 */
final class TeamRole implements JsonSerializable
{
    private const OWNER = 'owner';
    private const ADMIN = 'admin';
    private const MEMBER = 'member';
    private const VIEWER = 'viewer';

    private const HIERARCHY = [
        self::OWNER => 4,
        self::ADMIN => 3,
        self::MEMBER => 2,
        self::VIEWER => 1,
    ];

    private const PERMISSIONS = [
        self::OWNER => [
            'manage_team',
            'manage_sites',
            'manage_billing',
            'delete_team',
            'invite_members',
            'remove_members',
            'change_roles',
            'view_sites',
            'create_sites',
            'delete_sites',
            'manage_backups',
            'manage_deployments',
            'view_logs',
        ],
        self::ADMIN => [
            'manage_sites',
            'invite_members',
            'remove_members',
            'view_sites',
            'create_sites',
            'delete_sites',
            'manage_backups',
            'manage_deployments',
            'view_logs',
        ],
        self::MEMBER => [
            'view_sites',
            'create_sites',
            'manage_backups',
            'manage_deployments',
            'view_logs',
        ],
        self::VIEWER => [
            'view_sites',
            'view_logs',
        ],
    ];

    /**
     * Create a new TeamRole instance
     *
     * @param string $value The role name
     * @throws InvalidArgumentException If role is invalid
     */
    public function __construct(
        public readonly string $value
    ) {
        $this->validate();
    }

    /**
     * Validate the role
     *
     * @throws InvalidArgumentException If role is invalid
     */
    private function validate(): void
    {
        if (!isset(self::HIERARCHY[$this->value])) {
            throw new InvalidArgumentException("Invalid team role: {$this->value}");
        }
    }

    /**
     * Create owner role
     *
     * @return self
     */
    public static function owner(): self
    {
        return new self(self::OWNER);
    }

    /**
     * Create admin role
     *
     * @return self
     */
    public static function admin(): self
    {
        return new self(self::ADMIN);
    }

    /**
     * Create member role
     *
     * @return self
     */
    public static function member(): self
    {
        return new self(self::MEMBER);
    }

    /**
     * Create viewer role
     *
     * @return self
     */
    public static function viewer(): self
    {
        return new self(self::VIEWER);
    }

    /**
     * Create from string
     *
     * @param string $role
     * @return self
     */
    public static function fromString(string $role): self
    {
        return new self(strtolower(trim($role)));
    }

    /**
     * Check if this is the owner role
     *
     * @return bool
     */
    public function isOwner(): bool
    {
        return $this->value === self::OWNER;
    }

    /**
     * Check if this is the admin role
     *
     * @return bool
     */
    public function isAdmin(): bool
    {
        return $this->value === self::ADMIN;
    }

    /**
     * Check if this is the member role
     *
     * @return bool
     */
    public function isMember(): bool
    {
        return $this->value === self::MEMBER;
    }

    /**
     * Check if this is the viewer role
     *
     * @return bool
     */
    public function isViewer(): bool
    {
        return $this->value === self::VIEWER;
    }

    /**
     * Check if this role can manage the team
     *
     * @return bool
     */
    public function canManageTeam(): bool
    {
        return $this->hasPermission('manage_team');
    }

    /**
     * Check if this role can manage sites
     *
     * @return bool
     */
    public function canManageSites(): bool
    {
        return $this->hasPermission('manage_sites');
    }

    /**
     * Check if this role can manage billing
     *
     * @return bool
     */
    public function canManageBilling(): bool
    {
        return $this->hasPermission('manage_billing');
    }

    /**
     * Check if this role can invite members
     *
     * @return bool
     */
    public function canInviteMembers(): bool
    {
        return $this->hasPermission('invite_members');
    }

    /**
     * Check if this role can remove members
     *
     * @return bool
     */
    public function canRemoveMembers(): bool
    {
        return $this->hasPermission('remove_members');
    }

    /**
     * Check if this role can create sites
     *
     * @return bool
     */
    public function canCreateSites(): bool
    {
        return $this->hasPermission('create_sites');
    }

    /**
     * Check if this role can delete sites
     *
     * @return bool
     */
    public function canDeleteSites(): bool
    {
        return $this->hasPermission('delete_sites');
    }

    /**
     * Check if this role has a specific permission
     *
     * @param string $permission
     * @return bool
     */
    public function hasPermission(string $permission): bool
    {
        return in_array($permission, $this->getPermissions(), true);
    }

    /**
     * Check if this role is higher than another
     *
     * @param TeamRole $other
     * @return bool
     */
    public function isHigherThan(TeamRole $other): bool
    {
        return self::HIERARCHY[$this->value] > self::HIERARCHY[$other->value];
    }

    /**
     * Check if this role is lower than another
     *
     * @param TeamRole $other
     * @return bool
     */
    public function isLowerThan(TeamRole $other): bool
    {
        return self::HIERARCHY[$this->value] < self::HIERARCHY[$other->value];
    }

    /**
     * Check if this role equals another
     *
     * @param TeamRole $other
     * @return bool
     */
    public function equals(TeamRole $other): bool
    {
        return $this->value === $other->value;
    }

    /**
     * Check if this role is at least as high as another
     *
     * @param TeamRole $other
     * @return bool
     */
    public function isAtLeast(TeamRole $other): bool
    {
        return self::HIERARCHY[$this->value] >= self::HIERARCHY[$other->value];
    }

    /**
     * Get all permissions for this role
     *
     * @return array<int, string>
     */
    public function getPermissions(): array
    {
        return self::PERMISSIONS[$this->value];
    }

    /**
     * Get the hierarchy level
     *
     * @return int
     */
    public function getLevel(): int
    {
        return self::HIERARCHY[$this->value];
    }

    /**
     * Get a human-readable label
     *
     * @return string
     */
    public function label(): string
    {
        return ucfirst($this->value);
    }

    /**
     * Get all available roles
     *
     * @return array<int, self>
     */
    public static function all(): array
    {
        return [
            self::owner(),
            self::admin(),
            self::member(),
            self::viewer(),
        ];
    }

    /**
     * Get all role names
     *
     * @return array<int, string>
     */
    public static function values(): array
    {
        return array_keys(self::HIERARCHY);
    }

    /**
     * Convert to string
     *
     * @return string
     */
    public function __toString(): string
    {
        return $this->value;
    }

    /**
     * Serialize to JSON
     *
     * @return array<string, mixed>
     */
    public function jsonSerialize(): array
    {
        return [
            'value' => $this->value,
            'label' => $this->label(),
            'level' => $this->getLevel(),
            'permissions' => $this->getPermissions(),
        ];
    }
}
