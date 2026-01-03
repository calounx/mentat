<?php

declare(strict_types=1);

namespace Tests\Unit\Services;

use App\Services\TracingService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Tests\TestCase;

class TracingServiceTest extends TestCase
{
    private TracingService $service;

    protected function setUp(): void
    {
        parent::setUp();
        $this->service = new TracingService();
    }

    public function test_generates_unique_trace_id(): void
    {
        $traceId1 = $this->service->generateTraceId();
        $traceId2 = $this->service->generateTraceId();

        $this->assertIsString($traceId1);
        $this->assertIsString($traceId2);
        $this->assertNotEquals($traceId1, $traceId2);
        $this->assertMatchesRegularExpression('/^[a-f0-9]{32}$/', $traceId1);
    }

    public function test_generates_unique_span_id(): void
    {
        $spanId1 = $this->service->generateSpanId();
        $spanId2 = $this->service->generateSpanId();

        $this->assertIsString($spanId1);
        $this->assertIsString($spanId2);
        $this->assertNotEquals($spanId1, $spanId2);
        $this->assertMatchesRegularExpression('/^[a-f0-9]{16}$/', $spanId1);
    }

    public function test_starts_trace(): void
    {
        $traceId = $this->service->startTrace('http.request');

        $this->assertNotNull($traceId);
        $this->assertTrue($this->service->hasActiveTrace());
    }

    public function test_ends_trace(): void
    {
        $traceId = $this->service->startTrace('http.request');
        $this->service->endTrace($traceId);

        $trace = $this->service->getTrace($traceId);

        $this->assertNotNull($trace);
        $this->assertArrayHasKey('duration_ms', $trace);
        $this->assertGreaterThan(0, $trace['duration_ms']);
    }

    public function test_creates_child_spans(): void
    {
        $traceId = $this->service->startTrace('http.request');
        $spanId = $this->service->startSpan('database.query', $traceId);

        $this->assertNotNull($spanId);

        $this->service->endSpan($spanId);
        $this->service->endTrace($traceId);

        $trace = $this->service->getTrace($traceId);

        $this->assertArrayHasKey('spans', $trace);
        $this->assertCount(1, $trace['spans']);
    }

    public function test_nests_multiple_spans(): void
    {
        $traceId = $this->service->startTrace('http.request');
        $span1 = $this->service->startSpan('service.call', $traceId);
        $span2 = $this->service->startSpan('database.query', $traceId, $span1);

        $this->service->endSpan($span2);
        $this->service->endSpan($span1);
        $this->service->endTrace($traceId);

        $trace = $this->service->getTrace($traceId);

        $this->assertCount(2, $trace['spans']);
    }

    public function test_adds_tags_to_trace(): void
    {
        $traceId = $this->service->startTrace('http.request');
        $this->service->addTags($traceId, [
            'http.method' => 'GET',
            'http.url' => '/api/sites',
            'http.status' => 200,
        ]);

        $this->service->endTrace($traceId);

        $trace = $this->service->getTrace($traceId);

        $this->assertEquals('GET', $trace['tags']['http.method']);
        $this->assertEquals('/api/sites', $trace['tags']['http.url']);
        $this->assertEquals(200, $trace['tags']['http.status']);
    }

    public function test_adds_logs_to_span(): void
    {
        $traceId = $this->service->startTrace('http.request');
        $spanId = $this->service->startSpan('database.query', $traceId);

        $this->service->logEvent($spanId, 'query.executed', [
            'sql' => 'SELECT * FROM users',
            'rows' => 10,
        ]);

        $this->service->endSpan($spanId);
        $this->service->endTrace($traceId);

        $trace = $this->service->getTrace($traceId);
        $span = $trace['spans'][0];

        $this->assertArrayHasKey('logs', $span);
        $this->assertCount(1, $span['logs']);
        $this->assertEquals('query.executed', $span['logs'][0]['event']);
    }

    public function test_propagates_trace_context_in_request(): void
    {
        $traceId = $this->service->generateTraceId();
        $spanId = $this->service->generateSpanId();

        $headers = $this->service->injectTraceContext($traceId, $spanId);

        $this->assertArrayHasKey('X-Trace-Id', $headers);
        $this->assertArrayHasKey('X-Span-Id', $headers);
        $this->assertEquals($traceId, $headers['X-Trace-Id']);
        $this->assertEquals($spanId, $headers['X-Span-Id']);
    }

    public function test_extracts_trace_context_from_request(): void
    {
        $traceId = 'abc123def456';
        $spanId = 'span123';

        $request = Request::create('/api/test', 'GET', [], [], [], [
            'HTTP_X_TRACE_ID' => $traceId,
            'HTTP_X_SPAN_ID' => $spanId,
        ]);

        $context = $this->service->extractTraceContext($request);

        $this->assertEquals($traceId, $context['trace_id']);
        $this->assertEquals($spanId, $context['span_id']);
    }

    public function test_correlates_logs_with_trace_id(): void
    {
        Log::shouldReceive('info')
            ->once()
            ->withArgs(function ($message, $context) {
                return isset($context['trace_id']) && isset($context['span_id']);
            });

        $traceId = $this->service->startTrace('operation');
        $this->service->logWithTrace('Test message', ['key' => 'value']);
        $this->service->endTrace($traceId);
    }

    public function test_measures_span_duration_accurately(): void
    {
        $traceId = $this->service->startTrace('test');
        $spanId = $this->service->startSpan('sleep', $traceId);

        usleep(50000); // 50ms

        $this->service->endSpan($spanId);
        $this->service->endTrace($traceId);

        $trace = $this->service->getTrace($traceId);
        $span = $trace['spans'][0];

        $this->assertGreaterThanOrEqual(45, $span['duration_ms']);
        $this->assertLessThan(100, $span['duration_ms']);
    }

    public function test_tracks_errors_in_spans(): void
    {
        $traceId = $this->service->startTrace('operation');
        $spanId = $this->service->startSpan('failing_operation', $traceId);

        $exception = new \RuntimeException('Test error');
        $this->service->recordException($spanId, $exception);

        $this->service->endSpan($spanId);
        $this->service->endTrace($traceId);

        $trace = $this->service->getTrace($traceId);
        $span = $trace['spans'][0];

        $this->assertTrue($span['error']);
        $this->assertEquals('RuntimeException', $span['error_type']);
        $this->assertEquals('Test error', $span['error_message']);
    }

    public function test_samples_traces_based_on_rate(): void
    {
        $this->service->setSamplingRate(0.5); // 50% sampling

        $sampledCount = 0;
        $iterations = 100;

        for ($i = 0; $i < $iterations; $i++) {
            if ($this->service->shouldSampleTrace()) {
                $sampledCount++;
            }
        }

        // Should be approximately 50 sampled traces
        $this->assertGreaterThan(30, $sampledCount);
        $this->assertLessThan(70, $sampledCount);
    }

    public function test_always_samples_traces_with_errors(): void
    {
        $this->service->setSamplingRate(0.0); // 0% sampling

        $traceId = $this->service->startTrace('operation');
        $spanId = $this->service->startSpan('error_operation', $traceId);

        $this->service->recordException($spanId, new \Exception('Error'));

        $this->service->endSpan($spanId);
        $this->service->endTrace($traceId);

        // Should still be recorded despite 0% sampling
        $trace = $this->service->getTrace($traceId);
        $this->assertNotNull($trace);
    }

    public function test_exports_trace_to_jaeger_format(): void
    {
        $traceId = $this->service->startTrace('http.request');
        $this->service->addTags($traceId, ['http.method' => 'GET']);
        $this->service->endTrace($traceId);

        $jaegerFormat = $this->service->exportToJaeger($traceId);

        $this->assertIsArray($jaegerFormat);
        $this->assertArrayHasKey('traceID', $jaegerFormat);
        $this->assertArrayHasKey('spans', $jaegerFormat);
        $this->assertArrayHasKey('processes', $jaegerFormat);
    }

    public function test_exports_trace_to_zipkin_format(): void
    {
        $traceId = $this->service->startTrace('http.request');
        $this->service->endTrace($traceId);

        $zipkinFormat = $this->service->exportToZipkin($traceId);

        $this->assertIsArray($zipkinFormat);
        $this->assertArrayHasKey('traceId', $zipkinFormat[0]);
        $this->assertArrayHasKey('id', $zipkinFormat[0]);
        $this->assertArrayHasKey('timestamp', $zipkinFormat[0]);
    }

    public function test_cleans_up_old_traces(): void
    {
        $oldTraceId = $this->service->startTrace('old_operation');
        $this->service->endTrace($oldTraceId);

        // Manually set old timestamp
        $trace = $this->service->getTrace($oldTraceId);
        $trace['timestamp'] = now()->subHours(25)->timestamp;

        $this->service->cleanupOldTraces(24); // Remove traces older than 24 hours

        $this->assertNull($this->service->getTrace($oldTraceId));
    }

    public function test_performance_with_many_spans(): void
    {
        $startTime = microtime(true);

        $traceId = $this->service->startTrace('performance_test');

        for ($i = 0; $i < 100; $i++) {
            $spanId = $this->service->startSpan("operation_{$i}", $traceId);
            $this->service->endSpan($spanId);
        }

        $this->service->endTrace($traceId);

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // Should create and end 100 spans in under 200ms
        $this->assertLessThan(200, $duration);
    }
}
