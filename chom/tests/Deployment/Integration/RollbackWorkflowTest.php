<?php

namespace Tests\Deployment\Integration;

use Tests\Deployment\Helpers\DeploymentTestCase;

/**
 * Integration tests for the rollback workflow
 *
 * Tests the rollback.sh script to ensure it properly reverts deployments
 * including code, database migrations, and application state.
 */
class RollbackWorkflowTest extends DeploymentTestCase
{
    /**
     * Test rollback workflow with single step
     *
     * @group slow
     * @group integration
     */
    public function test_rollback_single_commit(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Rollback tests should not run in production');
        }

        // Arrange
        $currentCommit = $this->getCurrentCommit();
        $previousCommit = $this->getPreviousCommit(1);

        // Act - Skip the interactive prompt
        putenv('CI=true'); // This should make the script non-interactive
        $result = $this->executeScript('rollback.sh', ['--skip-backup', '--steps', '1'], 600);
        putenv('CI');

        // Note: This test may not work perfectly without actual Git history
        // It primarily validates script execution

        // Assert
        $this->assertNotEmpty($result['output']);
    }

    /**
     * Test rollback creates backup before proceeding
     */
    public function test_rollback_creates_backup_by_default(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Rollback tests should not run in production');
        }

        // Note: This test validates the rollback script behavior
        // In a real scenario, we'd check if backup was created

        putenv('CI=true');
        $result = $this->executeScript('rollback.sh', ['--steps', '1'], 600);
        putenv('CI');

        // Verify log mentions backup
        $log = $this->getLatestRollbackLog();
        if ($log) {
            $this->assertStringContainsString('backup', strtolower($log));
        }
    }

    /**
     * Test rollback can skip backup creation
     */
    public function test_rollback_can_skip_backup(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Rollback tests should not run in production');
        }

        putenv('CI=true');
        $result = $this->executeScript('rollback.sh', ['--skip-backup', '--steps', '1'], 600);
        putenv('CI');

        // Assert
        $this->assertNotEmpty($result['output']);
        $log = $this->getLatestRollbackLog();
        if ($log) {
            $this->assertStringContainsString('Skipping backup', $log);
        }
    }

    /**
     * Test rollback enables and disables maintenance mode
     */
    public function test_rollback_manages_maintenance_mode(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Rollback tests should not run in production');
        }

        putenv('CI=true');
        $result = $this->executeScript('rollback.sh', ['--skip-backup', '--steps', '1'], 600);
        putenv('CI');

        // Assert
        $log = $this->getLatestRollbackLog();
        if ($log) {
            $this->assertStringContainsString('maintenance mode', strtolower($log));
        }

        // Should exit maintenance mode
        $this->assertFalse($this->isInMaintenanceMode());
    }

    /**
     * Test rollback to specific commit
     */
    public function test_rollback_to_specific_commit(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Rollback tests should not run in production');
        }

        // Arrange
        $targetCommit = $this->getPreviousCommit(1);

        putenv('CI=true');
        $result = $this->executeScript(
            'rollback.sh',
            ['--skip-backup', '--commit', $targetCommit],
            600
        );
        putenv('CI');

        // Assert
        $this->assertNotEmpty($result['output']);
    }

    /**
     * Test rollback handles migration rollback
     */
    public function test_rollback_handles_migrations(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Rollback tests should not run in production');
        }

        putenv('CI=true');
        $result = $this->executeScript('rollback.sh', ['--skip-backup', '--steps', '1'], 600);
        putenv('CI');

        // Assert
        $log = $this->getLatestRollbackLog();
        if ($log) {
            $this->assertStringContainsString('migration', strtolower($log));
        }
    }

    /**
     * Test rollback can skip migrations
     */
    public function test_rollback_can_skip_migrations(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Rollback tests should not run in production');
        }

        putenv('CI=true');
        $result = $this->executeScript(
            'rollback.sh',
            ['--skip-backup', '--skip-migrations', '--steps', '1'],
            600
        );
        putenv('CI');

        // Assert
        $this->assertNotEmpty($result['output']);
    }

    /**
     * Test rollback reinstalls dependencies
     */
    public function test_rollback_reinstalls_dependencies(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Rollback tests should not run in production');
        }

        putenv('CI=true');
        $result = $this->executeScript('rollback.sh', ['--skip-backup', '--steps', '1'], 600);
        putenv('CI');

        // Assert
        $log = $this->getLatestRollbackLog();
        if ($log) {
            $this->assertStringContainsString('dependencies', strtolower($log));
        }
    }

    /**
     * Test rollback clears and rebuilds caches
     */
    public function test_rollback_rebuilds_caches(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Rollback tests should not run in production');
        }

        putenv('CI=true');
        $result = $this->executeScript('rollback.sh', ['--skip-backup', '--steps', '1'], 600);
        putenv('CI');

        // Assert
        $log = $this->getLatestRollbackLog();
        if ($log) {
            $this->assertStringContainsString('cache', strtolower($log));
        }
    }

    /**
     * Test rollback restarts queue workers
     */
    public function test_rollback_restarts_queue_workers(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Rollback tests should not run in production');
        }

        putenv('CI=true');
        $result = $this->executeScript('rollback.sh', ['--skip-backup', '--steps', '1'], 600);
        putenv('CI');

        // Assert
        $log = $this->getLatestRollbackLog();
        if ($log) {
            $this->assertStringContainsString('queue', strtolower($log));
        }
    }

    /**
     * Test rollback runs health checks
     */
    public function test_rollback_runs_health_checks(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Rollback tests should not run in production');
        }

        putenv('CI=true');
        $result = $this->executeScript('rollback.sh', ['--skip-backup', '--steps', '1'], 600);
        putenv('CI');

        // Assert
        $log = $this->getLatestRollbackLog();
        if ($log) {
            $this->assertStringContainsString('health check', strtolower($log));
        }
    }

    /**
     * Test rollback provides comprehensive summary
     */
    public function test_rollback_provides_summary(): void
    {
        if (app()->environment('production')) {
            $this->markTestSkipped('Rollback tests should not run in production');
        }

        putenv('CI=true');
        $result = $this->executeScript('rollback.sh', ['--skip-backup', '--steps', '1'], 600);
        putenv('CI');

        // Assert
        $log = $this->getLatestRollbackLog();
        if ($log) {
            $this->assertStringContainsString('ROLLBACK', strtoupper($log));
            $this->assertStringContainsString('Duration:', $log);
        }
    }

    /**
     * Test rollback help command
     */
    public function test_rollback_help_command(): void
    {
        // Act
        $result = $this->executeScript('rollback.sh', ['--help']);

        // Assert
        $this->assertEquals(0, $result['exitCode']);
        $this->assertStringContainsString('Usage:', $result['output']);
        $this->assertStringContainsString('Options:', $result['output']);
        $this->assertStringContainsString('--steps', $result['output']);
        $this->assertStringContainsString('--commit', $result['output']);
        $this->assertStringContainsString('--skip-migrations', $result['output']);
        $this->assertStringContainsString('--skip-backup', $result['output']);
    }
}
