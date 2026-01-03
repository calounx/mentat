<?php

declare(strict_types=1);

namespace App\Modules\Team\ValueObjects;

/**
 * Team Role Value Object
 *
 * Encapsulates team role information with hierarchy.
 */
final readonly class TeamRole
{
    private const ROLES = ['owner', 'admin', 'member', 'viewer'];

    private const HIERARCHY = [
        'owner' => 4,
        'admin' => 3,
        'member' => 2,
        'viewer' => 1,
    ];

    public function __construct(
        private string $role
    ) {
        $this->validate();
    }

    /**
     * Create owner role.
     *
     * @return self
     */
    public static function owner(): self
    {
        return new self('owner');
    }

    /**
     * Create admin role.
     *
     * @return self
     */
    public static function admin(): self
    {
        return new self('admin');
    }

    /**
     * Create member role.
     *
     * @return self
     */
    public static function member(): self
    {
        return new self('member');
    }

    /**
     * Create viewer role.
     *
     * @return self
     */
    public static function viewer(): self
    {
        return new self('viewer');
    }

    /**
     * Create from string.
     *
     * @param string $role Role string
     * @return self
     * @throws \InvalidArgumentException
     */
    public static function fromString(string $role): self
    {
        return new self($role);
    }

    /**
     * Get role as string.
     *
     * @return string
     */
    public function toString(): string
    {
        return $this->role;
    }

    /**
     * Get role hierarchy level.
     *
     * @return int
     */
    public function getLevel(): int
    {
        return self::HIERARCHY[$this->role];
    }

    /**
     * Check if this role is higher than another.
     *
     * @param TeamRole $other
     * @return bool
     */
    public function isHigherThan(TeamRole $other): bool
    {
        return $this->getLevel() > $other->getLevel();
    }

    /**
     * Check if this role is lower than another.
     *
     * @param TeamRole $other
     * @return bool
     */
    public function isLowerThan(TeamRole $other): bool
    {
        return $this->getLevel() < $other->getLevel();
    }

    /**
     * Check if this role equals another.
     *
     * @param TeamRole $other
     * @return bool
     */
    public function equals(TeamRole $other): bool
    {
        return $this->role === $other->role;
    }

    /**
     * Check if role is owner.
     *
     * @return bool
     */
    public function isOwner(): bool
    {
        return $this->role === 'owner';
    }

    /**
     * Check if role is admin.
     *
     * @return bool
     */
    public function isAdmin(): bool
    {
        return $this->role === 'admin';
    }

    /**
     * Check if role has admin privileges (owner or admin).
     *
     * @return bool
     */
    public function hasAdminPrivileges(): bool
    {
        return in_array($this->role, ['owner', 'admin'], true);
    }

    /**
     * Get all available roles.
     *
     * @return array
     */
    public static function getAllRoles(): array
    {
        return self::ROLES;
    }

    /**
     * Validate the role.
     *
     * @return void
     * @throws \InvalidArgumentException
     */
    private function validate(): void
    {
        if (!in_array($this->role, self::ROLES, true)) {
            throw new \InvalidArgumentException(
                sprintf(
                    'Invalid team role: %s. Valid roles: %s',
                    $this->role,
                    implode(', ', self::ROLES)
                )
            );
        }
    }

    /**
     * String representation.
     *
     * @return string
     */
    public function __toString(): string
    {
        return $this->role;
    }
}
