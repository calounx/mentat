<?php

declare(strict_types=1);

namespace Tests\Unit\Services\Observability;

use App\Services\MetricsCollector;
use Illuminate\Support\Facades\Redis;
use Tests\TestCase;

class MetricsCollectorTest extends TestCase
{
    private MetricsCollector $metrics;

    protected function setUp(): void
    {
        parent::setUp();
        $this->metrics = new MetricsCollector();

        // Clear metrics before each test
        $this->metrics->clear();
    }

    protected function tearDown(): void
    {
        // Clean up metrics after each test
        $this->metrics->clear();
        parent::tearDown();
    }

    public function test_increment_counter(): void
    {
        $this->metrics->incrementCounter('test_counter', ['label' => 'value']);
        $this->metrics->incrementCounter('test_counter', ['label' => 'value'], 5.0);

        $export = $this->metrics->export();

        $this->assertStringContainsString('test_counter', $export);
        $this->assertStringContainsString('label="value"', $export);
    }

    public function test_set_gauge(): void
    {
        $this->metrics->setGauge('test_gauge', 42.5, ['type' => 'test']);

        $export = $this->metrics->export();

        $this->assertStringContainsString('test_gauge', $export);
        $this->assertStringContainsString('42.5', $export);
    }

    public function test_increment_gauge(): void
    {
        $this->metrics->setGauge('test_gauge', 10.0);
        $this->metrics->incrementGauge('test_gauge', 5.0);

        $export = $this->metrics->export();

        $this->assertStringContainsString('test_gauge', $export);
        $this->assertStringContainsString('15', $export);
    }

    public function test_decrement_gauge(): void
    {
        $this->metrics->setGauge('test_gauge', 10.0);
        $this->metrics->decrementGauge('test_gauge', 3.0);

        $export = $this->metrics->export();

        $this->assertStringContainsString('test_gauge', $export);
        $this->assertStringContainsString('7', $export);
    }

    public function test_observe_histogram(): void
    {
        $this->metrics->observeHistogram('test_duration', 0.15, ['operation' => 'test']);
        $this->metrics->observeHistogram('test_duration', 0.25, ['operation' => 'test']);
        $this->metrics->observeHistogram('test_duration', 0.35, ['operation' => 'test']);

        $export = $this->metrics->export();

        $this->assertStringContainsString('test_duration_count', $export);
        $this->assertStringContainsString('test_duration_sum', $export);
        $this->assertStringContainsString('test_duration_bucket', $export);
    }

    public function test_record_http_request(): void
    {
        $this->metrics->recordHttpRequest('GET', 'api.users.index', 200, 0.125);

        $export = $this->metrics->export();

        $this->assertStringContainsString('http_requests_total', $export);
        $this->assertStringContainsString('http_request_duration_seconds', $export);
        $this->assertStringContainsString('method="GET"', $export);
        $this->assertStringContainsString('status="200"', $export);
    }

    public function test_record_http_request_with_error(): void
    {
        $this->metrics->recordHttpRequest('POST', 'api.sites.store', 500, 0.05);

        $export = $this->metrics->export();

        $this->assertStringContainsString('http_requests_errors_total', $export);
        $this->assertStringContainsString('status="500"', $export);
    }

    public function test_record_database_query(): void
    {
        $this->metrics->recordDatabaseQuery('SELECT * FROM users', 0.015, 'mysql');

        $export = $this->metrics->export();

        $this->assertStringContainsString('db_queries_total', $export);
        $this->assertStringContainsString('db_query_duration_seconds', $export);
        $this->assertStringContainsString('type="select"', $export);
    }

    public function test_record_slow_database_query(): void
    {
        // Record a slow query (> 100ms threshold)
        $this->metrics->recordDatabaseQuery('SELECT * FROM large_table', 0.15, 'mysql');

        $export = $this->metrics->export();

        $this->assertStringContainsString('db_queries_slow_total', $export);
    }

    public function test_record_cache_operation(): void
    {
        $this->metrics->recordCacheOperation('hit', 'redis');
        $this->metrics->recordCacheOperation('miss', 'redis');

        $export = $this->metrics->export();

        $this->assertStringContainsString('cache_operations_total', $export);
        $this->assertStringContainsString('operation="hit"', $export);
        $this->assertStringContainsString('operation="miss"', $export);
    }

    public function test_record_queue_job(): void
    {
        $this->metrics->recordQueueJob('App\Jobs\TestJob', 'default', 1.5, true);

        $export = $this->metrics->export();

        $this->assertStringContainsString('queue_jobs_total', $export);
        $this->assertStringContainsString('queue_job_duration_seconds', $export);
        $this->assertStringContainsString('status="success"', $export);
    }

    public function test_record_queue_job_failure(): void
    {
        $this->metrics->recordQueueJob('App\Jobs\TestJob', 'default', 0.5, false);

        $export = $this->metrics->export();

        $this->assertStringContainsString('queue_jobs_failed_total', $export);
        $this->assertStringContainsString('status="failed"', $export);
    }

    public function test_record_vps_operation(): void
    {
        $this->metrics->recordVpsOperation('provision', 45.0, true, 'digitalocean');

        $export = $this->metrics->export();

        $this->assertStringContainsString('vps_operations_total', $export);
        $this->assertStringContainsString('vps_operation_duration_seconds', $export);
        $this->assertStringContainsString('operation="provision"', $export);
        $this->assertStringContainsString('provider="digitalocean"', $export);
    }

    public function test_record_site_provisioning(): void
    {
        $this->metrics->recordSiteProvisioning('wordpress', true, 60.0);

        $export = $this->metrics->export();

        $this->assertStringContainsString('site_provisioning_total', $export);
        $this->assertStringContainsString('site_provisioning_duration_seconds', $export);
        $this->assertStringContainsString('site_type="wordpress"', $export);
    }

    public function test_record_tenant_usage(): void
    {
        $this->metrics->recordTenantUsage('tenant-123', 5, 10.5, 15);

        $export = $this->metrics->export();

        $this->assertStringContainsString('tenant_sites_count', $export);
        $this->assertStringContainsString('tenant_storage_gb', $export);
        $this->assertStringContainsString('tenant_backups_count', $export);
        $this->assertStringContainsString('tenant_id="tenant-123"', $export);
    }

    public function test_export_prometheus_format(): void
    {
        $this->metrics->incrementCounter('test_counter', ['label' => 'value']);

        $export = $this->metrics->export();

        // Check for Prometheus format
        $this->assertStringContainsString('# Prometheus metrics for CHOM Laravel application', $export);
        $this->assertStringContainsString('# HELP', $export);
        $this->assertStringContainsString('# TYPE', $export);
    }

    public function test_clear_metrics(): void
    {
        $this->metrics->incrementCounter('test_counter');
        $this->metrics->setGauge('test_gauge', 100);

        $exportBefore = $this->metrics->export();
        $this->assertStringContainsString('test_counter', $exportBefore);

        $this->metrics->clear();

        $exportAfter = $this->metrics->export();
        $this->assertStringNotContainsString('test_counter', $exportAfter);
    }

    public function test_metrics_disabled(): void
    {
        config(['observability.metrics.enabled' => false]);

        $this->metrics->incrementCounter('test_counter');
        $export = $this->metrics->export();

        $this->assertEmpty($export);
    }
}
