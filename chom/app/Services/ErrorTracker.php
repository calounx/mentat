<?php

declare(strict_types=1);

namespace App\Services;

use Illuminate\Support\Facades\Auth;
use Throwable;

/**
 * Error Tracker Service
 *
 * Captures and tracks application errors with rich context including
 * user information, request data, and environment details.
 * Supports error grouping and deduplication.
 */
class ErrorTracker
{
    private TracingService $tracing;
    private StructuredLogger $logger;
    private array $errorGroups = [];

    public function __construct(TracingService $tracing, StructuredLogger $logger)
    {
        $this->tracing = $tracing;
        $this->logger = $logger;
    }

    /**
     * Capture an exception.
     *
     * @param Throwable $exception
     * @param array $extraContext Additional context
     * @return string|null Error ID
     */
    public function captureException(Throwable $exception, array $extraContext = []): ?string
    {
        if (!config('observability.error_tracking.enabled', true)) {
            return null;
        }

        // Check if exception should be ignored
        if ($this->shouldIgnoreException($exception)) {
            return null;
        }

        $errorId = $this->generateErrorId();
        $groupKey = $this->getGroupKey($exception);

        $context = $this->buildErrorContext($exception, $extraContext);

        // Add error to group for deduplication
        if (!isset($this->errorGroups[$groupKey])) {
            $this->errorGroups[$groupKey] = [
                'first_seen' => now(),
                'count' => 0,
                'last_error_id' => null,
            ];
        }

        $this->errorGroups[$groupKey]['count']++;
        $this->errorGroups[$groupKey]['last_seen'] = now();
        $this->errorGroups[$groupKey]['last_error_id'] = $errorId;

        // Log the error
        $this->logger->error('Exception captured', array_merge($context, [
            'error_id' => $errorId,
            'error_group' => $groupKey,
            'occurrence_count' => $this->errorGroups[$groupKey]['count'],
        ]));

        // Send to error tracking service
        $this->sendToTrackingService($errorId, $exception, $context);

        return $errorId;
    }

    /**
     * Capture a message (non-exception error).
     *
     * @param string $message
     * @param string $level Error level (error, warning, info)
     * @param array $extraContext Additional context
     * @return string|null Error ID
     */
    public function captureMessage(string $message, string $level = 'error', array $extraContext = []): ?string
    {
        if (!config('observability.error_tracking.enabled', true)) {
            return null;
        }

        $errorId = $this->generateErrorId();

        $context = array_merge($extraContext, [
            'error_id' => $errorId,
            'message' => $message,
            'level' => $level,
        ]);

        // Add standard context
        $context = array_merge($context, $this->getStandardContext());

        $this->logger->log($level, $message, $context);

        return $errorId;
    }

    /**
     * Add breadcrumb for debugging context.
     *
     * @param string $message
     * @param string $category
     * @param array $data
     * @return void
     */
    public function addBreadcrumb(string $message, string $category = 'default', array $data = []): void
    {
        if (!config('observability.error_tracking.capture_context.breadcrumbs', true)) {
            return;
        }

        // Add breadcrumb to trace context
        $this->tracing->addEvent('breadcrumb', [
            'message' => $message,
            'category' => $category,
            'data' => $data,
            'timestamp' => now()->toIso8601String(),
        ]);
    }

    /**
     * Set user context for error tracking.
     *
     * @param string $id User ID
     * @param string|null $email User email
     * @param array $extraData Additional user data
     * @return void
     */
    public function setUserContext(string $id, ?string $email = null, array $extraData = []): void
    {
        $userData = array_merge([
            'id' => $id,
            'email' => $email,
        ], $extraData);

        $this->tracing->setBaggage('user', $userData);
    }

    /**
     * Set custom tags for error context.
     *
     * @param array $tags Key-value pairs
     * @return void
     */
    public function setTags(array $tags): void
    {
        foreach ($tags as $key => $value) {
            $this->tracing->setBaggage("tag.{$key}", $value);
        }
    }

    /**
     * Get error statistics.
     *
     * @return array
     */
    public function getErrorStatistics(): array
    {
        $totalErrors = 0;
        $uniqueErrors = count($this->errorGroups);

        foreach ($this->errorGroups as $group) {
            $totalErrors += $group['count'];
        }

        return [
            'total_errors' => $totalErrors,
            'unique_errors' => $uniqueErrors,
            'error_groups' => $this->errorGroups,
        ];
    }

    /**
     * Build comprehensive error context.
     *
     * @param Throwable $exception
     * @param array $extraContext
     * @return array
     */
    private function buildErrorContext(Throwable $exception, array $extraContext = []): array
    {
        $context = [
            'exception_class' => get_class($exception),
            'exception_message' => $exception->getMessage(),
            'exception_code' => $exception->getCode(),
            'file' => $exception->getFile(),
            'line' => $exception->getLine(),
            'stack_trace' => $this->formatStackTrace($exception),
        ];

        // Add previous exception if exists
        if ($previous = $exception->getPrevious()) {
            $context['previous_exception'] = [
                'class' => get_class($previous),
                'message' => $previous->getMessage(),
                'file' => $previous->getFile(),
                'line' => $previous->getLine(),
            ];
        }

        // Add standard context
        $context = array_merge($context, $this->getStandardContext());

        // Add extra context
        $context = array_merge($context, $extraContext);

        return $context;
    }

    /**
     * Get standard context (user, request, environment).
     *
     * @return array
     */
    private function getStandardContext(): array
    {
        $context = [];
        $captureConfig = config('observability.error_tracking.capture_context', []);

        // User context
        if ($captureConfig['user'] ?? true) {
            $user = Auth::user();
            if ($user) {
                $context['user'] = [
                    'id' => $user->id,
                    'email' => $user->email,
                    'team_id' => $user->team_id ?? null,
                ];
            }
        }

        // Request context
        if ($captureConfig['request'] ?? true) {
            $request = request();
            if ($request) {
                $context['request'] = [
                    'url' => $request->fullUrl(),
                    'method' => $request->method(),
                    'ip' => $request->ip(),
                    'user_agent' => $request->userAgent(),
                    'headers' => $this->sanitizeHeaders($request->headers->all()),
                    'query' => $request->query->all(),
                    'body' => $this->sanitizeRequestBody($request->all()),
                ];
            }
        }

        // Environment context
        if ($captureConfig['environment'] ?? true) {
            $context['environment'] = [
                'app_env' => config('app.env'),
                'app_debug' => config('app.debug'),
                'app_version' => config('app.version', '1.0.0'),
                'php_version' => PHP_VERSION,
                'laravel_version' => app()->version(),
            ];
        }

        // Trace context
        if ($traceId = $this->tracing->getTraceId()) {
            $context['trace_id'] = $traceId;
        }

        return $context;
    }

    /**
     * Format exception stack trace.
     *
     * @param Throwable $exception
     * @return array
     */
    private function formatStackTrace(Throwable $exception): array
    {
        $trace = $exception->getTrace();
        $formatted = [];

        foreach ($trace as $frame) {
            $formatted[] = [
                'file' => $frame['file'] ?? 'unknown',
                'line' => $frame['line'] ?? 0,
                'function' => $frame['function'] ?? 'unknown',
                'class' => $frame['class'] ?? null,
                'type' => $frame['type'] ?? null,
            ];
        }

        return $formatted;
    }

    /**
     * Generate error group key for deduplication.
     *
     * @param Throwable $exception
     * @return string
     */
    private function getGroupKey(Throwable $exception): string
    {
        $groupConfig = config('observability.error_tracking.grouping', []);

        $parts = [];

        if ($groupConfig['by_exception_class'] ?? true) {
            $parts[] = get_class($exception);
        }

        if ($groupConfig['by_file_and_line'] ?? true) {
            $parts[] = $exception->getFile();
            $parts[] = $exception->getLine();
        }

        return md5(implode(':', $parts));
    }

    /**
     * Check if exception should be ignored.
     *
     * @param Throwable $exception
     * @return bool
     */
    private function shouldIgnoreException(Throwable $exception): bool
    {
        $ignorePatterns = config('observability.error_tracking.grouping.ignore_patterns', []);

        $exceptionClass = get_class($exception);

        foreach ($ignorePatterns as $pattern) {
            if (str_contains($exceptionClass, $pattern)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Sanitize request headers to remove sensitive data.
     *
     * @param array $headers
     * @return array
     */
    private function sanitizeHeaders(array $headers): array
    {
        $sensitiveHeaders = [
            'authorization',
            'cookie',
            'x-api-key',
            'x-auth-token',
        ];

        $sanitized = [];

        foreach ($headers as $key => $value) {
            if (in_array(strtolower($key), $sensitiveHeaders)) {
                $sanitized[$key] = '[REDACTED]';
            } else {
                $sanitized[$key] = $value;
            }
        }

        return $sanitized;
    }

    /**
     * Sanitize request body to remove sensitive data.
     *
     * @param array $data
     * @return array
     */
    private function sanitizeRequestBody(array $data): array
    {
        $sensitiveFields = [
            'password',
            'password_confirmation',
            'current_password',
            'token',
            'api_key',
            'secret',
            'credit_card',
            'cvv',
        ];

        $sanitized = [];

        foreach ($data as $key => $value) {
            if (in_array(strtolower($key), $sensitiveFields)) {
                $sanitized[$key] = '[REDACTED]';
            } elseif (is_array($value)) {
                $sanitized[$key] = $this->sanitizeRequestBody($value);
            } else {
                $sanitized[$key] = $value;
            }
        }

        return $sanitized;
    }

    /**
     * Generate a unique error ID.
     *
     * @return string
     */
    private function generateErrorId(): string
    {
        return \Illuminate\Support\Str::uuid()->toString();
    }

    /**
     * Send error to tracking service (Sentry, Bugsnag, etc.).
     *
     * @param string $errorId
     * @param Throwable $exception
     * @param array $context
     * @return void
     */
    private function sendToTrackingService(string $errorId, Throwable $exception, array $context): void
    {
        $driver = config('observability.error_tracking.driver');

        if ($driver === 'sentry') {
            $this->sendToSentry($errorId, $exception, $context);
        } elseif ($driver === 'bugsnag') {
            $this->sendToBugsnag($errorId, $exception, $context);
        }
    }

    /**
     * Send error to Sentry.
     *
     * @param string $errorId
     * @param Throwable $exception
     * @param array $context
     * @return void
     */
    private function sendToSentry(string $errorId, Throwable $exception, array $context): void
    {
        // In production, this would use the Sentry SDK
        // For now, we log the structured error data
        \Log::channel('sentry')->error('Sentry error', [
            'error_id' => $errorId,
            'exception' => get_class($exception),
            'message' => $exception->getMessage(),
            'context' => $context,
        ]);
    }

    /**
     * Send error to Bugsnag.
     *
     * @param string $errorId
     * @param Throwable $exception
     * @param array $context
     * @return void
     */
    private function sendToBugsnag(string $errorId, Throwable $exception, array $context): void
    {
        // In production, this would use the Bugsnag SDK
        // For now, we log the structured error data
        \Log::channel('bugsnag')->error('Bugsnag error', [
            'error_id' => $errorId,
            'exception' => get_class($exception),
            'message' => $exception->getMessage(),
            'context' => $context,
        ]);
    }
}
