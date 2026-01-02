<?php

namespace App\Livewire\Admin;

use App\Services\Monitoring\MetricsCollector;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use Livewire\Component;

class PerformanceDashboard extends Component
{
    public array $metrics = [];

    public array $systemMetrics = [];

    public array $databaseMetrics = [];

    public array $cacheMetrics = [];

    public array $queueMetrics = [];

    public int $refreshInterval = 5000; // milliseconds

    protected MetricsCollector $metricsCollector;

    public function boot(MetricsCollector $metricsCollector): void
    {
        $this->metricsCollector = $metricsCollector;
    }

    public function mount(): void
    {
        $this->loadMetrics();
    }

    public function refresh(): void
    {
        $this->loadMetrics();
    }

    protected function loadMetrics(): void
    {
        $this->systemMetrics = $this->getSystemMetrics();
        $this->databaseMetrics = $this->getDatabaseMetrics();
        $this->cacheMetrics = $this->getCacheMetrics();
        $this->queueMetrics = $this->getQueueMetrics();
        $this->metrics = $this->getApplicationMetrics();
    }

    protected function getSystemMetrics(): array
    {
        $memoryLimit = $this->convertToBytes(ini_get('memory_limit'));
        $memoryUsage = memory_get_usage(true);
        $memoryPeak = memory_get_peak_usage(true);

        $storagePath = storage_path();
        $diskFree = disk_free_space($storagePath);
        $diskTotal = disk_total_space($storagePath);
        $diskUsed = $diskTotal - $diskFree;

        return [
            'memory' => [
                'current' => $this->formatBytes($memoryUsage),
                'peak' => $this->formatBytes($memoryPeak),
                'limit' => ini_get('memory_limit'),
                'percentage' => $memoryLimit > 0 ? round(($memoryUsage / $memoryLimit) * 100, 2) : 0,
            ],
            'disk' => [
                'free' => $this->formatBytes($diskFree),
                'used' => $this->formatBytes($diskUsed),
                'total' => $this->formatBytes($diskTotal),
                'percentage' => round(($diskUsed / $diskTotal) * 100, 2),
            ],
            'php' => [
                'version' => PHP_VERSION,
                'max_execution_time' => ini_get('max_execution_time'),
                'post_max_size' => ini_get('post_max_size'),
                'upload_max_filesize' => ini_get('upload_max_filesize'),
            ],
        ];
    }

    protected function getDatabaseMetrics(): array
    {
        try {
            // Get connection status
            $connected = DB::connection()->getPdo() !== null;

            // Get database size (MySQL)
            $dbName = DB::connection()->getDatabaseName();
            $driver = DB::connection()->getDriverName();

            $size = null;
            if ($driver === 'mysql') {
                $result = DB::select('
                    SELECT
                        SUM(data_length + index_length) as size
                    FROM information_schema.TABLES
                    WHERE table_schema = ?
                ', [$dbName]);

                $size = $result[0]->size ?? 0;
            }

            // Get slow query log status
            $slowQueryThreshold = config('monitoring.performance.slow_query_threshold', 1000);

            return [
                'connected' => $connected,
                'driver' => $driver,
                'database' => $dbName,
                'size' => $size ? $this->formatBytes($size) : 'N/A',
                'slow_query_threshold' => $slowQueryThreshold.'ms',
            ];
        } catch (\Exception $e) {
            return [
                'connected' => false,
                'error' => $e->getMessage(),
            ];
        }
    }

    protected function getCacheMetrics(): array
    {
        try {
            $driver = config('cache.default');
            $connected = false;
            $info = [];

            if ($driver === 'redis') {
                Redis::ping();
                $connected = true;

                $redisInfo = Redis::info();
                $info = [
                    'used_memory' => $redisInfo['used_memory_human'] ?? 'N/A',
                    'connected_clients' => $redisInfo['connected_clients'] ?? 'N/A',
                    'total_commands' => $redisInfo['total_commands_processed'] ?? 'N/A',
                    'keyspace_hits' => $redisInfo['keyspace_hits'] ?? 0,
                    'keyspace_misses' => $redisInfo['keyspace_misses'] ?? 0,
                ];

                $hits = (int) ($info['keyspace_hits'] ?? 0);
                $misses = (int) ($info['keyspace_misses'] ?? 0);
                $total = $hits + $misses;

                $info['hit_rate'] = $total > 0 ? round(($hits / $total) * 100, 2).'%' : 'N/A';
            }

            return [
                'driver' => $driver,
                'connected' => $connected,
                'info' => $info,
            ];
        } catch (\Exception $e) {
            return [
                'driver' => config('cache.default'),
                'connected' => false,
                'error' => $e->getMessage(),
            ];
        }
    }

    protected function getQueueMetrics(): array
    {
        try {
            $driver = config('queue.default');
            $connection = config("queue.connections.{$driver}");

            return [
                'driver' => $driver,
                'connection' => $connection['connection'] ?? 'N/A',
                'queue' => $connection['queue'] ?? 'default',
            ];
        } catch (\Exception $e) {
            return [
                'driver' => config('queue.default'),
                'error' => $e->getMessage(),
            ];
        }
    }

    protected function getApplicationMetrics(): array
    {
        $metrics = [];

        // Try to get recent metrics from MetricsCollector
        try {
            $recentMetrics = $this->metricsCollector->getAll('*request*');

            // Calculate average response time
            $responseTimes = [];
            foreach ($recentMetrics as $key => $value) {
                if (str_contains($key, 'duration')) {
                    $responseTimes[] = (float) $value;
                }
            }

            if (! empty($responseTimes)) {
                $metrics['avg_response_time'] = round(array_sum($responseTimes) / count($responseTimes), 2).'ms';
            } else {
                $metrics['avg_response_time'] = 'N/A';
            }

            $metrics['total_requests'] = count($recentMetrics);
        } catch (\Exception $e) {
            $metrics['error'] = $e->getMessage();
        }

        $metrics['environment'] = config('app.env');
        $metrics['debug_mode'] = config('app.debug') ? 'Enabled' : 'Disabled';
        $metrics['laravel_version'] = app()->version();

        return $metrics;
    }

    protected function convertToBytes(string $value): int
    {
        if ($value === '-1') {
            return -1;
        }

        $value = trim($value);
        $last = strtolower($value[strlen($value) - 1] ?? '');
        $value = (int) $value;

        return match ($last) {
            'g' => $value * 1024 * 1024 * 1024,
            'm' => $value * 1024 * 1024,
            'k' => $value * 1024,
            default => $value,
        };
    }

    protected function formatBytes(int $bytes, int $precision = 2): string
    {
        $units = ['B', 'KB', 'MB', 'GB', 'TB'];

        for ($i = 0; $bytes > 1024 && $i < count($units) - 1; $i++) {
            $bytes /= 1024;
        }

        return round($bytes, $precision).' '.$units[$i];
    }

    public function render()
    {
        return view('livewire.admin.performance-dashboard');
    }
}
