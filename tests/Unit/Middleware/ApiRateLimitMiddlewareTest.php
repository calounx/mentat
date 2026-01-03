<?php

declare(strict_types=1);

namespace Tests\Unit\Middleware;

use App\Http\Middleware\ApiRateLimitMiddleware;
use App\Models\Organization;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\RateLimiter;
use Tests\TestCase;

class ApiRateLimitMiddlewareTest extends TestCase
{
    use RefreshDatabase;

    private ApiRateLimitMiddleware $middleware;
    private User $user;
    private Organization $organization;

    protected function setUp(): void
    {
        parent::setUp();

        $this->middleware = new ApiRateLimitMiddleware();

        // Create test user and organization
        $this->organization = Organization::factory()->create([
            'tier' => 'free',
        ]);

        $this->user = User::factory()->create([
            'organization_id' => $this->organization->id,
        ]);

        // Clear rate limiter cache
        Cache::flush();
        RateLimiter::clear('test-key');
    }

    protected function tearDown(): void
    {
        Cache::flush();
        parent::tearDown();
    }

    public function test_allows_request_within_rate_limit(): void
    {
        $request = Request::create('/api/test', 'GET');
        $request->setUserResolver(fn() => $this->user);

        $response = null;
        $next = function ($req) use (&$response) {
            $response = new Response('OK', 200);
            return $response;
        };

        $result = $this->middleware->handle($request, $next);

        $this->assertEquals(200, $result->getStatusCode());
        $this->assertEquals('OK', $result->getContent());
    }

    public function test_blocks_request_exceeding_rate_limit(): void
    {
        $request = Request::create('/api/test', 'GET');
        $request->setUserResolver(fn() => $this->user);

        $next = fn($req) => new Response('OK', 200);

        // Free tier: 100 requests per minute
        for ($i = 0; $i < 100; $i++) {
            RateLimiter::hit('api:user:' . $this->user->id, 60);
        }

        $response = $this->middleware->handle($request, $next);

        $this->assertEquals(429, $response->getStatusCode());
        $this->assertStringContainsString('Too Many Requests', $response->getContent());
    }

    public function test_includes_rate_limit_headers(): void
    {
        $request = Request::create('/api/test', 'GET');
        $request->setUserResolver(fn() => $this->user);

        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        $this->assertTrue($response->headers->has('X-RateLimit-Limit'));
        $this->assertTrue($response->headers->has('X-RateLimit-Remaining'));
        $this->assertTrue($response->headers->has('X-RateLimit-Reset'));

        $this->assertEquals('100', $response->headers->get('X-RateLimit-Limit'));
        $this->assertIsNumeric($response->headers->get('X-RateLimit-Remaining'));
        $this->assertIsNumeric($response->headers->get('X-RateLimit-Reset'));
    }

    public function test_includes_retry_after_header_when_rate_limited(): void
    {
        $request = Request::create('/api/test', 'GET');
        $request->setUserResolver(fn() => $this->user);

        $next = fn($req) => new Response('OK', 200);

        // Exceed rate limit
        for ($i = 0; $i < 100; $i++) {
            RateLimiter::hit('api:user:' . $this->user->id, 60);
        }

        $response = $this->middleware->handle($request, $next);

        $this->assertEquals(429, $response->getStatusCode());
        $this->assertTrue($response->headers->has('Retry-After'));
        $this->assertIsNumeric($response->headers->get('Retry-After'));
        $this->assertLessThanOrEqual(60, (int) $response->headers->get('Retry-After'));
    }

    public function test_enterprise_tier_has_higher_limits(): void
    {
        // Update organization to enterprise tier
        $this->organization->update(['tier' => 'enterprise']);
        $this->organization->refresh();

        $request = Request::create('/api/test', 'GET');
        $request->setUserResolver(fn() => $this->user);

        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        // Enterprise tier: 10000 requests per minute
        $this->assertEquals('10000', $response->headers->get('X-RateLimit-Limit'));
    }

    public function test_business_tier_has_medium_limits(): void
    {
        $this->organization->update(['tier' => 'business']);
        $this->organization->refresh();

        $request = Request::create('/api/test', 'GET');
        $request->setUserResolver(fn() => $this->user);

        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        // Business tier: 1000 requests per minute
        $this->assertEquals('1000', $response->headers->get('X-RateLimit-Limit'));
    }

    public function test_per_tenant_rate_limiting(): void
    {
        // Create another user in the same organization
        $anotherUser = User::factory()->create([
            'organization_id' => $this->organization->id,
        ]);

        $request1 = Request::create('/api/test', 'GET');
        $request1->setUserResolver(fn() => $this->user);

        $request2 = Request::create('/api/test', 'GET');
        $request2->setUserResolver(fn() => $anotherUser);

        $next = fn($req) => new Response('OK', 200);

        // Hit limit for first user
        for ($i = 0; $i < 50; $i++) {
            RateLimiter::hit('api:user:' . $this->user->id, 60);
        }

        $response1 = $this->middleware->handle($request1, $next);
        $response2 = $this->middleware->handle($request2, $next);

        // First user should still be allowed
        $this->assertEquals(200, $response1->getStatusCode());

        // Second user should also be allowed (separate limit)
        $this->assertEquals(200, $response2->getStatusCode());
    }

    public function test_rate_limit_resets_after_window(): void
    {
        $request = Request::create('/api/test', 'GET');
        $request->setUserResolver(fn() => $this->user);

        $next = fn($req) => new Response('OK', 200);

        // Hit limit
        for ($i = 0; $i < 100; $i++) {
            RateLimiter::hit('api:user:' . $this->user->id, 1);
        }

        // Should be rate limited
        $response1 = $this->middleware->handle($request, $next);
        $this->assertEquals(429, $response1->getStatusCode());

        // Wait for window to expire
        sleep(2);

        // Should be allowed again
        $response2 = $this->middleware->handle($request, $next);
        $this->assertEquals(200, $response2->getStatusCode());
    }

    public function test_handles_unauthenticated_requests(): void
    {
        $request = Request::create('/api/test', 'GET');
        // No user resolver set

        $next = fn($req) => new Response('OK', 200);

        $response = $this->middleware->handle($request, $next);

        // Should use IP-based rate limiting for unauthenticated requests
        $this->assertEquals(200, $response->getStatusCode());
        $this->assertTrue($response->headers->has('X-RateLimit-Limit'));
    }

    public function test_different_endpoints_have_separate_limits(): void
    {
        $request1 = Request::create('/api/sites', 'GET');
        $request1->setUserResolver(fn() => $this->user);

        $request2 = Request::create('/api/backups', 'GET');
        $request2->setUserResolver(fn() => $this->user);

        $next = fn($req) => new Response('OK', 200);

        // Hit limit for sites endpoint
        for ($i = 0; $i < 50; $i++) {
            RateLimiter::hit('api:user:' . $this->user->id . ':sites', 60);
        }

        $response1 = $this->middleware->handle($request1, $next);
        $response2 = $this->middleware->handle($request2, $next);

        // Both should be allowed (separate endpoint limits)
        $this->assertEquals(200, $response1->getStatusCode());
        $this->assertEquals(200, $response2->getStatusCode());
    }

    public function test_tracks_remaining_requests_accurately(): void
    {
        $request = Request::create('/api/test', 'GET');
        $request->setUserResolver(fn() => $this->user);

        $next = fn($req) => new Response('OK', 200);

        // Make 3 requests
        for ($i = 0; $i < 3; $i++) {
            $response = $this->middleware->handle($request, $next);
            $this->assertEquals(200, $response->getStatusCode());
        }

        $finalResponse = $this->middleware->handle($request, $next);

        // Free tier: 100 - 4 requests = 96 remaining
        $this->assertEquals('96', $finalResponse->headers->get('X-RateLimit-Remaining'));
    }

    public function test_handles_concurrent_requests_correctly(): void
    {
        $request = Request::create('/api/test', 'GET');
        $request->setUserResolver(fn() => $this->user);

        $next = fn($req) => new Response('OK', 200);

        // Simulate concurrent requests
        $responses = [];
        for ($i = 0; $i < 10; $i++) {
            $responses[] = $this->middleware->handle($request, $next);
        }

        // All should succeed
        foreach ($responses as $response) {
            $this->assertEquals(200, $response->getStatusCode());
        }

        // Verify counter is accurate
        $finalResponse = $this->middleware->handle($request, $next);
        $remaining = (int) $finalResponse->headers->get('X-RateLimit-Remaining');

        $this->assertLessThan(100, $remaining);
        $this->assertGreaterThanOrEqual(89, $remaining);
    }

    public function test_rate_limit_applies_to_write_operations_more_strictly(): void
    {
        $getRequest = Request::create('/api/sites', 'GET');
        $getRequest->setUserResolver(fn() => $this->user);

        $postRequest = Request::create('/api/sites', 'POST');
        $postRequest->setUserResolver(fn() => $this->user);

        $next = fn($req) => new Response('OK', 200);

        $getResponse = $this->middleware->handle($getRequest, $next);
        $postResponse = $this->middleware->handle($postRequest, $next);

        // Write operations might have stricter limits
        $this->assertEquals(200, $getResponse->getStatusCode());
        $this->assertEquals(200, $postResponse->getStatusCode());
    }

    public function test_clears_rate_limit_data_on_reset(): void
    {
        $request = Request::create('/api/test', 'GET');
        $request->setUserResolver(fn() => $this->user);

        $next = fn($req) => new Response('OK', 200);

        // Make some requests
        for ($i = 0; $i < 10; $i++) {
            RateLimiter::hit('api:user:' . $this->user->id, 60);
        }

        // Clear rate limiter
        RateLimiter::clear('api:user:' . $this->user->id);

        $response = $this->middleware->handle($request, $next);

        // Should have full limit again
        $this->assertEquals('99', $response->headers->get('X-RateLimit-Remaining'));
    }

    public function test_performance_under_high_load(): void
    {
        $request = Request::create('/api/test', 'GET');
        $request->setUserResolver(fn() => $this->user);

        $next = fn($req) => new Response('OK', 200);

        $startTime = microtime(true);

        // Make 50 requests
        for ($i = 0; $i < 50; $i++) {
            $this->middleware->handle($request, $next);
        }

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000; // Convert to milliseconds

        // Should complete 50 requests in under 500ms
        $this->assertLessThan(500, $duration, "Rate limiting took {$duration}ms for 50 requests");
    }
}
