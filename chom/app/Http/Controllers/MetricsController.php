<?php

namespace App\Http\Controllers;

use App\Services\Monitoring\MetricsCollector;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;

/**
 * Prometheus Metrics Export Controller
 *
 * Exposes application metrics in Prometheus text format for scraping.
 * This endpoint should be protected in production or accessed via internal network only.
 *
 * Endpoint: GET /metrics
 * Format: Prometheus text exposition format
 *
 * @see https://prometheus.io/docs/instrumenting/exposition_formats/
 */
class MetricsController extends Controller
{
    public function __construct(
        private readonly MetricsCollector $metricsCollector
    ) {}

    /**
     * Export metrics in Prometheus format.
     *
     * Returns all collected metrics in Prometheus text exposition format.
     * This endpoint is designed to be scraped by Prometheus.
     */
    public function index(): Response
    {
        $output = [];
        $namespace = config('monitoring.prometheus.namespace', 'chom');

        // Add application info metric
        $output[] = $this->formatHelp("{$namespace}_app_info", 'Application information');
        $output[] = $this->formatType("{$namespace}_app_info", 'gauge');
        $output[] = $this->formatMetric("{$namespace}_app_info", 1, [
            'version' => config('app.version', '1.0.0'),
            'environment' => config('app.env'),
            'php_version' => PHP_VERSION,
            'laravel_version' => app()->version(),
        ]);

        // Add uptime metric
        $output[] = $this->formatHelp("{$namespace}_uptime_seconds", 'Application uptime in seconds');
        $output[] = $this->formatType("{$namespace}_uptime_seconds", 'gauge');
        $startTime = defined('LARAVEL_START') ? LARAVEL_START : $_SERVER['REQUEST_TIME_FLOAT'] ?? time();
        $output[] = $this->formatMetric("{$namespace}_uptime_seconds", time() - $startTime);

        // Memory metrics
        $output[] = $this->formatHelp("{$namespace}_memory_usage_bytes", 'Current memory usage in bytes');
        $output[] = $this->formatType("{$namespace}_memory_usage_bytes", 'gauge');
        $output[] = $this->formatMetric("{$namespace}_memory_usage_bytes", memory_get_usage(true));

        $output[] = $this->formatHelp("{$namespace}_memory_peak_bytes", 'Peak memory usage in bytes');
        $output[] = $this->formatType("{$namespace}_memory_peak_bytes", 'gauge');
        $output[] = $this->formatMetric("{$namespace}_memory_peak_bytes", memory_get_peak_usage(true));

        // Disk space metrics
        $storagePath = storage_path();
        $output[] = $this->formatHelp("{$namespace}_disk_free_bytes", 'Free disk space in bytes');
        $output[] = $this->formatType("{$namespace}_disk_free_bytes", 'gauge');
        $output[] = $this->formatMetric("{$namespace}_disk_free_bytes", disk_free_space($storagePath));

        $output[] = $this->formatHelp("{$namespace}_disk_total_bytes", 'Total disk space in bytes');
        $output[] = $this->formatType("{$namespace}_disk_total_bytes", 'gauge');
        $output[] = $this->formatMetric("{$namespace}_disk_total_bytes", disk_total_space($storagePath));

        // Database connection pool metrics
        $output[] = $this->formatHelp("{$namespace}_db_connections_active", 'Number of active database connections');
        $output[] = $this->formatType("{$namespace}_db_connections_active", 'gauge');
        $output[] = $this->formatMetric("{$namespace}_db_connections_active", $this->getActiveDbConnections());

        // Get custom metrics from MetricsCollector
        $customMetrics = $this->metricsCollector->getAll();
        foreach ($customMetrics as $key => $value) {
            if ($value !== null) {
                // Clean up the metric name
                $metricName = $this->sanitizeMetricName($key);
                $output[] = $this->formatMetric("{$namespace}_{$metricName}", (float) $value);
            }
        }

        // Add health status metric
        $output[] = $this->formatHelp("{$namespace}_health_status", 'Application health status (1=healthy, 0=unhealthy)');
        $output[] = $this->formatType("{$namespace}_health_status", 'gauge');
        $output[] = $this->formatMetric("{$namespace}_health_status", $this->isHealthy() ? 1 : 0);

        // Business metrics from database (if available)
        $this->addBusinessMetrics($output, $namespace);

        return response(implode("\n", $output) . "\n", 200)
            ->header('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
    }

    /**
     * Format HELP line for Prometheus metric.
     */
    private function formatHelp(string $name, string $help): string
    {
        return "# HELP {$name} {$help}";
    }

    /**
     * Format TYPE line for Prometheus metric.
     */
    private function formatType(string $name, string $type): string
    {
        return "# TYPE {$name} {$type}";
    }

    /**
     * Format a metric line with optional labels.
     */
    private function formatMetric(string $name, float|int $value, array $labels = []): string
    {
        if (empty($labels)) {
            return "{$name} {$value}";
        }

        $labelPairs = [];
        foreach ($labels as $key => $labelValue) {
            // Escape special characters in label values
            $escapedValue = str_replace(['\\', '"', "\n"], ['\\\\', '\\"', '\\n'], (string) $labelValue);
            $labelPairs[] = "{$key}=\"{$escapedValue}\"";
        }

        $labelString = '{' . implode(',', $labelPairs) . '}';
        return "{$name}{$labelString} {$value}";
    }

    /**
     * Sanitize metric name to be Prometheus-compatible.
     */
    private function sanitizeMetricName(string $name): string
    {
        // Remove prefix if present
        $name = preg_replace('/^metrics:/', '', $name);
        // Replace invalid characters with underscores
        $name = preg_replace('/[^a-zA-Z0-9_:]/', '_', $name);
        // Ensure it doesn't start with a number
        if (preg_match('/^[0-9]/', $name)) {
            $name = '_' . $name;
        }
        return $name;
    }

    /**
     * Get active database connections count.
     */
    private function getActiveDbConnections(): int
    {
        try {
            // This works for MySQL/MariaDB
            $result = DB::select('SHOW STATUS LIKE "Threads_connected"');
            return isset($result[0]) ? (int) $result[0]->Value : 0;
        } catch (\Exception $e) {
            return 0;
        }
    }

    /**
     * Check if application is healthy.
     */
    private function isHealthy(): bool
    {
        try {
            DB::connection()->getPdo();
            return true;
        } catch (\Exception $e) {
            return false;
        }
    }

    /**
     * Add business metrics from database.
     */
    private function addBusinessMetrics(array &$output, string $namespace): void
    {
        try {
            // Total sites count
            $sitesCount = DB::table('sites')->count();
            $output[] = $this->formatHelp("{$namespace}_sites_total", 'Total number of sites');
            $output[] = $this->formatType("{$namespace}_sites_total", 'gauge');
            $output[] = $this->formatMetric("{$namespace}_sites_total", $sitesCount);

            // Sites by status
            $sitesByStatus = DB::table('sites')
                ->select('status', DB::raw('count(*) as count'))
                ->groupBy('status')
                ->get();

            $output[] = $this->formatHelp("{$namespace}_sites_by_status", 'Number of sites by status');
            $output[] = $this->formatType("{$namespace}_sites_by_status", 'gauge');
            foreach ($sitesByStatus as $status) {
                $output[] = $this->formatMetric("{$namespace}_sites_by_status", $status->count, [
                    'status' => $status->status ?? 'unknown',
                ]);
            }

            // Total tenants/organizations
            $tenantsCount = DB::table('tenants')->count();
            $output[] = $this->formatHelp("{$namespace}_tenants_total", 'Total number of tenants');
            $output[] = $this->formatType("{$namespace}_tenants_total", 'gauge');
            $output[] = $this->formatMetric("{$namespace}_tenants_total", $tenantsCount);

            // Total users
            $usersCount = DB::table('users')->count();
            $output[] = $this->formatHelp("{$namespace}_users_total", 'Total number of users');
            $output[] = $this->formatType("{$namespace}_users_total", 'gauge');
            $output[] = $this->formatMetric("{$namespace}_users_total", $usersCount);

            // Backups in last 24 hours
            $recentBackups = DB::table('site_backups')
                ->where('created_at', '>=', now()->subDay())
                ->count();
            $output[] = $this->formatHelp("{$namespace}_backups_last_24h", 'Backups created in last 24 hours');
            $output[] = $this->formatType("{$namespace}_backups_last_24h", 'gauge');
            $output[] = $this->formatMetric("{$namespace}_backups_last_24h", $recentBackups);

            // VPS servers count and status
            if (DB::getSchemaBuilder()->hasTable('vps_servers')) {
                $vpsCount = DB::table('vps_servers')->count();
                $output[] = $this->formatHelp("{$namespace}_vps_servers_total", 'Total number of VPS servers');
                $output[] = $this->formatType("{$namespace}_vps_servers_total", 'gauge');
                $output[] = $this->formatMetric("{$namespace}_vps_servers_total", $vpsCount);
            }

        } catch (\Exception $e) {
            // Log but don't fail if business metrics can't be collected
            logger()->warning('Failed to collect business metrics for Prometheus', [
                'error' => $e->getMessage(),
            ]);
        }
    }
}
