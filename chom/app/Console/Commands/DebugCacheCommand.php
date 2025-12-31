<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Redis;

class DebugCacheCommand extends Command
{
    protected $signature = 'debug:cache {--flush : Flush all caches}';

    protected $description = 'Debug cache configuration and status';

    public function handle(): int
    {
        $this->components->info('Cache Debug Information');
        $this->newLine();

        // Display cache configuration
        $this->components->info('Cache Configuration:');
        $this->table(
            ['Setting', 'Value'],
            [
                ['Default Driver', config('cache.default')],
                ['Cache Prefix', config('cache.prefix')],
                ['Redis Client', config('database.redis.client')],
                ['Redis Host', config('database.redis.default.host')],
                ['Redis Port', config('database.redis.default.port')],
            ]
        );

        // Test cache connection
        $this->newLine();
        $this->components->info('Testing Cache Connection:');

        try {
            $testKey = 'cache_debug_test_' . time();
            $testValue = 'test_value_' . rand(1000, 9999);

            Cache::put($testKey, $testValue, 60);
            $retrieved = Cache::get($testKey);

            if ($retrieved === $testValue) {
                $this->components->info('✓ Cache write/read test passed');
                Cache::forget($testKey);
            } else {
                $this->components->error('✗ Cache write/read test failed');
            }
        } catch (\Exception $e) {
            $this->components->error("✗ Cache test failed: {$e->getMessage()}");
        }

        // Redis-specific debugging
        if (config('cache.default') === 'redis') {
            $this->newLine();
            $this->components->info('Redis Information:');

            try {
                $redis = Redis::connection();

                // Get server info
                $info = $redis->info();

                $this->table(
                    ['Metric', 'Value'],
                    [
                        ['Version', $info['redis_version'] ?? 'N/A'],
                        ['Uptime (days)', round(($info['uptime_in_seconds'] ?? 0) / 86400, 2)],
                        ['Connected Clients', $info['connected_clients'] ?? 'N/A'],
                        ['Used Memory', $this->formatBytes($info['used_memory'] ?? 0)],
                        ['Total Keys', $redis->dbsize()],
                        ['Hits', $info['keyspace_hits'] ?? 'N/A'],
                        ['Misses', $info['keyspace_misses'] ?? 'N/A'],
                    ]
                );

                // Check if specific databases have keys
                $this->newLine();
                $this->components->info('Redis Database Keys:');
                $databases = [];

                foreach (['cache', 'queue', 'session'] as $connection) {
                    try {
                        $conn = Redis::connection($connection);
                        $db = config("database.redis.{$connection}.database", 0);
                        $count = $conn->dbsize();
                        $databases[] = [ucfirst($connection), "DB {$db}", $count];
                    } catch (\Exception $e) {
                        $databases[] = [ucfirst($connection), 'N/A', 'Error'];
                    }
                }

                $this->table(['Connection', 'Database', 'Keys'], $databases);

                // Sample keys
                $this->newLine();
                $this->components->info('Sample Cache Keys (first 10):');
                $prefix = config('cache.prefix', 'laravel_cache');
                $keys = $redis->keys("{$prefix}:*");

                if (count($keys) > 0) {
                    $sampleKeys = array_slice($keys, 0, 10);
                    foreach ($sampleKeys as $key) {
                        $ttl = $redis->ttl($key);
                        $ttlInfo = $ttl > 0 ? "TTL: {$ttl}s" : ($ttl === -1 ? 'No expiry' : 'Expired');
                        $this->line("  - {$key} ({$ttlInfo})");
                    }

                    if (count($keys) > 10) {
                        $this->line("  ... and " . (count($keys) - 10) . " more keys");
                    }
                } else {
                    $this->line('  No keys found');
                }

            } catch (\Exception $e) {
                $this->components->error("Redis connection failed: {$e->getMessage()}");
            }
        }

        // Flush option
        if ($this->option('flush')) {
            $this->newLine();
            if ($this->confirm('Are you sure you want to flush all caches?', false)) {
                Cache::flush();
                $this->components->info('✓ All caches flushed successfully');
            }
        }

        // Recommendations
        $this->newLine();
        $this->components->info('Recommendations:');

        $issues = [];

        if (config('cache.default') === 'file') {
            $issues[] = 'Using file cache driver - consider Redis for better performance';
        }

        if (config('cache.default') === 'redis' && !extension_loaded('redis')) {
            $issues[] = 'Redis driver selected but phpredis extension not loaded';
        }

        if (empty(config('cache.prefix'))) {
            $issues[] = 'No cache prefix set - may cause key conflicts in shared Redis instances';
        }

        if (count($issues) > 0) {
            foreach ($issues as $issue) {
                $this->components->warn("- {$issue}");
            }
        } else {
            $this->components->info('No issues found!');
        }

        return self::SUCCESS;
    }

    /**
     * Format bytes to human-readable format.
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
