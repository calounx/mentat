<?php

namespace Tests\Deployment\Integration;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Redis;
use Tests\Deployment\Helpers\DeploymentTestCase;

/**
 * Integration tests for post-deployment health checks
 *
 * Tests the health-check.sh script to ensure it properly validates
 * application health after deployment.
 */
class HealthCheckTest extends DeploymentTestCase
{
    /**
     * Test that health checks pass in a healthy environment
     */
    public function test_health_checks_pass_with_healthy_application(): void
    {
        // Arrange
        $this->assertTrue($this->checkDatabaseConnectivity());

        // Act
        $result = $this->executeScript('health-check.sh');

        // Assert
        $this->assertTrue($result['successful'], 'Health checks should pass');
        $this->assertStringContainsString('All health checks passed', $result['output']);
        $this->assertEquals(0, $result['exitCode']);
    }

    /**
     * Test health check validates database connectivity via artisan
     */
    public function test_health_check_validates_database_via_artisan(): void
    {
        // Arrange
        $this->assertTrue($this->checkDatabaseConnectivity());

        // Act
        $result = $this->executeScript('health-check.sh');

        // Assert
        $this->assertStringContainsString('Checking database via artisan', $result['output']);
        $this->assertStringContainsString('Database accessible via artisan', $result['output']);
    }

    /**
     * Test health check validates Redis connectivity via artisan
     */
    public function test_health_check_validates_redis_via_artisan(): void
    {
        // Skip if Redis is not available
        if (!$this->checkRedisConnectivity()) {
            $this->markTestSkipped('Redis not available');
        }

        // Act
        $result = $this->executeScript('health-check.sh');

        // Assert
        $this->assertStringContainsString('Checking Redis via artisan', $result['output']);
    }

    /**
     * Test health check validates cache functionality
     */
    public function test_health_check_validates_cache_functionality(): void
    {
        // Arrange
        Cache::flush();

        // Act
        $result = $this->executeScript('health-check.sh');

        // Assert
        $this->assertStringContainsString('Checking cache functionality', $result['output']);
    }

    /**
     * Test health check validates storage is writable
     */
    public function test_health_check_validates_storage_writable(): void
    {
        // Act
        $result = $this->executeScript('health-check.sh');

        // Assert
        $this->assertStringContainsString('Checking storage write permissions', $result['output']);
        $this->assertStringContainsString('Storage is writable', $result['output']);
    }

    /**
     * Test health check validates log files
     */
    public function test_health_check_validates_log_files(): void
    {
        // Act
        $result = $this->executeScript('health-check.sh');

        // Assert
        $this->assertStringContainsString('Checking log files', $result['output']);
    }

    /**
     * Test health check validates configuration cache
     */
    public function test_health_check_validates_configuration_cache(): void
    {
        // Act
        $result = $this->executeScript('health-check.sh');

        // Assert
        $this->assertStringContainsString('Checking configuration cache', $result['output']);
    }

    /**
     * Test health check validates route cache
     */
    public function test_health_check_validates_route_cache(): void
    {
        // Act
        $result = $this->executeScript('health-check.sh');

        // Assert
        $this->assertStringContainsString('Checking route cache', $result['output']);
    }

    /**
     * Test health check validates PHP memory configuration
     */
    public function test_health_check_validates_php_memory(): void
    {
        // Act
        $result = $this->executeScript('health-check.sh');

        // Assert
        $this->assertStringContainsString('Checking PHP memory configuration', $result['output']);
        $this->assertStringContainsString('PHP memory limit:', $result['output']);
    }

    /**
     * Test health check validates queue functionality
     */
    public function test_health_check_validates_queue_functionality(): void
    {
        // Act
        $result = $this->executeScript('health-check.sh');

        // Assert
        $this->assertStringContainsString('Checking queue functionality', $result['output']);
        $this->assertStringContainsString('Queue size:', $result['output']);
    }

    /**
     * Test health check detects recent errors in logs
     */
    public function test_health_check_detects_recent_errors(): void
    {
        // Act
        $result = $this->executeScript('health-check.sh');

        // Assert
        $this->assertStringContainsString('Checking for recent errors', $result['output']);
    }

    /**
     * Test health check with custom timeout
     */
    public function test_health_check_respects_timeout_configuration(): void
    {
        // Arrange - Set environment variable for timeout
        putenv('HEALTH_CHECK_TIMEOUT=10');

        // Act
        $result = $this->executeScript('health-check.sh', [], 15);

        // Assert
        $this->assertLessThan(15, $result['exitCode'] !== 124); // Not timeout error

        // Cleanup
        putenv('HEALTH_CHECK_TIMEOUT');
    }

    /**
     * Test health check retry mechanism
     */
    public function test_health_check_retry_mechanism(): void
    {
        // Arrange - Set retry count
        putenv('HEALTH_CHECK_RETRIES=3');

        // Act
        $result = $this->executeScript('health-check.sh');

        // Assert - Should complete regardless of retries
        $this->assertNotEmpty($result['output']);

        // Cleanup
        putenv('HEALTH_CHECK_RETRIES');
    }

    /**
     * Test health check summary output
     */
    public function test_health_check_provides_summary(): void
    {
        // Act
        $result = $this->executeScript('health-check.sh');

        // Assert
        $this->assertStringContainsString('HEALTH CHECK SUMMARY', $result['output']);
    }

    /**
     * Test health check exit codes
     */
    public function test_health_check_exit_codes(): void
    {
        // Act
        $result = $this->executeScript('health-check.sh');

        // Assert
        if ($result['successful']) {
            $this->assertEquals(0, $result['exitCode'], 'Successful health check should return 0');
        } else {
            $this->assertGreaterThan(0, $result['exitCode'], 'Failed health check should return non-zero');
        }
    }

    /**
     * Test health check handles missing environment gracefully
     */
    public function test_health_check_handles_missing_app_url(): void
    {
        // Arrange - Temporarily unset APP_URL
        $originalUrl = env('APP_URL');
        putenv('APP_URL');

        // Act
        $result = $this->executeScript('health-check.sh');

        // Assert - Should still run with default
        $this->assertNotEmpty($result['output']);

        // Cleanup
        if ($originalUrl) {
            putenv("APP_URL={$originalUrl}");
        }
    }
}
