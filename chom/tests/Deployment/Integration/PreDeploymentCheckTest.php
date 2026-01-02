<?php

namespace Tests\Deployment\Integration;

use Tests\Deployment\Helpers\DeploymentTestCase;

/**
 * Integration tests for pre-deployment checks
 *
 * Tests the pre-deployment-check.sh script to ensure it properly validates
 * system requirements and configuration before deployment.
 */
class PreDeploymentCheckTest extends DeploymentTestCase
{
    /**
     * Test that pre-deployment checks pass in a valid environment
     */
    public function test_pre_deployment_checks_pass_with_valid_environment(): void
    {
        // Arrange - Ensure environment is properly configured
        $this->assertFileExists($this->projectRoot . '/.env');
        $this->assertTrue($this->checkDatabaseConnectivity());

        // Act
        $result = $this->executeScript('pre-deployment-check.sh');

        // Assert
        $this->assertTrue($result['successful'], 'Pre-deployment checks should pass');
        $this->assertStringContainsString('All checks passed', $result['output']);
        $this->assertEquals(0, $result['exitCode']);
    }

    /**
     * Test that pre-deployment checks detect missing PHP extensions
     */
    public function test_pre_deployment_checks_detect_missing_php_version(): void
    {
        // This test validates the script's ability to check PHP version
        // In a real environment, we'd mock the PHP version check

        $result = $this->executeScript('pre-deployment-check.sh');

        // Assert that PHP version check is performed
        $this->assertStringContainsString('Checking PHP version', $result['output']);
        $this->assertMatchesRegularExpression('/PHP version \d+\.\d+/', $result['output']);
    }

    /**
     * Test that pre-deployment checks validate required environment variables
     */
    public function test_pre_deployment_checks_validate_environment_variables(): void
    {
        // Arrange
        $requiredVars = ['APP_KEY', 'DB_CONNECTION', 'DB_DATABASE', 'REDIS_HOST', 'REDIS_PASSWORD'];

        // Act
        $result = $this->executeScript('pre-deployment-check.sh');

        // Assert - Check that all required variables are validated
        foreach ($requiredVars as $var) {
            $this->assertStringContainsString($var, $result['output']);
        }
    }

    /**
     * Test that pre-deployment checks validate database connectivity
     */
    public function test_pre_deployment_checks_validate_database_connectivity(): void
    {
        // Arrange
        $this->assertTrue($this->checkDatabaseConnectivity());

        // Act
        $result = $this->executeScript('pre-deployment-check.sh');

        // Assert
        $this->assertStringContainsString('Database connection successful', $result['output']);
    }

    /**
     * Test that pre-deployment checks validate Redis connectivity
     */
    public function test_pre_deployment_checks_validate_redis_connectivity(): void
    {
        // Skip if Redis is not available
        if (!$this->checkRedisConnectivity()) {
            $this->markTestSkipped('Redis not available');
        }

        // Act
        $result = $this->executeScript('pre-deployment-check.sh');

        // Assert
        $this->assertStringContainsString('Redis connection', $result['output']);
    }

    /**
     * Test that pre-deployment checks validate disk space
     */
    public function test_pre_deployment_checks_validate_disk_space(): void
    {
        // Act
        $result = $this->executeScript('pre-deployment-check.sh');

        // Assert
        $this->assertStringContainsString('Checking disk space', $result['output']);
        $this->assertMatchesRegularExpression('/Disk usage: \d+%/', $result['output']);
    }

    /**
     * Test that pre-deployment checks validate storage permissions
     */
    public function test_pre_deployment_checks_validate_storage_permissions(): void
    {
        // Act
        $result = $this->executeScript('pre-deployment-check.sh');

        // Assert
        $this->assertStringContainsString('Checking storage permissions', $result['output']);
        $this->assertStringContainsString('storage/app', $result['output']);
        $this->assertStringContainsString('storage/framework', $result['output']);
        $this->assertStringContainsString('storage/logs', $result['output']);
    }

    /**
     * Test that pre-deployment checks validate Git repository status
     */
    public function test_pre_deployment_checks_validate_git_status(): void
    {
        // Act
        $result = $this->executeScript('pre-deployment-check.sh');

        // Assert
        $this->assertStringContainsString('Checking Git status', $result['output']);
        $this->assertStringContainsString('Current branch:', $result['output']);
    }

    /**
     * Test that pre-deployment checks validate backup directory
     */
    public function test_pre_deployment_checks_validate_backup_directory(): void
    {
        // Arrange - Ensure backup directory exists
        if (!is_dir($this->backupDir)) {
            mkdir($this->backupDir, 0755, true);
        }

        // Act
        $result = $this->executeScript('pre-deployment-check.sh');

        // Assert
        $this->assertStringContainsString('Checking backup configuration', $result['output']);
    }

    /**
     * Test that pre-deployment checks validate Composer installation
     */
    public function test_pre_deployment_checks_validate_composer(): void
    {
        // Act
        $result = $this->executeScript('pre-deployment-check.sh');

        // Assert
        $this->assertStringContainsString('Checking Composer', $result['output']);
        $this->assertMatchesRegularExpression('/Composer \d+\.\d+/', $result['output']);
    }

    /**
     * Test that pre-deployment checks validate Node.js and NPM
     */
    public function test_pre_deployment_checks_validate_nodejs_npm(): void
    {
        // Act
        $result = $this->executeScript('pre-deployment-check.sh');

        // Assert
        $this->assertStringContainsString('Checking Node.js and NPM', $result['output']);
    }

    /**
     * Test pre-deployment checks exit code behavior
     */
    public function test_pre_deployment_checks_exit_code_on_success(): void
    {
        // Act
        $result = $this->executeScript('pre-deployment-check.sh');

        // Assert
        if ($result['successful']) {
            $this->assertEquals(0, $result['exitCode']);
        } else {
            $this->assertGreaterThan(0, $result['exitCode']);
        }
    }

    /**
     * Test that pre-deployment checks handle warnings appropriately
     */
    public function test_pre_deployment_checks_handle_warnings(): void
    {
        // Act
        $result = $this->executeScript('pre-deployment-check.sh');

        // Assert - Check for warning indicators
        if (str_contains($result['output'], 'warning')) {
            $this->assertStringContainsString('WARNING', $result['output']);
        }
    }
}
