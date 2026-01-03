<?php

declare(strict_types=1);

namespace Tests\Unit\Rules;

use App\Rules\DomainNameRule;
use Tests\TestCase;

/**
 * Domain Name Rule Test
 *
 * Tests domain validation including:
 * - RFC compliance
 * - IDN homograph attack detection
 * - Punycode validation
 * - TLD validation
 *
 * @package Tests\Unit\Rules
 */
class DomainNameRuleTest extends TestCase
{
    /**
     * Test valid domain names.
     *
     * @dataProvider validDomainsProvider
     */
    public function test_valid_domains(string $domain): void
    {
        $rule = new DomainNameRule();
        $passes = true;

        $rule->validate('domain', $domain, function ($message) use (&$passes) {
            $passes = false;
        });

        $this->assertTrue($passes, "Domain {$domain} should be valid");
    }

    /**
     * Test invalid domain names.
     *
     * @dataProvider invalidDomainsProvider
     */
    public function test_invalid_domains(string $domain): void
    {
        $rule = new DomainNameRule();
        $passes = true;

        $rule->validate('domain', $domain, function ($message) use (&$passes) {
            $passes = false;
        });

        $this->assertFalse($passes, "Domain {$domain} should be invalid");
    }

    /**
     * Test IDN character detection.
     */
    public function test_idn_character_detection(): void
    {
        $rule = new DomainNameRule(allowIdn: false);
        $passes = true;

        $rule->validate('domain', 'тест.com', function ($message) use (&$passes) {
            $passes = false;
        });

        $this->assertFalse($passes, 'Cyrillic characters should be rejected when IDN is disabled');
    }

    /**
     * Test dangerous IDN character detection.
     */
    public function test_dangerous_idn_characters(): void
    {
        $rule = new DomainNameRule(allowIdn: true);
        $passes = true;

        // Cyrillic 'а' looks like Latin 'a'
        $rule->validate('domain', 'pаypal.com', function ($message) use (&$passes) {
            $passes = false;
        });

        $this->assertFalse($passes, 'Dangerous IDN characters should be rejected');
    }

    /**
     * Test TLD validation.
     */
    public function test_tld_validation(): void
    {
        $rule = new DomainNameRule(requireValidTld: true);
        $passes = true;

        $rule->validate('domain', 'example.invalidtld', function ($message) use (&$passes) {
            $passes = false;
        });

        $this->assertFalse($passes, 'Invalid TLD should be rejected');
    }

    /**
     * Test domain length limits.
     */
    public function test_domain_length_limits(): void
    {
        $rule = new DomainNameRule();

        // Total domain length > 253 characters
        $longDomain = str_repeat('a', 250) . '.com';
        $passes = true;

        $rule->validate('domain', $longDomain, function ($message) use (&$passes) {
            $passes = false;
        });

        $this->assertFalse($passes, 'Domain exceeding max length should be rejected');
    }

    /**
     * Test label length limits.
     */
    public function test_label_length_limits(): void
    {
        $rule = new DomainNameRule();

        // Label length > 63 characters
        $longLabel = str_repeat('a', 64) . '.com';
        $passes = true;

        $rule->validate('domain', $longLabel, function ($message) use (&$passes) {
            $passes = false;
        });

        $this->assertFalse($passes, 'Label exceeding max length should be rejected');
    }

    /**
     * Provide valid domain names.
     */
    public static function validDomainsProvider(): array
    {
        return [
            ['example.com'],
            ['subdomain.example.com'],
            ['test-domain.co.uk'],
            ['123.456.789.com'],
            ['a.b.c.d.example.com'],
        ];
    }

    /**
     * Provide invalid domain names.
     */
    public static function invalidDomainsProvider(): array
    {
        return [
            ['example'], // No TLD
            ['-example.com'], // Starts with hyphen
            ['example-.com'], // Ends with hyphen
            ['example..com'], // Double dot
            ['.example.com'], // Starts with dot
            ['example.com.'], // Ends with dot
        ];
    }
}
