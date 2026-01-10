<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use App\Services\MetricsCollector;
use App\Services\TracingService;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Prometheus Metrics Middleware
 *
 * Collects HTTP request metrics for monitoring and observability.
 * Tracks request count, duration, status codes, and active requests.
 */
class PrometheusMetricsMiddleware
{
    private MetricsCollector $metrics;
    private TracingService $tracing;

    public function __construct(MetricsCollector $metrics, TracingService $tracing)
    {
        $this->metrics = $metrics;
        $this->tracing = $tracing;
    }

    /**
     * Handle an incoming request.
     *
     * @param Request $request
     * @param Closure $next
     * @return Response
     */
    public function handle(Request $request, Closure $next): Response
    {
        if (!config('observability.metrics.enabled', true)) {
            return $next($request);
        }

        // Skip metrics collection for metrics endpoint to avoid recursion
        if ($this->isMetricsEndpoint($request)) {
            return $next($request);
        }

        // Start trace span
        $spanId = $this->tracing->startSpan('http.request', [
            'http.method' => $request->method(),
            'http.url' => $request->fullUrl(),
            'http.route' => $request->route()?->getName() ?? $request->path(),
        ]);

        // Increment active requests gauge
        $this->metrics->incrementGauge('http_requests_active', 1);

        $startTime = microtime(true);

        try {
            $response = $next($request);

            // Record successful request metrics
            $this->recordMetrics($request, $response, $startTime);

            // Add trace ID to response headers (for debugging)
            $traceId = $this->tracing->getTraceId();
            if ($traceId) {
                $response->headers->set('X-Trace-ID', $traceId);
            }

            return $response;
        } catch (\Throwable $e) {
            // Record error metrics
            $this->recordErrorMetrics($request, $e, $startTime);

            // Finish span with error
            $this->tracing->finishSpan($spanId, [
                'error' => true,
                'error.message' => $e->getMessage(),
                'error.class' => get_class($e),
            ]);

            throw $e;
        } finally {
            // Decrement active requests gauge
            $this->metrics->decrementGauge('http_requests_active', 1);

            // Finish trace span if not already finished
            if (!isset($e)) {
                $this->tracing->finishSpan($spanId, [
                    'http.status_code' => $response->getStatusCode(),
                ]);
            }
        }
    }

    /**
     * Record request metrics.
     *
     * @param Request $request
     * @param Response $response
     * @param float $startTime
     * @return void
     */
    private function recordMetrics(Request $request, Response $response, float $startTime): void
    {
        $duration = microtime(true) - $startTime;
        $method = $request->method();
        $route = $this->getRouteName($request);
        $statusCode = $response->getStatusCode();

        // Record HTTP request metrics
        $this->metrics->recordHttpRequest($method, $route, $statusCode, $duration);

        // Record route-specific metrics
        $this->recordRouteMetrics($route, $duration, $statusCode);

        // Record tenant metrics if applicable
        if ($tenantId = $request->user()?->team_id) {
            $this->recordTenantMetrics($tenantId, $route, $statusCode);
        }

        // Log slow requests
        $slowThreshold = config('observability.logging.performance.slow_request_threshold_ms', 500) / 1000;
        if ($duration > $slowThreshold) {
            \Log::warning('Slow HTTP request detected', [
                'method' => $method,
                'route' => $route,
                'duration_ms' => round($duration * 1000, 2),
                'status_code' => $statusCode,
                'url' => $request->fullUrl(),
            ]);
        }
    }

    /**
     * Record error metrics for failed requests.
     *
     * @param Request $request
     * @param \Throwable $exception
     * @param float $startTime
     * @return void
     */
    private function recordErrorMetrics(Request $request, \Throwable $exception, float $startTime): void
    {
        $duration = microtime(true) - $startTime;
        $method = $request->method();
        $route = $this->getRouteName($request);

        $labels = [
            'method' => $method,
            'route' => $route,
            'exception' => get_class($exception),
        ];

        $this->metrics->incrementCounter('http_requests_exceptions_total', $labels);

        // Still record duration even for exceptions
        $this->metrics->observeHistogram(
            'http_request_duration_seconds',
            $duration,
            array_merge($labels, ['status' => '500']),
            'http_duration'
        );
    }

    /**
     * Record route-specific metrics.
     *
     * @param string $route
     * @param float $duration
     * @param int $statusCode
     * @return void
     */
    private function recordRouteMetrics(string $route, float $duration, int $statusCode): void
    {
        // Track API endpoint performance
        if (str_starts_with($route, 'api.')) {
            $labels = ['endpoint' => $route];

            $this->metrics->incrementCounter('api_requests_total', $labels);
            $this->metrics->observeHistogram('api_request_duration_seconds', $duration, $labels, 'http_duration');

            if ($statusCode >= 400) {
                $errorLabels = array_merge($labels, ['status' => (string)$statusCode]);
                $this->metrics->incrementCounter('api_requests_errors_total', $errorLabels);
            }
        }
    }

    /**
     * Record tenant-specific metrics.
     *
     * @param string $tenantId
     * @param string $route
     * @param int $statusCode
     * @return void
     */
    private function recordTenantMetrics(string $tenantId, string $route, int $statusCode): void
    {
        $labels = ['tenant_id' => $tenantId];

        $this->metrics->incrementCounter('tenant_requests_total', $labels);

        if ($statusCode >= 500) {
            $this->metrics->incrementCounter('tenant_errors_total', $labels);
        }

        // Track specific tenant operations
        if (str_contains($route, 'sites')) {
            $this->metrics->incrementCounter('tenant_site_operations_total', $labels);
        } elseif (str_contains($route, 'backups')) {
            $this->metrics->incrementCounter('tenant_backup_operations_total', $labels);
        }
    }

    /**
     * Get normalized route name.
     *
     * @param Request $request
     * @return string
     */
    private function getRouteName(Request $request): string
    {
        $route = $request->route();

        if ($route && $route->getName()) {
            return $route->getName();
        }

        // Fallback to path with parameters normalized
        $path = $request->path();

        // Replace UUIDs with placeholder
        $path = preg_replace(
            '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/',
            '{id}',
            $path
        );

        // Replace numeric IDs with placeholder
        $path = preg_replace('/\/\d+/', '/{id}', $path);

        return $path ?: 'unknown';
    }

    /**
     * Check if the request is for the metrics endpoint.
     *
     * @param Request $request
     * @return bool
     */
    private function isMetricsEndpoint(Request $request): bool
    {
        $metricsPath = config('observability.metrics.endpoint.path', '/metrics');
        return $request->path() === ltrim($metricsPath, '/');
    }
}
