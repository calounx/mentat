<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;

/**
 * Performance Monitoring Middleware
 *
 * Tracks request execution time and logs slow requests.
 * Adds X-Response-Time header to all responses.
 */
class PerformanceMonitoring
{
    /**
     * Threshold for logging slow requests (in milliseconds)
     */
    private const SLOW_REQUEST_THRESHOLD = 1000;

    /**
     * Handle an incoming request.
     *
     * @param  \Closure(\Illuminate\Http\Request): (\Symfony\Component\HttpFoundation\Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        // Record start time with microsecond precision
        $startTime = microtime(true);

        // Process the request
        $response = $next($request);

        // Calculate execution time in milliseconds
        $executionTime = (microtime(true) - $startTime) * 1000;

        // Add response time header
        $response->headers->set('X-Response-Time', number_format($executionTime, 2).'ms');

        // Log slow requests
        if ($executionTime > self::SLOW_REQUEST_THRESHOLD) {
            $this->logSlowRequest($request, $executionTime);
        }

        // Log performance metrics for all requests in debug mode
        if (config('app.debug')) {
            $this->logPerformanceMetrics($request, $executionTime, $response);
        }

        return $response;
    }

    /**
     * Log slow request details.
     */
    private function logSlowRequest(Request $request, float $executionTime): void
    {
        Log::channel('performance')->warning('Slow request detected', [
            'method' => $request->method(),
            'url' => $request->fullUrl(),
            'route' => $request->route()?->getName() ?? 'unknown',
            'execution_time_ms' => round($executionTime, 2),
            'memory_peak_mb' => round(memory_get_peak_usage(true) / 1024 / 1024, 2),
            'user_id' => auth()->id(),
            'ip' => $request->ip(),
            'user_agent' => $request->userAgent(),
        ]);
    }

    /**
     * Log detailed performance metrics.
     */
    private function logPerformanceMetrics(Request $request, float $executionTime, Response $response): void
    {
        Log::channel('performance')->debug('Request performance', [
            'method' => $request->method(),
            'url' => $request->fullUrl(),
            'route' => $request->route()?->getName() ?? 'unknown',
            'execution_time_ms' => round($executionTime, 2),
            'memory_peak_mb' => round(memory_get_peak_usage(true) / 1024 / 1024, 2),
            'memory_current_mb' => round(memory_get_usage(true) / 1024 / 1024, 2),
            'status_code' => $response->getStatusCode(),
            'user_id' => auth()->id(),
            'db_queries' => $this->getQueryCount(),
        ]);
    }

    /**
     * Get database query count if query logging is enabled.
     */
    private function getQueryCount(): ?int
    {
        try {
            return count(\DB::getQueryLog());
        } catch (\Exception $e) {
            return null;
        }
    }
}
