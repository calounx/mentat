<?php

declare(strict_types=1);

namespace Tests\Regression;

use App\Models\Site;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\WithMockObservability;
use Tests\TestCase;

/**
 * Regression test for PromQL injection vulnerability
 *
 * Ensures the PromQL injection vulnerability remains fixed
 *
 * @package Tests\Regression
 */
class PromQLInjectionPreventionTest extends TestCase
{
    use RefreshDatabase;
    use WithMockObservability;

    /**
     * Test PromQL injection is prevented (Regression for VULN-2024-001)
     *
     * @return void
     */
    public function test_promql_injection_is_sanitized(): void
    {
        $user = User::factory()->create();
        $site = Site::factory()->create(['user_id' => $user->id]);

        $this->setUpObservabilityMocks();

        $maliciousQuery = 'up{job="test"} or vector(1)';
        $sanitizedQuery = 'up{job="test"}';

        $this->mockPromQLInjectionPrevention($maliciousQuery, $sanitizedQuery);

        $response = $this->actingAs($user)
            ->post("/api/v1/sites/{$site->id}/metrics/query", [
                'query' => $maliciousQuery,
            ]);

        $response->assertStatus(200);
        $this->assertQueryWasSanitized('prometheus');
    }
}
