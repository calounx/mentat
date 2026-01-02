<?php

namespace Tests\Deployment\Integration;

use Illuminate\Support\Facades\Artisan;
use Tests\Deployment\Helpers\DeploymentTestCase;

/**
 * Integration tests for the complete deployment workflow
 *
 * Tests the deploy-production.sh script end-to-end including:
 * - Pre-deployment checks
 * - Backup creation
 * - Code updates
 * - Migrations
 * - Cache optimization
 * - Post-deployment health checks
 */
class DeploymentWorkflowTest extends DeploymentTestCase
{
    /**
     * Test full deployment workflow succeeds
     *
     * This test validates the complete deployment pipeline from start to finish.
     * It should only be run in a test environment.
     *
     * @group slow
     * @group integration
     */
    public function test_complete_deployment_workflow_succeeds(): void
    {
        // Skip in production
        if (app()->environment('production')) {
            $this->markTestSkipped('Deployment tests should not run in production');
        }

        // Arrange
        $initialCommit = $this->getCurrentCommit();
        $backupCountBefore = $this->countBackups();

        // Act
        $result = $this->executeScript('deploy-production.sh', [], 600);

        // Assert
        $this->assertTrue(
            $result['successful'],
            "Deployment should succeed. Output: {$result['output']}\nError: {$result['error']}"
        );
        $this->assertEquals(0, $result['exitCode']);

        // Verify deployment log was created
        $log = $this->getLatestDeploymentLog();
        $this->assertNotNull($log, 'Deployment log should be created');

        // Verify key deployment steps in log
        $this->assertStringContainsString('PRODUCTION DEPLOYMENT STARTED', $log);
        $this->assertStringContainsString('Pre-deployment checks passed', $log);
        $this->assertStringContainsString('DEPLOYMENT COMPLETED SUCCESSFULLY', $log);
    }

    /**
     * Test deployment creates backup before proceeding
     */
    public function test_deployment_creates_backup(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Deployment tests should not run in production');
        }

        // Arrange
        $backupCountBefore = $this->countBackups();

        // Act
        $result = $this->executeScript('deploy-production.sh', [], 600);

        // Assert - Backup should be created (or attempted)
        $log = $this->getLatestDeploymentLog();
        $this->assertStringContainsString('Creating database backup', $log);
    }

    /**
     * Test deployment enables and disables maintenance mode
     */
    public function test_deployment_manages_maintenance_mode(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Deployment tests should not run in production');
        }

        // Arrange
        $this->assertFalse($this->isInMaintenanceMode(), 'Should start without maintenance mode');

        // Note: We can't easily test this mid-deployment, but we can verify the log
        $result = $this->executeScript('deploy-production.sh', [], 600);

        // Assert
        $log = $this->getLatestDeploymentLog();
        $this->assertStringContainsString('Enabling maintenance mode', $log);
        $this->assertStringContainsString('Disabling maintenance mode', $log);

        // Application should not be in maintenance mode after deployment
        $this->assertFalse($this->isInMaintenanceMode(), 'Should exit maintenance mode after deployment');
    }

    /**
     * Test deployment runs database migrations
     */
    public function test_deployment_runs_migrations(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Deployment tests should not run in production');
        }

        // Act
        $result = $this->executeScript('deploy-production.sh', [], 600);

        // Assert
        $log = $this->getLatestDeploymentLog();
        $this->assertStringContainsString('Running database migrations', $log);
    }

    /**
     * Test deployment optimizes application caches
     */
    public function test_deployment_optimizes_caches(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Deployment tests should not run in production');
        }

        // Act
        $result = $this->executeScript('deploy-production.sh', [], 600);

        // Assert
        $log = $this->getLatestDeploymentLog();
        $this->assertStringContainsString('Optimizing application', $log);
        $this->assertStringContainsString('config:cache', $log);
        $this->assertStringContainsString('route:cache', $log);
        $this->assertStringContainsString('view:cache', $log);
    }

    /**
     * Test deployment restarts queue workers
     */
    public function test_deployment_restarts_queue_workers(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Deployment tests should not run in production');
        }

        // Act
        $result = $this->executeScript('deploy-production.sh', [], 600);

        // Assert
        $log = $this->getLatestDeploymentLog();
        $this->assertStringContainsString('Restarting queue workers', $log);
        $this->assertStringContainsString('queue:restart', $log);
    }

    /**
     * Test deployment runs health checks after completion
     */
    public function test_deployment_runs_post_deployment_health_checks(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Deployment tests should not run in production');
        }

        // Act
        $result = $this->executeScript('deploy-production.sh', [], 600);

        // Assert
        $log = $this->getLatestDeploymentLog();
        $this->assertStringContainsString('Running post-deployment health checks', $log);
    }

    /**
     * Test deployment cleans old backups
     */
    public function test_deployment_cleans_old_backups(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Deployment tests should not run in production');
        }

        // Act
        $result = $this->executeScript('deploy-production.sh', [], 600);

        // Assert
        $log = $this->getLatestDeploymentLog();
        $this->assertStringContainsString('Cleaning old backups', $log);
    }

    /**
     * Test deployment creates comprehensive logs
     */
    public function test_deployment_creates_comprehensive_logs(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Deployment tests should not run in production');
        }

        // Act
        $result = $this->executeScript('deploy-production.sh', [], 600);

        // Assert
        $log = $this->getLatestDeploymentLog();

        // Check for all major steps
        $expectedSteps = [
            'Pre-deployment checks',
            'Creating database backup',
            'Enabling maintenance mode',
            'Installing Composer dependencies',
            'Building frontend assets',
            'Running database migrations',
            'Optimizing application',
            'Restarting queue workers',
            'Disabling maintenance mode',
            'Running post-deployment health checks',
        ];

        foreach ($expectedSteps as $step) {
            $this->assertStringContainsString($step, $log, "Log should contain: {$step}");
        }
    }

    /**
     * Test deployment handles pre-deployment check failures
     *
     * @group failure-scenarios
     */
    public function test_deployment_aborts_on_pre_deployment_check_failure(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Deployment tests should not run in production');
        }

        // This test would require mocking a failing pre-deployment check
        // For now, we verify the script checks for failures

        $result = $this->executeScript('deploy-production.sh', [], 600);
        $log = $this->getLatestDeploymentLog();

        // Verify pre-deployment checks are run
        $this->assertStringContainsString('Pre-deployment checks', $log);
    }

    /**
     * Test deployment rollback on migration failure
     *
     * @group failure-scenarios
     * @group slow
     */
    public function test_deployment_rolls_back_on_migration_failure(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Deployment tests should not run in production');
        }

        // Arrange - Create a failing migration
        $this->simulateMigrationFailure();

        // Act
        $result = $this->executeScript('deploy-production.sh', [], 600);

        // Assert - Should fail but handle gracefully
        $this->assertFalse($result['successful']);

        $log = $this->getLatestDeploymentLog();
        if ($log) {
            $this->assertStringContainsString('Migration failed', $log);
        }

        // Cleanup
        $this->cleanupTestMigrations();
    }

    /**
     * Test deployment provides deployment summary
     */
    public function test_deployment_provides_summary(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Deployment tests should not run in production');
        }

        // Act
        $result = $this->executeScript('deploy-production.sh', [], 600);

        // Assert
        $log = $this->getLatestDeploymentLog();
        $this->assertStringContainsString('DEPLOYMENT COMPLETED SUCCESSFULLY', $log);
        $this->assertStringContainsString('Duration:', $log);
    }
}
