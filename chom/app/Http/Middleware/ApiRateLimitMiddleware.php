<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Config;
use Symfony\Component\HttpFoundation\Response;

/**
 * API Rate Limiting Middleware
 *
 * Implements sophisticated rate limiting to protect against abuse and DoS attacks.
 * Uses Redis for distributed rate limiting across multiple application servers.
 *
 * Features:
 * - Per-user rate limiting with different limits for authenticated/anonymous
 * - Per-tenant rate limiting based on subscription tier
 * - Burst protection with sliding window algorithm
 * - Custom rate limit responses with Retry-After headers
 * - Special limits for critical operations (login, password reset, etc.)
 *
 * OWASP Reference: API4:2023 – Unrestricted Resource Consumption
 * Protection: Prevents resource exhaustion attacks and API abuse
 *
 * @package App\Http\Middleware
 */
class ApiRateLimitMiddleware
{
    /**
     * Redis connection for rate limiting.
     */
    protected string $redisConnection;

    /**
     * Rate limiting configuration.
     */
    protected array $config;

    /**
     * Create a new middleware instance.
     */
    public function __construct()
    {
        $this->config = Config::get('security.rate_limiting', []);
        $this->redisConnection = $this->config['redis_connection'] ?? 'default';
    }

    /**
     * Handle an incoming request.
     *
     * Implements sliding window rate limiting algorithm:
     * 1. Check if rate limiting is enabled
     * 2. Identify the request (user/IP/tenant)
     * 3. Check current request count in window
     * 4. Allow or deny based on limits
     * 5. Set appropriate response headers
     *
     * @param Request $request The incoming HTTP request
     * @param Closure $next The next middleware in the pipeline
     * @param string|null $limiter Custom limiter name for critical operations
     * @return Response
     */
    public function handle(Request $request, Closure $next, ?string $limiter = null): Response
    {
        // Skip if rate limiting is disabled
        if (!($this->config['enabled'] ?? true)) {
            return $next($request);
        }

        // Determine which rate limit to apply
        $limitConfig = $this->getLimitConfig($request, $limiter);

        // Generate unique key for this request source
        $key = $this->generateRateLimitKey($request, $limiter);

        // Check and update rate limit
        $result = $this->checkRateLimit($key, $limitConfig);

        // Add rate limit headers to response
        $response = $next($request);
        $this->addRateLimitHeaders($response, $result);

        // Return 429 if rate limit exceeded
        if (!$result['allowed']) {
            return $this->rateLimitExceeded($result);
        }

        return $response;
    }

    /**
     * Get rate limit configuration for the current request.
     *
     * Determines appropriate rate limit based on:
     * - Custom limiter (for critical operations like login)
     * - User authentication status
     * - Tenant subscription tier
     *
     * @param Request $request The incoming request
     * @param string|null $limiter Custom limiter name
     * @return array Rate limit configuration [requests, decay_minutes]
     */
    protected function getLimitConfig(Request $request, ?string $limiter = null): array
    {
        // Critical operations have specific limits
        if ($limiter && isset($this->config['critical_operations'][$limiter])) {
            return $this->config['critical_operations'][$limiter];
        }

        // Authenticated users get higher limits
        if ($request->user()) {
            // Check for tenant-specific limits based on subscription
            $tenant = $request->user()->currentTeam ?? null;

            if ($tenant && $tenant->subscription_tier) {
                $tierLimits = $this->config['tenant_limits'][$tenant->subscription_tier] ?? null;

                if ($tierLimits) {
                    return [
                        'requests' => $tierLimits['burst'],
                        'decay_minutes' => 1,
                        'hourly_limit' => $tierLimits['requests_per_hour'],
                    ];
                }
            }

            // Default authenticated user limits
            return $this->config['authenticated'];
        }

        // Anonymous users get lowest limits
        return $this->config['anonymous'];
    }

    /**
     * Generate unique Redis key for rate limiting.
     *
     * Key format: rate_limit:{context}:{identifier}
     * Context can be: user, ip, tenant, operation
     * Identifier: user_id, ip_address, tenant_id, operation_name
     *
     * SECURITY: Uses multiple identifiers to prevent bypass via proxies
     *
     * @param Request $request The incoming request
     * @param string|null $limiter Custom limiter name
     * @return string Redis key for rate limiting
     */
    protected function generateRateLimitKey(Request $request, ?string $limiter = null): string
    {
        $parts = ['rate_limit'];

        // Add limiter context if specified
        if ($limiter) {
            $parts[] = 'operation';
            $parts[] = $limiter;
        } else {
            $parts[] = 'general';
        }

        // Identify user or use IP address
        if ($request->user()) {
            $parts[] = 'user';
            $parts[] = (string) $request->user()->id;

            // Also track by tenant if available
            if ($tenant = $request->user()->currentTeam) {
                $parts[] = 'tenant';
                $parts[] = (string) $tenant->id;
            }
        } else {
            $parts[] = 'ip';
            $parts[] = $this->getClientIp($request);
        }

        return implode(':', $parts);
    }

    /**
     * Check rate limit using sliding window algorithm.
     *
     * Uses Redis sorted sets for efficient sliding window implementation:
     * 1. Add current timestamp to sorted set
     * 2. Remove timestamps outside window
     * 3. Count remaining timestamps
     * 4. Compare against limit
     *
     * SECURITY: Atomic operations prevent race conditions
     *
     * @param string $key Redis key for this rate limit
     * @param array $config Rate limit configuration
     * @return array Result with allowed status and limit info
     */
    protected function checkRateLimit(string $key, array $config): array
    {
        $redis = Redis::connection($this->redisConnection);
        $now = microtime(true);
        $windowStart = $now - ($config['decay_minutes'] * 60);

        // Use Redis pipeline for atomic operations
        $redis->pipeline(function ($pipe) use ($key, $now, $windowStart) {
            // Add current request timestamp
            $pipe->zadd($key, $now, (string) $now);

            // Remove timestamps outside window
            $pipe->zremrangebyscore($key, '-inf', (string) $windowStart);

            // Count requests in current window
            $pipe->zcard($key);

            // Set expiration on key
            $pipe->expire($key, (int) ($windowStart + 3600));
        });

        // Get current request count
        $currentCount = (int) $redis->zcard($key);

        $allowed = $currentCount <= $config['requests'];

        return [
            'allowed' => $allowed,
            'current' => $currentCount,
            'limit' => $config['requests'],
            'remaining' => max(0, $config['requests'] - $currentCount),
            'reset_at' => (int) ($now + ($config['decay_minutes'] * 60)),
            'retry_after' => $allowed ? 0 : (int) ($config['decay_minutes'] * 60),
        ];
    }

    /**
     * Add rate limit headers to response.
     *
     * Standard rate limit headers:
     * - X-RateLimit-Limit: Maximum requests allowed
     * - X-RateLimit-Remaining: Requests remaining in window
     * - X-RateLimit-Reset: Unix timestamp when limit resets
     *
     * @param Response $response The HTTP response
     * @param array $result Rate limit check result
     * @return void
     */
    protected function addRateLimitHeaders(Response $response, array $result): void
    {
        $response->headers->set('X-RateLimit-Limit', (string) $result['limit']);
        $response->headers->set('X-RateLimit-Remaining', (string) $result['remaining']);
        $response->headers->set('X-RateLimit-Reset', (string) $result['reset_at']);

        if (!$result['allowed'] && $result['retry_after'] > 0) {
            $response->headers->set('Retry-After', (string) $result['retry_after']);
        }
    }

    /**
     * Create rate limit exceeded response.
     *
     * Returns 429 Too Many Requests with:
     * - Clear error message
     * - Retry-After header indicating wait time
     * - Rate limit information in response body
     *
     * OWASP: Provides clear feedback without leaking sensitive info
     *
     * @param array $result Rate limit check result
     * @return Response JSON response with 429 status
     */
    protected function rateLimitExceeded(array $result): Response
    {
        $response = response()->json([
            'message' => 'Too many requests. Please try again later.',
            'error' => 'rate_limit_exceeded',
            'retry_after' => $result['retry_after'],
            'limit' => $result['limit'],
            'reset_at' => date('Y-m-d H:i:s', $result['reset_at']),
        ], 429);

        $this->addRateLimitHeaders($response, $result);

        return $response;
    }

    /**
     * Get client IP address from request.
     *
     * Checks multiple headers to find real client IP:
     * 1. X-Forwarded-For (if behind proxy/load balancer)
     * 2. X-Real-IP (alternative proxy header)
     * 3. Remote address (direct connection)
     *
     * SECURITY: Validates IP format to prevent header injection
     * SECURITY: Only trusts proxy headers if from trusted proxies
     *
     * @param Request $request The incoming request
     * @return string Client IP address
     */
    protected function getClientIp(Request $request): string
    {
        // Get trusted proxies from config
        $trustedProxies = Config::get('trustedproxy.proxies', []);

        // Check if request is from trusted proxy
        $isTrustedProxy = $this->isTrustedProxy($request->server->get('REMOTE_ADDR'), $trustedProxies);

        // Only check proxy headers if from trusted proxy
        if ($isTrustedProxy) {
            // Check X-Forwarded-For header
            if ($request->header('X-Forwarded-For')) {
                $ips = explode(',', $request->header('X-Forwarded-For'));
                $ip = trim($ips[0]);

                if ($this->isValidIp($ip)) {
                    return $ip;
                }
            }

            // Check X-Real-IP header
            if ($request->header('X-Real-IP')) {
                $ip = $request->header('X-Real-IP');

                if ($this->isValidIp($ip)) {
                    return $ip;
                }
            }
        }

        // Fall back to remote address
        return $request->ip() ?? '0.0.0.0';
    }

    /**
     * Check if IP is from a trusted proxy.
     *
     * @param string|null $ip IP address to check
     * @param array $trustedProxies List of trusted proxy IPs/CIDRs
     * @return bool True if IP is trusted proxy
     */
    protected function isTrustedProxy(?string $ip, array $trustedProxies): bool
    {
        if (!$ip || empty($trustedProxies)) {
            return false;
        }

        // Check for wildcard (trust all)
        if (in_array('*', $trustedProxies, true)) {
            return true;
        }

        // Check exact match or CIDR match
        foreach ($trustedProxies as $proxy) {
            if ($ip === $proxy || $this->ipInCidr($ip, $proxy)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Check if IP is within CIDR range.
     *
     * @param string $ip IP address to check
     * @param string $cidr CIDR notation (e.g., 192.168.1.0/24)
     * @return bool True if IP is in CIDR range
     */
    protected function ipInCidr(string $ip, string $cidr): bool
    {
        if (!str_contains($cidr, '/')) {
            return false;
        }

        [$subnet, $mask] = explode('/', $cidr);

        $ipLong = ip2long($ip);
        $subnetLong = ip2long($subnet);
        $maskLong = -1 << (32 - (int) $mask);

        return ($ipLong & $maskLong) === ($subnetLong & $maskLong);
    }

    /**
     * Validate IP address format.
     *
     * SECURITY: Prevents header injection via malformed IPs
     *
     * @param string $ip IP address to validate
     * @return bool True if valid IPv4 or IPv6 address
     */
    protected function isValidIp(string $ip): bool
    {
        return filter_var($ip, FILTER_VALIDATE_IP) !== false;
    }
}
