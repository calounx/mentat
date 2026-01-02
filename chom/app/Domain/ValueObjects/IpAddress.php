<?php

namespace App\Domain\ValueObjects;

use InvalidArgumentException;

/**
 * IP Address Value Object.
 *
 * Represents a valid IPv4 or IPv6 address.
 * Immutable value object following Domain-Driven Design principles.
 */
final class IpAddress
{
    private string $value;

    private string $version; // 'ipv4' or 'ipv6'

    /**
     * Create a new IpAddress value object.
     *
     * @throws InvalidArgumentException
     */
    private function __construct(string $value)
    {
        $this->validate($value);
        $this->value = $value;
        $this->version = $this->detectVersion($value);
    }

    /**
     * Create IP address from string.
     *
     * @throws InvalidArgumentException
     */
    public static function fromString(string $value): self
    {
        return new self($value);
    }

    /**
     * Get the IP address as a string.
     */
    public function toString(): string
    {
        return $this->value;
    }

    /**
     * Get the IP address as a string (magic method).
     */
    public function __toString(): string
    {
        return $this->value;
    }

    /**
     * Get IP version.
     *
     * @return string 'ipv4' or 'ipv6'
     */
    public function getVersion(): string
    {
        return $this->version;
    }

    /**
     * Check if this is an IPv4 address.
     */
    public function isIpv4(): bool
    {
        return $this->version === 'ipv4';
    }

    /**
     * Check if this is an IPv6 address.
     */
    public function isIpv6(): bool
    {
        return $this->version === 'ipv6';
    }

    /**
     * Check if IP address is private.
     */
    public function isPrivate(): bool
    {
        return ! filter_var(
            $this->value,
            FILTER_VALIDATE_IP,
            FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE
        );
    }

    /**
     * Check if IP address is public.
     */
    public function isPublic(): bool
    {
        return ! $this->isPrivate();
    }

    /**
     * Check if IP address is in a specific subnet.
     *
     * @param  string  $subnet  (e.g., '192.168.0.0/24')
     */
    public function isInSubnet(string $subnet): bool
    {
        if ($this->isIpv6()) {
            // IPv6 subnet checking would require additional library
            return false;
        }

        [$subnetIp, $maskBits] = explode('/', $subnet);

        $ip = ip2long($this->value);
        $subnet = ip2long($subnetIp);
        $mask = -1 << (32 - (int) $maskBits);

        return ($ip & $mask) === ($subnet & $mask);
    }

    /**
     * Check if IP equals another IP.
     */
    public function equals(IpAddress $other): bool
    {
        return $this->value === $other->value;
    }

    /**
     * Validate IP address format.
     *
     * @throws InvalidArgumentException
     */
    private function validate(string $value): void
    {
        if (empty($value)) {
            throw new InvalidArgumentException('IP address cannot be empty');
        }

        // Validate using PHP's built-in filter
        if (! filter_var($value, FILTER_VALIDATE_IP)) {
            throw new InvalidArgumentException('Invalid IP address format: '.$value);
        }

        // Check for localhost (usually not allowed for VPS servers)
        $localhostAddresses = ['127.0.0.1', '::1', '0.0.0.0', '::'];
        if (in_array($value, $localhostAddresses, true)) {
            throw new InvalidArgumentException('Localhost IP addresses are not allowed');
        }
    }

    /**
     * Detect IP version.
     */
    private function detectVersion(string $value): string
    {
        if (filter_var($value, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
            return 'ipv4';
        }

        if (filter_var($value, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6)) {
            return 'ipv6';
        }

        return 'unknown';
    }

    /**
     * Check if IP address passes basic validation without throwing exception.
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
     * Get reverse DNS lookup format (for IPv4).
     */
    public function getReverseDnsFormat(): ?string
    {
        if (! $this->isIpv4()) {
            return null;
        }

        $parts = array_reverse(explode('.', $this->value));

        return implode('.', $parts).'.in-addr.arpa';
    }

    /**
     * Serialize for JSON.
     */
    public function jsonSerialize(): string
    {
        return $this->value;
    }
}
