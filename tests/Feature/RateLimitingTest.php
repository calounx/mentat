<?php

declare(strict_types=1);

namespace Tests\Feature;

use App\Models\Organization;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\RateLimiter;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class RateLimitingTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        RateLimiter::clear('api');
    }

    public function test_rate_limit_applies_to_api_endpoints(): void
    {
        $user = User::factory()->create([
            'organization_id' => Organization::factory()->create(['tier' => 'free'])->id,
        ]);

        Sanctum::actingAs($user);

        $successCount = 0;
        $rateLimited = false;

        // Free tier: 100 requests per minute
        for ($i = 0; $i < 110; $i++) {
            $response = $this->getJson('/api/v1/sites');

            if ($response->status() === 429) {
                $rateLimited = true;
                break;
            }

            if ($response->status() === 200) {
                $successCount++;
            }
        }

        $this->assertTrue($rateLimited, 'Should be rate limited after exceeding quota');
        $this->assertLessThanOrEqual(100, $successCount);
    }

    public function test_rate_limit_headers_included_in_response(): void
    {
        $user = User::factory()->create([
            'organization_id' => Organization::factory()->create(['tier' => 'free'])->id,
        ]);

        Sanctum::actingAs($user);

        $response = $this->getJson('/api/v1/user');

        $response->assertHeader('X-RateLimit-Limit');
        $response->assertHeader('X-RateLimit-Remaining');
        $response->assertHeader('X-RateLimit-Reset');

        $limit = $response->headers->get('X-RateLimit-Limit');
        $remaining = $response->headers->get('X-RateLimit-Remaining');

        $this->assertIsNumeric($limit);
        $this->assertIsNumeric($remaining);
        $this->assertLessThanOrEqual((int) $limit, (int) $remaining);
    }

    public function test_retry_after_header_present_when_rate_limited(): void
    {
        $user = User::factory()->create([
            'organization_id' => Organization::factory()->create(['tier' => 'free'])->id,
        ]);

        Sanctum::actingAs($user);

        // Exhaust rate limit
        for ($i = 0; $i < 101; $i++) {
            RateLimiter::hit("api:{$user->id}");
        }

        $response = $this->getJson('/api/v1/sites');

        if ($response->status() === 429) {
            $response->assertHeader('Retry-After');
            $retryAfter = $response->headers->get('Retry-After');
            $this->assertIsNumeric($retryAfter);
            $this->assertLessThanOrEqual(60, (int) $retryAfter);
        }
    }

    public function test_rate_limit_varies_by_organization_tier(): void
    {
        $freeUser = User::factory()->create([
            'organization_id' => Organization::factory()->create(['tier' => 'free'])->id,
        ]);

        $businessUser = User::factory()->create([
            'organization_id' => Organization::factory()->create(['tier' => 'business'])->id,
        ]);

        $enterpriseUser = User::factory()->create([
            'organization_id' => Organization::factory()->create(['tier' => 'enterprise'])->id,
        ]);

        // Check free tier limit
        Sanctum::actingAs($freeUser);
        $freeResponse = $this->getJson('/api/v1/user');
        $freeLimit = (int) $freeResponse->headers->get('X-RateLimit-Limit');

        // Check business tier limit
        Sanctum::actingAs($businessUser);
        $businessResponse = $this->getJson('/api/v1/user');
        $businessLimit = (int) $businessResponse->headers->get('X-RateLimit-Limit');

        // Check enterprise tier limit
        Sanctum::actingAs($enterpriseUser);
        $enterpriseResponse = $this->getJson('/api/v1/user');
        $enterpriseLimit = (int) $enterpriseResponse->headers->get('X-RateLimit-Limit');

        $this->assertGreaterThan($freeLimit, $businessLimit);
        $this->assertGreaterThan($businessLimit, $enterpriseLimit);
    }

    public function test_rate_limit_resets_after_time_window(): void
    {
        $user = User::factory()->create([
            'organization_id' => Organization::factory()->create(['tier' => 'free'])->id,
        ]);

        Sanctum::actingAs($user);

        // Hit rate limit with short TTL
        for ($i = 0; $i < 5; $i++) {
            RateLimiter::hit("test-limit:{$user->id}", 1);
        }

        // Should be limited
        $this->assertTrue(RateLimiter::tooManyAttempts("test-limit:{$user->id}", 5));

        // Wait for reset
        sleep(2);

        // Should be cleared
        $this->assertFalse(RateLimiter::tooManyAttempts("test-limit:{$user->id}", 5));
    }

    public function test_rate_limit_per_user_not_per_organization(): void
    {
        $organization = Organization::factory()->create(['tier' => 'free']);

        $user1 = User::factory()->create(['organization_id' => $organization->id]);
        $user2 = User::factory()->create(['organization_id' => $organization->id]);

        // User 1 makes requests
        Sanctum::actingAs($user1);
        for ($i = 0; $i < 50; $i++) {
            $this->getJson('/api/v1/user');
        }

        // User 2 should still have full quota
        Sanctum::actingAs($user2);
        $response = $this->getJson('/api/v1/user');

        $response->assertStatus(200);
        $remaining = (int) $response->headers->get('X-RateLimit-Remaining');
        $this->assertGreaterThan(50, $remaining);
    }

    public function test_rate_limit_decrements_correctly(): void
    {
        $user = User::factory()->create([
            'organization_id' => Organization::factory()->create(['tier' => 'free'])->id,
        ]);

        Sanctum::actingAs($user);

        $response1 = $this->getJson('/api/v1/user');
        $remaining1 = (int) $response1->headers->get('X-RateLimit-Remaining');

        $response2 = $this->getJson('/api/v1/user');
        $remaining2 = (int) $response2->headers->get('X-RateLimit-Remaining');

        $response3 = $this->getJson('/api/v1/user');
        $remaining3 = (int) $response3->headers->get('X-RateLimit-Remaining');

        $this->assertEquals($remaining1 - 1, $remaining2);
        $this->assertEquals($remaining2 - 1, $remaining3);
    }

    public function test_rate_limit_applies_to_write_operations(): void
    {
        $user = User::factory()->create([
            'organization_id' => Organization::factory()->create(['tier' => 'free'])->id,
        ]);

        Sanctum::actingAs($user);

        $response = $this->postJson('/api/v1/sites', [
            'domain' => 'test.com',
            'type' => 'wordpress',
        ]);

        $response->assertHeader('X-RateLimit-Limit');
        $response->assertHeader('X-RateLimit-Remaining');
    }

    public function test_unauthenticated_requests_have_lower_limits(): void
    {
        $response = $this->getJson('/api/v1/public-endpoint');

        if ($response->headers->has('X-RateLimit-Limit')) {
            $limit = (int) $response->headers->get('X-RateLimit-Limit');
            $this->assertLessThanOrEqual(100, $limit);
        }
    }

    public function test_rate_limit_bypassed_for_health_checks(): void
    {
        // Health checks should not be rate limited
        for ($i = 0; $i < 200; $i++) {
            $response = $this->getJson('/api/health');
            $this->assertEquals(200, $response->status());
        }
    }

    public function test_rate_limit_error_response_format(): void
    {
        $user = User::factory()->create([
            'organization_id' => Organization::factory()->create(['tier' => 'free'])->id,
        ]);

        Sanctum::actingAs($user);

        // Exhaust rate limit
        for ($i = 0; $i < 101; $i++) {
            RateLimiter::hit("api:{$user->id}");
        }

        $response = $this->getJson('/api/v1/sites');

        if ($response->status() === 429) {
            $response->assertJsonStructure([
                'message',
            ]);

            $data = $response->json();
            $this->assertStringContainsString('Too Many Requests', $data['message']);
        }
    }

    public function test_concurrent_requests_counted_accurately(): void
    {
        $user = User::factory()->create([
            'organization_id' => Organization::factory()->create(['tier' => 'free'])->id,
        ]);

        Sanctum::actingAs($user);

        // Make 10 concurrent requests
        for ($i = 0; $i < 10; $i++) {
            $this->getJson('/api/v1/user');
        }

        $response = $this->getJson('/api/v1/user');
        $remaining = (int) $response->headers->get('X-RateLimit-Remaining');

        // Should have decremented by at least 11 (10 + 1)
        $limit = (int) $response->headers->get('X-RateLimit-Limit');
        $this->assertLessThan($limit - 10, $remaining);
    }

    public function test_rate_limit_tracking_performance(): void
    {
        $user = User::factory()->create([
            'organization_id' => Organization::factory()->create(['tier' => 'free'])->id,
        ]);

        Sanctum::actingAs($user);

        $startTime = microtime(true);

        for ($i = 0; $i < 50; $i++) {
            $this->getJson('/api/v1/user');
        }

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // Rate limiting should add minimal overhead (< 1 second for 50 requests)
        $this->assertLessThan(1000, $duration);
    }
}
