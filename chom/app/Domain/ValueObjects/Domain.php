<?php

namespace App\Domain\ValueObjects;

use InvalidArgumentException;

/**
 * Domain Value Object.
 *
 * Represents a valid internet domain name.
 * Immutable value object following Domain-Driven Design principles.
 */
final class Domain
{
    private string $value;

    /**
     * Create a new Domain value object.
     *
     * @throws InvalidArgumentException
     */
    private function __construct(string $value)
    {
        $this->validate($value);
        $this->value = strtolower($value);
    }

    /**
     * Create domain from string.
     *
     * @throws InvalidArgumentException
     */
    public static function fromString(string $value): self
    {
        return new self($value);
    }

    /**
     * Get the domain as a string.
     */
    public function toString(): string
    {
        return $this->value;
    }

    /**
     * Get the domain as a string (magic method).
     */
    public function __toString(): string
    {
        return $this->value;
    }

    /**
     * Get the top-level domain (TLD).
     */
    public function getTld(): string
    {
        $parts = explode('.', $this->value);

        return end($parts);
    }

    /**
     * Get the domain without the TLD.
     */
    public function getWithoutTld(): string
    {
        $parts = explode('.', $this->value);
        array_pop($parts);

        return implode('.', $parts);
    }

    /**
     * Get subdomain (if any).
     */
    public function getSubdomain(): ?string
    {
        $parts = explode('.', $this->value);
        if (count($parts) > 2) {
            array_pop($parts); // Remove TLD
            array_pop($parts); // Remove domain

            return implode('.', $parts);
        }

        return null;
    }

    /**
     * Check if this is a subdomain.
     */
    public function isSubdomain(): bool
    {
        return count(explode('.', $this->value)) > 2;
    }

    /**
     * Check if domain equals another domain.
     */
    public function equals(Domain $other): bool
    {
        return $this->value === $other->value;
    }

    /**
     * Validate domain format.
     *
     * @throws InvalidArgumentException
     */
    private function validate(string $value): void
    {
        // Check length
        if (strlen($value) > 253) {
            throw new InvalidArgumentException('Domain name too long (max 253 characters)');
        }

        if (strlen($value) < 3) {
            throw new InvalidArgumentException('Domain name too short (min 3 characters)');
        }

        // Check for localhost or reserved domains BEFORE format validation
        $reserved = ['localhost', 'localhost.localdomain', 'test', 'invalid', 'example'];
        $lowerValue = strtolower($value);

        foreach ($reserved as $reservedDomain) {
            if (str_contains($lowerValue, $reservedDomain)) {
                throw new InvalidArgumentException('Reserved domain name: '.$value);
            }
        }

        // Check for SQL injection patterns
        $suspiciousPatterns = [
            "/'--/i",
            "/'#/i",
            "/'\/\*/i",
            '/;/',
            "/\bor\b.*=/i",
            "/\band\b.*=/i",
            "/\bunion\b/i",
            "/\bselect\b/i",
            "/\bdrop\b/i",
            "/\binsert\b/i",
            "/\bupdate\b/i",
            "/\bdelete\b/i",
        ];

        foreach ($suspiciousPatterns as $pattern) {
            if (preg_match($pattern, $value)) {
                throw new InvalidArgumentException('Invalid domain format: '.$value);
            }
        }

        // Check format using regex
        $pattern = '/^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$/i';
        if (! preg_match($pattern, $value)) {
            throw new InvalidArgumentException('Invalid domain format: '.$value);
        }
    }

    /**
     * Check if domain passes basic validation without throwing exception.
     */
    public static function isValid(string $value): bool
    {
        try {
            new self($value);

            return true;
        } catch (InvalidArgumentException $e) {
            return false;
        }
    }

    /**
     * Serialize for JSON.
     */
    public function jsonSerialize(): string
    {
        return $this->value;
    }
}
