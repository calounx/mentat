<?php

declare(strict_types=1);

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

/**
 * Domain Name Validation Rule
 *
 * Validates domain names with protection against:
 * - IDN homograph attacks (look-alike characters)
 * - Invalid TLDs
 * - Malformed domain structures
 * - Punycode injection
 *
 * OWASP Reference: A03:2021 – Injection
 * Protection: Prevents domain-based attacks and phishing
 *
 * @package App\Rules
 */
class DomainNameRule implements ValidationRule
{
    /**
     * List of dangerous characters in IDN domains.
     * These can be used for homograph attacks.
     */
    protected array $dangerousIdnCharacters = [
        'а', 'е', 'о', 'р', 'с', 'у', 'х', // Cyrillic look-alikes
        'ο', 'а', 'е', 'і', 'о', 'р', 'с', 'у', 'х', // Greek look-alikes
    ];

    /**
     * Allow internationalized domain names (IDN).
     */
    protected bool $allowIdn;

    /**
     * Require valid TLD.
     */
    protected bool $requireValidTld;

    /**
     * Create a new rule instance.
     *
     * @param bool $allowIdn Allow internationalized domain names
     * @param bool $requireValidTld Require valid TLD
     */
    public function __construct(bool $allowIdn = false, bool $requireValidTld = true)
    {
        $this->allowIdn = $allowIdn;
        $this->requireValidTld = $requireValidTld;
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
            $fail("The {$attribute} must be a valid domain name.");
            return;
        }

        // Check basic format
        if (!$this->isValidFormat($value)) {
            $fail("The {$attribute} must be a valid domain name.");
            return;
        }

        // Check for IDN homograph attacks
        if (!$this->allowIdn && $this->containsIdnCharacters($value)) {
            $fail("The {$attribute} contains internationalized characters which are not allowed.");
            return;
        }

        // Check for dangerous IDN characters even if IDN is allowed
        if ($this->containsDangerousIdnCharacters($value)) {
            $fail("The {$attribute} contains potentially malicious characters.");
            return;
        }

        // Validate TLD
        if ($this->requireValidTld && !$this->hasValidTld($value)) {
            $fail("The {$attribute} must have a valid top-level domain.");
            return;
        }

        // Check for punycode injection
        if ($this->hasPunycodeInjection($value)) {
            $fail("The {$attribute} contains invalid punycode encoding.");
            return;
        }

        // Check length constraints per RFC 1035
        if (!$this->hasValidLength($value)) {
            $fail("The {$attribute} exceeds maximum domain length.");
            return;
        }
    }

    /**
     * Check if domain has valid basic format.
     *
     * RFC 1035 compliant validation:
     * - Labels separated by dots
     * - Labels start and end with alphanumeric
     * - Labels may contain hyphens (not at start/end)
     * - At least one dot (TLD required)
     *
     * @param string $domain Domain name
     * @return bool True if valid format
     */
    protected function isValidFormat(string $domain): bool
    {
        // Must contain at least one dot
        if (!str_contains($domain, '.')) {
            return false;
        }

        // Check overall format
        $pattern = '/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$/i';

        return (bool) preg_match($pattern, $domain);
    }

    /**
     * Check if domain contains internationalized characters.
     *
     * @param string $domain Domain name
     * @return bool True if contains non-ASCII characters
     */
    protected function containsIdnCharacters(string $domain): bool
    {
        return !mb_check_encoding($domain, 'ASCII');
    }

    /**
     * Check for dangerous IDN characters (homograph attack).
     *
     * SECURITY: Detects look-alike characters used in phishing
     *
     * @param string $domain Domain name
     * @return bool True if contains dangerous characters
     */
    protected function containsDangerousIdnCharacters(string $domain): bool
    {
        foreach ($this->dangerousIdnCharacters as $char) {
            if (str_contains($domain, $char)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Check if domain has valid TLD.
     *
     * Validates against list of known TLDs.
     *
     * @param string $domain Domain name
     * @return bool True if has valid TLD
     */
    protected function hasValidTld(string $domain): bool
    {
        $parts = explode('.', $domain);

        if (count($parts) < 2) {
            return false;
        }

        $tld = strtolower(end($parts));

        // Common valid TLDs
        $validTlds = [
            'com', 'net', 'org', 'edu', 'gov', 'mil', 'int',
            'info', 'biz', 'name', 'pro', 'aero', 'coop', 'museum',
            'io', 'co', 'app', 'dev', 'tech', 'digital', 'cloud',
            'ai', 'me', 'tv', 'cc', 'ws', 'us', 'uk', 'ca', 'au',
            'de', 'fr', 'it', 'es', 'nl', 'ru', 'cn', 'jp', 'br',
        ];

        return in_array($tld, $validTlds, true);
    }

    /**
     * Check for punycode injection attempts.
     *
     * SECURITY: Detects malformed punycode that could bypass filters
     *
     * @param string $domain Domain name
     * @return bool True if punycode injection detected
     */
    protected function hasPunycodeInjection(string $domain): bool
    {
        // Check for xn-- prefix (punycode indicator)
        if (!str_contains($domain, 'xn--')) {
            return false;
        }

        // Attempt to decode each punycode label
        $labels = explode('.', $domain);

        foreach ($labels as $label) {
            if (str_starts_with($label, 'xn--')) {
                // Try to decode punycode
                $decoded = idn_to_utf8($label, IDNA_DEFAULT, INTL_IDNA_VARIANT_UTS46);

                // If decoding fails, it's malformed punycode
                if ($decoded === false) {
                    return true;
                }

                // Check if decoded contains dangerous characters
                if ($this->containsDangerousIdnCharacters($decoded)) {
                    return true;
                }
            }
        }

        return false;
    }

    /**
     * Check if domain length is within RFC limits.
     *
     * RFC 1035:
     * - Total domain length: 253 characters
     * - Label length: 63 characters
     *
     * @param string $domain Domain name
     * @return bool True if valid length
     */
    protected function hasValidLength(string $domain): bool
    {
        // Total domain length
        if (strlen($domain) > 253) {
            return false;
        }

        // Check each label
        $labels = explode('.', $domain);

        foreach ($labels as $label) {
            if (strlen($label) > 63) {
                return false;
            }

            // Labels must be at least 1 character
            if (strlen($label) < 1) {
                return false;
            }
        }

        return true;
    }
}
