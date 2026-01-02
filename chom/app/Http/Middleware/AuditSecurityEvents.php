<?php

namespace App\Http\Middleware;

use App\Models\AuditLog;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * Audit Security Events Middleware
 *
 * SECURITY: Comprehensive security event logging for compliance and threat detection.
 * This middleware automatically logs authentication, authorization, and sensitive operations.
 *
 * Events logged:
 * - Authentication successes and failures
 * - Authorization failures (403 responses)
 * - Sensitive operations (write/delete on critical resources)
 * - Cross-tenant access attempts
 * - API rate limit violations
 *
 * OWASP Reference: A09:2021 – Security Logging and Monitoring Failures
 * Proper logging is essential for detecting and responding to security incidents.
 */
class AuditSecurityEvents
{
    /**
     * Handle an incoming request.
     *
     * @param  \Closure(\Illuminate\Http\Request): (\Symfony\Component\HttpFoundation\Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        // Process request
        $response = $next($request);

        // Log after response is generated to capture response status
        $this->logSecurityEvents($request, $response);

        return $response;
    }

    /**
     * Log security-relevant events based on request and response.
     *
     * SECURITY: Captures critical security events for audit trail and threat detection.
     */
    protected function logSecurityEvents(Request $request, Response $response): void
    {
        // Log authentication failures (401 Unauthorized)
        if ($response->getStatusCode() === 401) {
            $this->logAuthenticationFailure($request);
        }

        // Log authorization failures (403 Forbidden)
        if ($response->getStatusCode() === 403) {
            $this->logAuthorizationFailure($request);
        }

        // Log successful authentication events
        if ($this->isAuthenticationEndpoint($request) && $response->getStatusCode() === 200) {
            $this->logAuthenticationSuccess($request);
        }

        // Log sensitive write operations on critical resources
        if ($this->isSensitiveOperation($request) && $response->isSuccessful()) {
            $this->logSensitiveOperation($request);
        }

        // Log rate limit violations (429 Too Many Requests)
        if ($response->getStatusCode() === 429) {
            $this->logRateLimitViolation($request);
        }
    }

    /**
     * Log authentication failure event.
     *
     * SECURITY: Multiple failures from same IP may indicate brute force attack.
     * High severity to enable monitoring and alerting.
     */
    protected function logAuthenticationFailure(Request $request): void
    {
        AuditLog::log(
            action: 'authentication.failed',
            organization: null,
            user: null,
            resourceType: 'authentication',
            resourceId: null,
            metadata: [
                'email' => $request->input('email'),
                'path' => $request->path(),
                'method' => $request->method(),
            ],
            severity: 'high'
        );
    }

    /**
     * Log authorization failure event.
     *
     * SECURITY: Authorization failures may indicate privilege escalation attempts.
     * High severity especially if user attempting cross-tenant access.
     */
    protected function logAuthorizationFailure(Request $request): void
    {
        $user = Auth::user();
        $organization = $user?->organization;

        // Detect potential cross-tenant access attempts
        $severity = $this->detectsCrossTenantAttempt($request) ? 'critical' : 'high';

        AuditLog::log(
            action: 'authorization.denied',
            organization: $organization,
            user: $user,
            resourceType: $this->extractResourceType($request),
            resourceId: $this->extractResourceId($request),
            metadata: [
                'path' => $request->path(),
                'method' => $request->method(),
                'route_name' => $request->route()?->getName(),
            ],
            severity: $severity
        );
    }

    /**
     * Log successful authentication event.
     *
     * SECURITY: Track all successful logins for forensic analysis.
     * Medium severity - normal security-relevant event.
     */
    protected function logAuthenticationSuccess(Request $request): void
    {
        $user = Auth::user();

        AuditLog::log(
            action: 'authentication.success',
            organization: $user?->organization,
            user: $user,
            resourceType: 'authentication',
            resourceId: null,
            metadata: [
                'method' => $this->detectAuthMethod($request),
                'two_factor_used' => $request->has('two_factor_code'),
            ],
            severity: 'medium'
        );
    }

    /**
     * Log sensitive operation.
     *
     * SECURITY: Track operations on critical resources for audit trail.
     * Severity varies based on operation type.
     */
    protected function logSensitiveOperation(Request $request): void
    {
        $user = Auth::user();
        $organization = $user?->organization;

        $action = $this->describeOperation($request);
        $severity = $this->isDeleteOperation($request) ? 'high' : 'medium';

        AuditLog::log(
            action: $action,
            organization: $organization,
            user: $user,
            resourceType: $this->extractResourceType($request),
            resourceId: $this->extractResourceId($request),
            metadata: [
                'method' => $request->method(),
                'path' => $request->path(),
                'input' => $this->sanitizeInput($request->except(['password', 'password_confirmation'])),
            ],
            severity: $severity
        );
    }

    /**
     * Log rate limit violation.
     *
     * SECURITY: Excessive requests may indicate abuse or automated attack.
     * High severity to enable monitoring and blocking.
     */
    protected function logRateLimitViolation(Request $request): void
    {
        $user = Auth::user();

        AuditLog::log(
            action: 'api.rate_limit_exceeded',
            organization: $user?->organization,
            user: $user,
            resourceType: 'api',
            resourceId: null,
            metadata: [
                'path' => $request->path(),
                'method' => $request->method(),
            ],
            severity: 'high'
        );
    }

    /**
     * Check if request is to authentication endpoint.
     */
    protected function isAuthenticationEndpoint(Request $request): bool
    {
        return in_array($request->path(), [
            'api/v1/auth/login',
            'api/v1/auth/register',
            'api/v1/auth/two-factor-challenge',
        ]);
    }

    /**
     * Check if operation is sensitive and should be logged.
     *
     * SECURITY: Focus on write operations to critical resources.
     */
    protected function isSensitiveOperation(Request $request): bool
    {
        // Only log write operations (POST, PUT, PATCH, DELETE)
        if (! in_array($request->method(), ['POST', 'PUT', 'PATCH', 'DELETE'])) {
            return false;
        }

        // Critical resources that require audit logging
        $sensitivePatterns = [
            'api/v1/users',
            'api/v1/teams',
            'api/v1/sites',
            'api/v1/vps-servers',
            'api/v1/backups',
        ];

        foreach ($sensitivePatterns as $pattern) {
            if (str_starts_with($request->path(), $pattern)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Detect potential cross-tenant access attempts.
     *
     * SECURITY: Cross-tenant access is CRITICAL security violation.
     */
    protected function detectsCrossTenantAttempt(Request $request): bool
    {
        // Check if URL contains different organization/tenant ID than user's
        $user = Auth::user();
        if (! $user) {
            return false;
        }

        // Extract tenant/org IDs from route parameters
        $routeTenantId = $request->route('tenant_id') ?? $request->route('organization_id');
        if (! $routeTenantId) {
            return false;
        }

        // Compare with user's organization
        return $routeTenantId !== $user->organization_id;
    }

    /**
     * Extract resource type from request.
     */
    protected function extractResourceType(Request $request): ?string
    {
        $path = $request->path();

        // Extract resource from API path (e.g., api/v1/sites/123 -> 'site')
        if (preg_match('#api/v1/([^/]+)#', $path, $matches)) {
            return rtrim($matches[1], 's'); // Remove trailing 's' for singular
        }

        return null;
    }

    /**
     * Extract resource ID from request.
     */
    protected function extractResourceId(Request $request): ?string
    {
        // Try to get from route parameter
        return $request->route('id')
            ?? $request->route('site')
            ?? $request->route('user')
            ?? $request->route('team')
            ?? null;
    }

    /**
     * Describe operation for audit log.
     */
    protected function describeOperation(Request $request): string
    {
        $resource = $this->extractResourceType($request);
        $method = $request->method();

        $actionMap = [
            'POST' => "{$resource}.created",
            'PUT' => "{$resource}.updated",
            'PATCH' => "{$resource}.updated",
            'DELETE' => "{$resource}.deleted",
        ];

        return $actionMap[$method] ?? "{$resource}.modified";
    }

    /**
     * Check if operation is delete.
     */
    protected function isDeleteOperation(Request $request): bool
    {
        return $request->method() === 'DELETE';
    }

    /**
     * Detect authentication method used.
     */
    protected function detectAuthMethod(Request $request): string
    {
        if ($request->bearerToken()) {
            return 'token';
        }

        if (Auth::viaRemember()) {
            return 'remember_token';
        }

        return 'credentials';
    }

    /**
     * Sanitize input for logging.
     *
     * SECURITY: Remove sensitive data before logging.
     */
    protected function sanitizeInput(array $input): array
    {
        $sensitiveKeys = ['password', 'token', 'secret', 'api_key', 'private_key'];

        foreach ($sensitiveKeys as $key) {
            if (isset($input[$key])) {
                $input[$key] = '[REDACTED]';
            }
        }

        return $input;
    }
}
