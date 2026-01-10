<?php

declare(strict_types=1);

namespace App\Services;

use Illuminate\Support\Str;

/**
 * Distributed Tracing Service
 *
 * Provides distributed tracing capabilities for tracking requests across
 * multiple services and components. Generates trace IDs and manages span context.
 */
class TracingService
{
    private ?string $traceId = null;
    private ?string $parentSpanId = null;
    private array $spans = [];
    private array $baggage = [];

    /**
     * Start a new trace.
     *
     * @param string|null $traceId Optional trace ID (for continuing existing trace)
     * @return string Trace ID
     */
    public function startTrace(?string $traceId = null): string
    {
        if (!config('observability.tracing.enabled', true)) {
            return '';
        }

        $this->traceId = $traceId ?? $this->generateTraceId();
        $this->parentSpanId = null;
        $this->spans = [];

        \Log::debug('Trace started', ['trace_id' => $this->traceId]);

        return $this->traceId;
    }

    /**
     * Get the current trace ID.
     *
     * @return string|null
     */
    public function getTraceId(): ?string
    {
        return $this->traceId;
    }

    /**
     * Start a new span within the current trace.
     *
     * @param string $operationName Operation name
     * @param array $tags Optional span tags
     * @return string Span ID
     */
    public function startSpan(string $operationName, array $tags = []): string
    {
        if (!config('observability.tracing.enabled', true)) {
            return '';
        }

        // Initialize trace if not already started
        if ($this->traceId === null) {
            $this->startTrace();
        }

        $spanId = $this->generateSpanId();

        $span = [
            'span_id' => $spanId,
            'trace_id' => $this->traceId,
            'parent_span_id' => $this->parentSpanId,
            'operation_name' => $operationName,
            'start_time' => microtime(true),
            'tags' => array_merge($tags, $this->baggage),
        ];

        $this->spans[$spanId] = $span;
        $this->parentSpanId = $spanId;

        \Log::debug('Span started', [
            'trace_id' => $this->traceId,
            'span_id' => $spanId,
            'operation' => $operationName,
        ]);

        return $spanId;
    }

    /**
     * Finish a span and record its duration.
     *
     * @param string $spanId Span ID
     * @param array $tags Additional tags to add on completion
     * @return void
     */
    public function finishSpan(string $spanId, array $tags = []): void
    {
        if (!config('observability.tracing.enabled', true)) {
            return;
        }

        if (!isset($this->spans[$spanId])) {
            \Log::warning('Attempted to finish non-existent span', ['span_id' => $spanId]);
            return;
        }

        $span = &$this->spans[$spanId];
        $span['end_time'] = microtime(true);
        $span['duration'] = $span['end_time'] - $span['start_time'];
        $span['tags'] = array_merge($span['tags'], $tags);

        // Restore parent span as current
        $this->parentSpanId = $span['parent_span_id'];

        \Log::debug('Span finished', [
            'trace_id' => $this->traceId,
            'span_id' => $spanId,
            'operation' => $span['operation_name'],
            'duration_ms' => round($span['duration'] * 1000, 2),
        ]);

        // Export span if driver is configured
        $this->exportSpan($span);
    }

    /**
     * Add baggage item to trace context.
     *
     * Baggage is propagated across all spans in the trace.
     *
     * @param string $key
     * @param mixed $value
     * @return void
     */
    public function setBaggage(string $key, mixed $value): void
    {
        $this->baggage[$key] = $value;
    }

    /**
     * Get baggage item from trace context.
     *
     * @param string $key
     * @return mixed
     */
    public function getBaggage(string $key): mixed
    {
        return $this->baggage[$key] ?? null;
    }

    /**
     * Get all baggage items.
     *
     * @return array
     */
    public function getAllBaggage(): array
    {
        return $this->baggage;
    }

    /**
     * Add a tag to the current span.
     *
     * @param string $key
     * @param mixed $value
     * @return void
     */
    public function addTag(string $key, mixed $value): void
    {
        if ($this->parentSpanId && isset($this->spans[$this->parentSpanId])) {
            $this->spans[$this->parentSpanId]['tags'][$key] = $value;
        }
    }

    /**
     * Add an event/log to the current span.
     *
     * @param string $event Event name
     * @param array $payload Event payload
     * @return void
     */
    public function addEvent(string $event, array $payload = []): void
    {
        if (!$this->parentSpanId || !isset($this->spans[$this->parentSpanId])) {
            return;
        }

        if (!isset($this->spans[$this->parentSpanId]['events'])) {
            $this->spans[$this->parentSpanId]['events'] = [];
        }

        $this->spans[$this->parentSpanId]['events'][] = [
            'timestamp' => microtime(true),
            'event' => $event,
            'payload' => $payload,
        ];
    }

    /**
     * Extract trace context from HTTP headers.
     *
     * Supports W3C Trace Context and Jaeger formats.
     *
     * @param array $headers HTTP headers
     * @return void
     */
    public function extractContext(array $headers): void
    {
        if (!config('observability.tracing.enabled', true)) {
            return;
        }

        // W3C Trace Context format
        if (isset($headers['traceparent'])) {
            $this->extractW3CContext($headers['traceparent']);
        }
        // Jaeger format
        elseif (isset($headers['uber-trace-id'])) {
            $this->extractJaegerContext($headers['uber-trace-id']);
        }
        // X-B3 format (Zipkin)
        elseif (isset($headers['x-b3-traceid'])) {
            $this->extractB3Context($headers);
        }

        // Extract baggage
        if (isset($headers['baggage'])) {
            $this->extractBaggage($headers['baggage']);
        }
    }

    /**
     * Inject trace context into HTTP headers.
     *
     * @return array HTTP headers with trace context
     */
    public function injectContext(): array
    {
        if (!config('observability.tracing.enabled', true) || !$this->traceId) {
            return [];
        }

        $headers = [];

        $driver = config('observability.tracing.driver', 'jaeger');

        if ($driver === 'jaeger') {
            $headers['uber-trace-id'] = $this->formatJaegerContext();
        } elseif ($driver === 'zipkin') {
            $headers = array_merge($headers, $this->formatB3Context());
        }

        // Always include W3C Trace Context for maximum compatibility
        $headers['traceparent'] = $this->formatW3CContext();

        // Include baggage
        if (!empty($this->baggage)) {
            $headers['baggage'] = $this->formatBaggage();
        }

        return $headers;
    }

    /**
     * Get all spans in the current trace.
     *
     * @return array
     */
    public function getSpans(): array
    {
        return $this->spans;
    }

    /**
     * Generate a unique trace ID.
     *
     * @return string
     */
    private function generateTraceId(): string
    {
        return Str::random(32);
    }

    /**
     * Generate a unique span ID.
     *
     * @return string
     */
    private function generateSpanId(): string
    {
        return Str::random(16);
    }

    /**
     * Extract W3C Trace Context.
     *
     * Format: version-traceid-spanid-flags
     *
     * @param string $traceparent
     * @return void
     */
    private function extractW3CContext(string $traceparent): void
    {
        $parts = explode('-', $traceparent);
        if (count($parts) === 4) {
            $this->traceId = $parts[1];
            $this->parentSpanId = $parts[2];
        }
    }

    /**
     * Extract Jaeger trace context.
     *
     * Format: traceid:spanid:parentid:flags
     *
     * @param string $uberTraceId
     * @return void
     */
    private function extractJaegerContext(string $uberTraceId): void
    {
        $parts = explode(':', $uberTraceId);
        if (count($parts) >= 2) {
            $this->traceId = $parts[0];
            $this->parentSpanId = $parts[1];
        }
    }

    /**
     * Extract B3 (Zipkin) trace context.
     *
     * @param array $headers
     * @return void
     */
    private function extractB3Context(array $headers): void
    {
        if (isset($headers['x-b3-traceid'])) {
            $this->traceId = $headers['x-b3-traceid'];
        }
        if (isset($headers['x-b3-spanid'])) {
            $this->parentSpanId = $headers['x-b3-spanid'];
        }
    }

    /**
     * Extract baggage from header.
     *
     * @param string $baggageHeader
     * @return void
     */
    private function extractBaggage(string $baggageHeader): void
    {
        $items = explode(',', $baggageHeader);
        foreach ($items as $item) {
            $parts = explode('=', trim($item), 2);
            if (count($parts) === 2) {
                $this->baggage[$parts[0]] = urldecode($parts[1]);
            }
        }
    }

    /**
     * Format W3C Trace Context header.
     *
     * @return string
     */
    private function formatW3CContext(): string
    {
        $spanId = $this->parentSpanId ?? $this->generateSpanId();
        return sprintf('00-%s-%s-01', $this->traceId, $spanId);
    }

    /**
     * Format Jaeger trace context header.
     *
     * @return string
     */
    private function formatJaegerContext(): string
    {
        $spanId = $this->parentSpanId ?? $this->generateSpanId();
        return sprintf('%s:%s:0:1', $this->traceId, $spanId);
    }

    /**
     * Format B3 (Zipkin) trace context headers.
     *
     * @return array
     */
    private function formatB3Context(): array
    {
        $spanId = $this->parentSpanId ?? $this->generateSpanId();

        return [
            'X-B3-TraceId' => $this->traceId,
            'X-B3-SpanId' => $spanId,
            'X-B3-Sampled' => '1',
        ];
    }

    /**
     * Format baggage header.
     *
     * @return string
     */
    private function formatBaggage(): string
    {
        $items = [];
        foreach ($this->baggage as $key => $value) {
            $items[] = $key . '=' . urlencode((string)$value);
        }
        return implode(',', $items);
    }

    /**
     * Export span to tracing backend.
     *
     * @param array $span
     * @return void
     */
    private function exportSpan(array $span): void
    {
        $driver = config('observability.tracing.driver');

        if ($driver === 'jaeger') {
            $this->exportToJaeger($span);
        } elseif ($driver === 'zipkin') {
            $this->exportToZipkin($span);
        }
    }

    /**
     * Export span to Jaeger.
     *
     * @param array $span
     * @return void
     */
    private function exportToJaeger(array $span): void
    {
        // In production, this would send to Jaeger agent via UDP
        // For now, we'll log structured span data
        \Log::info('Jaeger span', [
            'trace_id' => $span['trace_id'],
            'span_id' => $span['span_id'],
            'parent_span_id' => $span['parent_span_id'],
            'operation_name' => $span['operation_name'],
            'duration_ms' => round($span['duration'] * 1000, 2),
            'tags' => $span['tags'],
            'events' => $span['events'] ?? [],
        ]);
    }

    /**
     * Export span to Zipkin.
     *
     * @param array $span
     * @return void
     */
    private function exportToZipkin(array $span): void
    {
        // In production, this would POST to Zipkin HTTP endpoint
        // For now, we'll log structured span data
        \Log::info('Zipkin span', [
            'traceId' => $span['trace_id'],
            'id' => $span['span_id'],
            'parentId' => $span['parent_span_id'],
            'name' => $span['operation_name'],
            'timestamp' => (int)($span['start_time'] * 1000000), // microseconds
            'duration' => (int)($span['duration'] * 1000000), // microseconds
            'tags' => $span['tags'],
        ]);
    }
}
