<?php

namespace Tests\Unit\Services;

use App\Services\Sites\Provisioners\HtmlSiteProvisioner;
use App\Services\Sites\Provisioners\LaravelSiteProvisioner;
use App\Services\Sites\Provisioners\ProvisionerFactory;
use App\Services\Sites\Provisioners\WordPressSiteProvisioner;
use InvalidArgumentException;
use Tests\TestCase;

class ProvisionerFactoryTest extends TestCase
{
    private ProvisionerFactory $factory;

    protected function setUp(): void
    {
        parent::setUp();
        $this->factory = new ProvisionerFactory;
    }

    /** @test */
    public function it_creates_wordpress_provisioner(): void
    {
        $provisioner = $this->factory->make('wordpress');

        $this->assertInstanceOf(WordPressSiteProvisioner::class, $provisioner);
        $this->assertEquals('wordpress', $provisioner->getSiteType());
    }

    /** @test */
    public function it_creates_html_provisioner(): void
    {
        $provisioner = $this->factory->make('html');

        $this->assertInstanceOf(HtmlSiteProvisioner::class, $provisioner);
        $this->assertEquals('html', $provisioner->getSiteType());
    }

    /** @test */
    public function it_creates_laravel_provisioner(): void
    {
        $provisioner = $this->factory->make('laravel');

        $this->assertInstanceOf(LaravelSiteProvisioner::class, $provisioner);
        $this->assertEquals('laravel', $provisioner->getSiteType());
    }

    /** @test */
    public function it_throws_exception_for_unsupported_type(): void
    {
        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('Unsupported site type: unknown');

        $this->factory->make('unknown');
    }

    /** @test */
    public function it_returns_supported_types(): void
    {
        $types = $this->factory->getSupportedTypes();

        $this->assertIsArray($types);
        $this->assertContains('wordpress', $types);
        $this->assertContains('html', $types);
        $this->assertContains('laravel', $types);
    }

    /** @test */
    public function it_checks_if_type_is_supported(): void
    {
        $this->assertTrue($this->factory->supports('wordpress'));
        $this->assertTrue($this->factory->supports('html'));
        $this->assertTrue($this->factory->supports('laravel'));
        $this->assertFalse($this->factory->supports('unknown'));
    }

    /** @test */
    public function it_returns_all_provisioners(): void
    {
        $provisioners = $this->factory->all();

        $this->assertIsArray($provisioners);
        $this->assertArrayHasKey('wordpress', $provisioners);
        $this->assertArrayHasKey('html', $provisioners);
        $this->assertArrayHasKey('laravel', $provisioners);

        $this->assertInstanceOf(WordPressSiteProvisioner::class, $provisioners['wordpress']);
        $this->assertInstanceOf(HtmlSiteProvisioner::class, $provisioners['html']);
        $this->assertInstanceOf(LaravelSiteProvisioner::class, $provisioners['laravel']);
    }
}
