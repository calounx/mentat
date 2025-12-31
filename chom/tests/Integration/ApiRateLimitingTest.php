<?php

declare(strict_types=1);

namespace Tests\Integration;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\WithSecurityTesting;
use Tests\TestCase;

/**
 * Integration test for API rate limiting across subscription tiers
 *
 * @package Tests\Integration
 */
class ApiRateLimitingTest extends TestCase
{
    use RefreshDatabase;
    use WithSecurityTesting;

    /**
     * Test basic tier rate limiting
     *
     * @return void
     */
    public function test_basic_tier_rate_limit_enforced(): void
    {
        $user = User::factory()->create(['subscription_tier' => 'basic']);

        $this->assertRateLimiting('/api/v1/sites', 60, $user);
    }

    /**
     * Test professional tier has higher limits
     *
     * @return void
     */
    public function test_professional_tier_has_higher_rate_limit(): void
    {
        $user = User::factory()->create(['subscription_tier' => 'professional']);

        // Professional tier should allow more requests
        for ($i = 0; $i < 100; $i++) {
            $response = $this->actingAs($user)->get('/api/v1/sites');
            $this->assertNotEquals(429, $response->status());
        }
    }

    /**
     * Test rate limit headers are present
     *
     * @return void
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
     *
     * @return void
     */
    public function test_rate_limit_cannot_be_bypassed(): void
    {
        $user = User::factory()->create(['subscription_tier' => 'basic']);

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
