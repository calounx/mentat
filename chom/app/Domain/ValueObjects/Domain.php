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
     * @param string $value
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
     * @param string $value
     * @return self
     * @throws InvalidArgumentException
     */
    public static function fromString(string $value): self
    {
        return new self($value);
    }

    /**
     * Get the domain as a string.
     *
     * @return string
     */
    public function toString(): string
    {
        return $this->value;
    }

    /**
     * Get the domain as a string (magic method).
     *
     * @return string
     */
    public function __toString(): string
    {
        return $this->value;
    }

    /**
     * Get the top-level domain (TLD).
     *
     * @return string
     */
    public function getTld(): string
    {
        $parts = explode('.', $this->value);
        return end($parts);
    }

    /**
     * Get the domain without the TLD.
     *
     * @return string
     */
    public function getWithoutTld(): string
    {
        $parts = explode('.', $this->value);
        array_pop($parts);
        return implode('.', $parts);
    }

    /**
     * Get subdomain (if any).
     *
     * @return string|null
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
     *
     * @return bool
     */
    public function isSubdomain(): bool
    {
        return count(explode('.', $this->value)) > 2;
    }

    /**
     * Check if domain equals another domain.
     *
     * @param Domain $other
     * @return bool
     */
    public function equals(Domain $other): bool
    {
        return $this->value === $other->value;
    }

    /**
     * Validate domain format.
     *
     * @param string $value
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

        // Check format using regex
        $pattern = '/^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$/i';
        if (!preg_match($pattern, $value)) {
            throw new InvalidArgumentException('Invalid domain format: ' . $value);
        }

        // Check for SQL injection patterns
        $suspiciousPatterns = [
            "/'--/i",
            "/'#/i",
            "/'\/\*/i",
            "/;/",
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
                throw new InvalidArgumentException('Domain contains suspicious characters or patterns');
            }
        }

        // Check for localhost or reserved domains
        $reserved = ['localhost', 'localhost.localdomain', 'test', 'invalid', 'example'];
        $lowerValue = strtolower($value);

        foreach ($reserved as $reservedDomain) {
            if (str_contains($lowerValue, $reservedDomain)) {
                throw new InvalidArgumentException('Reserved domain name: ' . $value);
            }
        }
    }

    /**
     * Check if domain passes basic validation without throwing exception.
     *
     * @param string $value
     * @return bool
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
     *
     * @return string
     */
    public function jsonSerialize(): string
    {
        return $this->value;
    }
}
