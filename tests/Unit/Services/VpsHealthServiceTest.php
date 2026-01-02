<?php

namespace Tests\Unit\Services;

use App\Models\VpsServer;
use App\Services\VPS\VpsHealthService;
use App\Services\VPS\VpsConnectionManager;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Mockery;
use Tests\TestCase;

/**
 * VPS Health Service Test
 *
 * Tests comprehensive health checking functionality for VPS servers including:
 * - System resource monitoring
 * - Service availability checks
 * - Performance metrics collection
 * - Alert threshold validation
 */
class VpsHealthServiceTest extends TestCase
{
    use RefreshDatabase;

    private VpsHealthService $healthService;
    private $mockConnectionManager;

    protected function setUp(): void
    {
        parent::setUp();

        $this->mockConnectionManager = Mockery::mock(VpsConnectionManager::class);
        $this->healthService = new VpsHealthService($this->mockConnectionManager);
    }

    protected function tearDown(): void
    {
        Mockery::close();
        parent::tearDown();
    }

    public function test_checks_vps_cpu_usage(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->with($vps, Mockery::pattern('/top|mpstat/'))
            ->andReturn(['stdout' => '25.5', 'exit_code' => 0]);

        $health = $this->healthService->checkHealth($vps);

        $this->assertArrayHasKey('cpu_usage', $health);
        $this->assertLessThan(100, $health['cpu_usage']);
        $this->assertEquals('healthy', $health['status']);
    }

    public function test_checks_vps_memory_usage(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->with($vps, Mockery::pattern('/free|vmstat/'))
            ->andReturn([
                'stdout' => 'Mem: 8192 4096 4096',
                'exit_code' => 0,
            ]);

        $health = $this->healthService->checkHealth($vps);

        $this->assertArrayHasKey('memory_usage', $health);
        $this->assertArrayHasKey('memory_total', $health);
        $this->assertArrayHasKey('memory_used', $health);
    }

    public function test_checks_vps_disk_usage(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->with($vps, 'df -h /')
            ->andReturn([
                'stdout' => 'Filesystem Size Used Avail Use% Mounted
                            /dev/sda1 100G 45G 55G 45% /',
                'exit_code' => 0,
            ]);

        $health = $this->healthService->checkHealth($vps);

        $this->assertArrayHasKey('disk_usage', $health);
        $this->assertLessThan(100, $health['disk_usage']);
    }

    public function test_checks_nginx_service_status(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->with($vps, 'systemctl is-active nginx')
            ->andReturn(['stdout' => 'active', 'exit_code' => 0]);

        $health = $this->healthService->checkServiceHealth($vps, 'nginx');

        $this->assertTrue($health['nginx']['running']);
        $this->assertEquals('active', $health['nginx']['status']);
    }

    public function test_checks_mysql_service_status(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->with($vps, Mockery::pattern('/systemctl.*mysql/'))
            ->andReturn(['stdout' => 'active', 'exit_code' => 0]);

        $health = $this->healthService->checkServiceHealth($vps, 'mysql');

        $this->assertTrue($health['mysql']['running']);
    }

    public function test_detects_high_cpu_usage(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->andReturn(['stdout' => '95.5', 'exit_code' => 0]);

        $health = $this->healthService->checkHealth($vps);

        $this->assertEquals('warning', $health['status']);
        $this->assertArrayHasKey('alerts', $health);
        $this->assertStringContainsString('CPU', $health['alerts'][0]);
    }

    public function test_detects_high_memory_usage(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->andReturn([
                'stdout' => 'Mem: 8192 7800 392',
                'exit_code' => 0,
            ]);

        $health = $this->healthService->checkHealth($vps);

        $this->assertEquals('warning', $health['status']);
        $this->assertStringContainsString('Memory', implode('', $health['alerts']));
    }

    public function test_detects_high_disk_usage(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->andReturn([
                'stdout' => '/dev/sda1 100G 92G 8G 92% /',
                'exit_code' => 0,
            ]);

        $health = $this->healthService->checkHealth($vps);

        $this->assertEquals('warning', $health['status']);
        $this->assertStringContainsString('Disk', implode('', $health['alerts']));
    }

    public function test_detects_stopped_service(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->with($vps, Mockery::pattern('/systemctl.*nginx/'))
            ->andReturn(['stdout' => 'inactive', 'exit_code' => 3]);

        $health = $this->healthService->checkServiceHealth($vps, 'nginx');

        $this->assertFalse($health['nginx']['running']);
        $this->assertEquals('critical', $health['status']);
    }

    public function test_checks_network_connectivity(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->with($vps, 'ping -c 4 8.8.8.8')
            ->andReturn([
                'stdout' => '4 packets transmitted, 4 received, 0% packet loss',
                'exit_code' => 0,
            ]);

        $health = $this->healthService->checkNetworkHealth($vps);

        $this->assertTrue($health['network']['connected']);
        $this->assertEquals(0, $health['network']['packet_loss']);
    }

    public function test_handles_ssh_connection_failure(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->andThrow(new \RuntimeException('SSH connection failed'));

        $health = $this->healthService->checkHealth($vps);

        $this->assertEquals('critical', $health['status']);
        $this->assertStringContainsString('connection', $health['error']);
    }

    public function test_aggregates_multiple_health_checks(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->andReturn(['stdout' => '25.5', 'exit_code' => 0])
            ->andReturn(['stdout' => 'Mem: 8192 4096 4096', 'exit_code' => 0])
            ->andReturn(['stdout' => '/dev/sda1 100G 45G 55G 45% /', 'exit_code' => 0]);

        $health = $this->healthService->checkHealth($vps);

        $this->assertArrayHasKey('cpu_usage', $health);
        $this->assertArrayHasKey('memory_usage', $health);
        $this->assertArrayHasKey('disk_usage', $health);
        $this->assertEquals('healthy', $health['status']);
    }

    public function test_caches_health_check_results(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->once()
            ->andReturn(['stdout' => '25.5', 'exit_code' => 0]);

        // First call
        $health1 = $this->healthService->checkHealth($vps, cache: true);

        // Second call should use cache
        $health2 = $this->healthService->checkHealth($vps, cache: true);

        $this->assertEquals($health1, $health2);
    }

    public function test_respects_cache_ttl(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->twice()
            ->andReturn(['stdout' => '25.5', 'exit_code' => 0]);

        $this->healthService->checkHealth($vps, cache: true, ttl: 1);

        sleep(2);

        // Cache should have expired
        $this->healthService->checkHealth($vps, cache: true, ttl: 1);

        $this->assertTrue(true); // If we get here, second call was made
    }

    public function test_checks_load_average(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->with($vps, Mockery::pattern('/uptime|cat \/proc\/loadavg/'))
            ->andReturn([
                'stdout' => 'load average: 1.23, 1.45, 1.67',
                'exit_code' => 0,
            ]);

        $health = $this->healthService->checkHealth($vps);

        $this->assertArrayHasKey('load_average', $health);
        $this->assertIsArray($health['load_average']);
        $this->assertCount(3, $health['load_average']);
    }

    public function test_provides_uptime_information(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->with($vps, 'uptime -p')
            ->andReturn([
                'stdout' => 'up 15 days, 3 hours, 45 minutes',
                'exit_code' => 0,
            ]);

        $health = $this->healthService->checkHealth($vps);

        $this->assertArrayHasKey('uptime', $health);
        $this->assertStringContainsString('days', $health['uptime']);
    }

    public function test_validates_health_status_levels(): void
    {
        $vps = VpsServer::factory()->create();

        // Test healthy status
        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->andReturn(['stdout' => '25.5', 'exit_code' => 0]);

        $health = $this->healthService->checkHealth($vps);
        $this->assertEquals('healthy', $health['status']);

        // Test warning status (high usage but not critical)
        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->andReturn(['stdout' => '85.0', 'exit_code' => 0]);

        $health = $this->healthService->checkHealth($vps);
        $this->assertEquals('warning', $health['status']);
    }

    public function test_generates_health_report(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->andReturn(['stdout' => '25.5', 'exit_code' => 0]);

        $report = $this->healthService->generateHealthReport($vps);

        $this->assertArrayHasKey('server_id', $report);
        $this->assertArrayHasKey('timestamp', $report);
        $this->assertArrayHasKey('metrics', $report);
        $this->assertArrayHasKey('status', $report);
        $this->assertEquals($vps->id, $report['server_id']);
    }

    public function test_tracks_health_history(): void
    {
        $vps = VpsServer::factory()->create();

        $this->mockConnectionManager
            ->shouldReceive('execute')
            ->andReturn(['stdout' => '25.5', 'exit_code' => 0]);

        $this->healthService->checkHealth($vps, storeHistory: true);
        $this->healthService->checkHealth($vps, storeHistory: true);
        $this->healthService->checkHealth($vps, storeHistory: true);

        $history = $this->healthService->getHealthHistory($vps, limit: 3);

        $this->assertCount(3, $history);
        $this->assertIsArray($history[0]);
    }
}
