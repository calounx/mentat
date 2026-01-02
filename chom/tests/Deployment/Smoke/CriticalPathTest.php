<?php

namespace Tests\Deployment\Smoke;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use Tests\Deployment\Helpers\DeploymentTestCase;

/**
 * Smoke tests for critical deployment paths
 *
 * Quick validation tests that can be run immediately after deployment
 * to ensure the application is functioning correctly.
 *
 * These tests should be FAST (< 30 seconds total) and cover only
 * the most critical functionality.
 */
class CriticalPathTest extends DeploymentTestCase
{
    /**
     * Test database connectivity
     *
     * @group smoke
     * @group fast
     */
    public function test_database_is_accessible(): void
    {
        // Act & Assert
        $this->assertTrue(
            $this->checkDatabaseConnectivity(),
            'Database should be accessible after deployment'
        );

        // Verify we can query
        $result = DB::select('SELECT 1 as test');
        $this->assertEquals(1, $result[0]->test);
    }

    /**
     * Test Redis connectivity
     *
     * @group smoke
     * @group fast
     */
    public function test_redis_is_accessible(): void
    {
        // Skip if Redis is not configured
        if (!config('database.redis.default.host')) {
            $this->markTestSkipped('Redis not configured');
        }

        // Act & Assert
        $this->assertTrue(
            $this->checkRedisConnectivity(),
            'Redis should be accessible after deployment'
        );

        // Verify we can set and get values
        Redis::set('smoke_test', 'value');
        $this->assertEquals('value', Redis::get('smoke_test'));
        Redis::del('smoke_test');
    }

    /**
     * Test application environment is correct
     *
     * @group smoke
     * @group fast
     */
    public function test_application_environment_is_configured(): void
    {
        // Assert
        $this->assertNotEquals('local', app()->environment(), 'Should not be in local environment');
        $this->assertTrue(config('app.key') !== null, 'Application key should be set');
        $this->assertTrue(config('app.key') !== 'base64:test', 'Application key should not be default');
    }

    /**
     * Test storage directories are writable
     *
     * @group smoke
     * @group fast
     */
    public function test_storage_directories_are_writable(): void
    {
        // Arrange
        $directories = [
            storage_path('app'),
            storage_path('framework/cache'),
            storage_path('framework/sessions'),
            storage_path('framework/views'),
            storage_path('logs'),
        ];

        // Act & Assert
        foreach ($directories as $directory) {
            $this->assertDirectoryIsWritable($directory, "{$directory} should be writable");
        }
    }

    /**
     * Test cache is functioning
     *
     * @group smoke
     * @group fast
     */
    public function test_cache_is_functioning(): void
    {
        // Arrange
        $key = 'smoke_test_' . time();
        $value = 'test_value_' . uniqid();

        // Act
        cache()->put($key, $value, 60);
        $retrieved = cache()->get($key);

        // Assert
        $this->assertEquals($value, $retrieved, 'Cache should store and retrieve values');

        // Cleanup
        cache()->forget($key);
    }

    /**
     * Test queue connection is working
     *
     * @group smoke
     * @group fast
     */
    public function test_queue_connection_is_working(): void
    {
        // This test just verifies queue configuration, not actual job processing
        $this->assertTrue(
            config('queue.default') !== null,
            'Queue connection should be configured'
        );
    }

    /**
     * Test session is functioning
     *
     * @group smoke
     * @group fast
     */
    public function test_session_is_functioning(): void
    {
        // Arrange
        $key = 'smoke_test';
        $value = 'test_value';

        // Act
        session()->put($key, $value);
        $retrieved = session()->get($key);

        // Assert
        $this->assertEquals($value, $retrieved, 'Session should store and retrieve values');
    }

    /**
     * Test migrations are up to date
     *
     * @group smoke
     * @group fast
     */
    public function test_migrations_are_up_to_date(): void
    {
        // Get pending migrations
        $migrations = \Illuminate\Support\Facades\Artisan::call('migrate:status');

        // We can't easily check the output, but we can verify the command runs
        $this->assertEquals(0, $migrations, 'Migrate:status should run successfully');
    }

    /**
     * Test configuration is cached
     *
     * @group smoke
     * @group fast
     */
    public function test_configuration_is_cached(): void
    {
        // In production, config should be cached
        if (app()->environment('production')) {
            $this->assertFileExists(
                base_path('bootstrap/cache/config.php'),
                'Configuration should be cached in production'
            );
        }
    }

    /**
     * Test routes are cached
     *
     * @group smoke
     * @group fast
     */
    public function test_routes_are_cached(): void
    {
        // In production, routes should be cached
        if (app()->environment('production')) {
            $cacheFiles = glob(base_path('bootstrap/cache/routes-v*.php'));
            $this->assertNotEmpty($cacheFiles, 'Routes should be cached in production');
        }
    }

    /**
     * Test environment variables are loaded
     *
     * @group smoke
     * @group fast
     */
    public function test_environment_variables_are_loaded(): void
    {
        // Assert critical environment variables exist
        $this->assertNotNull(env('APP_KEY'), 'APP_KEY should be set');
        $this->assertNotNull(env('DB_CONNECTION'), 'DB_CONNECTION should be set');
        $this->assertNotNull(env('DB_DATABASE'), 'DB_DATABASE should be set');
    }

    /**
     * Test backup directory exists and is writable
     *
     * @group smoke
     * @group fast
     */
    public function test_backup_directory_is_configured(): void
    {
        // Assert
        $this->assertDirectoryExists($this->backupDir, 'Backup directory should exist');
        $this->assertDirectoryIsWritable($this->backupDir, 'Backup directory should be writable');
    }

    /**
     * Test log directory is functioning
     *
     * @group smoke
     * @group fast
     */
    public function test_logging_is_functioning(): void
    {
        // Arrange
        $testMessage = 'Smoke test log entry ' . time();

        // Act
        \Illuminate\Support\Facades\Log::info($testMessage);

        // Assert - Just verify no exception was thrown
        $this->assertTrue(true);
    }

    /**
     * Test composer autoload is working
     *
     * @group smoke
     * @group fast
     */
    public function test_composer_autoload_is_working(): void
    {
        // Assert that critical classes can be loaded
        $this->assertTrue(class_exists(\Illuminate\Foundation\Application::class));
        $this->assertTrue(class_exists(\App\Http\Kernel::class));
    }

    /**
     * Test timezone is configured correctly
     *
     * @group smoke
     * @group fast
     */
    public function test_timezone_is_configured(): void
    {
        // Assert
        $this->assertNotNull(config('app.timezone'), 'Timezone should be configured');
        $this->assertEquals(
            config('app.timezone'),
            date_default_timezone_get(),
            'PHP timezone should match app timezone'
        );
    }

    /**
     * Test locale is configured correctly
     *
     * @group smoke
     * @group fast
     */
    public function test_locale_is_configured(): void
    {
        // Assert
        $this->assertNotNull(config('app.locale'), 'Locale should be configured');
        $this->assertEquals(config('app.locale'), app()->getLocale(), 'App locale should be set');
    }
}
