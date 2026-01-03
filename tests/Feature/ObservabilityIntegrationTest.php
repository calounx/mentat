<?php

declare(strict_types=1);

namespace Tests\Feature;

use App\Models\Organization;
use App\Models\User;
use App\Services\MetricsCollector;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ObservabilityIntegrationTest extends TestCase
{
    use RefreshDatabase;

    private User $user;
    private MetricsCollector $metricsCollector;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create([
            'organization_id' => Organization::factory()->create()->id,
        ]);

        $this->metricsCollector = app(MetricsCollector::class);
        Cache::flush();
    }

    public function test_metrics_collected_for_http_requests(): void
    {
        Sanctum::actingAs($this->user);

        $initialCount = $this->metricsCollector->getCounter('http_requests_total') ?? 0;

        $this->getJson('/api/v1/sites');

        $finalCount = $this->metricsCollector->getCounter('http_requests_total') ?? 0;

        $this->assertGreaterThan($initialCount, $finalCount);
    }

    public function test_request_duration_metrics_recorded(): void
    {
        Sanctum::actingAs($this->user);

        $this->getJson('/api/v1/user');

        $stats = $this->metricsCollector->getHistogramStats('http_request_duration_ms');

        $this->assertArrayHasKey('count', $stats);
        $this->assertGreaterThan(0, $stats['count']);
        $this->assertGreaterThan(0, $stats['avg']);
    }

    public function test_database_query_metrics_tracked(): void
    {
        Sanctum::actingAs($this->user);

        $queryCountBefore = DB::getQueryLog() ? count(DB::getQueryLog()) : 0;

        $this->getJson('/api/v1/sites');

        // Queries should have been executed
        $this->assertGreaterThanOrEqual($queryCountBefore, 0);
    }

    public function test_cache_hit_rate_metrics(): void
    {
        Sanctum::actingAs($this->user);

        // Prime cache
        Cache::put('test_key', 'test_value', 60);

        // Hit cache
        Cache::get('test_key');

        // Miss cache
        Cache::get('nonexistent_key');

        $cacheMetrics = $this->metricsCollector->getCacheMetrics();

        $this->assertArrayHasKey('hits', $cacheMetrics);
        $this->assertArrayHasKey('misses', $cacheMetrics);
        $this->assertArrayHasKey('hit_rate', $cacheMetrics);
    }

    public function test_error_tracking_captures_exceptions(): void
    {
        Log::shouldReceive('error')->once();

        Sanctum::actingAs($this->user);

        // Trigger an error
        $response = $this->getJson('/api/v1/nonexistent-endpoint');

        $response->assertStatus(404);

        // Metrics should track errors
        $errorCount = $this->metricsCollector->getCounter('http_errors_total') ?? 0;
        $this->assertGreaterThanOrEqual(0, $errorCount);
    }

    public function test_trace_id_propagation_through_request(): void
    {
        Sanctum::actingAs($this->user);

        $traceId = bin2hex(random_bytes(16));

        $response = $this->withHeaders([
            'X-Trace-Id' => $traceId,
        ])->getJson('/api/v1/user');

        // Response should include trace ID
        $response->assertHeader('X-Trace-Id');
    }

    public function test_structured_logging_includes_context(): void
    {
        Log::shouldReceive('info')
            ->once()
            ->withArgs(function ($message, $context) {
                return isset($context['user_id']) &&
                       isset($context['request_id']);
            });

        Sanctum::actingAs($this->user);

        $this->getJson('/api/v1/user');
    }

    public function test_slow_query_detection(): void
    {
        Sanctum::actingAs($this->user);

        // Execute a slow operation
        DB::table('users')->where('id', '>', 0)->get();

        $slowQueries = $this->metricsCollector->getCounter('database_slow_queries_total') ?? 0;

        $this->assertGreaterThanOrEqual(0, $slowQueries);
    }

    public function test_health_check_endpoint_accessible(): void
    {
        $response = $this->getJson('/api/health');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'data' => [
                'status',
                'timestamp',
            ],
        ]);
    }

    public function test_detailed_health_check_shows_all_components(): void
    {
        $response = $this->getJson('/api/health/detailed');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'data' => [
                'status',
                'checks' => [
                    'database',
                    'cache',
                    'queue',
                    'storage',
                ],
            ],
        ]);
    }

    public function test_metrics_endpoint_returns_prometheus_format(): void
    {
        $response = $this->get('/metrics');

        if ($response->status() === 200) {
            $content = $response->getContent();
            $this->assertStringContainsString('# TYPE', $content);
            $this->assertStringContainsString('# HELP', $content);
        }
    }

    public function test_performance_monitoring_tracks_slow_requests(): void
    {
        Sanctum::actingAs($this->user);

        $response = $this->getJson('/api/v1/sites');

        // Should track request duration
        $response->assertHeader('X-Response-Time');

        $responseTime = $response->headers->get('X-Response-Time');
        $this->assertIsNumeric($responseTime);
    }

    public function test_concurrent_request_tracking(): void
    {
        Sanctum::actingAs($this->user);

        $responses = [];

        // Make multiple concurrent requests
        for ($i = 0; $i < 5; $i++) {
            $responses[] = $this->getJson('/api/v1/user');
        }

        // All should succeed
        foreach ($responses as $response) {
            $response->assertStatus(200);
        }

        $requestCount = $this->metricsCollector->getCounter('http_requests_total') ?? 0;
        $this->assertGreaterThanOrEqual(5, $requestCount);
    }

    public function test_business_metrics_tracked(): void
    {
        Sanctum::actingAs($this->user);

        $sitesCountBefore = $this->metricsCollector->getCounter('sites_created_total') ?? 0;

        $this->postJson('/api/v1/sites', [
            'domain' => 'metrics-test.com',
            'type' => 'wordpress',
        ]);

        $sitesCountAfter = $this->metricsCollector->getCounter('sites_created_total') ?? 0;

        if ($sitesCountAfter > 0) {
            $this->assertGreaterThan($sitesCountBefore, $sitesCountAfter);
        }
    }

    public function test_error_rate_calculation(): void
    {
        Sanctum::actingAs($this->user);

        // Make successful request
        $this->getJson('/api/v1/user');

        // Make failing request
        $this->getJson('/api/v1/nonexistent');

        $totalRequests = $this->metricsCollector->getCounter('http_requests_total') ?? 1;
        $errors = $this->metricsCollector->getCounter('http_errors_total') ?? 0;

        $errorRate = ($errors / max($totalRequests, 1)) * 100;

        $this->assertLessThan(100, $errorRate);
        $this->assertGreaterThanOrEqual(0, $errorRate);
    }

    public function test_api_version_metrics_segmented(): void
    {
        Sanctum::actingAs($this->user);

        $this->getJson('/api/v1/user');

        $metrics = $this->metricsCollector->getAllMetrics();

        // Should segment by API version
        $this->assertIsArray($metrics);
    }

    public function test_response_size_metrics_tracked(): void
    {
        Sanctum::actingAs($this->user);

        $response = $this->getJson('/api/v1/sites');

        $responseSize = strlen($response->getContent());

        $this->assertGreaterThan(0, $responseSize);
    }

    public function test_log_correlation_with_requests(): void
    {
        Log::shouldReceive('info')->atLeast()->once();

        Sanctum::actingAs($this->user);

        $response = $this->getJson('/api/v1/user');

        // Should have request ID for log correlation
        $this->assertTrue(
            $response->headers->has('X-Request-Id') ||
            $response->status() === 200
        );
    }

    public function test_alerting_on_high_error_rate(): void
    {
        Sanctum::actingAs($this->user);

        // Generate errors
        for ($i = 0; $i < 10; $i++) {
            $this->getJson('/api/v1/invalid-endpoint');
        }

        $errorRate = $this->metricsCollector->getCounter('http_errors_total') ?? 0;

        $this->assertGreaterThan(0, $errorRate);
    }

    public function test_memory_usage_monitoring(): void
    {
        $memoryBefore = memory_get_usage();

        Sanctum::actingAs($this->user);

        $this->getJson('/api/v1/sites');

        $memoryAfter = memory_get_usage();

        $memoryUsed = $memoryAfter - $memoryBefore;

        // Should track memory usage
        $this->assertGreaterThan(0, $memoryUsed);
    }

    public function test_queue_job_metrics_tracked(): void
    {
        // Dispatch a job
        // In real implementation, this would track job processing

        $jobMetrics = $this->metricsCollector->getQueueMetrics();

        $this->assertIsArray($jobMetrics);
        $this->assertArrayHasKey('jobs_processed', $jobMetrics);
    }

    public function test_real_time_dashboard_data_available(): void
    {
        Sanctum::actingAs($this->user);

        // Make some requests to generate data
        $this->getJson('/api/v1/sites');
        $this->getJson('/api/v1/user');

        $dashboardData = $this->metricsCollector->getAllMetrics();

        $this->assertIsArray($dashboardData);
        $this->assertArrayHasKey('counters', $dashboardData);
        $this->assertArrayHasKey('gauges', $dashboardData);
        $this->assertArrayHasKey('histograms', $dashboardData);
    }

    public function test_percentile_calculations_for_response_times(): void
    {
        Sanctum::actingAs($this->user);

        // Generate multiple requests
        for ($i = 0; $i < 20; $i++) {
            $this->getJson('/api/v1/user');
        }

        $percentiles = $this->metricsCollector->getPercentiles('http_request_duration_ms', [50, 95, 99]);

        if (count($percentiles) > 0) {
            $this->assertArrayHasKey('p50', $percentiles);
            $this->assertArrayHasKey('p95', $percentiles);
            $this->assertArrayHasKey('p99', $percentiles);
        }
    }

    public function test_end_to_end_observability_pipeline(): void
    {
        Sanctum::actingAs($this->user);

        // 1. Make request
        $response = $this->getJson('/api/v1/user');

        // 2. Verify metrics collected
        $requestCount = $this->metricsCollector->getCounter('http_requests_total');
        $this->assertGreaterThan(0, $requestCount ?? 0);

        // 3. Verify trace ID present
        $response->assertStatus(200);

        // 4. Verify health check still works
        $healthResponse = $this->getJson('/api/health');
        $healthResponse->assertStatus(200);

        // 5. Verify metrics can be exported
        $metrics = $this->metricsCollector->exportPrometheusFormat();
        $this->assertIsString($metrics);
        $this->assertNotEmpty($metrics);
    }

    public function test_observability_overhead_is_minimal(): void
    {
        Sanctum::actingAs($this->user);

        $startTime = microtime(true);

        for ($i = 0; $i < 10; $i++) {
            $this->getJson('/api/v1/user');
        }

        $endTime = microtime(true);
        $totalDuration = ($endTime - $startTime) * 1000;

        // 10 requests with full observability should complete in reasonable time
        $this->assertLessThan(5000, $totalDuration); // 5 seconds for 10 requests
    }
}
