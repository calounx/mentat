<?php

declare(strict_types=1);

namespace App\ValueObjects;

use InvalidArgumentException;
use JsonSerializable;

/**
 * Domain name value object
 *
 * Represents and validates a domain name.
 */
final class DomainName implements JsonSerializable
{
    private const MAX_LENGTH = 253;
    private const MAX_LABEL_LENGTH = 63;

    /**
     * Create a new DomainName instance
     *
     * @param string $value The domain name
     * @throws InvalidArgumentException If domain is invalid
     */
    public function __construct(
        public readonly string $value
    ) {
        $this->validate();
    }

    /**
     * Validate the domain name
     *
     * @throws InvalidArgumentException If domain is invalid
     */
    private function validate(): void
    {
        if (empty($this->value)) {
            throw new InvalidArgumentException('Domain name cannot be empty');
        }

        $domain = $this->value;

        if ($this->isWildcard()) {
            $domain = substr($domain, 2);
        }

        if (strlen($domain) > self::MAX_LENGTH) {
            throw new InvalidArgumentException(
                "Domain name exceeds maximum length of " . self::MAX_LENGTH . " characters"
            );
        }

        $pattern = '/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i';
        if (!preg_match($pattern, $domain)) {
            throw new InvalidArgumentException("Invalid domain name format: {$this->value}");
        }

        $labels = explode('.', $domain);
        foreach ($labels as $label) {
            if (strlen($label) > self::MAX_LABEL_LENGTH) {
                throw new InvalidArgumentException(
                    "Domain label exceeds maximum length of " . self::MAX_LABEL_LENGTH . " characters"
                );
            }
        }

        if (count($labels) < 2) {
            throw new InvalidArgumentException("Domain must have at least two labels: {$this->value}");
        }
    }

    /**
     * Create from string
     *
     * @param string $domain
     * @return self
     */
    public static function fromString(string $domain): self
    {
        return new self(strtolower(trim($domain)));
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
     * Get the root domain (domain + TLD)
     *
     * @return string
     */
    public function getRoot(): string
    {
        $domain = $this->isWildcard() ? substr($this->value, 2) : $this->value;
        $parts = explode('.', $domain);

        if (count($parts) <= 2) {
            return $domain;
        }

        return implode('.', array_slice($parts, -2));
    }

    /**
     * Get the subdomain part (if any)
     *
     * @return string|null
     */
    public function getSubdomain(): ?string
    {
        $domain = $this->isWildcard() ? substr($this->value, 2) : $this->value;
        $parts = explode('.', $domain);

        if (count($parts) <= 2) {
            return null;
        }

        return implode('.', array_slice($parts, 0, -2));
    }

    /**
     * Get the top-level domain (TLD)
     *
     * @return string
     */
    public function getTld(): string
    {
        $domain = $this->isWildcard() ? substr($this->value, 2) : $this->value;
        $parts = explode('.', $domain);
        return end($parts);
    }

    /**
     * Check if this is a wildcard domain
     *
     * @return bool
     */
    public function isWildcard(): bool
    {
        return str_starts_with($this->value, '*.');
    }

    /**
     * Check if this domain equals another
     *
     * @param DomainName $other
     * @return bool
     */
    public function equals(DomainName $other): bool
    {
        return $this->value === $other->value;
    }

    /**
     * Check if this domain matches a pattern
     *
     * @param string $pattern Glob pattern (e.g., "*.example.com")
     * @return bool
     */
    public function matches(string $pattern): bool
    {
        $pattern = str_replace('.', '\.', $pattern);
        $pattern = str_replace('*', '.*', $pattern);
        $pattern = '/^' . $pattern . '$/i';

        return (bool)preg_match($pattern, $this->value);
    }

    /**
     * Check if this is a subdomain of another domain
     *
     * @param DomainName $parent
     * @return bool
     */
    public function isSubdomainOf(DomainName $parent): bool
    {
        return str_ends_with($this->value, '.' . $parent->value);
    }

    /**
     * Create a subdomain of this domain
     *
     * @param string $subdomain
     * @return self
     */
    public function withSubdomain(string $subdomain): self
    {
        return new self($subdomain . '.' . $this->value);
    }

    /**
     * Get all parts of the domain
     *
     * @return array<int, string>
     */
    public function getParts(): array
    {
        $domain = $this->isWildcard() ? substr($this->value, 2) : $this->value;
        return explode('.', $domain);
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
            'root' => $this->getRoot(),
            'subdomain' => $this->getSubdomain(),
            'tld' => $this->getTld(),
            'is_wildcard' => $this->isWildcard(),
        ];
    }
}
