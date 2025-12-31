<?php

declare(strict_types=1);

namespace Tests\Api;

use App\Models\Site;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * API contract tests for Site endpoints
 *
 * Ensures API responses match documented contracts
 *
 * @package Tests\Api
 */
class SiteEndpointContractTest extends TestCase
{
    use RefreshDatabase;

    protected User $user;

    protected function setUp(): void
    {
        parent::setUp();
        $this->user = User::factory()->create();
    }

    /**
     * Test site list response structure
     *
     * @return void
     */
    public function test_site_list_returns_correct_structure(): void
    {
        Site::factory()->create(['user_id' => $this->user->id]);

        $response = $this->actingAs($this->user)
            ->get('/api/v1/sites');

        $response->assertStatus(200)
            ->assertJsonStructure([
                'data' => [
                    '*' => [
                        'id',
                        'domain',
                        'type',
                        'status',
                        'created_at',
                        'updated_at',
                    ],
                ],
                'meta' => [
                    'current_page',
                    'total',
                ],
            ]);
    }

    /**
     * Test site creation response structure
     *
     * @return void
     */
    public function test_site_creation_returns_correct_structure(): void
    {
        $response = $this->actingAs($this->user)
            ->post('/api/v1/sites', [
                'domain' => 'test.com',
                'type' => 'html',
            ]);

        $response->assertStatus(201)
            ->assertJsonStructure([
                'data' => [
                    'id',
                    'domain',
                    'type',
                    'status',
                    'vps_id',
                    'created_at',
                ],
            ]);
    }

    /**
     * Test error response format is consistent
     *
     * @return void
     */
    public function test_error_responses_follow_standard_format(): void
    {
        $response = $this->actingAs($this->user)
            ->post('/api/v1/sites', [
                'domain' => '', // Invalid
            ]);

        $response->assertStatus(422)
            ->assertJsonStructure([
                'message',
                'errors' => [
                    'domain',
                ],
            ]);
    }
}
