<?php

declare(strict_types=1);

namespace App\ValueObjects;

use InvalidArgumentException;

/**
 * SMS Notification Value Object
 *
 * Represents an SMS notification with phone number and message.
 * Immutable value object ensuring valid SMS configurations.
 *
 * @package App\ValueObjects
 */
final class SmsNotification
{
    /**
     * @param string $phone Recipient phone number in E.164 format
     * @param string $message SMS message content
     * @param array<string, mixed> $metadata Additional metadata
     */
    public function __construct(
        public readonly string $phone,
        public readonly string $message,
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
            phone: (string) ($data['phone'] ?? ''),
            message: (string) ($data['message'] ?? ''),
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
            'phone' => $this->phone,
            'message' => $this->message,
            'metadata' => $this->metadata,
        ];
    }

    /**
     * Validate SMS notification
     *
     * @throws InvalidArgumentException
     */
    private function validate(): void
    {
        if (empty($this->phone)) {
            throw new InvalidArgumentException('Phone number is required');
        }

        // Basic E.164 format validation
        if (!preg_match('/^\+[1-9]\d{1,14}$/', $this->phone)) {
            throw new InvalidArgumentException('Phone number must be in E.164 format (e.g., +1234567890)');
        }

        if (empty($this->message)) {
            throw new InvalidArgumentException('Message is required');
        }

        if (strlen($this->message) > 1600) {
            throw new InvalidArgumentException('Message exceeds maximum length of 1600 characters');
        }
    }

    /**
     * Get message length
     *
     * @return int
     */
    public function getMessageLength(): int
    {
        return strlen($this->message);
    }

    /**
     * Get estimated SMS segments
     *
     * @return int
     */
    public function getSegmentCount(): int
    {
        $length = $this->getMessageLength();
        if ($length <= 160) {
            return 1;
        }
        return (int) ceil($length / 153);
    }
}
