<?php

declare(strict_types=1);

namespace Tests\Api;

use App\Models\Organization;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * API contract tests for Site endpoints
 *
 * Ensures API responses match documented contracts
 */
class SiteEndpointContractTest extends TestCase
{
    use RefreshDatabase;

    protected User $user;

    protected Organization $organization;

    protected Tenant $tenant;

    protected function setUp(): void
    {
        parent::setUp();

        // Create organization with default tenant
        $this->organization = Organization::factory()->create();
        $this->tenant = Tenant::factory()->create([
            'organization_id' => $this->organization->id,
        ]);
        $this->organization->update(['default_tenant_id' => $this->tenant->id]);

        // Create user in organization
        $this->user = User::factory()->create([
            'organization_id' => $this->organization->id,
        ]);
    }

    /**
     * Test site list response structure
     */
    public function test_site_list_returns_correct_structure(): void
    {
        Site::factory()->create(['tenant_id' => $this->tenant->id]);

        $response = $this->actingAs($this->user)
            ->getJson('/api/v1/sites');

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
     */
    public function test_site_creation_returns_correct_structure(): void
    {
        $response = $this->actingAs($this->user)
            ->postJson('/api/v1/sites', [
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
     */
    public function test_error_responses_follow_standard_format(): void
    {
        $response = $this->actingAs($this->user)
            ->postJson('/api/v1/sites', [
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
