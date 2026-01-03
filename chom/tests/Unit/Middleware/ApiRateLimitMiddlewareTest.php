<?php

declare(strict_types=1);

namespace Tests\Unit\Middleware;

use App\Http\Middleware\ApiRateLimitMiddleware;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Redis;
use Tests\TestCase;

/**
 * API Rate Limit Middleware Test
 *
 * Tests rate limiting functionality including:
 * - Per-user limits
 * - Per-tenant limits
 * - Anonymous limits
 * - Critical operation limits
 * - Rate limit headers
 *
 * @package Tests\Unit\Middleware
 */
class ApiRateLimitMiddlewareTest extends TestCase
{
    protected ApiRateLimitMiddleware $middleware;

    protected function setUp(): void
    {
        parent::setUp();

        $this->middleware = new ApiRateLimitMiddleware();

        // Configure rate limiting
        Config::set('security.rate_limiting', [
            'enabled' => true,
            'redis_connection' => 'default',
            'authenticated' => [
                'requests' => 100,
                'decay_minutes' => 1,
            ],
            'anonymous' => [
                'requests' => 20,
                'decay_minutes' => 1,
            ],
            'critical_operations' => [
                'login' => [
                    'requests' => 5,
                    'decay_minutes' => 15,
                ],
            ],
        ]);

        // Clear Redis before each test
        Redis::flushall();
    }

    /**
     * Test that requests under limit are allowed.
     */
    public function test_requests_under_limit_are_allowed(): void
    {
        $request = Request::create('/api/test', 'GET');
        $request->setUserResolver(fn() => null); // Anonymous

        $response = $this->middleware->handle(
            $request,
            fn($req) => new Response('OK', 200)
        );

        $this->assertEquals(200, $response->getStatusCode());
        $this->assertEquals('OK', $response->getContent());
    }

    /**
     * Test that rate limit headers are added.
     */
    public function test_rate_limit_headers_are_added(): void
    {
        $request = Request::create('/api/test', 'GET');
        $request->setUserResolver(fn() => null); // Anonymous

        $response = $this->middleware->handle(
            $request,
            fn($req) => new Response('OK', 200)
        );

        $this->assertTrue($response->headers->has('X-RateLimit-Limit'));
        $this->assertTrue($response->headers->has('X-RateLimit-Remaining'));
        $this->assertTrue($response->headers->has('X-RateLimit-Reset'));
    }

    /**
     * Test that requests over limit are rejected.
     */
    public function test_requests_over_limit_are_rejected(): void
    {
        $request = Request::create('/api/test', 'GET');
        $request->setUserResolver(fn() => null); // Anonymous

        // Make requests up to limit
        for ($i = 0; $i < 20; $i++) {
            $response = $this->middleware->handle(
                $request,
                fn($req) => new Response('OK', 200)
            );
            $this->assertEquals(200, $response->getStatusCode());
        }

        // Next request should be rate limited
        $response = $this->middleware->handle(
            $request,
            fn($req) => new Response('OK', 200)
        );

        $this->assertEquals(429, $response->getStatusCode());
        $this->assertTrue($response->headers->has('Retry-After'));
    }

    /**
     * Test that authenticated users get higher limits.
     */
    public function test_authenticated_users_get_higher_limits(): void
    {
        $user = (object) ['id' => 1];
        $request = Request::create('/api/test', 'GET');
        $request->setUserResolver(fn() => $user);

        // Should allow more than 20 requests (anonymous limit)
        for ($i = 0; $i < 50; $i++) {
            $response = $this->middleware->handle(
                $request,
                fn($req) => new Response('OK', 200)
            );
            $this->assertEquals(200, $response->getStatusCode());
        }
    }

    /**
     * Test critical operation limits.
     */
    public function test_critical_operation_limits(): void
    {
        $request = Request::create('/api/login', 'POST');
        $request->setUserResolver(fn() => null);

        // Make requests up to critical limit (5)
        for ($i = 0; $i < 5; $i++) {
            $response = $this->middleware->handle(
                $request,
                fn($req) => new Response('OK', 200),
                'login'
            );
            $this->assertEquals(200, $response->getStatusCode());
        }

        // Next request should be rate limited
        $response = $this->middleware->handle(
            $request,
            fn($req) => new Response('OK', 200),
            'login'
        );

        $this->assertEquals(429, $response->getStatusCode());
    }

    /**
     * Test that rate limiting is disabled when config is set.
     */
    public function test_rate_limiting_can_be_disabled(): void
    {
        Config::set('security.rate_limiting.enabled', false);

        $request = Request::create('/api/test', 'GET');
        $request->setUserResolver(fn() => null);

        // Make many requests, all should succeed
        for ($i = 0; $i < 100; $i++) {
            $response = $this->middleware->handle(
                $request,
                fn($req) => new Response('OK', 200)
            );
            $this->assertEquals(200, $response->getStatusCode());
        }
    }

    /**
     * Test IP address extraction from different headers.
     */
    public function test_ip_address_extraction(): void
    {
        // Test with X-Forwarded-For header
        $request = Request::create('/api/test', 'GET');
        $request->headers->set('X-Forwarded-For', '192.168.1.100, 10.0.0.1');
        $request->server->set('REMOTE_ADDR', '10.0.0.1');
        $request->setUserResolver(fn() => null);

        $response = $this->middleware->handle(
            $request,
            fn($req) => new Response('OK', 200)
        );

        $this->assertEquals(200, $response->getStatusCode());
    }

    protected function tearDown(): void
    {
        Redis::flushall();
        parent::tearDown();
    }
}
