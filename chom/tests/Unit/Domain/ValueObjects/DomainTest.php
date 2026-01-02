<?php

namespace Tests\Unit\Domain\ValueObjects;

use App\Domain\ValueObjects\Domain;
use InvalidArgumentException;
use PHPUnit\Framework\TestCase;
use PHPUnit\Framework\Attributes\Test;

class DomainTest extends TestCase
{
    #[Test]
    public function it_creates_valid_domain_from_string(): void
    {
        $domain = Domain::fromString('my-site.com');

        $this->assertEquals('my-site.com', $domain->toString());
        $this->assertEquals('my-site.com', (string) $domain);
    }

    #[Test]
    public function it_converts_domain_to_lowercase(): void
    {
        $domain = Domain::fromString('MY-SITE.COM');

        $this->assertEquals('my-site.com', $domain->toString());
    }

    #[Test]
    public function it_extracts_tld(): void
    {
        $domain = Domain::fromString('my-site.com');

        $this->assertEquals('com', $domain->getTld());
    }

    #[Test]
    public function it_extracts_domain_without_tld(): void
    {
        $domain = Domain::fromString('my-site.com');

        $this->assertEquals('my-site', $domain->getWithoutTld());
    }

    #[Test]
    public function it_detects_subdomain(): void
    {
        $domain = Domain::fromString('blog.my-site.com');

        $this->assertTrue($domain->isSubdomain());
        $this->assertEquals('blog', $domain->getSubdomain());
    }

    #[Test]
    public function it_detects_non_subdomain(): void
    {
        $domain = Domain::fromString('my-site.com');

        $this->assertFalse($domain->isSubdomain());
        $this->assertNull($domain->getSubdomain());
    }

    #[Test]
    public function it_compares_domains_for_equality(): void
    {
        $domain1 = Domain::fromString('my-site.com');
        $domain2 = Domain::fromString('my-site.com');
        $domain3 = Domain::fromString('different.com');

        $this->assertTrue($domain1->equals($domain2));
        $this->assertFalse($domain1->equals($domain3));
    }

    #[Test]
    public function it_rejects_too_long_domain(): void
    {
        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('Domain name too long');

        Domain::fromString(str_repeat('a', 254).'.com');
    }

    #[Test]
    public function it_rejects_too_short_domain(): void
    {
        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('Domain name too short');

        Domain::fromString('a');
    }

    #[Test]
    public function it_rejects_invalid_format(): void
    {
        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('Invalid domain format');

        Domain::fromString('not a domain');
    }

    #[Test]
    public function it_rejects_sql_injection_attempts(): void
    {
        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('Invalid domain format');

        Domain::fromString("my-site.com'; DROP TABLE users--");
    }

    #[Test]
    public function it_rejects_reserved_domains(): void
    {
        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('Reserved domain name:');

        Domain::fromString('localhost');
    }

    #[Test]
    public function it_validates_domain_without_exception(): void
    {
        $this->assertTrue(Domain::isValid('my-site.com'));
        $this->assertFalse(Domain::isValid('invalid domain'));
        $this->assertFalse(Domain::isValid('localhost'));
    }
}
