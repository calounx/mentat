<?php

declare(strict_types=1);

namespace App\ValueObjects;

use InvalidArgumentException;

/**
 * In-App Notification Value Object
 *
 * Represents an in-app notification for user display.
 * Immutable value object ensuring valid notification configurations.
 *
 * @package App\ValueObjects
 */
final class InAppNotification
{
    public const TYPE_INFO = 'info';
    public const TYPE_SUCCESS = 'success';
    public const TYPE_WARNING = 'warning';
    public const TYPE_ERROR = 'error';

    /**
     * @param int|string $userId User ID to notify
     * @param string $title Notification title
     * @param string $body Notification body
     * @param string $type Notification type (info, success, warning, error)
     * @param string|null $actionUrl Optional action URL
     * @param string|null $actionText Optional action button text
     * @param array<string, mixed> $metadata Additional metadata
     */
    public function __construct(
        public readonly int|string $userId,
        public readonly string $title,
        public readonly string $body,
        public readonly string $type = self::TYPE_INFO,
        public readonly ?string $actionUrl = null,
        public readonly ?string $actionText = null,
        public readonly array $metadata = []
    ) {
        $this->validate();
    }

    /**
     * Create from array
     *
     * @param array<string, mixed> $data
     * @return self
     */
    public static function fromArray(array $data): self
    {
        return new self(
            userId: $data['user_id'] ?? $data['userId'] ?? 0,
            title: (string) ($data['title'] ?? ''),
            body: (string) ($data['body'] ?? ''),
            type: (string) ($data['type'] ?? self::TYPE_INFO),
            actionUrl: $data['action_url'] ?? $data['actionUrl'] ?? null,
            actionText: $data['action_text'] ?? $data['actionText'] ?? null,
            metadata: (array) ($data['metadata'] ?? [])
        );
    }

    /**
     * Convert to array representation
     *
     * @return array<string, mixed>
     */
    public function toArray(): array
    {
        return [
            'user_id' => $this->userId,
            'title' => $this->title,
            'body' => $this->body,
            'type' => $this->type,
            'action_url' => $this->actionUrl,
            'action_text' => $this->actionText,
            'metadata' => $this->metadata,
        ];
    }

    /**
     * Validate notification
     *
     * @throws InvalidArgumentException
     */
    private function validate(): void
    {
        if (empty($this->userId)) {
            throw new InvalidArgumentException('User ID is required');
        }

        if (empty($this->title)) {
            throw new InvalidArgumentException('Title is required');
        }

        if (empty($this->body)) {
            throw new InvalidArgumentException('Body is required');
        }

        $validTypes = [self::TYPE_INFO, self::TYPE_SUCCESS, self::TYPE_WARNING, self::TYPE_ERROR];
        if (!in_array($this->type, $validTypes, true)) {
            throw new InvalidArgumentException(
                sprintf('Invalid type: %s. Must be one of: %s', $this->type, implode(', ', $validTypes))
            );
        }
    }

    /**
     * Check if has action
     *
     * @return bool
     */
    public function hasAction(): bool
    {
        return $this->actionUrl !== null && $this->actionText !== null;
    }
}
