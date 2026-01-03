<?php

declare(strict_types=1);

namespace App\Modules\Team\ValueObjects;

/**
 * Permission Value Object
 *
 * Encapsulates granular permission information.
 */
final readonly class Permission
{
    private const PERMISSIONS = [
        'manage_sites',
        'manage_backups',
        'manage_billing',
        'view_analytics',
        'manage_team',
    ];

    public function __construct(
        private string $permission
    ) {
        $this->validate();
    }

    /**
     * Create manage sites permission.
     *
     * @return self
     */
    public static function manageSites(): self
    {
        return new self('manage_sites');
    }

    /**
     * Create manage backups permission.
     *
     * @return self
     */
    public static function manageBackups(): self
    {
        return new self('manage_backups');
    }

    /**
     * Create manage billing permission.
     *
     * @return self
     */
    public static function manageBilling(): self
    {
        return new self('manage_billing');
    }

    /**
     * Create view analytics permission.
     *
     * @return self
     */
    public static function viewAnalytics(): self
    {
        return new self('view_analytics');
    }

    /**
     * Create manage team permission.
     *
     * @return self
     */
    public static function manageTeam(): self
    {
        return new self('manage_team');
    }

    /**
     * Create from string.
     *
     * @param string $permission Permission string
     * @return self
     * @throws \InvalidArgumentException
     */
    public static function fromString(string $permission): self
    {
        return new self($permission);
    }

    /**
     * Get permission as string.
     *
     * @return string
     */
    public function toString(): string
    {
        return $this->permission;
    }

    /**
     * Check if permission equals another.
     *
     * @param Permission $other
     * @return bool
     */
    public function equals(Permission $other): bool
    {
        return $this->permission === $other->permission;
    }

    /**
     * Get all available permissions.
     *
     * @return array
     */
    public static function getAllPermissions(): array
    {
        return self::PERMISSIONS;
    }

    /**
     * Create permission set from array of strings.
     *
     * @param array $permissions Permission strings
     * @return array Array of Permission objects
     */
    public static function createSet(array $permissions): array
    {
        return array_map(
            fn(string $p) => new self($p),
            $permissions
        );
    }

    /**
     * Validate the permission.
     *
     * @return void
     * @throws \InvalidArgumentException
     */
    private function validate(): void
    {
        if (!in_array($this->permission, self::PERMISSIONS, true)) {
            throw new \InvalidArgumentException(
                sprintf(
                    'Invalid permission: %s. Valid permissions: %s',
                    $this->permission,
                    implode(', ', self::PERMISSIONS)
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
        return $this->permission;
    }
}
