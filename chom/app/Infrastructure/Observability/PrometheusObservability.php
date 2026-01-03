<?php

declare(strict_types=1);

namespace App\Infrastructure\Observability;

use App\Contracts\Infrastructure\ObservabilityInterface;
use App\ValueObjects\TraceId;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Prometheus Observability Implementation
 *
 * Implements observability using Prometheus metrics format.
 * Stores metrics in memory/cache for scraping by Prometheus.
 *
 * Pattern: Adapter Pattern - adapts Prometheus to observability interface
 * Integration: Works with Prometheus push gateway or pull scraping
 *
 * @package App\Infrastructure\Observability
 */
class PrometheusObservability implements ObservabilityInterface
{
    /**
     * @var array<string, array<string, mixed>> Active traces
     */
    private array $traces = [];

    /**
     * @var array<string, mixed> Metrics buffer
     */
    private array $metricsBuffer = [];

    public function __construct(
        private readonly ?string $pushGatewayUrl = null,
        private readonly string $namespace = 'chom',
        private readonly int $bufferSize = 100
    ) {
    }

    /**
     * {@inheritDoc}
     */
    public function recordMetric(string $name, float $value, array $tags = []): void
    {
        $metricName = $this->formatMetricName($name);

        $this->addToBuffer([
            'type' => 'gauge',
            'name' => $metricName,
            'value' => $value,
            'tags' => $tags,
            'timestamp' => time(),
        ]);

        Log::debug('Prometheus metric recorded', [
            'name' => $metricName,
            'value' => $value,
            'tags' => $tags,
        ]);
    }

    /**
     * {@inheritDoc}
     */
    public function incrementCounter(string $name, int $value = 1, array $tags = []): void
    {
        $metricName = $this->formatMetricName($name);
        $cacheKey = $this->getCacheKey($metricName, $tags);

        $current = Cache::get($cacheKey, 0);
        $newValue = $current + $value;
        Cache::put($cacheKey, $newValue, now()->addHours(24));

        $this->addToBuffer([
            'type' => 'counter',
            'name' => $metricName,
            'value' => $newValue,
            'tags' => $tags,
            'timestamp' => time(),
        ]);
    }

    /**
     * {@inheritDoc}
     */
    public function recordTiming(string $name, int $milliseconds, array $tags = []): void
    {
        $metricName = $this->formatMetricName($name . '_duration_ms');

        $this->addToBuffer([
            'type' => 'histogram',
            'name' => $metricName,
            'value' => $milliseconds,
            'tags' => $tags,
            'timestamp' => time(),
        ]);
    }

    /**
     * {@inheritDoc}
     */
    public function recordEvent(string $name, array $data = []): void
    {
        $metricName = $this->formatMetricName($name . '_events_total');

        $this->incrementCounter($metricName, 1, [
            'event_type' => $name,
            ...$data,
        ]);

        Log::info('Prometheus event recorded', [
            'name' => $name,
            'data' => $data,
        ]);
    }

    /**
     * {@inheritDoc}
     */
    public function startTrace(string $name, array $context = []): TraceId
    {
        $traceId = TraceId::generate();

        $this->traces[$traceId->value] = [
            'name' => $name,
            'context' => $context,
            'start_time' => microtime(true),
            'trace_id' => $traceId->value,
        ];

        Log::debug('Prometheus trace started', [
            'trace_id' => $traceId->value,
            'name' => $name,
        ]);

        return $traceId;
    }

    /**
     * {@inheritDoc}
     */
    public function endTrace(TraceId $traceId, array $metadata = []): void
    {
        if (!isset($this->traces[$traceId->value])) {
            Log::warning('Attempted to end non-existent trace', [
                'trace_id' => $traceId->value,
            ]);
            return;
        }

        $trace = $this->traces[$traceId->value];
        $duration = (microtime(true) - $trace['start_time']) * 1000; // Convert to ms

        $this->recordTiming($trace['name'], (int) $duration, [
            'trace_id' => $traceId->value,
            ...$metadata,
        ]);

        unset($this->traces[$traceId->value]);

        Log::debug('Prometheus trace ended', [
            'trace_id' => $traceId->value,
            'duration_ms' => $duration,
        ]);
    }

    /**
     * {@inheritDoc}
     */
    public function logError(Throwable $exception, array $context = []): void
    {
        $this->incrementCounter('errors_total', 1, [
            'exception_class' => get_class($exception),
            'message' => substr($exception->getMessage(), 0, 100),
            ...$context,
        ]);

        Log::error('Prometheus error logged', [
            'exception' => get_class($exception),
            'message' => $exception->getMessage(),
            'context' => $context,
        ]);
    }

    /**
     * {@inheritDoc}
     */
    public function recordGauge(string $name, float $value, array $tags = []): void
    {
        $this->recordMetric($name, $value, $tags);
    }

    /**
     * {@inheritDoc}
     */
    public function recordHistogram(string $name, float $value, array $tags = []): void
    {
        $metricName = $this->formatMetricName($name);

        $this->addToBuffer([
            'type' => 'histogram',
            'name' => $metricName,
            'value' => $value,
            'tags' => $tags,
            'timestamp' => time(),
        ]);
    }

    /**
     * {@inheritDoc}
     */
    public function flush(): void
    {
        if (empty($this->metricsBuffer)) {
            return;
        }

        if ($this->pushGatewayUrl) {
            $this->pushMetrics();
        }

        // Store in cache for pull-based scraping
        $this->storeMetricsInCache();

        $this->metricsBuffer = [];

        Log::debug('Prometheus metrics flushed');
    }

    /**
     * Get metrics in Prometheus exposition format
     *
     * @return string
     */
    public function getMetrics(): string
    {
        $metrics = Cache::get('prometheus_metrics', []);
        $output = [];

        foreach ($metrics as $metric) {
            $labels = $this->formatLabels($metric['tags'] ?? []);
            $metricLine = sprintf(
                '%s%s %s %d',
                $metric['name'],
                $labels ? '{' . $labels . '}' : '',
                $metric['value'],
                $metric['timestamp']
            );
            $output[] = $metricLine;
        }

        return implode("\n", $output) . "\n";
    }

    /**
     * Format metric name to Prometheus format
     *
     * @param string $name
     * @return string
     */
    private function formatMetricName(string $name): string
    {
        $name = strtolower($name);
        $name = str_replace(['.', '-', ' '], '_', $name);
        return $this->namespace . '_' . $name;
    }

    /**
     * Format labels for Prometheus
     *
     * @param array<string, string|int|float> $tags
     * @return string
     */
    private function formatLabels(array $tags): string
    {
        if (empty($tags)) {
            return '';
        }

        $labels = [];
        foreach ($tags as $key => $value) {
            $key = str_replace(['.', '-', ' '], '_', (string) $key);
            $value = addslashes((string) $value);
            $labels[] = "{$key}=\"{$value}\"";
        }

        return implode(',', $labels);
    }

    /**
     * Add metric to buffer
     *
     * @param array<string, mixed> $metric
     * @return void
     */
    private function addToBuffer(array $metric): void
    {
        $this->metricsBuffer[] = $metric;

        if (count($this->metricsBuffer) >= $this->bufferSize) {
            $this->flush();
        }
    }

    /**
     * Store metrics in cache
     *
     * @return void
     */
    private function storeMetricsInCache(): void
    {
        $existing = Cache::get('prometheus_metrics', []);
        $merged = array_merge($existing, $this->metricsBuffer);

        // Keep only last 1000 metrics
        if (count($merged) > 1000) {
            $merged = array_slice($merged, -1000);
        }

        Cache::put('prometheus_metrics', $merged, now()->addHours(24));
    }

    /**
     * Push metrics to Prometheus push gateway
     *
     * @return void
     */
    private function pushMetrics(): void
    {
        if (!$this->pushGatewayUrl) {
            return;
        }

        $metricsText = $this->formatMetricsForPush();

        try {
            $ch = curl_init($this->pushGatewayUrl . '/metrics/job/chom');
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, $metricsText);
            curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: text/plain']);
            curl_setopt($ch, CURLOPT_TIMEOUT, 5);

            curl_exec($ch);
            curl_close($ch);
        } catch (\Exception $e) {
            Log::warning('Failed to push metrics to Prometheus', [
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Format metrics for push gateway
     *
     * @return string
     */
    private function formatMetricsForPush(): string
    {
        $output = [];

        foreach ($this->metricsBuffer as $metric) {
            $labels = $this->formatLabels($metric['tags'] ?? []);
            $output[] = sprintf(
                '%s%s %s',
                $metric['name'],
                $labels ? '{' . $labels . '}' : '',
                $metric['value']
            );
        }

        return implode("\n", $output) . "\n";
    }

    /**
     * Get cache key for metric
     *
     * @param string $name
     * @param array<string, mixed> $tags
     * @return string
     */
    private function getCacheKey(string $name, array $tags): string
    {
        $tagStr = json_encode($tags);
        return "prometheus_counter:{$name}:" . md5($tagStr);
    }
}
