<?php

declare(strict_types=1);

namespace App\ValueObjects;

use InvalidArgumentException;

/**
 * Webhook Notification Value Object
 *
 * Represents a webhook notification with URL, method, and payload.
 * Immutable value object ensuring valid webhook configurations.
 *
 * @package App\ValueObjects
 */
final class WebhookNotification
{
    /**
     * @param string $url Webhook URL
     * @param array<string, mixed> $payload Request payload
     * @param string $method HTTP method (GET, POST, PUT, etc.)
     * @param array<string, string> $headers Additional HTTP headers
     * @param int $timeout Request timeout in seconds
     * @param array<string, mixed> $metadata Additional metadata
     */
    public function __construct(
        public readonly string $url,
        public readonly array $payload,
        public readonly string $method = 'POST',
        public readonly array $headers = [],
        public readonly int $timeout = 30,
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
            url: (string) ($data['url'] ?? ''),
            payload: (array) ($data['payload'] ?? []),
            method: (string) ($data['method'] ?? 'POST'),
            headers: (array) ($data['headers'] ?? []),
            timeout: (int) ($data['timeout'] ?? 30),
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
            'url' => $this->url,
            'payload' => $this->payload,
            'method' => $this->method,
            'headers' => $this->headers,
            'timeout' => $this->timeout,
            'metadata' => $this->metadata,
        ];
    }

    /**
     * Validate webhook notification
     *
     * @throws InvalidArgumentException
     */
    private function validate(): void
    {
        if (empty($this->url)) {
            throw new InvalidArgumentException('URL is required');
        }

        if (!filter_var($this->url, FILTER_VALIDATE_URL)) {
            throw new InvalidArgumentException('Invalid URL format');
        }

        $validMethods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];
        if (!in_array(strtoupper($this->method), $validMethods, true)) {
            throw new InvalidArgumentException(
                sprintf('Invalid HTTP method: %s. Must be one of: %s', $this->method, implode(', ', $validMethods))
            );
        }

        if ($this->timeout < 1 || $this->timeout > 300) {
            throw new InvalidArgumentException('Timeout must be between 1 and 300 seconds');
        }
    }
}
