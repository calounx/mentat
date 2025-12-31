<?php

namespace Tests\Unit\Domain\ValueObjects;

use App\Domain\ValueObjects\Domain;
use InvalidArgumentException;
use PHPUnit\Framework\TestCase;

class DomainTest extends TestCase
{
    /** @test */
    public function it_creates_valid_domain_from_string(): void
    {
        $domain = Domain::fromString('example.com');

        $this->assertEquals('example.com', $domain->toString());
        $this->assertEquals('example.com', (string) $domain);
    }

    /** @test */
    public function it_converts_domain_to_lowercase(): void
    {
        $domain = Domain::fromString('EXAMPLE.COM');

        $this->assertEquals('example.com', $domain->toString());
    }

    /** @test */
    public function it_extracts_tld(): void
    {
        $domain = Domain::fromString('example.com');

        $this->assertEquals('com', $domain->getTld());
    }

    /** @test */
    public function it_extracts_domain_without_tld(): void
    {
        $domain = Domain::fromString('example.com');

        $this->assertEquals('example', $domain->getWithoutTld());
    }

    /** @test */
    public function it_detects_subdomain(): void
    {
        $domain = Domain::fromString('blog.example.com');

        $this->assertTrue($domain->isSubdomain());
        $this->assertEquals('blog', $domain->getSubdomain());
    }

    /** @test */
    public function it_detects_non_subdomain(): void
    {
        $domain = Domain::fromString('example.com');

        $this->assertFalse($domain->isSubdomain());
        $this->assertNull($domain->getSubdomain());
    }

    /** @test */
    public function it_compares_domains_for_equality(): void
    {
        $domain1 = Domain::fromString('example.com');
        $domain2 = Domain::fromString('example.com');
        $domain3 = Domain::fromString('different.com');

        $this->assertTrue($domain1->equals($domain2));
        $this->assertFalse($domain1->equals($domain3));
    }

    /** @test */
    public function it_rejects_too_long_domain(): void
    {
        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('Domain name too long');

        Domain::fromString(str_repeat('a', 254) . '.com');
    }

    /** @test */
    public function it_rejects_too_short_domain(): void
    {
        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('Domain name too short');

        Domain::fromString('a');
    }

    /** @test */
    public function it_rejects_invalid_format(): void
    {
        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('Invalid domain format');

        Domain::fromString('not a domain');
    }

    /** @test */
    public function it_rejects_sql_injection_attempts(): void
    {
        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('suspicious characters');

        Domain::fromString("example.com'; DROP TABLE users--");
    }

    /** @test */
    public function it_rejects_reserved_domains(): void
    {
        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('Reserved domain name');

        Domain::fromString('localhost');
    }

    /** @test */
    public function it_validates_domain_without_exception(): void
    {
        $this->assertTrue(Domain::isValid('example.com'));
        $this->assertFalse(Domain::isValid('invalid domain'));
        $this->assertFalse(Domain::isValid('localhost'));
    }
}
