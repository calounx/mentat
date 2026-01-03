<?php

declare(strict_types=1);

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

/**
 * Secure Email Validation Rule
 *
 * Validates email addresses with protection against:
 * - Invalid RFC 5322 format
 * - Disposable email services
 * - Role-based emails (optional)
 * - Plus addressing abuse (optional)
 *
 * OWASP Reference: A03:2021 – Injection
 * Protection: Prevents email-based attacks and abuse
 *
 * @package App\Rules
 */
class SecureEmailRule implements ValidationRule
{
    /**
     * Block disposable email providers.
     */
    protected bool $blockDisposable;

    /**
     * Block role-based emails (admin@, noreply@, etc.).
     */
    protected bool $blockRoleBased;

    /**
     * Block plus addressing (user+tag@domain.com).
     */
    protected bool $blockPlusAddressing;

    /**
     * Common disposable email domains.
     */
    protected array $disposableDomains = [
        'tempmail.com', 'guerrillamail.com', '10minutemail.com',
        'mailinator.com', 'throwaway.email', 'temp-mail.org',
        'yopmail.com', 'trashmail.com', 'maildrop.cc',
        'getnada.com', 'fakeinbox.com', 'sharklasers.com',
    ];

    /**
     * Role-based email prefixes.
     */
    protected array $roleBasedPrefixes = [
        'admin', 'administrator', 'noreply', 'no-reply',
        'postmaster', 'hostmaster', 'webmaster', 'abuse',
        'security', 'info', 'support', 'sales', 'marketing',
    ];

    /**
     * Create a new rule instance.
     *
     * @param bool $blockDisposable Block disposable email providers
     * @param bool $blockRoleBased Block role-based emails
     * @param bool $blockPlusAddressing Block plus addressing
     */
    public function __construct(
        bool $blockDisposable = true,
        bool $blockRoleBased = false,
        bool $blockPlusAddressing = false
    ) {
        $this->blockDisposable = $blockDisposable;
        $this->blockRoleBased = $blockRoleBased;
        $this->blockPlusAddressing = $blockPlusAddressing;
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
            $fail("The {$attribute} must be a valid email address.");
            return;
        }

        // Validate RFC 5322 format
        if (!$this->isValidFormat($value)) {
            $fail("The {$attribute} must be a valid email address.");
            return;
        }

        // Extract parts
        [$localPart, $domain] = explode('@', $value);

        // Check for disposable email providers
        if ($this->blockDisposable && $this->isDisposableEmail($domain)) {
            $fail("The {$attribute} cannot be from a disposable email provider.");
            return;
        }

        // Check for role-based emails
        if ($this->blockRoleBased && $this->isRoleBasedEmail($localPart)) {
            $fail("The {$attribute} cannot be a role-based email address.");
            return;
        }

        // Check for plus addressing
        if ($this->blockPlusAddressing && $this->hasPlusAddressing($localPart)) {
            $fail("The {$attribute} cannot contain plus addressing.");
            return;
        }

        // Check for suspicious patterns
        if ($this->hasSuspiciousPattern($value)) {
            $fail("The {$attribute} contains suspicious patterns.");
            return;
        }
    }

    /**
     * Check if email has valid RFC 5322 format.
     *
     * @param string $email Email address
     * @return bool True if valid
     */
    protected function isValidFormat(string $email): bool
    {
        // Use filter_var for RFC 5322 compliance
        if (filter_var($email, FILTER_VALIDATE_EMAIL) === false) {
            return false;
        }

        // Additional checks for @ and domain
        if (!str_contains($email, '@')) {
            return false;
        }

        [$localPart, $domain] = explode('@', $email, 2);

        // Local part checks
        if (strlen($localPart) === 0 || strlen($localPart) > 64) {
            return false;
        }

        // Domain checks
        if (strlen($domain) === 0 || strlen($domain) > 255) {
            return false;
        }

        // Domain must have at least one dot
        if (!str_contains($domain, '.')) {
            return false;
        }

        return true;
    }

    /**
     * Check if email is from disposable provider.
     *
     * SECURITY: Prevents abuse via temporary email addresses
     *
     * @param string $domain Email domain
     * @return bool True if disposable
     */
    protected function isDisposableEmail(string $domain): bool
    {
        $domain = strtolower($domain);

        // Check exact match
        if (in_array($domain, $this->disposableDomains, true)) {
            return true;
        }

        // Check if subdomain of disposable provider
        foreach ($this->disposableDomains as $disposable) {
            if (str_ends_with($domain, '.' . $disposable)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Check if email is role-based.
     *
     * @param string $localPart Local part of email
     * @return bool True if role-based
     */
    protected function isRoleBasedEmail(string $localPart): bool
    {
        $localPart = strtolower($localPart);

        // Remove plus addressing for check
        if (str_contains($localPart, '+')) {
            $localPart = explode('+', $localPart)[0];
        }

        return in_array($localPart, $this->roleBasedPrefixes, true);
    }

    /**
     * Check if email uses plus addressing.
     *
     * Plus addressing: user+tag@domain.com
     *
     * @param string $localPart Local part of email
     * @return bool True if uses plus addressing
     */
    protected function hasPlusAddressing(string $localPart): bool
    {
        return str_contains($localPart, '+');
    }

    /**
     * Check for suspicious patterns.
     *
     * SECURITY: Detects potential injection attempts
     *
     * @param string $email Email address
     * @return bool True if suspicious
     */
    protected function hasSuspiciousPattern(string $email): bool
    {
        // Check for multiple @ symbols
        if (substr_count($email, '@') > 1) {
            return true;
        }

        // Check for SQL injection patterns
        $sqlPatterns = ['\'', '"', '--', '/*', '*/', ';'];

        foreach ($sqlPatterns as $pattern) {
            if (str_contains($email, $pattern)) {
                return true;
            }
        }

        // Check for script tags
        if (preg_match('/<script|javascript:/i', $email)) {
            return true;
        }

        // Check for null bytes
        if (str_contains($email, "\0")) {
            return true;
        }

        return false;
    }
}
