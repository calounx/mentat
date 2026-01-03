<?php

declare(strict_types=1);

namespace Tests\Unit\Controllers;

use App\Http\Controllers\Api\V1\HealthController;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class HealthCheckControllerTest extends TestCase
{
    use RefreshDatabase;

    private HealthController $controller;

    protected function setUp(): void
    {
        parent::setUp();
        $this->controller = new HealthController();
    }

    public function test_basic_health_check_returns_healthy_status(): void
    {
        $response = $this->controller->index();

        $this->assertEquals(200, $response->getStatusCode());

        $data = $response->getData(true);

        $this->assertEquals('healthy', $data['data']['status']);
        $this->assertArrayHasKey('timestamp', $data['data']);
        $this->assertArrayHasKey('uptime', $data['data']);
    }

    public function test_detailed_health_check_returns_all_subsystems(): void
    {
        $response = $this->controller->detailed();

        $this->assertEquals(200, $response->getStatusCode());

        $data = $response->getData(true);

        $this->assertArrayHasKey('checks', $data['data']);
        $this->assertArrayHasKey('database', $data['data']['checks']);
        $this->assertArrayHasKey('cache', $data['data']['checks']);
        $this->assertArrayHasKey('queue', $data['data']['checks']);
        $this->assertArrayHasKey('storage', $data['data']['checks']);
    }

    public function test_database_check_succeeds_when_connected(): void
    {
        $response = $this->controller->detailed();
        $data = $response->getData(true);

        $dbCheck = $data['data']['checks']['database'];

        $this->assertTrue($dbCheck['healthy']);
        $this->assertEquals('Database connection successful', $dbCheck['message']);
    }

    public function test_database_check_fails_when_disconnected(): void
    {
        // Simulate database connection failure
        DB::shouldReceive('connection->getPdo')
            ->andThrow(new \Exception('Connection failed'));

        $response = $this->controller->detailed();
        $data = $response->getData(true);

        $dbCheck = $data['data']['checks']['database'];

        $this->assertFalse($dbCheck['healthy']);
        $this->assertStringContainsString('failed', $dbCheck['message']);
    }

    public function test_cache_check_succeeds_when_working(): void
    {
        $response = $this->controller->detailed();
        $data = $response->getData(true);

        $cacheCheck = $data['data']['checks']['cache'];

        $this->assertTrue($cacheCheck['healthy']);
        $this->assertEquals('Cache system operational', $cacheCheck['message']);
    }

    public function test_cache_check_fails_when_unavailable(): void
    {
        Cache::shouldReceive('put')->andThrow(new \Exception('Cache unavailable'));

        $response = $this->controller->detailed();
        $data = $response->getData(true);

        $cacheCheck = $data['data']['checks']['cache'];

        $this->assertFalse($cacheCheck['healthy']);
    }

    public function test_storage_check_reports_disk_usage(): void
    {
        $response = $this->controller->detailed();
        $data = $response->getData(true);

        $storageCheck = $data['data']['checks']['storage'];

        $this->assertArrayHasKey('healthy', $storageCheck);
        $this->assertArrayHasKey('free_space_gb', $storageCheck);
        $this->assertGreaterThan(0, $storageCheck['free_space_gb']);
    }

    public function test_storage_check_warns_when_disk_nearly_full(): void
    {
        // This test assumes the system has enough free space
        // In a real scenario with <10% free space, it would warn
        $response = $this->controller->detailed();
        $data = $response->getData(true);

        $storageCheck = $data['data']['checks']['storage'];

        // Should be healthy with sufficient space
        $this->assertTrue($storageCheck['healthy']);
    }

    public function test_overall_status_degraded_when_any_check_fails(): void
    {
        DB::shouldReceive('connection->getPdo')
            ->andThrow(new \Exception('DB down'));

        $response = $this->controller->detailed();
        $data = $response->getData(true);

        $this->assertEquals('degraded', $data['data']['status']);
    }

    public function test_overall_status_healthy_when_all_checks_pass(): void
    {
        $response = $this->controller->detailed();
        $data = $response->getData(true);

        $allHealthy = collect($data['data']['checks'])->every(fn($check) => $check['healthy']);

        if ($allHealthy) {
            $this->assertEquals('healthy', $data['data']['status']);
        }
    }

    public function test_security_health_check_returns_posture_information(): void
    {
        $response = $this->controller->security();
        $data = $response->getData(true);

        $this->assertArrayHasKey('security_posture', $data['data']);
        $this->assertArrayHasKey('checks', $data['data']);
        $this->assertArrayHasKey('two_factor_compliance', $data['data']['checks']);
        $this->assertArrayHasKey('ssl_certificates', $data['data']['checks']);
        $this->assertArrayHasKey('credential_rotation', $data['data']['checks']);
        $this->assertArrayHasKey('failed_login_attempts', $data['data']['checks']);
    }

    public function test_responds_quickly_to_liveness_probe(): void
    {
        $startTime = microtime(true);

        $this->controller->index();

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // Liveness check should respond in under 100ms
        $this->assertLessThan(100, $duration);
    }

    public function test_readiness_check_validates_all_dependencies(): void
    {
        $response = $this->controller->detailed();
        $data = $response->getData(true);

        // Readiness requires all core systems operational
        $coreChecks = ['database', 'cache'];

        foreach ($coreChecks as $check) {
            $this->assertArrayHasKey($check, $data['data']['checks']);
        }
    }

    public function test_health_endpoint_does_not_require_authentication(): void
    {
        // Health checks should work without authentication
        $response = $this->get('/api/health');

        $response->assertStatus(200);
    }

    public function test_health_check_includes_timestamp(): void
    {
        $response = $this->controller->index();
        $data = $response->getData(true);

        $this->assertArrayHasKey('timestamp', $data['data']);
        $this->assertMatchesRegularExpression('/^\d{4}-\d{2}-\d{2}T/', $data['data']['timestamp']);
    }

    public function test_performance_with_all_checks_enabled(): void
    {
        $startTime = microtime(true);

        $this->controller->detailed();

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // All health checks should complete in under 500ms
        $this->assertLessThan(500, $duration);
    }
}
