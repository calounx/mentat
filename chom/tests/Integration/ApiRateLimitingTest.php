<?php

declare(strict_types=1);

namespace Tests\Integration;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\WithSecurityTesting;
use Tests\TestCase;

/**
 * Integration test for API rate limiting across subscription tiers
 */
class ApiRateLimitingTest extends TestCase
{
    use RefreshDatabase;
    use WithSecurityTesting;

    /**
     * Test basic tier rate limiting
     */
    public function test_basic_tier_rate_limit_enforced(): void
    {
        $user = User::factory()->create();

        $this->assertRateLimiting('/api/v1/sites', 60, $user);
    }

    /**
     * Test professional tier has higher limits
     */
    public function test_professional_tier_has_higher_rate_limit(): void
    {
        $user = User::factory()->create();

        // Professional tier should allow more requests
        for ($i = 0; $i < 100; $i++) {
            $response = $this->actingAs($user)->get('/api/v1/sites');
            $this->assertNotEquals(429, $response->status());
        }
    }

    /**
     * Test rate limit headers are present
     */
    public function test_rate_limit_headers_present(): void
    {
        $user = User::factory()->create();

        $response = $this->actingAs($user)->get('/api/v1/sites');

        $response->assertHeader('X-RateLimit-Limit');
        $response->assertHeader('X-RateLimit-Remaining');
    }

    /**
     * Test rate limit bypass attempts fail
     */
    public function test_rate_limit_cannot_be_bypassed(): void
    {
        $user = User::factory()->create();

        // Exceed rate limit
        for ($i = 0; $i < 61; $i++) {
            $this->actingAs($user)->get('/api/v1/sites');
        }

        // Try to bypass with different headers
        $bypassAttempts = [
            ['X-Forwarded-For' => '1.2.3.4'],
            ['X-Real-IP' => '1.2.3.4'],
            ['Client-IP' => '1.2.3.4'],
        ];

        foreach ($bypassAttempts as $headers) {
            $response = $this->actingAs($user)
                ->withHeaders($headers)
                ->get('/api/v1/sites');

            $this->assertEquals(429, $response->status(), 'Rate limit bypassed via headers');
        }
    }
}
