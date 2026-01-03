<?php

declare(strict_types=1);

namespace Tests\Unit\Rules;

use App\Rules\DomainNameRule;
use Tests\TestCase;

class DomainNameRuleTest extends TestCase
{
    private DomainNameRule $rule;

    protected function setUp(): void
    {
        parent::setUp();
        $this->rule = new DomainNameRule();
    }

    public function test_accepts_valid_domain_names(): void
    {
        $validDomains = [
            'example.com',
            'subdomain.example.com',
            'deep.subdomain.example.com',
            'test-site.com',
            'site123.com',
            'example.co.uk',
            'test.io',
            'my-awesome-site.dev',
        ];

        foreach ($validDomains as $domain) {
            $this->assertTrue(
                $this->rule->passes('domain', $domain),
                "Failed to accept valid domain: {$domain}"
            );
        }
    }

    public function test_rejects_invalid_domain_names(): void
    {
        $invalidDomains = [
            '',
            ' ',
            'invalid domain.com',
            'example..com',
            '.example.com',
            'example.com.',
            '-example.com',
            'example-.com',
            'exam ple.com',
            'exam@ple.com',
            'example.c',
        ];

        foreach ($invalidDomains as $domain) {
            $this->assertFalse(
                $this->rule->passes('domain', $domain),
                "Failed to reject invalid domain: {$domain}"
            );
        }
    }

    public function test_rejects_domains_with_special_characters(): void
    {
        $invalidDomains = [
            'example!.com',
            'exam#ple.com',
            'example$.com',
            'example%.com',
            'example^.com',
            'example&.com',
            'example*.com',
            'example(.com',
            'example).com',
        ];

        foreach ($invalidDomains as $domain) {
            $this->assertFalse($this->rule->passes('domain', $domain));
        }
    }

    public function test_accepts_internationalized_domain_names(): void
    {
        $validIDNs = [
            'münchen.de',
            'españa.es',
            'москва.рф',
        ];

        foreach ($validIDNs as $domain) {
            $this->assertTrue(
                $this->rule->passes('domain', $domain),
                "Failed to accept valid IDN: {$domain}"
            );
        }
    }

    public function test_rejects_domains_exceeding_max_length(): void
    {
        // Max domain length is 253 characters
        $longDomain = str_repeat('a', 250) . '.com';

        $this->assertFalse($this->rule->passes('domain', $longDomain));
    }

    public function test_rejects_labels_exceeding_63_characters(): void
    {
        // Each label (part between dots) max 63 characters
        $longLabel = str_repeat('a', 64) . '.example.com';

        $this->assertFalse($this->rule->passes('domain', $longLabel));
    }

    public function test_accepts_domains_with_numbers(): void
    {
        $validDomains = [
            '123.com',
            'site123.com',
            '123-site.com',
            'site-123.com',
        ];

        foreach ($validDomains as $domain) {
            $this->assertTrue($this->rule->passes('domain', $domain));
        }
    }

    public function test_rejects_domains_starting_with_number_only_tld(): void
    {
        $this->assertFalse($this->rule->passes('domain', 'example.123'));
    }

    public function test_rejects_localhost(): void
    {
        $this->assertFalse($this->rule->passes('domain', 'localhost'));
    }

    public function test_rejects_ip_addresses(): void
    {
        $ipAddresses = [
            '192.168.1.1',
            '10.0.0.1',
            '127.0.0.1',
            '2001:0db8:85a3:0000:0000:8a2e:0370:7334',
        ];

        foreach ($ipAddresses as $ip) {
            $this->assertFalse(
                $this->rule->passes('domain', $ip),
                "Should reject IP address: {$ip}"
            );
        }
    }

    public function test_rejects_domains_with_protocol(): void
    {
        $domainsWithProtocol = [
            'http://example.com',
            'https://example.com',
            'ftp://example.com',
        ];

        foreach ($domainsWithProtocol as $domain) {
            $this->assertFalse($this->rule->passes('domain', $domain));
        }
    }

    public function test_rejects_domains_with_paths(): void
    {
        $domainsWithPaths = [
            'example.com/path',
            'example.com/path/to/page',
            'example.com?query=value',
        ];

        foreach ($domainsWithPaths as $domain) {
            $this->assertFalse($this->rule->passes('domain', $domain));
        }
    }

    public function test_accepts_punycode_domains(): void
    {
        // Punycode representation of internationalized domains
        $punycodeDomains = [
            'xn--mnchen-3ya.de',
            'xn--espaa-rta.es',
        ];

        foreach ($punycodeDomains as $domain) {
            $this->assertTrue($this->rule->passes('domain', $domain));
        }
    }

    public function test_returns_correct_error_message(): void
    {
        $this->rule->passes('domain', 'invalid domain');

        $message = $this->rule->message();

        $this->assertIsString($message);
        $this->assertStringContainsString('domain', strtolower($message));
        $this->assertStringContainsString('valid', strtolower($message));
    }

    public function test_handles_null_value(): void
    {
        $this->assertFalse($this->rule->passes('domain', null));
    }

    public function test_handles_numeric_value(): void
    {
        $this->assertFalse($this->rule->passes('domain', 12345));
    }

    public function test_handles_array_value(): void
    {
        $this->assertFalse($this->rule->passes('domain', ['example.com']));
    }

    public function test_rejects_reserved_domains(): void
    {
        $reservedDomains = [
            'example.com',
            'example.org',
            'example.net',
            'test.com',
            'invalid.com',
        ];

        $rule = new DomainNameRule(['reject_reserved' => true]);

        foreach ($reservedDomains as $domain) {
            $this->assertFalse(
                $rule->passes('domain', $domain),
                "Should reject reserved domain: {$domain}"
            );
        }
    }

    public function test_accepts_all_valid_tlds(): void
    {
        $validTLDs = [
            'example.com',
            'example.net',
            'example.org',
            'example.io',
            'example.dev',
            'example.app',
            'example.ai',
            'example.co',
        ];

        foreach ($validTLDs as $domain) {
            $this->assertTrue($this->rule->passes('domain', $domain));
        }
    }

    public function test_validates_subdomain_depth(): void
    {
        $deepSubdomain = 'a.b.c.d.e.f.g.h.i.j.example.com';

        // Should accept reasonable subdomain depth
        $this->assertTrue($this->rule->passes('domain', $deepSubdomain));
    }

    public function test_performance_with_many_validations(): void
    {
        $domains = array_merge(
            array_fill(0, 50, 'valid-domain.com'),
            array_fill(0, 50, 'invalid domain.com')
        );

        $startTime = microtime(true);

        foreach ($domains as $domain) {
            $this->rule->passes('domain', $domain);
        }

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // 100 validations should complete in under 50ms
        $this->assertLessThan(50, $duration);
    }
}
