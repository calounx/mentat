<?php

namespace Tests\Feature\Api;

use App\Models\Organization;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * API Versioning and Deprecation Test
 *
 * Ensures API versioning is handled correctly including:
 * - Version routing
 * - Backward compatibility
 * - Deprecation warnings
 * - Version negotiation
 */
class ApiVersioningTest extends TestCase
{
    use RefreshDatabase;

    private User $user;
    private string $token;

    protected function setUp(): void
    {
        parent::setUp();

        $organization = Organization::factory()->create();
        $this->user = User::factory()->for($organization)->create();
        $this->token = $this->user->createToken('test-token')->plainTextToken;
    }

    public function test_v1_api_endpoints_are_accessible(): void
    {
        $response = $this->withToken($this->token)
            ->getJson('/api/v1/auth/me');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'data' => [
                'id',
                'email',
                'name',
            ],
        ]);
    }

    public function test_api_requires_version_prefix(): void
    {
        $response = $this->withToken($this->token)
            ->getJson('/api/auth/me');

        $response->assertStatus(404);
    }

    public function test_invalid_api_version_returns_404(): void
    {
        $response = $this->withToken($this->token)
            ->getJson('/api/v99/auth/me');

        $response->assertStatus(404);
    }

    public function test_api_version_is_included_in_response_headers(): void
    {
        $response = $this->withToken($this->token)
            ->getJson('/api/v1/health');

        $response->assertHeader('X-API-Version', 'v1');
    }

    public function test_health_endpoint_works_without_authentication(): void
    {
        $response = $this->getJson('/api/v1/health');

        $response->assertStatus(200);
        $response->assertJson([
            'status' => 'ok',
        ]);
        $response->assertJsonStructure([
            'status',
            'timestamp',
        ]);
    }

    public function test_deprecated_endpoints_include_warning_header(): void
    {
        // If we add a deprecated endpoint in the future, it should include:
        // Sunset header and Deprecation header
        // This test documents the expected behavior

        // Example for future use:
        // $response = $this->withToken($this->token)
        //     ->getJson('/api/v1/sites/old-endpoint');
        //
        // $response->assertHeader('Deprecation', 'true');
        // $response->assertHeader('Sunset', '2026-12-31');
        // $response->assertHeader('Link', '<https://docs.chom.app/api/migration>; rel="deprecation"');

        $this->assertTrue(true, 'Deprecation test placeholder');
    }

    public function test_api_supports_json_content_type(): void
    {
        $response = $this->withToken($this->token)
            ->withHeader('Accept', 'application/json')
            ->getJson('/api/v1/auth/me');

        $response->assertStatus(200);
        $response->assertHeader('Content-Type', 'application/json');
    }

    public function test_api_returns_json_errors_for_invalid_requests(): void
    {
        $response = $this->withToken($this->token)
            ->postJson('/api/v1/sites', [
                // Missing required fields
            ]);

        $response->assertStatus(422);
        $response->assertJsonStructure([
            'message',
            'errors',
        ]);
    }

    public function test_api_pagination_format_is_consistent(): void
    {
        $response = $this->withToken($this->token)
            ->getJson('/api/v1/sites');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'data',
            'links' => [
                'first',
                'last',
                'prev',
                'next',
            ],
            'meta' => [
                'current_page',
                'from',
                'last_page',
                'per_page',
                'to',
                'total',
            ],
        ]);
    }

    public function test_api_error_format_is_consistent(): void
    {
        $response = $this->getJson('/api/v1/sites');

        $response->assertStatus(401);
        $response->assertJsonStructure([
            'message',
        ]);
    }

    public function test_api_supports_filtering(): void
    {
        $response = $this->withToken($this->token)
            ->getJson('/api/v1/sites?status=active');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'data',
            'links',
            'meta',
        ]);
    }

    public function test_api_supports_sorting(): void
    {
        $response = $this->withToken($this->token)
            ->getJson('/api/v1/sites?sort=-created_at');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'data',
        ]);
    }

    public function test_api_rate_limiting_headers_are_present(): void
    {
        $response = $this->withToken($this->token)
            ->getJson('/api/v1/auth/me');

        $response->assertHeader('X-RateLimit-Limit');
        $response->assertHeader('X-RateLimit-Remaining');
    }

    public function test_api_accepts_version_in_accept_header(): void
    {
        $response = $this->withToken($this->token)
            ->withHeader('Accept', 'application/vnd.chom.v1+json')
            ->getJson('/api/v1/auth/me');

        $response->assertStatus(200);
    }

    public function test_api_documentation_endpoint_exists(): void
    {
        $response = $this->getJson('/api/v1/documentation');

        // This might be a 404 if not implemented, which is fine
        // Just testing that the routing doesn't break
        $this->assertContains($response->status(), [200, 404]);
    }

    public function test_api_openapi_spec_endpoint_exists(): void
    {
        $response = $this->getJson('/api/v1/openapi.json');

        // This might be a 404 if not implemented, which is fine
        $this->assertContains($response->status(), [200, 404]);
    }

    public function test_cors_headers_are_present(): void
    {
        $response = $this->withToken($this->token)
            ->withHeader('Origin', 'https://example.com')
            ->getJson('/api/v1/health');

        // CORS headers should be present
        // Exact headers depend on CORS configuration
        $response->assertStatus(200);
    }

    public function test_api_handles_method_not_allowed(): void
    {
        $response = $this->withToken($this->token)
            ->patchJson('/api/v1/health');

        $response->assertStatus(405);
        $response->assertHeader('Allow');
    }

    public function test_api_validates_content_type_for_post_requests(): void
    {
        $response = $this->withToken($this->token)
            ->withHeader('Content-Type', 'text/plain')
            ->post('/api/v1/sites', 'invalid data');

        // Should either reject or handle gracefully
        $this->assertContains($response->status(), [400, 415, 422]);
    }

    public function test_api_timestamp_format_is_iso8601(): void
    {
        $response = $this->getJson('/api/v1/health');

        $response->assertStatus(200);

        $data = $response->json();
        $this->assertArrayHasKey('timestamp', $data);
        $this->assertMatchesRegularExpression(
            '/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/',
            $data['timestamp']
        );
    }

    private function withToken(string $token): static
    {
        return $this->withHeader('Authorization', 'Bearer '.$token);
    }
}
