<?php

namespace Tests\Deployment\Helpers;

use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Process;
use Tests\TestCase;

/**
 * Base test case for deployment tests
 * Provides common utilities and setup for deployment testing
 */
abstract class DeploymentTestCase extends TestCase
{
    protected string $scriptsDir;
    protected string $projectRoot;
    protected string $backupDir;
    protected string $logDir;

    protected function setUp(): void
    {
        parent::setUp();

        $this->projectRoot = base_path();
        $this->scriptsDir = base_path('scripts');
        $this->backupDir = storage_path('app/backups');
        $this->logDir = storage_path('logs');

        // Ensure backup and log directories exist
        if (!is_dir($this->backupDir)) {
            mkdir($this->backupDir, 0755, true);
        }
        if (!is_dir($this->logDir)) {
            mkdir($this->logDir, 0755, true);
        }
    }

    /**
     * Execute a deployment script and return the result
     */
    protected function executeScript(string $scriptName, array $args = [], int $timeout = 300): array
    {
        $scriptPath = "{$this->scriptsDir}/{$scriptName}";

        if (!file_exists($scriptPath)) {
            throw new \RuntimeException("Script not found: {$scriptPath}");
        }

        $command = "bash {$scriptPath} " . implode(' ', $args);

        $process = Process::timeout($timeout)->run($command);

        return [
            'exitCode' => $process->exitCode(),
            'output' => $process->output(),
            'error' => $process->errorOutput(),
            'successful' => $process->successful(),
        ];
    }

    /**
     * Create a test backup file
     */
    protected function createTestBackup(string $name = null): string
    {
        $name = $name ?? 'test_backup_' . time() . '.sql';
        $backupPath = "{$this->backupDir}/{$name}";

        file_put_contents($backupPath, "-- Test backup file\n");

        return $backupPath;
    }

    /**
     * Get the latest deployment log file
     */
    protected function getLatestDeploymentLog(): ?string
    {
        $logs = glob("{$this->logDir}/deployment_*.log");

        if (empty($logs)) {
            return null;
        }

        usort($logs, fn($a, $b) => filemtime($b) - filemtime($a));

        return file_get_contents($logs[0]);
    }

    /**
     * Get the latest rollback log file
     */
    protected function getLatestRollbackLog(): ?string
    {
        $logs = glob("{$this->logDir}/rollback_*.log");

        if (empty($logs)) {
            return null;
        }

        usort($logs, fn($a, $b) => filemtime($b) - filemtime($a));

        return file_get_contents($logs[0]);
    }

    /**
     * Check if application is in maintenance mode
     */
    protected function isInMaintenanceMode(): bool
    {
        return app()->isDownForMaintenance();
    }

    /**
     * Simulate a database migration failure
     */
    protected function simulateMigrationFailure(): void
    {
        // Create a migration that will fail
        $migrationPath = database_path('migrations/' . date('Y_m_d_His') . '_failing_migration.php');
        $content = <<<'PHP'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        throw new \Exception('Simulated migration failure');
    }

    public function down(): void
    {
        // Nothing to rollback
    }
};
PHP;

        file_put_contents($migrationPath, $content);
    }

    /**
     * Clean up test migrations
     */
    protected function cleanupTestMigrations(): void
    {
        $migrations = glob(database_path('migrations/*_failing_migration.php'));
        foreach ($migrations as $migration) {
            unlink($migration);
        }
    }

    /**
     * Check if a URL is accessible
     */
    protected function checkUrlAccessibility(string $url, int $expectedStatus = 200): bool
    {
        try {
            $response = \Illuminate\Support\Facades\Http::timeout(5)->get($url);
            return $response->status() === $expectedStatus;
        } catch (\Exception $e) {
            return false;
        }
    }

    /**
     * Measure response time for a URL
     */
    protected function measureResponseTime(string $url): float
    {
        $start = microtime(true);

        try {
            \Illuminate\Support\Facades\Http::timeout(30)->get($url);
        } catch (\Exception $e) {
            // Ignore errors, we're just measuring time
        }

        return (microtime(true) - $start) * 1000; // Convert to milliseconds
    }

    /**
     * Check database connectivity
     */
    protected function checkDatabaseConnectivity(): bool
    {
        try {
            DB::connection()->getPdo();
            return true;
        } catch (\Exception $e) {
            return false;
        }
    }

    /**
     * Check Redis connectivity
     */
    protected function checkRedisConnectivity(): bool
    {
        try {
            \Illuminate\Support\Facades\Redis::connection()->ping();
            return true;
        } catch (\Exception $e) {
            return false;
        }
    }

    /**
     * Get current Git commit hash
     */
    protected function getCurrentCommit(): string
    {
        $process = Process::run('git rev-parse HEAD');
        return trim($process->output());
    }

    /**
     * Get the previous commit hash
     */
    protected function getPreviousCommit(int $steps = 1): string
    {
        $process = Process::run("git rev-parse HEAD~{$steps}");
        return trim($process->output());
    }

    /**
     * Count files in backup directory
     */
    protected function countBackups(): int
    {
        return count(glob("{$this->backupDir}/*.sql"));
    }

    /**
     * Wait for condition to be true
     */
    protected function waitFor(callable $condition, int $timeout = 30, int $interval = 1): bool
    {
        $start = time();

        while (time() - $start < $timeout) {
            if ($condition()) {
                return true;
            }
            sleep($interval);
        }

        return false;
    }

    /**
     * Clean up after tests
     */
    protected function tearDown(): void
    {
        // Ensure maintenance mode is disabled
        if ($this->isInMaintenanceMode()) {
            Artisan::call('up');
        }

        // Clean up test migrations
        $this->cleanupTestMigrations();

        parent::tearDown();
    }
}
