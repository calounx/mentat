<?php

namespace App\Rules;

use App\Domain\ValueObjects\IpAddress;
use Illuminate\Contracts\Validation\Rule;

/**
 * Valid IP Address Validation Rule.
 *
 * Validates IP address format (IPv4 or IPv6).
 * Uses the IpAddress value object for validation logic.
 */
class ValidIpAddress implements Rule
{
    private string $message = 'The :attribute must be a valid IP address.';
    private bool $allowPrivate;
    private ?string $requiredVersion;

    /**
     * Create a new rule instance.
     *
     * @param bool $allowPrivate Allow private IP addresses
     * @param string|null $requiredVersion Required IP version ('ipv4' or 'ipv6')
     */
    public function __construct(
        bool $allowPrivate = true,
        ?string $requiredVersion = null
    ) {
        $this->allowPrivate = $allowPrivate;
        $this->requiredVersion = $requiredVersion;
    }

    /**
     * Determine if the validation rule passes.
     *
     * @param string $attribute
     * @param mixed $value
     * @return bool
     */
    public function passes($attribute, $value): bool
    {
        if (!is_string($value)) {
            $this->message = 'The :attribute must be a string.';
            return false;
        }

        // Use the IpAddress value object for validation
        if (!IpAddress::isValid($value)) {
            try {
                IpAddress::fromString($value);
            } catch (\InvalidArgumentException $e) {
                $this->message = $e->getMessage();
            }
            return false;
        }

        try {
            $ip = IpAddress::fromString($value);

            // Check if private IPs are allowed
            if (!$this->allowPrivate && $ip->isPrivate()) {
                $this->message = 'The :attribute must be a public IP address.';
                return false;
            }

            // Check IP version requirement
            if ($this->requiredVersion !== null) {
                if ($this->requiredVersion === 'ipv4' && !$ip->isIpv4()) {
                    $this->message = 'The :attribute must be an IPv4 address.';
                    return false;
                }

                if ($this->requiredVersion === 'ipv6' && !$ip->isIpv6()) {
                    $this->message = 'The :attribute must be an IPv6 address.';
                    return false;
                }
            }

            return true;
        } catch (\InvalidArgumentException $e) {
            $this->message = $e->getMessage();
            return false;
        }
    }

    /**
     * Get the validation error message.
     *
     * @return string
     */
    public function message(): string
    {
        return $this->message;
    }

    /**
     * Static factory for public IPs only.
     *
     * @return self
     */
    public static function publicOnly(): self
    {
        return new self(allowPrivate: false);
    }

    /**
     * Static factory for IPv4 only.
     *
     * @return self
     */
    public static function ipv4Only(): self
    {
        return new self(requiredVersion: 'ipv4');
    }

    /**
     * Static factory for IPv6 only.
     *
     * @return self
     */
    public static function ipv6Only(): self
    {
        return new self(requiredVersion: 'ipv6');
    }
}
