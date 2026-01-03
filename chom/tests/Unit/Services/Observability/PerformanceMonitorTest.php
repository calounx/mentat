<?php

declare(strict_types=1);

namespace Tests\Unit\Services\Observability;

use App\Services\MetricsCollector;
use App\Services\PerformanceMonitor;
use App\Services\StructuredLogger;
use Tests\TestCase;

class PerformanceMonitorTest extends TestCase
{
    private PerformanceMonitor $monitor;

    protected function setUp(): void
    {
        parent::setUp();

        $metrics = $this->createMock(MetricsCollector::class);
        $logger = $this->createMock(StructuredLogger::class);

        $this->monitor = new PerformanceMonitor($metrics, $logger);
    }

    public function test_start_and_finish_operation(): void
    {
        $operationId = $this->monitor->startOperation('test.operation', [
            'context' => 'value',
        ]);

        $this->assertNotEmpty($operationId);

        usleep(10000); // 10ms delay

        $this->monitor->finishOperation($operationId);

        $activeOperations = $this->monitor->getActiveOperations();
        $this->assertEmpty($activeOperations);
    }

    public function test_track_callable(): void
    {
        $result = $this->monitor->track('test.callable', function () {
            usleep(5000); // 5ms delay
            return 'test_result';
        });

        $this->assertEquals('test_result', $result);
    }

    public function test_track_callable_with_exception(): void
    {
        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Test exception');

        $this->monitor->track('test.callable', function () {
            throw new \RuntimeException('Test exception');
        });
    }

    public function test_get_memory_usage(): void
    {
        $memoryUsage = $this->monitor->getMemoryUsage();

        $this->assertIsArray($memoryUsage);
        $this->assertArrayHasKey('current_bytes', $memoryUsage);
        $this->assertArrayHasKey('current_mb', $memoryUsage);
        $this->assertArrayHasKey('peak_bytes', $memoryUsage);
        $this->assertArrayHasKey('peak_mb', $memoryUsage);
        $this->assertArrayHasKey('limit_mb', $memoryUsage);
        $this->assertArrayHasKey('usage_percent', $memoryUsage);

        $this->assertGreaterThan(0, $memoryUsage['current_bytes']);
        $this->assertGreaterThan(0, $memoryUsage['current_mb']);
    }

    public function test_is_memory_usage_high(): void
    {
        config(['observability.performance.memory.threshold_mb' => 999999]);

        $isHigh = $this->monitor->isMemoryUsageHigh();

        $this->assertFalse($isHigh);
    }

    public function test_get_active_operations(): void
    {
        $operation1 = $this->monitor->startOperation('operation1');
        $operation2 = $this->monitor->startOperation('operation2');

        $activeOperations = $this->monitor->getActiveOperations();

        $this->assertCount(2, $activeOperations);
        $this->assertEquals('operation1', $activeOperations[0]['operation']);
        $this->assertEquals('operation2', $activeOperations[1]['operation']);

        $this->monitor->finishOperation($operation1);
        $this->monitor->finishOperation($operation2);
    }

    public function test_multiple_operations_tracking(): void
    {
        $op1 = $this->monitor->startOperation('operation1');
        usleep(5000);

        $op2 = $this->monitor->startOperation('operation2');
        usleep(3000);

        $active = $this->monitor->getActiveOperations();
        $this->assertCount(2, $active);

        $this->monitor->finishOperation($op2);
        $active = $this->monitor->getActiveOperations();
        $this->assertCount(1, $active);

        $this->monitor->finishOperation($op1);
        $active = $this->monitor->getActiveOperations();
        $this->assertEmpty($active);
    }
}
