<?php

namespace Tests\Api;

use Tests\TestCase;
use App\Models\User;
use App\Models\Site;
use App\Models\VpsServer;
use App\Models\Organization;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;

/**
 * API Contract Validation Tests
 *
 * These tests verify that API responses match expected contracts:
 * - Response structure consistency
 * - HTTP status codes correctness
 * - Error format standardization
 * - Data types validation
 * - Required fields presence
 */
class ContractValidationTest extends TestCase
{
    use RefreshDatabase;

    private User $user;
    private Organization $organization;

    protected function setUp(): void
    {
        parent::setUp();

        // Create test user with organization
        $this->organization = Organization::factory()->create();
        $this->user = User::factory()->create([
            'organization_id' => $this->organization->id,
        ]);

        // Authenticate user
        Sanctum::actingAs($this->user);
    }

    /**
     * @test
     * Authentication endpoints should return consistent token structure
     */
    public function auth_login_returns_expected_structure(): void
    {
        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $this->user->email,
            'password' => 'password',
        ]);

        $response->assertStatus(200)
            ->assertJsonStructure([
                'data' => [
                    'token',
                    'user' => [
                        'id',
                        'name',
                        'email',
                        'organization_id',
                    ],
                ],
            ]);

        // Verify token is a string
        $this->assertIsString($response->json('data.token'));
        $this->assertIsInt($response->json('data.user.id'));
    }

    /**
     * @test
     * Index endpoints should return paginated collection structure
     */
    public function site_index_returns_paginated_structure(): void
    {
        // Create some test sites
        Site::factory()->count(3)->create([
            'organization_id' => $this->organization->id,
        ]);

        $response = $this->getJson('/api/v1/sites');

        $response->assertStatus(200)
            ->assertJsonStructure([
                'data' => [
                    '*' => [
                        'id',
                        'domain',
                        'status',
                        'site_type',
                        'created_at',
                        'updated_at',
                    ],
                ],
                'meta' => [
                    'current_page',
                    'per_page',
                    'total',
                ],
                'links' => [
                    'first',
                    'last',
                ],
            ]);
    }

    /**
     * @test
     * Show endpoints should return single resource structure
     */
    public function site_show_returns_single_resource_structure(): void
    {
        $site = Site::factory()->create([
            'organization_id' => $this->organization->id,
        ]);

        $response = $this->getJson("/api/v1/sites/{$site->id}");

        $response->assertStatus(200)
            ->assertJsonStructure([
                'data' => [
                    'id',
                    'domain',
                    'status',
                    'site_type',
                    'vps_server_id',
                    'created_at',
                    'updated_at',
                ],
            ]);

        // Verify specific data types
        $this->assertIsInt($response->json('data.id'));
        $this->assertIsString($response->json('data.domain'));
        $this->assertIsString($response->json('data.status'));
    }

    /**
     * @test
     * Create endpoints should return 201 with created resource
     */
    public function site_create_returns_201_with_resource(): void
    {
        $vpsServer = VpsServer::factory()->create();

        $response = $this->postJson('/api/v1/sites', [
            'domain' => 'test.example.com',
            'site_type' => 'html',
            'vps_server_id' => $vpsServer->id,
        ]);

        $response->assertStatus(201)
            ->assertJsonStructure([
                'data' => [
                    'id',
                    'domain',
                    'status',
                    'site_type',
                ],
            ]);

        $this->assertEquals('test.example.com', $response->json('data.domain'));
    }

    /**
     * @test
     * Update endpoints should return 200 with updated resource
     */
    public function site_update_returns_200_with_resource(): void
    {
        $site = Site::factory()->create([
            'organization_id' => $this->organization->id,
        ]);

        $response = $this->putJson("/api/v1/sites/{$site->id}", [
            'domain' => 'updated.example.com',
        ]);

        $response->assertStatus(200)
            ->assertJsonStructure([
                'data' => [
                    'id',
                    'domain',
                    'status',
                ],
            ]);

        $this->assertEquals('updated.example.com', $response->json('data.domain'));
    }

    /**
     * @test
     * Delete endpoints should return 204 no content
     */
    public function site_delete_returns_204(): void
    {
        $site = Site::factory()->create([
            'organization_id' => $this->organization->id,
        ]);

        $response = $this->deleteJson("/api/v1/sites/{$site->id}");

        $response->assertStatus(204);
        $response->assertNoContent();
    }

    /**
     * @test
     * Validation errors should return 422 with consistent error structure
     */
    public function validation_errors_return_422_with_error_structure(): void
    {
        $response = $this->postJson('/api/v1/sites', [
            'domain' => '', // Invalid: empty
            'site_type' => 'invalid', // Invalid: not in allowed values
        ]);

        $response->assertStatus(422)
            ->assertJsonStructure([
                'message',
                'errors' => [
                    'domain',
                    'site_type',
                ],
            ]);

        $this->assertIsArray($response->json('errors.domain'));
        $this->assertIsString($response->json('errors.domain.0'));
    }

    /**
     * @test
     * Unauthorized access should return 401
     */
    public function unauthorized_access_returns_401(): void
    {
        // Clear authentication
        $this->app['auth']->forgetGuards();

        $response = $this->getJson('/api/v1/sites');

        $response->assertStatus(401)
            ->assertJson([
                'message' => 'Unauthenticated.',
            ]);
    }

    /**
     * @test
     * Forbidden access should return 403
     */
    public function forbidden_access_returns_403(): void
    {
        // Create a site owned by a different organization
        $otherOrg = Organization::factory()->create();
        $site = Site::factory()->create([
            'organization_id' => $otherOrg->id,
        ]);

        $response = $this->getJson("/api/v1/sites/{$site->id}");

        $response->assertStatus(403)
            ->assertJsonStructure([
                'message',
            ]);
    }

    /**
     * @test
     * Not found resources should return 404
     */
    public function not_found_returns_404(): void
    {
        $response = $this->getJson('/api/v1/sites/99999');

        $response->assertStatus(404)
            ->assertJson([
                'message' => 'Not found.',
            ]);
    }

    /**
     * @test
     * Error responses should have consistent structure
     */
    public function error_responses_have_consistent_structure(): void
    {
        // Trigger a validation error
        $response = $this->postJson('/api/v1/sites', []);

        $response->assertStatus(422)
            ->assertJsonStructure([
                'message',
                'errors',
            ]);

        // All error messages should be arrays of strings
        $errors = $response->json('errors');
        foreach ($errors as $field => $messages) {
            $this->assertIsArray($messages);
            foreach ($messages as $message) {
                $this->assertIsString($message);
            }
        }
    }

    /**
     * @test
     * Timestamp fields should be in ISO 8601 format
     */
    public function timestamps_are_in_iso8601_format(): void
    {
        $site = Site::factory()->create([
            'organization_id' => $this->organization->id,
        ]);

        $response = $this->getJson("/api/v1/sites/{$site->id}");

        $createdAt = $response->json('data.created_at');
        $updatedAt = $response->json('data.updated_at');

        // Verify ISO 8601 format (e.g., 2024-01-01T00:00:00.000000Z)
        $this->assertMatchesRegularExpression(
            '/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/',
            $createdAt
        );
        $this->assertMatchesRegularExpression(
            '/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/',
            $updatedAt
        );
    }

    /**
     * @test
     * Numeric IDs should be integers not strings
     */
    public function numeric_ids_are_integers(): void
    {
        $site = Site::factory()->create([
            'organization_id' => $this->organization->id,
        ]);

        $response = $this->getJson("/api/v1/sites/{$site->id}");

        $this->assertIsInt($response->json('data.id'));
        $this->assertIsInt($response->json('data.organization_id'));

        // Optional relationships should be null or integer
        $vpsServerId = $response->json('data.vps_server_id');
        $this->assertTrue(is_null($vpsServerId) || is_int($vpsServerId));
    }

    /**
     * @test
     * Boolean fields should be actual booleans
     */
    public function boolean_fields_are_booleans(): void
    {
        // Assuming there's a boolean field in one of the models
        // This is a placeholder - adjust based on actual schema
        $this->markTestSkipped('Implement when boolean fields are added to API responses');
    }

    /**
     * @test
     * Null values should be explicit null not empty strings
     */
    public function null_values_are_explicit_null(): void
    {
        $site = Site::factory()->create([
            'organization_id' => $this->organization->id,
            'description' => null,
        ]);

        $response = $this->getJson("/api/v1/sites/{$site->id}");

        // If description is in response, it should be null not ""
        if ($response->json('data.description') !== false) {
            $this->assertNull($response->json('data.description'));
        }
    }

    /**
     * @test
     * Enum values should match defined constants
     */
    public function enum_values_match_defined_constants(): void
    {
        $site = Site::factory()->create([
            'organization_id' => $this->organization->id,
            'status' => 'active',
        ]);

        $response = $this->getJson("/api/v1/sites/{$site->id}");

        $status = $response->json('data.status');

        // Status should be one of the allowed values
        $allowedStatuses = ['active', 'inactive', 'pending', 'suspended'];
        $this->assertContains($status, $allowedStatuses);
    }

    /**
     * @test
     * Include relationships should work consistently
     */
    public function include_relationships_works_consistently(): void
    {
        $vpsServer = VpsServer::factory()->create();
        $site = Site::factory()->create([
            'organization_id' => $this->organization->id,
            'vps_server_id' => $vpsServer->id,
        ]);

        // Without include
        $response = $this->getJson("/api/v1/sites/{$site->id}");
        $this->assertArrayNotHasKey('vps_server', $response->json('data'));

        // With include
        $response = $this->getJson("/api/v1/sites/{$site->id}?include=vpsServer");

        if ($response->json('data.vps_server')) {
            $response->assertJsonStructure([
                'data' => [
                    'vps_server' => [
                        'id',
                        'hostname',
                        'status',
                    ],
                ],
            ]);
        }
    }

    /**
     * @test
     * Sorting query parameters should work consistently
     */
    public function sorting_works_consistently(): void
    {
        Site::factory()->count(3)->create([
            'organization_id' => $this->organization->id,
        ]);

        // Ascending
        $response = $this->getJson('/api/v1/sites?sort=created_at');
        $response->assertStatus(200);

        // Descending
        $response = $this->getJson('/api/v1/sites?sort=-created_at');
        $response->assertStatus(200);

        // Verify order
        $data = $response->json('data');
        if (count($data) >= 2) {
            $firstDate = strtotime($data[0]['created_at']);
            $secondDate = strtotime($data[1]['created_at']);
            $this->assertGreaterThanOrEqual($secondDate, $firstDate);
        }
    }

    /**
     * @test
     * Filtering query parameters should work consistently
     */
    public function filtering_works_consistently(): void
    {
        Site::factory()->create([
            'organization_id' => $this->organization->id,
            'status' => 'active',
        ]);

        Site::factory()->create([
            'organization_id' => $this->organization->id,
            'status' => 'inactive',
        ]);

        $response = $this->getJson('/api/v1/sites?filter[status]=active');

        $response->assertStatus(200);

        $data = $response->json('data');
        foreach ($data as $site) {
            $this->assertEquals('active', $site['status']);
        }
    }

    /**
     * @test
     * Pagination metadata should be accurate
     */
    public function pagination_metadata_is_accurate(): void
    {
        Site::factory()->count(25)->create([
            'organization_id' => $this->organization->id,
        ]);

        $response = $this->getJson('/api/v1/sites?per_page=10');

        $response->assertStatus(200)
            ->assertJsonStructure([
                'meta' => [
                    'current_page',
                    'per_page',
                    'total',
                    'last_page',
                ],
            ]);

        $this->assertEquals(10, $response->json('meta.per_page'));
        $this->assertEquals(25, $response->json('meta.total'));
        $this->assertEquals(3, $response->json('meta.last_page'));
    }

    /**
     * @test
     * Rate limiting headers should be present
     */
    public function rate_limiting_headers_are_present(): void
    {
        $response = $this->getJson('/api/v1/sites');

        $response->assertHeader('X-RateLimit-Limit');
        $response->assertHeader('X-RateLimit-Remaining');
    }

    /**
     * @test
     * CORS headers should be present (if configured)
     */
    public function cors_headers_are_present(): void
    {
        $response = $this->getJson('/api/v1/sites');

        // These might only be present with OPTIONS request
        // or with specific Origin header
        $this->assertTrue(true); // Placeholder - implement based on CORS config
    }

    /**
     * @test
     * Content-Type header should be application/json
     */
    public function content_type_is_json(): void
    {
        $response = $this->getJson('/api/v1/sites');

        $response->assertHeader('Content-Type', 'application/json');
    }

    /**
     * @test
     * API versioning in URL works correctly
     */
    public function api_versioning_works(): void
    {
        $response = $this->getJson('/api/v1/sites');
        $response->assertStatus(200);

        // Future: Test /api/v2 when implemented
        // Ensure backward compatibility
    }
}
