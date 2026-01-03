<?php

declare(strict_types=1);

namespace App\ValueObjects;

use InvalidArgumentException;

/**
 * Email Notification Value Object
 *
 * Represents an email notification with recipients, subject, body and attachments.
 * Immutable value object ensuring valid email configurations.
 *
 * @package App\ValueObjects
 */
final class EmailNotification
{
    /**
     * @param array<string> $to Recipient email addresses
     * @param string $subject Email subject
     * @param string $body Email body content
     * @param array<string> $cc CC recipients
     * @param array<string> $bcc BCC recipients
     * @param array<string> $attachments File paths to attach
     * @param array<string, mixed> $metadata Additional metadata
     * @param string|null $from Sender email address
     * @param string|null $replyTo Reply-to email address
     * @param bool $isHtml Whether body is HTML
     */
    public function __construct(
        public readonly array $to,
        public readonly string $subject,
        public readonly string $body,
        public readonly array $cc = [],
        public readonly array $bcc = [],
        public readonly array $attachments = [],
        public readonly array $metadata = [],
        public readonly ?string $from = null,
        public readonly ?string $replyTo = null,
        public readonly bool $isHtml = true
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
            to: (array) ($data['to'] ?? []),
            subject: (string) ($data['subject'] ?? ''),
            body: (string) ($data['body'] ?? ''),
            cc: (array) ($data['cc'] ?? []),
            bcc: (array) ($data['bcc'] ?? []),
            attachments: (array) ($data['attachments'] ?? []),
            metadata: (array) ($data['metadata'] ?? []),
            from: $data['from'] ?? null,
            replyTo: $data['reply_to'] ?? $data['replyTo'] ?? null,
            isHtml: (bool) ($data['is_html'] ?? $data['isHtml'] ?? true)
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
            'to' => $this->to,
            'subject' => $this->subject,
            'body' => $this->body,
            'cc' => $this->cc,
            'bcc' => $this->bcc,
            'attachments' => $this->attachments,
            'metadata' => $this->metadata,
            'from' => $this->from,
            'reply_to' => $this->replyTo,
            'is_html' => $this->isHtml,
        ];
    }

    /**
     * Validate email notification
     *
     * @throws InvalidArgumentException
     */
    private function validate(): void
    {
        if (empty($this->to)) {
            throw new InvalidArgumentException('At least one recipient is required');
        }

        foreach ($this->to as $email) {
            if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
                throw new InvalidArgumentException("Invalid email address: {$email}");
            }
        }

        if (empty($this->subject)) {
            throw new InvalidArgumentException('Subject is required');
        }

        if (empty($this->body)) {
            throw new InvalidArgumentException('Body is required');
        }
    }

    /**
     * Get total recipient count
     *
     * @return int
     */
    public function getRecipientCount(): int
    {
        return count($this->to) + count($this->cc) + count($this->bcc);
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
}
