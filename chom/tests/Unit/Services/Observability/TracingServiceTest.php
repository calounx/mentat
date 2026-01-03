<?php

declare(strict_types=1);

namespace Tests\Unit\Services\Observability;

use App\Services\TracingService;
use Tests\TestCase;

class TracingServiceTest extends TestCase
{
    private TracingService $tracing;

    protected function setUp(): void
    {
        parent::setUp();
        $this->tracing = new TracingService();
    }

    public function test_start_trace(): void
    {
        $traceId = $this->tracing->startTrace();

        $this->assertNotEmpty($traceId);
        $this->assertEquals($traceId, $this->tracing->getTraceId());
    }

    public function test_start_trace_with_existing_id(): void
    {
        $existingTraceId = 'existing-trace-id-123';

        $traceId = $this->tracing->startTrace($existingTraceId);

        $this->assertEquals($existingTraceId, $traceId);
        $this->assertEquals($existingTraceId, $this->tracing->getTraceId());
    }

    public function test_start_and_finish_span(): void
    {
        $this->tracing->startTrace();

        $spanId = $this->tracing->startSpan('test.operation', [
            'test' => 'value',
        ]);

        $this->assertNotEmpty($spanId);

        usleep(10000); // 10ms delay

        $this->tracing->finishSpan($spanId);

        $spans = $this->tracing->getSpans();
        $this->assertCount(1, $spans);
        $this->assertEquals('test.operation', $spans[$spanId]['operation_name']);
        $this->assertArrayHasKey('duration', $spans[$spanId]);
        $this->assertGreaterThan(0, $spans[$spanId]['duration']);
    }

    public function test_nested_spans(): void
    {
        $this->tracing->startTrace();

        $parentSpanId = $this->tracing->startSpan('parent.operation');
        $childSpanId = $this->tracing->startSpan('child.operation');

        $this->tracing->finishSpan($childSpanId);
        $this->tracing->finishSpan($parentSpanId);

        $spans = $this->tracing->getSpans();

        $this->assertCount(2, $spans);
        $this->assertNull($spans[$parentSpanId]['parent_span_id']);
        $this->assertEquals($parentSpanId, $spans[$childSpanId]['parent_span_id']);
    }

    public function test_add_tag_to_span(): void
    {
        $this->tracing->startTrace();
        $spanId = $this->tracing->startSpan('test.operation');

        $this->tracing->addTag('http.method', 'GET');
        $this->tracing->addTag('http.status_code', 200);

        $this->tracing->finishSpan($spanId);

        $spans = $this->tracing->getSpans();
        $this->assertEquals('GET', $spans[$spanId]['tags']['http.method']);
        $this->assertEquals(200, $spans[$spanId]['tags']['http.status_code']);
    }

    public function test_add_event_to_span(): void
    {
        $this->tracing->startTrace();
        $spanId = $this->tracing->startSpan('test.operation');

        $this->tracing->addEvent('cache.miss', ['key' => 'user:123']);
        $this->tracing->addEvent('db.query', ['query' => 'SELECT * FROM users']);

        $this->tracing->finishSpan($spanId);

        $spans = $this->tracing->getSpans();
        $this->assertCount(2, $spans[$spanId]['events']);
        $this->assertEquals('cache.miss', $spans[$spanId]['events'][0]['event']);
    }

    public function test_baggage(): void
    {
        $this->tracing->startTrace();

        $this->tracing->setBaggage('user_id', '123');
        $this->tracing->setBaggage('tenant_id', 'tenant-456');

        $this->assertEquals('123', $this->tracing->getBaggage('user_id'));
        $this->assertEquals('tenant-456', $this->tracing->getBaggage('tenant_id'));

        $allBaggage = $this->tracing->getAllBaggage();
        $this->assertCount(2, $allBaggage);
    }

    public function test_baggage_propagates_to_spans(): void
    {
        $this->tracing->startTrace();
        $this->tracing->setBaggage('user_id', '123');

        $spanId = $this->tracing->startSpan('test.operation');
        $this->tracing->finishSpan($spanId);

        $spans = $this->tracing->getSpans();
        $this->assertEquals('123', $spans[$spanId]['tags']['user_id']);
    }

    public function test_inject_w3c_context(): void
    {
        $this->tracing->startTrace('0123456789abcdef0123456789abcdef');

        $headers = $this->tracing->injectContext();

        $this->assertArrayHasKey('traceparent', $headers);
        $this->assertStringContainsString('0123456789abcdef0123456789abcdef', $headers['traceparent']);
    }

    public function test_extract_w3c_context(): void
    {
        $headers = [
            'traceparent' => '00-0123456789abcdef0123456789abcdef-0123456789abcdef-01',
        ];

        $this->tracing->extractContext($headers);

        $this->assertEquals('0123456789abcdef0123456789abcdef', $this->tracing->getTraceId());
    }

    public function test_inject_jaeger_context(): void
    {
        config(['observability.tracing.driver' => 'jaeger']);

        $this->tracing->startTrace('trace123');

        $headers = $this->tracing->injectContext();

        $this->assertArrayHasKey('uber-trace-id', $headers);
        $this->assertStringContainsString('trace123', $headers['uber-trace-id']);
    }

    public function test_extract_jaeger_context(): void
    {
        $headers = [
            'uber-trace-id' => 'trace123:span456:0:1',
        ];

        $this->tracing->extractContext($headers);

        $this->assertEquals('trace123', $this->tracing->getTraceId());
    }

    public function test_inject_zipkin_context(): void
    {
        config(['observability.tracing.driver' => 'zipkin']);

        $this->tracing->startTrace('trace123');

        $headers = $this->tracing->injectContext();

        $this->assertArrayHasKey('X-B3-TraceId', $headers);
        $this->assertEquals('trace123', $headers['X-B3-TraceId']);
    }

    public function test_extract_b3_context(): void
    {
        $headers = [
            'x-b3-traceid' => 'trace123',
            'x-b3-spanid' => 'span456',
        ];

        $this->tracing->extractContext($headers);

        $this->assertEquals('trace123', $this->tracing->getTraceId());
    }

    public function test_tracing_disabled(): void
    {
        config(['observability.tracing.enabled' => false]);

        $traceId = $this->tracing->startTrace();
        $spanId = $this->tracing->startSpan('test.operation');

        $this->assertEmpty($traceId);
        $this->assertEmpty($spanId);
    }
}
