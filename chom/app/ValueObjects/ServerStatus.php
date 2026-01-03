<?php

declare(strict_types=1);

namespace App\ValueObjects;

use InvalidArgumentException;

/**
 * Server Status Value Object
 *
 * Represents the current status of a VPS server.
 * Immutable value object with predefined status states.
 *
 * @package App\ValueObjects
 */
final class ServerStatus
{
    public const STATUS_PROVISIONING = 'provisioning';
    public const STATUS_ONLINE = 'online';
    public const STATUS_OFFLINE = 'offline';
    public const STATUS_REBOOTING = 'rebooting';
    public const STATUS_MAINTENANCE = 'maintenance';
    public const STATUS_ERROR = 'error';
    public const STATUS_TERMINATED = 'terminated';

    /**
     * @param string $status Current status
     * @param string|null $message Optional status message
     * @param array<string, mixed> $metadata Additional status metadata
     * @param \DateTimeInterface|null $lastChecked When status was last checked
     */
    public function __construct(
        public readonly string $status,
        public readonly ?string $message = null,
        public readonly array $metadata = [],
        public readonly ?\DateTimeInterface $lastChecked = null
    ) {
        $this->validate();
    }

    /**
     * Create status from string
     *
     * @param string $status
     * @param string|null $message
     * @return self
     */
    public static function from(string $status, ?string $message = null): self
    {
        return new self($status, $message, [], new \DateTimeImmutable());
    }

    /**
     * Check if server is online
     *
     * @return bool
     */
    public function isOnline(): bool
    {
        return $this->status === self::STATUS_ONLINE;
    }

    /**
     * Check if server is offline
     *
     * @return bool
     */
    public function isOffline(): bool
    {
        return $this->status === self::STATUS_OFFLINE;
    }

    /**
     * Check if server is provisioning
     *
     * @return bool
     */
    public function isProvisioning(): bool
    {
        return $this->status === self::STATUS_PROVISIONING;
    }

    /**
     * Check if server has error
     *
     * @return bool
     */
    public function hasError(): bool
    {
        return $this->status === self::STATUS_ERROR;
    }

    /**
     * Check if server is available for operations
     *
     * @return bool
     */
    public function isAvailable(): bool
    {
        return $this->status === self::STATUS_ONLINE;
    }

    /**
     * Convert to array representation
     *
     * @return array<string, mixed>
     */
    public function toArray(): array
    {
        return [
            'status' => $this->status,
            'message' => $this->message,
            'metadata' => $this->metadata,
            'last_checked' => $this->lastChecked?->format('c'),
            'is_online' => $this->isOnline(),
            'is_available' => $this->isAvailable(),
        ];
    }

    /**
     * Validate status value
     *
     * @throws InvalidArgumentException
     */
    private function validate(): void
    {
        $validStatuses = [
            self::STATUS_PROVISIONING,
            self::STATUS_ONLINE,
            self::STATUS_OFFLINE,
            self::STATUS_REBOOTING,
            self::STATUS_MAINTENANCE,
            self::STATUS_ERROR,
            self::STATUS_TERMINATED,
        ];

        if (!in_array($this->status, $validStatuses, true)) {
            throw new InvalidArgumentException(
                sprintf('Invalid status: %s. Must be one of: %s', $this->status, implode(', ', $validStatuses))
            );
        }
    }
}
