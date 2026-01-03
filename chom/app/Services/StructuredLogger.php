<?php

declare(strict_types=1);

namespace App\Services;

use Illuminate\Support\Facades\Auth;
use Psr\Log\LoggerInterface;
use Psr\Log\LogLevel;

/**
 * Structured Logger Service
 *
 * Provides structured JSON logging with automatic context enrichment
 * including trace IDs, user IDs, tenant IDs, and request context.
 */
class StructuredLogger
{
    private LoggerInterface $logger;
    private TracingService $tracing;
    private array $globalContext = [];

    public function __construct(LoggerInterface $logger, TracingService $tracing)
    {
        $this->logger = $logger;
        $this->tracing = $tracing;
    }

    /**
     * Log an emergency message.
     *
     * @param string $message
     * @param array $context
     * @return void
     */
    public function emergency(string $message, array $context = []): void
    {
        $this->log(LogLevel::EMERGENCY, $message, $context);
    }

    /**
     * Log an alert message.
     *
     * @param string $message
     * @param array $context
     * @return void
     */
    public function alert(string $message, array $context = []): void
    {
        $this->log(LogLevel::ALERT, $message, $context);
    }

    /**
     * Log a critical message.
     *
     * @param string $message
     * @param array $context
     * @return void
     */
    public function critical(string $message, array $context = []): void
    {
        $this->log(LogLevel::CRITICAL, $message, $context);
    }

    /**
     * Log an error message.
     *
     * @param string $message
     * @param array $context
     * @return void
     */
    public function error(string $message, array $context = []): void
    {
        $this->log(LogLevel::ERROR, $message, $context);
    }

    /**
     * Log a warning message.
     *
     * @param string $message
     * @param array $context
     * @return void
     */
    public function warning(string $message, array $context = []): void
    {
        $this->log(LogLevel::WARNING, $message, $context);
    }

    /**
     * Log a notice message.
     *
     * @param string $message
     * @param array $context
     * @return void
     */
    public function notice(string $message, array $context = []): void
    {
        $this->log(LogLevel::NOTICE, $message, $context);
    }

    /**
     * Log an info message.
     *
     * @param string $message
     * @param array $context
     * @return void
     */
    public function info(string $message, array $context = []): void
    {
        $this->log(LogLevel::INFO, $message, $context);
    }

    /**
     * Log a debug message.
     *
     * @param string $message
     * @param array $context
     * @return void
     */
    public function debug(string $message, array $context = []): void
    {
        $this->log(LogLevel::DEBUG, $message, $context);
    }

    /**
     * Log a message at the specified level.
     *
     * @param string $level
     * @param string $message
     * @param array $context
     * @return void
     */
    public function log(string $level, string $message, array $context = []): void
    {
        if (!$this->shouldLog($level, $message)) {
            return;
        }

        $enrichedContext = $this->enrichContext($context);

        $this->logger->log($level, $message, $enrichedContext);
    }

    /**
     * Log a performance metric.
     *
     * @param string $operation Operation name
     * @param float $duration Duration in seconds
     * @param array $context Additional context
     * @return void
     */
    public function performance(string $operation, float $duration, array $context = []): void
    {
        $durationMs = round($duration * 1000, 2);

        $context = array_merge($context, [
            'operation' => $operation,
            'duration_ms' => $durationMs,
            'duration_seconds' => $duration,
        ]);

        $level = LogLevel::INFO;
        $message = "Performance metric: {$operation}";

        // Determine severity based on duration
        $slowThreshold = $this->getSlowThreshold($operation);
        if ($duration > $slowThreshold) {
            $level = LogLevel::WARNING;
            $message = "Slow operation detected: {$operation}";
            $context['slow'] = true;
            $context['threshold_ms'] = $slowThreshold * 1000;
        }

        $this->log($level, $message, $context);
    }

    /**
     * Log a slow database query.
     *
     * @param string $query SQL query
     * @param float $duration Duration in seconds
     * @param array $bindings Query bindings
     * @return void
     */
    public function slowQuery(string $query, float $duration, array $bindings = []): void
    {
        $context = [
            'query' => $query,
            'duration_ms' => round($duration * 1000, 2),
            'slow_query' => true,
        ];

        if (config('observability.performance.queries.log_bindings', false)) {
            $context['bindings'] = $bindings;
        }

        if (config('observability.performance.queries.backtrace', false)) {
            $context['backtrace'] = $this->getBacktrace();
        }

        $this->warning('Slow database query detected', $context);
    }

    /**
     * Log a business event.
     *
     * @param string $event Event name
     * @param array $data Event data
     * @return void
     */
    public function businessEvent(string $event, array $data = []): void
    {
        $context = array_merge($data, [
            'event_type' => 'business',
            'event_name' => $event,
        ]);

        $this->info("Business event: {$event}", $context);
    }

    /**
     * Log a security event.
     *
     * @param string $event Event name
     * @param array $data Event data
     * @param string $severity Severity level
     * @return void
     */
    public function securityEvent(string $event, array $data = [], string $severity = 'warning'): void
    {
        $context = array_merge($data, [
            'event_type' => 'security',
            'event_name' => $event,
            'ip_address' => request()?->ip(),
        ]);

        $this->log($severity, "Security event: {$event}", $context);
    }

    /**
     * Set global context that will be included in all logs.
     *
     * @param string $key
     * @param mixed $value
     * @return void
     */
    public function setGlobalContext(string $key, mixed $value): void
    {
        $this->globalContext[$key] = $value;
    }

    /**
     * Remove a global context key.
     *
     * @param string $key
     * @return void
     */
    public function removeGlobalContext(string $key): void
    {
        unset($this->globalContext[$key]);
    }

    /**
     * Clear all global context.
     *
     * @return void
     */
    public function clearGlobalContext(): void
    {
        $this->globalContext = [];
    }

    /**
     * Enrich context with automatic fields.
     *
     * @param array $context
     * @return array
     */
    private function enrichContext(array $context): array
    {
        $enrichConfig = config('observability.logging.enrich_context', []);

        $enriched = array_merge($this->globalContext, $context);

        // Add timestamp
        $enriched['timestamp'] = now()->toIso8601String();

        // Add trace ID
        if (($enrichConfig['trace_id'] ?? true) && $traceId = $this->tracing->getTraceId()) {
            $enriched['trace_id'] = $traceId;
        }

        // Add request ID
        if ($enrichConfig['request_id'] ?? true) {
            $enriched['request_id'] = $this->getRequestId();
        }

        // Add user ID
        if ($enrichConfig['user_id'] ?? true) {
            $user = Auth::user();
            if ($user) {
                $enriched['user_id'] = $user->id;
                $enriched['user_email'] = $user->email;
            }
        }

        // Add tenant ID
        if ($enrichConfig['tenant_id'] ?? true) {
            $user = Auth::user();
            if ($user && isset($user->team_id)) {
                $enriched['tenant_id'] = $user->team_id;
            }
        }

        // Add IP address
        if ($enrichConfig['ip_address'] ?? true) {
            $request = request();
            if ($request) {
                $enriched['ip_address'] = $request->ip();
            }
        }

        // Add user agent
        if ($enrichConfig['user_agent'] ?? false) {
            $request = request();
            if ($request) {
                $enriched['user_agent'] = $request->userAgent();
            }
        }

        // Add session ID
        if ($enrichConfig['session_id'] ?? false) {
            $request = request();
            if ($request && $request->hasSession()) {
                $enriched['session_id'] = $request->session()->getId();
            }
        }

        // Add environment
        $enriched['environment'] = config('app.env');

        // Add application info
        $enriched['app_name'] = config('app.name');
        $enriched['app_version'] = config('app.version', '1.0.0');

        return $enriched;
    }

    /**
     * Determine if a log should be written based on sampling configuration.
     *
     * @param string $level
     * @param string $message
     * @return bool
     */
    private function shouldLog(string $level, string $message): bool
    {
        if (!config('observability.logging.sampling.enabled', false)) {
            return true;
        }

        // Always log certain patterns
        $alwaysLogPatterns = config('observability.logging.sampling.patterns', []);
        foreach ($alwaysLogPatterns as $pattern) {
            if (str_contains(strtolower($level . ' ' . $message), strtolower($pattern))) {
                return true;
            }
        }

        // Apply sampling rate
        $samplingRate = config('observability.logging.sampling.rate', 0.1);
        return mt_rand() / mt_getrandmax() < $samplingRate;
    }

    /**
     * Get the request ID.
     *
     * @return string|null
     */
    private function getRequestId(): ?string
    {
        $request = request();

        if (!$request) {
            return null;
        }

        // Check for existing request ID header
        if ($request->hasHeader('X-Request-ID')) {
            return $request->header('X-Request-ID');
        }

        // Generate a new request ID
        static $requestId = null;
        if ($requestId === null) {
            $requestId = \Illuminate\Support\Str::uuid()->toString();
        }

        return $requestId;
    }

    /**
     * Get slow threshold for a given operation type.
     *
     * @param string $operation
     * @return float Threshold in seconds
     */
    private function getSlowThreshold(string $operation): float
    {
        $perfConfig = config('observability.logging.performance', []);

        if (str_contains($operation, 'query')) {
            return ($perfConfig['slow_query_threshold_ms'] ?? 100) / 1000;
        }

        if (str_contains($operation, 'request') || str_contains($operation, 'http')) {
            return ($perfConfig['slow_request_threshold_ms'] ?? 500) / 1000;
        }

        if (str_contains($operation, 'job') || str_contains($operation, 'queue')) {
            return ($perfConfig['slow_job_threshold_ms'] ?? 5000) / 1000;
        }

        return 1.0; // Default 1 second
    }

    /**
     * Get a filtered backtrace.
     *
     * @return array
     */
    private function getBacktrace(): array
    {
        $trace = debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS, 10);

        return array_map(function ($frame) {
            return [
                'file' => $frame['file'] ?? 'unknown',
                'line' => $frame['line'] ?? 0,
                'function' => $frame['function'] ?? 'unknown',
                'class' => $frame['class'] ?? null,
            ];
        }, array_slice($trace, 3)); // Skip the first 3 frames (this method and log methods)
    }
}
