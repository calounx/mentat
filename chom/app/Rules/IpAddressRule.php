<?php

declare(strict_types=1);

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

/**
 * IP Address Validation Rule
 *
 * Validates IP addresses with protection against:
 * - Invalid IPv4/IPv6 formats
 * - Private IP ranges (optionally)
 * - Reserved IP ranges
 * - Localhost addresses
 *
 * OWASP Reference: A03:2021 – Injection
 * Protection: Prevents SSRF and IP-based attacks
 *
 * @package App\Rules
 */
class IpAddressRule implements ValidationRule
{
    /**
     * Allow IPv6 addresses.
     */
    protected bool $allowIpv6;

    /**
     * Allow private IP ranges.
     */
    protected bool $allowPrivate;

    /**
     * Allow reserved IP ranges.
     */
    protected bool $allowReserved;

    /**
     * Create a new rule instance.
     *
     * @param bool $allowIpv6 Allow IPv6 addresses
     * @param bool $allowPrivate Allow private IP ranges
     * @param bool $allowReserved Allow reserved IP ranges
     */
    public function __construct(
        bool $allowIpv6 = true,
        bool $allowPrivate = false,
        bool $allowReserved = false
    ) {
        $this->allowIpv6 = $allowIpv6;
        $this->allowPrivate = $allowPrivate;
        $this->allowReserved = $allowReserved;
    }

    /**
     * Run the validation rule.
     *
     * @param string $attribute Attribute name
     * @param mixed $value Value to validate
     * @param Closure $fail Failure callback
     * @return void
     */
    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (!is_string($value)) {
            $fail("The {$attribute} must be a valid IP address.");
            return;
        }

        // Validate IP format
        if (!$this->isValidIpFormat($value)) {
            $fail("The {$attribute} must be a valid IP address.");
            return;
        }

        // Check if IPv6 is allowed
        if (!$this->allowIpv6 && $this->isIpv6($value)) {
            $fail("The {$attribute} must be an IPv4 address.");
            return;
        }

        // Check for private IP ranges
        if (!$this->allowPrivate && $this->isPrivateIp($value)) {
            $fail("The {$attribute} cannot be a private IP address.");
            return;
        }

        // Check for reserved IP ranges
        if (!$this->allowReserved && $this->isReservedIp($value)) {
            $fail("The {$attribute} cannot be a reserved IP address.");
            return;
        }
    }

    /**
     * Check if IP address has valid format.
     *
     * @param string $ip IP address
     * @return bool True if valid
     */
    protected function isValidIpFormat(string $ip): bool
    {
        return filter_var($ip, FILTER_VALIDATE_IP) !== false;
    }

    /**
     * Check if IP is IPv6.
     *
     * @param string $ip IP address
     * @return bool True if IPv6
     */
    protected function isIpv6(string $ip): bool
    {
        return filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6) !== false;
    }

    /**
     * Check if IP is in private range.
     *
     * Private ranges (RFC 1918):
     * - 10.0.0.0/8
     * - 172.16.0.0/12
     * - 192.168.0.0/16
     * - fc00::/7 (IPv6)
     *
     * SECURITY: Prevents SSRF attacks against internal resources
     *
     * @param string $ip IP address
     * @return bool True if private
     */
    protected function isPrivateIp(string $ip): bool
    {
        return filter_var(
            $ip,
            FILTER_VALIDATE_IP,
            FILTER_FLAG_NO_PRIV_RANGE
        ) === false;
    }

    /**
     * Check if IP is in reserved range.
     *
     * Reserved ranges include:
     * - 127.0.0.0/8 (localhost)
     * - 169.254.0.0/16 (link-local)
     * - 224.0.0.0/4 (multicast)
     * - ::1 (IPv6 localhost)
     *
     * SECURITY: Prevents localhost bypass attacks
     *
     * @param string $ip IP address
     * @return bool True if reserved
     */
    protected function isReservedIp(string $ip): bool
    {
        return filter_var(
            $ip,
            FILTER_VALIDATE_IP,
            FILTER_FLAG_NO_RES_RANGE
        ) === false;
    }
}
