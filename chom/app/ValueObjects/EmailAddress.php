<?php

declare(strict_types=1);

namespace App\ValueObjects;

use InvalidArgumentException;
use JsonSerializable;

/**
 * Email address value object
 *
 * Represents and validates an email address.
 */
final class EmailAddress implements JsonSerializable
{
    private const DISPOSABLE_DOMAINS = [
        'tempmail.com',
        'throwaway.email',
        'guerrillamail.com',
        'mailinator.com',
        '10minutemail.com',
        'temp-mail.org',
        'fakeinbox.com',
        'trashmail.com',
    ];

    /**
     * Create a new EmailAddress instance
     *
     * @param string $value The email address
     * @throws InvalidArgumentException If email is invalid
     */
    public function __construct(
        public readonly string $value
    ) {
        $this->validate();
    }

    /**
     * Validate the email address
     *
     * @throws InvalidArgumentException If email is invalid
     */
    private function validate(): void
    {
        if (empty($this->value)) {
            throw new InvalidArgumentException('Email address cannot be empty');
        }

        if (!filter_var($this->value, FILTER_VALIDATE_EMAIL)) {
            throw new InvalidArgumentException("Invalid email address: {$this->value}");
        }

        if (strlen($this->value) > 254) {
            throw new InvalidArgumentException('Email address exceeds maximum length of 254 characters');
        }

        $parts = explode('@', $this->value);
        if (count($parts) !== 2) {
            throw new InvalidArgumentException("Invalid email address format: {$this->value}");
        }

        [$local, $domain] = $parts;

        if (strlen($local) > 64) {
            throw new InvalidArgumentException('Email local part exceeds maximum length of 64 characters');
        }

        if (empty($domain)) {
            throw new InvalidArgumentException('Email domain cannot be empty');
        }
    }

    /**
     * Create from string
     *
     * @param string $email
     * @return self
     */
    public static function fromString(string $email): self
    {
        return new self(strtolower(trim($email)));
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
     * Get the local part (before @)
     *
     * @return string
     */
    public function getLocalPart(): string
    {
        return explode('@', $this->value)[0];
    }

    /**
     * Get the domain part (after @)
     *
     * @return string
     */
    public function getDomain(): string
    {
        return explode('@', $this->value)[1];
    }

    /**
     * Check if this email equals another
     *
     * @param EmailAddress $other
     * @return bool
     */
    public function equals(EmailAddress $other): bool
    {
        return $this->value === $other->value;
    }

    /**
     * Check if email is from a disposable email provider
     *
     * @return bool
     */
    public function isDisposable(): bool
    {
        $domain = $this->getDomain();
        return in_array($domain, self::DISPOSABLE_DOMAINS, true);
    }

    /**
     * Get a hashed version of the email (for privacy)
     *
     * @return string
     */
    public function hash(): string
    {
        return hash('sha256', $this->value);
    }

    /**
     * Get a masked version of the email for display
     *
     * @return string
     */
    public function mask(): string
    {
        [$local, $domain] = explode('@', $this->value);

        if (strlen($local) <= 2) {
            $masked = str_repeat('*', strlen($local));
        } else {
            $visible = substr($local, 0, 2);
            $masked = $visible . str_repeat('*', strlen($local) - 2);
        }

        return $masked . '@' . $domain;
    }

    /**
     * Check if email belongs to a specific domain
     *
     * @param string $domain
     * @return bool
     */
    public function belongsToDomain(string $domain): bool
    {
        return strtolower($this->getDomain()) === strtolower($domain);
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
            'local' => $this->getLocalPart(),
            'domain' => $this->getDomain(),
            'masked' => $this->mask(),
        ];
    }
}
