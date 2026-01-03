<?php

declare(strict_types=1);

namespace Tests\Unit\Infrastructure\Vps;

use App\Infrastructure\Vps\LocalVpsProvider;
use App\ValueObjects\ServerStatus;
use App\ValueObjects\VpsSpecification;
use PHPUnit\Framework\TestCase;

/**
 * Local VPS Provider Tests
 *
 * Tests LocalVpsProvider implementation.
 *
 * @package Tests\Unit\Infrastructure\Vps
 */
class LocalVpsProviderTest extends TestCase
{
    private LocalVpsProvider $provider;

    protected function setUp(): void
    {
        parent::setUp();
        $this->provider = new LocalVpsProvider(useDocker: false);
    }

    public function test_creates_server(): void
    {
        $spec = VpsSpecification::small();

        $server = $this->provider->createServer($spec);

        $this->assertIsArray($server);
        $this->assertArrayHasKey('id', $server);
        $this->assertArrayHasKey('ip_address', $server);
        $this->assertArrayHasKey('status', $server);
        $this->assertSame(ServerStatus::STATUS_ONLINE, $server['status']);
    }

    public function test_deletes_server(): void
    {
        $spec = VpsSpecification::small();
        $server = $this->provider->createServer($spec);

        $result = $this->provider->deleteServer($server['id']);

        $this->assertTrue($result);
    }

    public function test_gets_server_status(): void
    {
        $spec = VpsSpecification::small();
        $server = $this->provider->createServer($spec);

        $status = $this->provider->getServerStatus($server['id']);

        $this->assertInstanceOf(ServerStatus::class, $status);
        $this->assertTrue($status->isOnline());
    }

    public function test_checks_server_reachability(): void
    {
        $spec = VpsSpecification::small();
        $server = $this->provider->createServer($spec);

        $reachable = $this->provider->isServerReachable($server['id']);

        $this->assertTrue($reachable);
    }

    public function test_gets_server_metrics(): void
    {
        $spec = VpsSpecification::small();
        $server = $this->provider->createServer($spec);

        $metrics = $this->provider->getServerMetrics($server['id']);

        $this->assertIsArray($metrics);
        $this->assertArrayHasKey('cpu_usage_percent', $metrics);
        $this->assertArrayHasKey('ram_usage_mb', $metrics);
        $this->assertArrayHasKey('disk_usage_gb', $metrics);
    }

    public function test_executes_command(): void
    {
        $spec = VpsSpecification::small();
        $server = $this->provider->createServer($spec);

        $result = $this->provider->executeCommand($server['id'], 'echo "test"');

        $this->assertTrue($result->isSuccessful());
        $this->assertSame(0, $result->exitCode);
    }

    public function test_provider_name(): void
    {
        $this->assertSame('local', $this->provider->getProviderName());
    }
}
