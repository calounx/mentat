<?php

declare(strict_types=1);

namespace Tests\Concerns;

use Illuminate\Support\Facades\DB;

/**
 * Provides performance testing utilities
 *
 * This trait provides methods for benchmarking operations, asserting performance
 * thresholds, and detecting N+1 query problems.
 *
 * @package Tests\Concerns
 */
trait WithPerformanceTesting
{
    /**
     * Performance benchmarks for different operations (in milliseconds)
     */
    protected array $performanceBenchmarks = [
        'dashboard_load' => 100,
        'site_creation' => 2000,
        'cache_operation' => 1,
        'database_query' => 50,
        'api_response' => 200,
        'backup_creation' => 5000,
        'restore_operation' => 10000,
    ];

    /**
     * Query count at the start of a test
     */
    protected int $queryCountStart = 0;

    /**
     * Measure execution time of a callback
     *
     * @param callable $callback
     * @return array{time: float, result: mixed}
     */
    protected function measureExecutionTime(callable $callback): array
    {
        $start = microtime(true);
        $result = $callback();
        $end = microtime(true);

        $timeMs = ($end - $start) * 1000;

        return [
            'time' => $timeMs,
            'result' => $result,
        ];
    }

    /**
     * Assert operation completes within time threshold
     *
     * @param callable $callback
     * @param float $maxTimeMs Maximum allowed time in milliseconds
     * @param string $operationName Name for error messages
     * @return mixed The result of the callback
     */
    protected function assertPerformance(
        callable $callback,
        float $maxTimeMs,
        string $operationName = 'Operation'
    ): mixed {
        $measurement = $this->measureExecutionTime($callback);

        $this->assertLessThanOrEqual(
            $maxTimeMs,
            $measurement['time'],
            sprintf(
                '%s took %.2fms, expected maximum %.2fms',
                $operationName,
                $measurement['time'],
                $maxTimeMs
            )
        );

        return $measurement['result'];
    }

    /**
     * Assert operation meets standard benchmark
     *
     * @param callable $callback
     * @param string $benchmarkKey Key from $performanceBenchmarks
     * @return mixed
     */
    protected function assertBenchmark(callable $callback, string $benchmarkKey): mixed
    {
        if (!isset($this->performanceBenchmarks[$benchmarkKey])) {
            throw new \InvalidArgumentException("Unknown benchmark: {$benchmarkKey}");
        }

        return $this->assertPerformance(
            $callback,
            $this->performanceBenchmarks[$benchmarkKey],
            ucwords(str_replace('_', ' ', $benchmarkKey))
        );
    }

    /**
     * Start tracking database queries
     *
     * @return void
     */
    protected function startQueryTracking(): void
    {
        DB::enableQueryLog();
        $this->queryCountStart = count(DB::getQueryLog());
    }

    /**
     * Get query count since tracking started
     *
     * @return int
     */
    protected function getQueryCount(): int
    {
        return count(DB::getQueryLog()) - $this->queryCountStart;
    }

    /**
     * Assert maximum number of queries
     *
     * @param int $maxQueries
     * @param string $message
     * @return void
     */
    protected function assertMaxQueries(int $maxQueries, string $message = ''): void
    {
        $actualQueries = $this->getQueryCount();

        $this->assertLessThanOrEqual(
            $maxQueries,
            $actualQueries,
            $message ?: sprintf(
                'Expected maximum %d queries, but %d were executed. Possible N+1 query problem.',
                $maxQueries,
                $actualQueries
            )
        );
    }

    /**
     * Assert no N+1 queries by comparing query counts for different dataset sizes
     *
     * @param callable $setupCallback Callback that accepts count and returns test data
     * @param callable $testCallback Callback that processes the data
     * @param int $smallSize Small dataset size
     * @param int $largeSize Large dataset size
     * @return void
     */
    protected function assertNoN1Queries(
        callable $setupCallback,
        callable $testCallback,
        int $smallSize = 2,
        int $largeSize = 10
    ): void {
        // Test with small dataset
        $this->startQueryTracking();
        $smallData = $setupCallback($smallSize);
        $testCallback($smallData);
        $smallQueryCount = $this->getQueryCount();

        // Reset and test with large dataset
        DB::flushQueryLog();
        $this->startQueryTracking();
        $largeData = $setupCallback($largeSize);
        $testCallback($largeData);
        $largeQueryCount = $this->getQueryCount();

        // Query count should be the same regardless of dataset size
        $this->assertEquals(
            $smallQueryCount,
            $largeQueryCount,
            sprintf(
                'N+1 query detected: %d queries for %d items, %d queries for %d items',
                $smallQueryCount,
                $smallSize,
                $largeQueryCount,
                $largeSize
            )
        );
    }

    /**
     * Benchmark and compare multiple approaches
     *
     * @param array $approaches Array of ['name' => callable]
     * @param int $iterations Number of iterations
     * @return array Performance comparison results
     */
    protected function benchmarkApproaches(array $approaches, int $iterations = 100): array
    {
        $results = [];

        foreach ($approaches as $name => $callback) {
            $times = [];

            for ($i = 0; $i < $iterations; $i++) {
                $measurement = $this->measureExecutionTime($callback);
                $times[] = $measurement['time'];
            }

            $results[$name] = [
                'avg' => array_sum($times) / count($times),
                'min' => min($times),
                'max' => max($times),
                'median' => $this->calculateMedian($times),
            ];
        }

        return $results;
    }

    /**
     * Calculate median from array of numbers
     *
     * @param array $numbers
     * @return float
     */
    private function calculateMedian(array $numbers): float
    {
        sort($numbers);
        $count = count($numbers);
        $middle = floor($count / 2);

        if ($count % 2 === 0) {
            return ($numbers[$middle - 1] + $numbers[$middle]) / 2;
        }

        return $numbers[$middle];
    }

    /**
     * Assert cache hit rate
     *
     * @param callable $callback
     * @param float $minHitRate Minimum expected hit rate (0-1)
     * @return void
     */
    protected function assertCacheHitRate(callable $callback, float $minHitRate = 0.8): void
    {
        $hits = 0;
        $total = 10;

        for ($i = 0; $i < $total; $i++) {
            $cached = $callback();
            if ($cached) {
                $hits++;
            }
        }

        $hitRate = $hits / $total;

        $this->assertGreaterThanOrEqual(
            $minHitRate,
            $hitRate,
            sprintf(
                'Cache hit rate %.2f%% is below minimum %.2f%%',
                $hitRate * 100,
                $minHitRate * 100
            )
        );
    }

    /**
     * Get detailed query log
     *
     * @return array
     */
    protected function getDetailedQueryLog(): array
    {
        return collect(DB::getQueryLog())
            ->skip($this->queryCountStart)
            ->map(fn($query) => [
                'query' => $query['query'],
                'bindings' => $query['bindings'],
                'time' => $query['time'],
            ])
            ->toArray();
    }

    /**
     * Assert query uses index
     *
     * @param string $query
     * @param array $bindings
     * @return void
     */
    protected function assertQueryUsesIndex(string $query, array $bindings = []): void
    {
        $explain = DB::select("EXPLAIN {$query}", $bindings);

        $usesIndex = collect($explain)->contains(function ($row) {
            $possibleKey = $row->possible_keys ?? $row->POSSIBLE_KEYS ?? null;
            return $possibleKey !== null && $possibleKey !== '';
        });

        $this->assertTrue(
            $usesIndex,
            'Query does not use an index. Consider adding appropriate indexes.'
        );
    }

    /**
     * Profile memory usage
     *
     * @param callable $callback
     * @return array{memory_peak: int, memory_used: int, result: mixed}
     */
    protected function profileMemory(callable $callback): array
    {
        $memoryBefore = memory_get_usage(true);
        $peakBefore = memory_get_peak_usage(true);

        $result = $callback();

        $memoryAfter = memory_get_usage(true);
        $peakAfter = memory_get_peak_usage(true);

        return [
            'memory_peak' => $peakAfter - $peakBefore,
            'memory_used' => $memoryAfter - $memoryBefore,
            'result' => $result,
        ];
    }

    /**
     * Assert memory usage is below threshold
     *
     * @param callable $callback
     * @param int $maxMemoryBytes
     * @return mixed
     */
    protected function assertMemoryUsage(callable $callback, int $maxMemoryBytes): mixed
    {
        $profile = $this->profileMemory($callback);

        $this->assertLessThanOrEqual(
            $maxMemoryBytes,
            $profile['memory_used'],
            sprintf(
                'Memory usage %s exceeded maximum %s',
                $this->formatBytes($profile['memory_used']),
                $this->formatBytes($maxMemoryBytes)
            )
        );

        return $profile['result'];
    }

    /**
     * Format bytes to human-readable string
     *
     * @param int $bytes
     * @return string
     */
    private function formatBytes(int $bytes): string
    {
        $units = ['B', 'KB', 'MB', 'GB'];
        $i = 0;

        while ($bytes >= 1024 && $i < count($units) - 1) {
            $bytes /= 1024;
            $i++;
        }

        return round($bytes, 2) . ' ' . $units[$i];
    }
}
