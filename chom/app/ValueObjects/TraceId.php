<?php

declare(strict_types=1);

namespace App\ValueObjects;

use Ramsey\Uuid\Uuid;

/**
 * Trace ID Value Object
 *
 * Represents a unique identifier for distributed tracing.
 * Immutable value object for tracking requests across services.
 *
 * @package App\ValueObjects
 */
final class TraceId
{
    /**
     * @param string $value The trace identifier
     * @param \DateTimeInterface $createdAt When the trace was created
     */
    public function __construct(
        public readonly string $value,
        public readonly \DateTimeInterface $createdAt
    ) {
    }

    /**
     * Generate new trace ID
     *
     * @return self
     */
    public static function generate(): self
    {
        return new self(
            Uuid::uuid4()->toString(),
            new \DateTimeImmutable()
        );
    }

    /**
     * Create from existing value
     *
     * @param string $value
     * @return self
     */
    public static function fromString(string $value): self
    {
        return new self($value, new \DateTimeImmutable());
    }

    /**
     * Get short trace ID (first 8 characters)
     *
     * @return string
     */
    public function short(): string
    {
        return substr($this->value, 0, 8);
    }

    /**
     * Convert to string
     *
     * @return string
     */
    public function toString(): string
    {
        return $this->value;
    }

    /**
     * Convert to string (magic method)
     *
     * @return string
     */
    public function __toString(): string
    {
        return $this->value;
    }

    /**
     * Check equality with another trace ID
     *
     * @param TraceId $other
     * @return bool
     */
    public function equals(TraceId $other): bool
    {
        return $this->value === $other->value;
    }

    /**
     * Convert to array representation
     *
     * @return array<string, mixed>
     */
    public function toArray(): array
    {
        return [
            'trace_id' => $this->value,
            'created_at' => $this->createdAt->format('c'),
        ];
    }
}
