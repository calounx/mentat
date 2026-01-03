<?php

declare(strict_types=1);

namespace Tests\Unit\Services;

use App\Services\MetricsCollector;
use Illuminate\Support\Facades\Cache;
use Tests\TestCase;

class MetricsCollectorTest extends TestCase
{
    private MetricsCollector $collector;

    protected function setUp(): void
    {
        parent::setUp();

        $this->collector = new MetricsCollector();
        Cache::flush();
    }

    protected function tearDown(): void
    {
        Cache::flush();
        parent::tearDown();
    }

    public function test_increments_counter_metric(): void
    {
        $this->collector->incrementCounter('requests_total', 1, ['method' => 'GET']);

        $value = $this->collector->getCounter('requests_total', ['method' => 'GET']);

        $this->assertEquals(1, $value);
    }

    public function test_increments_counter_multiple_times(): void
    {
        $this->collector->incrementCounter('requests_total', 1);
        $this->collector->incrementCounter('requests_total', 1);
        $this->collector->incrementCounter('requests_total', 3);

        $value = $this->collector->getCounter('requests_total');

        $this->assertEquals(5, $value);
    }

    public function test_increments_counter_with_custom_amount(): void
    {
        $this->collector->incrementCounter('items_processed', 10);
        $this->collector->incrementCounter('items_processed', 25);

        $value = $this->collector->getCounter('items_processed');

        $this->assertEquals(35, $value);
    }

    public function test_records_gauge_metric(): void
    {
        $this->collector->gauge('active_connections', 42, ['server' => 'web-1']);

        $value = $this->collector->getGauge('active_connections', ['server' => 'web-1']);

        $this->assertEquals(42, $value);
    }

    public function test_gauge_overwrites_previous_value(): void
    {
        $this->collector->gauge('memory_usage', 100);
        $this->collector->gauge('memory_usage', 150);

        $value = $this->collector->getGauge('memory_usage');

        $this->assertEquals(150, $value);
    }

    public function test_records_histogram_metric(): void
    {
        $durations = [10.5, 25.3, 15.7, 45.2, 32.1];

        foreach ($durations as $duration) {
            $this->collector->histogram('request_duration_ms', $duration);
        }

        $stats = $this->collector->getHistogramStats('request_duration_ms');

        $this->assertArrayHasKey('count', $stats);
        $this->assertArrayHasKey('sum', $stats);
        $this->assertArrayHasKey('avg', $stats);
        $this->assertArrayHasKey('min', $stats);
        $this->assertArrayHasKey('max', $stats);

        $this->assertEquals(5, $stats['count']);
        $this->assertEquals(10.5, $stats['min']);
        $this->assertEquals(45.2, $stats['max']);
    }

    public function test_calculates_histogram_percentiles(): void
    {
        // Add 100 values
        for ($i = 1; $i <= 100; $i++) {
            $this->collector->histogram('response_time', $i);
        }

        $percentiles = $this->collector->getPercentiles('response_time', [50, 90, 95, 99]);

        $this->assertArrayHasKey('p50', $percentiles);
        $this->assertArrayHasKey('p90', $percentiles);
        $this->assertArrayHasKey('p95', $percentiles);
        $this->assertArrayHasKey('p99', $percentiles);

        $this->assertEqualsWithDelta(50, $percentiles['p50'], 5);
        $this->assertEqualsWithDelta(90, $percentiles['p90'], 5);
        $this->assertEqualsWithDelta(95, $percentiles['p95'], 5);
        $this->assertEqualsWithDelta(99, $percentiles['p99'], 5);
    }

    public function test_records_timing_metric(): void
    {
        $this->collector->recordTiming('db_query_duration', 25.5, ['query' => 'select']);

        $stats = $this->collector->getHistogramStats('db_query_duration');

        $this->assertEquals(1, $stats['count']);
        $this->assertEquals(25.5, $stats['sum']);
        $this->assertEquals(25.5, $stats['avg']);
    }

    public function test_records_metric_with_value(): void
    {
        $this->collector->recordMetric('cpu_usage_percent', 75.5, ['cpu' => 'cpu0']);

        $value = $this->collector->getGauge('cpu_usage_percent', ['cpu' => 'cpu0']);

        $this->assertEquals(75.5, $value);
    }

    public function test_separate_counters_for_different_tags(): void
    {
        $this->collector->incrementCounter('requests', 5, ['method' => 'GET']);
        $this->collector->incrementCounter('requests', 3, ['method' => 'POST']);

        $getRequests = $this->collector->getCounter('requests', ['method' => 'GET']);
        $postRequests = $this->collector->getCounter('requests', ['method' => 'POST']);

        $this->assertEquals(5, $getRequests);
        $this->assertEquals(3, $postRequests);
    }

    public function test_lists_all_metrics(): void
    {
        $this->collector->incrementCounter('metric1', 1);
        $this->collector->gauge('metric2', 100);
        $this->collector->histogram('metric3', 50);

        $metrics = $this->collector->getAllMetrics();

        $this->assertIsArray($metrics);
        $this->assertArrayHasKey('counters', $metrics);
        $this->assertArrayHasKey('gauges', $metrics);
        $this->assertArrayHasKey('histograms', $metrics);
    }

    public function test_exports_metrics_in_prometheus_format(): void
    {
        $this->collector->incrementCounter('http_requests_total', 100, ['status' => '200']);
        $this->collector->gauge('memory_usage_bytes', 1024000);

        $prometheusOutput = $this->collector->exportPrometheusFormat();

        $this->assertIsString($prometheusOutput);
        $this->assertStringContainsString('http_requests_total', $prometheusOutput);
        $this->assertStringContainsString('memory_usage_bytes', $prometheusOutput);
        $this->assertStringContainsString('100', $prometheusOutput);
        $this->assertStringContainsString('1024000', $prometheusOutput);
    }

    public function test_resets_metrics(): void
    {
        $this->collector->incrementCounter('test_counter', 10);
        $this->collector->gauge('test_gauge', 50);

        $this->collector->reset();

        $this->assertEquals(0, $this->collector->getCounter('test_counter'));
        $this->assertEquals(0, $this->collector->getGauge('test_gauge'));
    }

    public function test_resets_specific_metric(): void
    {
        $this->collector->incrementCounter('keep_counter', 10);
        $this->collector->incrementCounter('reset_counter', 20);

        $this->collector->resetMetric('reset_counter');

        $this->assertEquals(10, $this->collector->getCounter('keep_counter'));
        $this->assertEquals(0, $this->collector->getCounter('reset_counter'));
    }

    public function test_tracks_metric_timestamps(): void
    {
        $this->collector->incrementCounter('timed_metric', 1);

        $timestamp = $this->collector->getMetricTimestamp('timed_metric');

        $this->assertNotNull($timestamp);
        $this->assertEqualsWithDelta(time(), $timestamp, 2);
    }

    public function test_aggregates_metrics_over_time_window(): void
    {
        // Record metrics over time
        for ($i = 0; $i < 10; $i++) {
            $this->collector->incrementCounter('requests_per_minute', 1, [
                'timestamp' => now()->subSeconds($i * 6)->timestamp,
            ]);
        }

        $aggregated = $this->collector->aggregateByTimeWindow('requests_per_minute', 60);

        $this->assertIsArray($aggregated);
        $this->assertArrayHasKey('total', $aggregated);
        $this->assertEquals(10, $aggregated['total']);
    }

    public function test_calculates_rate_per_second(): void
    {
        $startTime = microtime(true);

        for ($i = 0; $i < 100; $i++) {
            $this->collector->incrementCounter('rate_test', 1);
        }

        sleep(1);

        $rate = $this->collector->getRate('rate_test');

        $this->assertGreaterThan(0, $rate);
        $this->assertLessThan(150, $rate); // Should be around 100/s
    }

    public function test_tracks_http_metrics(): void
    {
        $this->collector->recordHttpRequest('GET', '/api/sites', 200, 25.5);

        $metrics = $this->collector->getHttpMetrics();

        $this->assertArrayHasKey('requests_total', $metrics);
        $this->assertArrayHasKey('request_duration', $metrics);
    }

    public function test_tracks_database_metrics(): void
    {
        $this->collector->recordDatabaseQuery('SELECT', 'users', 15.2);

        $metrics = $this->collector->getDatabaseMetrics();

        $this->assertArrayHasKey('queries_total', $metrics);
        $this->assertArrayHasKey('query_duration', $metrics);
    }

    public function test_tracks_cache_metrics(): void
    {
        $this->collector->recordCacheHit('user:123');
        $this->collector->recordCacheMiss('user:456');

        $metrics = $this->collector->getCacheMetrics();

        $this->assertArrayHasKey('hits', $metrics);
        $this->assertArrayHasKey('misses', $metrics);
        $this->assertArrayHasKey('hit_rate', $metrics);

        $this->assertEquals(1, $metrics['hits']);
        $this->assertEquals(1, $metrics['misses']);
        $this->assertEquals(50.0, $metrics['hit_rate']);
    }

    public function test_tracks_queue_metrics(): void
    {
        $this->collector->recordJobProcessed('SendEmailJob', 125.5, 'success');
        $this->collector->recordJobProcessed('GenerateReportJob', 500.2, 'failed');

        $metrics = $this->collector->getQueueMetrics();

        $this->assertArrayHasKey('jobs_processed', $metrics);
        $this->assertArrayHasKey('jobs_failed', $metrics);
        $this->assertArrayHasKey('processing_duration', $metrics);
    }

    public function test_tracks_business_metrics(): void
    {
        $this->collector->recordBusinessMetric('sites_created', 5);
        $this->collector->recordBusinessMetric('backups_completed', 12);
        $this->collector->recordBusinessMetric('revenue_usd', 1250.50);

        $sitesCreated = $this->collector->getCounter('sites_created');
        $backupsCompleted = $this->collector->getCounter('backups_completed');
        $revenue = $this->collector->getGauge('revenue_usd');

        $this->assertEquals(5, $sitesCreated);
        $this->assertEquals(12, $backupsCompleted);
        $this->assertEquals(1250.50, $revenue);
    }

    public function test_handles_concurrent_metric_updates(): void
    {
        $iterations = 100;

        for ($i = 0; $i < $iterations; $i++) {
            $this->collector->incrementCounter('concurrent_test', 1);
        }

        $value = $this->collector->getCounter('concurrent_test');

        $this->assertEquals($iterations, $value);
    }

    public function test_prevents_metric_name_collision(): void
    {
        $this->collector->incrementCounter('test_metric', 5);
        $this->collector->gauge('test_metric_gauge', 10);

        $counter = $this->collector->getCounter('test_metric');
        $gauge = $this->collector->getGauge('test_metric_gauge');

        $this->assertEquals(5, $counter);
        $this->assertEquals(10, $gauge);
    }

    public function test_validates_metric_names(): void
    {
        $validNames = [
            'http_requests_total',
            'cpu_usage_percent',
            'memory_available_bytes',
        ];

        foreach ($validNames as $name) {
            $this->assertTrue($this->collector->isValidMetricName($name));
        }

        $invalidNames = [
            'invalid name',
            'invalid-name!',
            '123_starts_with_number',
        ];

        foreach ($invalidNames as $name) {
            $this->assertFalse($this->collector->isValidMetricName($name));
        }
    }

    public function test_performance_with_many_metrics(): void
    {
        $startTime = microtime(true);

        for ($i = 0; $i < 1000; $i++) {
            $this->collector->incrementCounter('perf_test', 1);
            $this->collector->gauge('gauge_test', $i);
            $this->collector->histogram('histogram_test', $i * 0.5);
        }

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // 3000 metric operations should complete in under 500ms
        $this->assertLessThan(500, $duration);
    }

    public function test_memory_efficiency_with_large_dataset(): void
    {
        $memoryBefore = memory_get_usage();

        for ($i = 0; $i < 10000; $i++) {
            $this->collector->histogram('memory_test', $i);
        }

        $memoryAfter = memory_get_usage();
        $memoryUsed = ($memoryAfter - $memoryBefore) / 1024 / 1024; // MB

        // Should use less than 10MB for 10,000 histogram values
        $this->assertLessThan(10, $memoryUsed);
    }
}
