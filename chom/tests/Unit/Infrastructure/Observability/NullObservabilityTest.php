<?php

declare(strict_types=1);

namespace Tests\Unit\Infrastructure\Observability;

use App\Infrastructure\Observability\NullObservability;
use PHPUnit\Framework\TestCase;

/**
 * Null Observability Tests
 *
 * Tests NullObservability implementation.
 *
 * @package Tests\Unit\Infrastructure\Observability
 */
class NullObservabilityTest extends TestCase
{
    private NullObservability $observability;

    protected function setUp(): void
    {
        parent::setUp();
        $this->observability = new NullObservability();
    }

    public function test_records_metric_without_error(): void
    {
        $this->observability->recordMetric('test.metric', 100.0, ['tag' => 'value']);

        $this->assertTrue(true); // No exception means success
    }

    public function test_increments_counter_without_error(): void
    {
        $this->observability->incrementCounter('test.counter', 5, ['tag' => 'value']);

        $this->assertTrue(true);
    }

    public function test_records_timing_without_error(): void
    {
        $this->observability->recordTiming('test.timing', 250, ['tag' => 'value']);

        $this->assertTrue(true);
    }

    public function test_records_event_without_error(): void
    {
        $this->observability->recordEvent('test.event', ['data' => 'value']);

        $this->assertTrue(true);
    }

    public function test_starts_and_ends_trace_without_error(): void
    {
        $traceId = $this->observability->startTrace('test.operation');

        $this->assertNotNull($traceId);

        $this->observability->endTrace($traceId);

        $this->assertTrue(true);
    }

    public function test_logs_error_without_error(): void
    {
        $exception = new \RuntimeException('Test exception');

        $this->observability->logError($exception, ['context' => 'test']);

        $this->assertTrue(true);
    }

    public function test_records_gauge_without_error(): void
    {
        $this->observability->recordGauge('test.gauge', 75.5);

        $this->assertTrue(true);
    }

    public function test_records_histogram_without_error(): void
    {
        $this->observability->recordHistogram('test.histogram', 123.45);

        $this->assertTrue(true);
    }

    public function test_flushes_without_error(): void
    {
        $this->observability->flush();

        $this->assertTrue(true);
    }
}
