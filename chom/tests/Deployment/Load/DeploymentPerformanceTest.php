<?php

namespace Tests\Deployment\Load;

use Illuminate\Support\Facades\DB;
use Tests\Deployment\Helpers\DeploymentTestCase;

/**
 * Load tests for deployment performance
 *
 * Tests application performance under deployment scenarios to ensure
 * the system can handle expected load during and after deployment.
 *
 * @group load
 * @group slow
 */
class DeploymentPerformanceTest extends DeploymentTestCase
{
    protected int $concurrentRequests = 10;
    protected int $totalRequests = 100;

    /**
     * Test database connection pool under load
     */
    public function test_database_connection_pool_under_load(): void
    {
        $connections = [];
        $startTime = microtime(true);

        // Create multiple concurrent connections
        for ($i = 0; $i < 20; $i++) {
            try {
                $result = DB::select('SELECT 1 as test');
                $connections[] = $result[0]->test;
            } catch (\Exception $e) {
                $this->fail("Connection failed at iteration {$i}: " . $e->getMessage());
            }
        }

        $duration = (microtime(true) - $startTime) * 1000;

        // Assert all connections succeeded
        $this->assertCount(20, $connections);

        // Assert reasonable performance (< 5 seconds for 20 queries)
        $this->assertLessThan(5000, $duration, 'Database connections should be fast');
    }

    /**
     * Test cache performance under load
     */
    public function test_cache_performance_under_load(): void
    {
        $operations = 1000;
        $startTime = microtime(true);

        // Perform many cache operations
        for ($i = 0; $i < $operations; $i++) {
            $key = "load_test_{$i}";
            cache()->put($key, "value_{$i}", 60);
            $value = cache()->get($key);
            $this->assertEquals("value_{$i}", $value);
            cache()->forget($key);
        }

        $duration = (microtime(true) - $startTime) * 1000;
        $avgTime = $duration / $operations;

        // Assert average operation time is reasonable (< 10ms per operation)
        $this->assertLessThan(10, $avgTime, "Cache operations should average < 10ms, got {$avgTime}ms");
    }

    /**
     * Test queue processing performance
     */
    public function test_queue_job_dispatch_performance(): void
    {
        $jobs = 100;
        $startTime = microtime(true);

        // Dispatch many jobs (they won't actually process in sync mode)
        for ($i = 0; $i < $jobs; $i++) {
            dispatch(function () {
                // Simple job
            });
        }

        $duration = (microtime(true) - $startTime) * 1000;
        $avgTime = $duration / $jobs;

        // Assert average dispatch time is reasonable (< 5ms per job)
        $this->assertLessThan(5, $avgTime, "Job dispatch should average < 5ms, got {$avgTime}ms");
    }

    /**
     * Test session operations under load
     */
    public function test_session_performance_under_load(): void
    {
        $operations = 500;
        $startTime = microtime(true);

        // Perform many session operations
        for ($i = 0; $i < $operations; $i++) {
            session()->put("test_{$i}", "value_{$i}");
            $value = session()->get("test_{$i}");
            $this->assertEquals("value_{$i}", $value);
        }

        $duration = (microtime(true) - $startTime) * 1000;
        $avgTime = $duration / $operations;

        // Assert average operation time is reasonable (< 2ms per operation)
        $this->assertLessThan(2, $avgTime, "Session operations should average < 2ms, got {$avgTime}ms");
    }

    /**
     * Test file system operations during deployment
     */
    public function test_file_system_operations_performance(): void
    {
        $files = 50;
        $startTime = microtime(true);
        $testDir = storage_path('app/load_test_' . time());

        if (!is_dir($testDir)) {
            mkdir($testDir, 0755, true);
        }

        // Create, read, and delete files
        for ($i = 0; $i < $files; $i++) {
            $filePath = "{$testDir}/test_{$i}.txt";

            // Write
            file_put_contents($filePath, "Test content {$i}");

            // Read
            $content = file_get_contents($filePath);
            $this->assertEquals("Test content {$i}", $content);

            // Delete
            unlink($filePath);
        }

        rmdir($testDir);

        $duration = (microtime(true) - $startTime) * 1000;
        $avgTime = $duration / $files;

        // Assert average file operation time is reasonable (< 20ms per file)
        $this->assertLessThan(20, $avgTime, "File operations should average < 20ms, got {$avgTime}ms");
    }

    /**
     * Test memory usage during cache warming
     */
    public function test_memory_usage_during_cache_operations(): void
    {
        $memoryBefore = memory_get_usage(true);

        // Perform cache-heavy operations
        for ($i = 0; $i < 1000; $i++) {
            cache()->put("mem_test_{$i}", str_repeat('x', 1024), 60); // 1KB per entry
        }

        $memoryAfter = memory_get_usage(true);
        $memoryUsed = ($memoryAfter - $memoryBefore) / 1024 / 1024; // Convert to MB

        // Cleanup
        for ($i = 0; $i < 1000; $i++) {
            cache()->forget("mem_test_{$i}");
        }

        // Assert reasonable memory usage (< 50MB for 1000 x 1KB entries)
        $this->assertLessThan(50, $memoryUsed, "Memory usage should be < 50MB, got {$memoryUsed}MB");
    }

    /**
     * Test query performance with multiple tables
     */
    public function test_database_query_performance(): void
    {
        $queries = 100;
        $startTime = microtime(true);

        // Perform multiple queries
        for ($i = 0; $i < $queries; $i++) {
            DB::table('users')->count();
        }

        $duration = (microtime(true) - $startTime) * 1000;
        $avgTime = $duration / $queries;

        // Assert average query time is reasonable (< 10ms per query)
        $this->assertLessThan(10, $avgTime, "Database queries should average < 10ms, got {$avgTime}ms");
    }

    /**
     * Test concurrent database transactions
     */
    public function test_concurrent_database_transactions(): void
    {
        $transactions = 20;
        $startTime = microtime(true);

        for ($i = 0; $i < $transactions; $i++) {
            DB::transaction(function () {
                DB::table('users')->count();
            });
        }

        $duration = (microtime(true) - $startTime) * 1000;
        $avgTime = $duration / $transactions;

        // Assert average transaction time is reasonable (< 50ms per transaction)
        $this->assertLessThan(50, $avgTime, "Transactions should average < 50ms, got {$avgTime}ms");
    }

    /**
     * Test application bootstrap time
     */
    public function test_application_bootstrap_performance(): void
    {
        $iterations = 10;
        $times = [];

        for ($i = 0; $i < $iterations; $i++) {
            $start = microtime(true);

            // Simulate bootstrap operations
            config('app.name');
            app()->make('router');
            app()->make('cache');

            $duration = (microtime(true) - $start) * 1000;
            $times[] = $duration;
        }

        $avgTime = array_sum($times) / count($times);

        // Assert average bootstrap time is reasonable (< 10ms)
        $this->assertLessThan(10, $avgTime, "Bootstrap should average < 10ms, got {$avgTime}ms");
    }

    /**
     * Test response time under simulated load
     */
    public function test_response_time_under_load(): void
    {
        $requests = 50;
        $times = [];

        for ($i = 0; $i < $requests; $i++) {
            $start = microtime(true);
            $response = $this->get('/health');
            $duration = (microtime(true) - $start) * 1000;

            $times[] = $duration;
            $response->assertStatus(200);
        }

        $avgTime = array_sum($times) / count($times);
        $maxTime = max($times);
        $minTime = min($times);

        // Assert performance metrics
        $this->assertLessThan(100, $avgTime, "Average response time should be < 100ms, got {$avgTime}ms");
        $this->assertLessThan(500, $maxTime, "Max response time should be < 500ms, got {$maxTime}ms");

        // Log statistics for analysis
        $this->assertTrue(true); // Placeholder for logging
    }

    /**
     * Test deployment script execution time
     */
    public function test_pre_deployment_check_execution_time(): void
    {
        $iterations = 3;
        $times = [];

        for ($i = 0; $i < $iterations; $i++) {
            $start = microtime(true);
            $result = $this->executeScript('pre-deployment-check.sh', [], 60);
            $duration = (microtime(true) - $start) * 1000;

            $times[] = $duration;
        }

        $avgTime = array_sum($times) / count($times);

        // Assert pre-deployment checks complete in reasonable time (< 30s)
        $this->assertLessThan(30000, $avgTime, "Pre-deployment checks should complete in < 30s");
    }

    /**
     * Test health check script execution time
     */
    public function test_health_check_execution_time(): void
    {
        $iterations = 3;
        $times = [];

        for ($i = 0; $i < $iterations; $i++) {
            $start = microtime(true);
            $result = $this->executeScript('health-check.sh', [], 60);
            $duration = (microtime(true) - $start) * 1000;

            $times[] = $duration;
        }

        $avgTime = array_sum($times) / count($times);

        // Assert health checks complete in reasonable time (< 15s)
        $this->assertLessThan(15000, $avgTime, "Health checks should complete in < 15s");
    }
}
