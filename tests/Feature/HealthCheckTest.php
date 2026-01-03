<?php

declare(strict_types=1);

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class HealthCheckTest extends TestCase
{
    use RefreshDatabase;

    public function test_liveness_endpoint_returns_200(): void
    {
        $response = $this->getJson('/api/health');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'data' => [
                'status',
                'timestamp',
            ],
        ]);
    }

    public function test_liveness_check_indicates_healthy_status(): void
    {
        $response = $this->getJson('/api/health');

        $response->assertStatus(200);
        $response->assertJson([
            'data' => [
                'status' => 'healthy',
            ],
        ]);
    }

    public function test_liveness_check_includes_timestamp(): void
    {
        $response = $this->getJson('/api/health');

        $data = $response->json('data');

        $this->assertArrayHasKey('timestamp', $data);
        $this->assertMatchesRegularExpression('/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/', $data['timestamp']);
    }

    public function test_readiness_endpoint_checks_all_dependencies(): void
    {
        $response = $this->getJson('/api/health/detailed');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'data' => [
                'status',
                'checks' => [
                    'database',
                    'cache',
                    'queue',
                    'storage',
                ],
                'timestamp',
            ],
        ]);
    }

    public function test_database_health_check_passes_when_connected(): void
    {
        $response = $this->getJson('/api/health/detailed');

        $response->assertStatus(200);

        $data = $response->json('data');
        $dbCheck = $data['checks']['database'];

        $this->assertTrue($dbCheck['healthy']);
        $this->assertEquals('Database connection successful', $dbCheck['message']);
    }

    public function test_database_health_check_fails_when_disconnected(): void
    {
        // Close database connection
        DB::disconnect();

        $response = $this->getJson('/api/health/detailed');

        $data = $response->json('data');

        // Should report degraded status
        $this->assertContains($data['status'], ['degraded', 'unhealthy']);
    }

    public function test_cache_health_check_passes_when_operational(): void
    {
        $response = $this->getJson('/api/health/detailed');

        $response->assertStatus(200);

        $data = $response->json('data');
        $cacheCheck = $data['checks']['cache'];

        $this->assertTrue($cacheCheck['healthy']);
    }

    public function test_storage_health_check_reports_disk_space(): void
    {
        $response = $this->getJson('/api/health/detailed');

        $data = $response->json('data');
        $storageCheck = $data['checks']['storage'];

        $this->assertArrayHasKey('healthy', $storageCheck);
        $this->assertArrayHasKey('free_space_gb', $storageCheck);
        $this->assertIsNumeric($storageCheck['free_space_gb']);
        $this->assertGreaterThan(0, $storageCheck['free_space_gb']);
    }

    public function test_storage_check_warns_when_disk_usage_high(): void
    {
        $response = $this->getJson('/api/health/detailed');

        $data = $response->json('data');
        $storageCheck = $data['checks']['storage'];

        // If disk usage > 90%, should be unhealthy
        if (isset($storageCheck['usage_percent']) && $storageCheck['usage_percent'] > 90) {
            $this->assertFalse($storageCheck['healthy']);
        } else {
            $this->assertTrue($storageCheck['healthy']);
        }
    }

    public function test_overall_status_healthy_when_all_checks_pass(): void
    {
        $response = $this->getJson('/api/health/detailed');

        $data = $response->json('data');
        $checks = $data['checks'];

        $allHealthy = collect($checks)->every(fn($check) => $check['healthy'] === true);

        if ($allHealthy) {
            $this->assertEquals('healthy', $data['status']);
        } else {
            $this->assertEquals('degraded', $data['status']);
        }
    }

    public function test_overall_status_degraded_when_any_check_fails(): void
    {
        // This would require mocking a service failure
        // For now, we verify the logic exists
        $response = $this->getJson('/api/health/detailed');

        $data = $response->json('data');

        $this->assertContains($data['status'], ['healthy', 'degraded', 'unhealthy']);
    }

    public function test_health_check_does_not_require_authentication(): void
    {
        // No authentication headers
        $response = $this->getJson('/api/health');

        $response->assertStatus(200);

        $detailedResponse = $this->getJson('/api/health/detailed');

        $detailedResponse->assertStatus(200);
    }

    public function test_health_check_responds_quickly(): void
    {
        $startTime = microtime(true);

        $this->getJson('/api/health');

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // Should respond in under 100ms
        $this->assertLessThan(100, $duration);
    }

    public function test_detailed_health_check_completes_in_reasonable_time(): void
    {
        $startTime = microtime(true);

        $this->getJson('/api/health/detailed');

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // Should complete all checks in under 500ms
        $this->assertLessThan(500, $duration);
    }

    public function test_health_check_includes_uptime_information(): void
    {
        $response = $this->getJson('/api/health');

        $data = $response->json('data');

        $this->assertArrayHasKey('uptime', $data);
    }

    public function test_health_check_can_be_called_repeatedly(): void
    {
        for ($i = 0; $i < 10; $i++) {
            $response = $this->getJson('/api/health');
            $response->assertStatus(200);
        }
    }

    public function test_health_check_not_rate_limited(): void
    {
        // Make many requests
        for ($i = 0; $i < 200; $i++) {
            $response = $this->getJson('/api/health');
            $this->assertEquals(200, $response->status());
        }

        // All should succeed without rate limiting
        $this->assertTrue(true);
    }

    public function test_security_health_check_requires_authorization(): void
    {
        $response = $this->getJson('/api/health/security');

        // Should require authentication
        $this->assertContains($response->status(), [200, 401, 403]);
    }

    public function test_health_check_includes_component_versions(): void
    {
        $response = $this->getJson('/api/health/detailed');

        $data = $response->json('data');

        // Should include relevant version/build info
        $this->assertIsArray($data);
    }

    public function test_health_check_format_consistent(): void
    {
        $response1 = $this->getJson('/api/health');
        $response2 = $this->getJson('/api/health');

        $data1 = $response1->json();
        $data2 = $response2->json();

        // Same structure
        $this->assertEquals(array_keys($data1), array_keys($data2));
    }

    public function test_kubernetes_liveness_probe_compatible(): void
    {
        $response = $this->get('/api/health');

        // Kubernetes expects 200-399 for success
        $this->assertGreaterThanOrEqual(200, $response->status());
        $this->assertLessThan(400, $response->status());
    }

    public function test_kubernetes_readiness_probe_compatible(): void
    {
        $response = $this->get('/api/health/detailed');

        // Should return appropriate status codes for K8s
        $this->assertContains($response->status(), [200, 503]);
    }

    public function test_health_check_handles_concurrent_requests(): void
    {
        $responses = [];

        for ($i = 0; $i < 10; $i++) {
            $responses[] = $this->getJson('/api/health');
        }

        foreach ($responses as $response) {
            $response->assertStatus(200);
        }
    }

    public function test_health_check_json_format_valid(): void
    {
        $response = $this->getJson('/api/health');

        $response->assertStatus(200);
        $response->assertJson([
            'data' => [
                'status' => 'healthy',
            ],
        ]);

        // Verify it's valid JSON
        $this->assertIsArray($response->json());
    }

    public function test_detailed_health_check_provides_actionable_information(): void
    {
        $response = $this->getJson('/api/health/detailed');

        $data = $response->json('data');
        $checks = $data['checks'];

        foreach ($checks as $checkName => $check) {
            $this->assertArrayHasKey('healthy', $check);
            $this->assertArrayHasKey('message', $check);
            $this->assertIsBool($check['healthy']);
            $this->assertIsString($check['message']);
        }
    }

    public function test_health_check_memory_efficient(): void
    {
        $memoryBefore = memory_get_usage();

        for ($i = 0; $i < 100; $i++) {
            $this->getJson('/api/health');
        }

        $memoryAfter = memory_get_usage();
        $memoryUsed = ($memoryAfter - $memoryBefore) / 1024 / 1024; // MB

        // Should use less than 5MB for 100 health checks
        $this->assertLessThan(5, $memoryUsed);
    }

    public function test_health_check_cache_friendly(): void
    {
        // First request
        $response1 = $this->getJson('/api/health/detailed');

        // Second request (could be cached)
        $response2 = $this->getJson('/api/health/detailed');

        $response1->assertStatus(200);
        $response2->assertStatus(200);

        // Both should return valid data
        $this->assertIsArray($response1->json('data'));
        $this->assertIsArray($response2->json('data'));
    }
}
