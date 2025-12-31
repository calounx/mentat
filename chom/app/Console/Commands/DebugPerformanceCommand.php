<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

class DebugPerformanceCommand extends Command
{
    protected $signature = 'debug:performance {route? : Route to profile (e.g., /api/v1/sites)}';

    protected $description = 'Debug and profile application performance';

    public function handle(): int
    {
        $this->components->info('Performance Debug Information');
        $this->newLine();

        // Database performance
        $this->components->info('Database Performance:');

        // Enable query logging
        DB::enableQueryLog();

        // Run a sample query
        $start = microtime(true);
        DB::table('users')->count();
        $queryTime = (microtime(true) - $start) * 1000;

        $queries = DB::getQueryLog();

        $this->table(
            ['Metric', 'Value'],
            [
                ['Query Count', count($queries)],
                ['Sample Query Time', round($queryTime, 2) . ' ms'],
                ['Connection', DB::getDriverName()],
            ]
        );

        // Show slow queries if any
        if (count($queries) > 0) {
            $this->newLine();
            $this->components->info('Recent Queries:');

            foreach ($queries as $query) {
                $time = round($query['time'], 2);
                $color = $time > 100 ? 'error' : ($time > 50 ? 'warn' : 'info');
                $this->components->{$color}("  [{$time}ms] {$query['query']}");
            }
        }

        // Memory usage
        $this->newLine();
        $this->components->info('Memory Usage:');
        $this->table(
            ['Metric', 'Value'],
            [
                ['Current Usage', $this->formatBytes(memory_get_usage())],
                ['Peak Usage', $this->formatBytes(memory_get_peak_usage())],
                ['Memory Limit', ini_get('memory_limit')],
            ]
        );

        // PHP configuration
        $this->newLine();
        $this->components->info('PHP Configuration:');
        $this->table(
            ['Setting', 'Value'],
            [
                ['Version', PHP_VERSION],
                ['Max Execution Time', ini_get('max_execution_time') . 's'],
                ['Memory Limit', ini_get('memory_limit')],
                ['Upload Max Filesize', ini_get('upload_max_filesize')],
                ['Post Max Size', ini_get('post_max_size')],
                ['OPcache Enabled', ini_get('opcache.enable') ? 'Yes' : 'No'],
            ]
        );

        // Cache performance
        $this->newLine();
        $this->components->info('Cache Performance:');

        $cacheStart = microtime(true);
        cache()->put('perf_test', 'value', 60);
        $writeTime = (microtime(true) - $cacheStart) * 1000;

        $readStart = microtime(true);
        cache()->get('perf_test');
        $readTime = (microtime(true) - $readStart) * 1000;

        cache()->forget('perf_test');

        $this->table(
            ['Operation', 'Time'],
            [
                ['Cache Write', round($writeTime, 2) . ' ms'],
                ['Cache Read', round($readTime, 2) . ' ms'],
            ]
        );

        // Route profiling
        if ($routePath = $this->argument('route')) {
            $this->newLine();
            $this->components->info("Profiling Route: {$routePath}");

            $route = Route::getRoutes()->match(
                \Illuminate\Http\Request::create($routePath, 'GET')
            );

            if ($route) {
                $this->table(
                    ['Property', 'Value'],
                    [
                        ['URI', $route->uri()],
                        ['Methods', implode(', ', $route->methods())],
                        ['Action', $route->getActionName()],
                        ['Middleware', implode(', ', $route->gatherMiddleware())],
                    ]
                );
            } else {
                $this->components->error("Route not found: {$routePath}");
            }
        }

        // Load testing recommendations
        $this->newLine();
        $this->components->info('Performance Recommendations:');

        $issues = [];

        if (!extension_loaded('opcache') || !ini_get('opcache.enable')) {
            $issues[] = 'OPcache is not enabled - enable it for better PHP performance';
        }

        if (config('app.debug') === true) {
            $issues[] = 'Debug mode is enabled - disable it in production for better performance';
        }

        if (config('cache.default') === 'file') {
            $issues[] = 'Using file cache - consider Redis for better performance';
        }

        if (config('queue.default') === 'sync') {
            $issues[] = 'Using sync queue driver - use Redis or database for async processing';
        }

        $memoryLimit = ini_get('memory_limit');
        if ($memoryLimit !== '-1' && intval($memoryLimit) < 256) {
            $issues[] = "Memory limit is low ({$memoryLimit}) - consider increasing to at least 256M";
        }

        if (count($issues) > 0) {
            foreach ($issues as $issue) {
                $this->components->warn("- {$issue}");
            }
        } else {
            $this->components->info('Configuration looks good!');
        }

        // Profiling tips
        $this->newLine();
        $this->components->info('Profiling Tips:');
        $this->line('- Use Laravel Telescope for detailed request profiling');
        $this->line('- Use Laravel Debugbar for development debugging');
        $this->line('- Use php artisan optimize to cache config, routes, and views');
        $this->line('- Use eager loading to avoid N+1 query problems');
        $this->line('- Use database indexes on frequently queried columns');
        $this->line('- Use Redis for caching and sessions');
        $this->line('- Use queue workers for long-running tasks');

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
