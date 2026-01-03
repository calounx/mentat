<?php

declare(strict_types=1);

namespace App\ValueObjects;

use InvalidArgumentException;

/**
 * Slack Notification Value Object
 *
 * Represents a Slack notification with channel, message and attachments.
 * Immutable value object ensuring valid Slack configurations.
 *
 * @package App\ValueObjects
 */
final class SlackNotification
{
    /**
     * @param string $channel Slack channel (e.g., #general, @username)
     * @param string $message Message text
     * @param array<array<string, mixed>> $attachments Slack message attachments
     * @param array<array<string, mixed>> $blocks Slack block kit blocks
     * @param string|null $username Custom username for the message
     * @param string|null $iconEmoji Custom emoji icon
     * @param array<string, mixed> $metadata Additional metadata
     */
    public function __construct(
        public readonly string $channel,
        public readonly string $message,
        public readonly array $attachments = [],
        public readonly array $blocks = [],
        public readonly ?string $username = null,
        public readonly ?string $iconEmoji = null,
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
            channel: (string) ($data['channel'] ?? ''),
            message: (string) ($data['message'] ?? ''),
            attachments: (array) ($data['attachments'] ?? []),
            blocks: (array) ($data['blocks'] ?? []),
            username: $data['username'] ?? null,
            iconEmoji: $data['icon_emoji'] ?? $data['iconEmoji'] ?? null,
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
            'channel' => $this->channel,
            'message' => $this->message,
            'attachments' => $this->attachments,
            'blocks' => $this->blocks,
            'username' => $this->username,
            'icon_emoji' => $this->iconEmoji,
            'metadata' => $this->metadata,
        ];
    }

    /**
     * Validate Slack notification
     *
     * @throws InvalidArgumentException
     */
    private function validate(): void
    {
        if (empty($this->channel)) {
            throw new InvalidArgumentException('Channel is required');
        }

        if (!str_starts_with($this->channel, '#') && !str_starts_with($this->channel, '@')) {
            throw new InvalidArgumentException('Channel must start with # or @');
        }

        if (empty($this->message)) {
            throw new InvalidArgumentException('Message is required');
        }
    }

    /**
     * Check if has attachments
     *
     * @return bool
     */
    public function hasAttachments(): bool
    {
        return !empty($this->attachments);
    }

    /**
     * Check if has blocks
     *
     * @return bool
     */
    public function hasBlocks(): bool
    {
        return !empty($this->blocks);
    }
}
