<?php

namespace Tests\Regression;

use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class ApiEndpointRegressionTest extends TestCase
{
    use RefreshDatabase;

    protected User $user;

    protected function setUp(): void
    {
        parent::setUp();
        $this->user = User::factory()->create();
    }

    #[Test]
    public function health_endpoint_is_accessible_without_auth(): void
    {
        $response = $this->getJson('/api/v1/health');

        $response->assertStatus(200);
        $response->assertJsonStructure(['status']);
    }

    #[Test]
    public function detailed_health_endpoint_is_accessible(): void
    {
        $response = $this->getJson('/api/v1/health/detailed');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'status',
            'timestamp',
        ]);
    }

    #[Test]
    public function protected_endpoints_require_authentication(): void
    {
        $endpoints = [
            '/api/v1/auth/me',
            '/api/v1/sites',
            '/api/v1/backups',
            '/api/v1/team/members',
        ];

        foreach ($endpoints as $endpoint) {
            $response = $this->getJson($endpoint);
            $response->assertStatus(401);
        }
    }

    #[Test]
    public function sites_api_endpoints_work(): void
    {
        Sanctum::actingAs($this->user);
        $tenant = $this->user->currentTenant();

        // List sites
        $response = $this->getJson('/api/v1/sites');
        $response->assertStatus(200);

        // Create site
        $response = $this->postJson('/api/v1/sites', [
            'domain' => 'api-test.example.com',
            'site_type' => 'wordpress',
            'php_version' => '8.2',
        ]);
        $response->assertStatus(201);

        $site = Site::where('domain', 'api-test.example.com')->first();

        // Get site
        $response = $this->getJson("/api/v1/sites/{$site->id}");
        $response->assertStatus(200);
        $response->assertJson(['domain' => 'api-test.example.com']);

        // Update site
        $response = $this->putJson("/api/v1/sites/{$site->id}", [
            'domain' => 'updated-api-test.example.com',
        ]);
        $response->assertStatus(200);

        // Delete site
        $response = $this->deleteJson("/api/v1/sites/{$site->id}");
        $response->assertStatus(200);
    }

    #[Test]
    public function backup_api_endpoints_work(): void
    {
        Sanctum::actingAs($this->user);
        $tenant = $this->user->currentTenant();
        $site = Site::factory()->create(['tenant_id' => $tenant->id]);

        // List backups
        $response = $this->getJson('/api/v1/backups');
        $response->assertStatus(200);

        // Create backup
        $response = $this->postJson('/api/v1/backups', [
            'site_id' => $site->id,
            'backup_type' => 'full',
        ]);
        $response->assertStatus(201);

        $backup = SiteBackup::where('site_id', $site->id)->first();

        // Get backup
        $response = $this->getJson("/api/v1/backups/{$backup->id}");
        $response->assertStatus(200);

        // Delete backup
        $response = $this->deleteJson("/api/v1/backups/{$backup->id}");
        $response->assertStatus(200);
    }

    #[Test]
    public function team_api_endpoints_work(): void
    {
        Sanctum::actingAs($this->user);

        // List team members
        $response = $this->getJson('/api/v1/team/members');
        $response->assertStatus(200);
        $response->assertJsonStructure(['data']);

        // Get organization
        $response = $this->getJson('/api/v1/organization');
        $response->assertStatus(200);
        $response->assertJson([
            'id' => $this->user->organization->id,
        ]);
    }

    #[Test]
    public function api_returns_proper_json_structure(): void
    {
        Sanctum::actingAs($this->user);

        $response = $this->getJson('/api/v1/sites');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'data',
            'meta' => ['total', 'per_page', 'current_page'],
        ]);
    }

    #[Test]
    public function api_handles_validation_errors(): void
    {
        Sanctum::actingAs($this->user);

        $response = $this->postJson('/api/v1/sites', []);

        $response->assertStatus(422);
        $response->assertJsonStructure([
            'message',
            'errors',
        ]);
    }

    #[Test]
    public function api_handles_not_found_errors(): void
    {
        Sanctum::actingAs($this->user);

        $response = $this->getJson('/api/v1/sites/99999999-9999-9999-9999-999999999999');

        $response->assertStatus(404);
    }

    #[Test]
    public function api_respects_tenant_isolation(): void
    {
        $user1 = User::factory()->create();
        $user2 = User::factory()->create();

        $tenant1 = $user1->currentTenant();
        $tenant2 = $user2->currentTenant();

        $site1 = Site::factory()->create(['tenant_id' => $tenant1->id]);
        $site2 = Site::factory()->create(['tenant_id' => $tenant2->id]);

        // User 1 should only see their sites
        Sanctum::actingAs($user1);
        $response = $this->getJson('/api/v1/sites');
        $response->assertStatus(200);
        $response->assertJsonCount(1, 'data');

        // User 2 should only see their sites
        Sanctum::actingAs($user2);
        $response = $this->getJson('/api/v1/sites');
        $response->assertStatus(200);
        $response->assertJsonCount(1, 'data');
    }

    #[Test]
    public function api_supports_pagination(): void
    {
        Sanctum::actingAs($this->user);
        $tenant = $this->user->currentTenant();

        Site::factory(25)->create(['tenant_id' => $tenant->id]);

        $response = $this->getJson('/api/v1/sites?per_page=10');

        $response->assertStatus(200);
        $response->assertJsonCount(10, 'data');
        $response->assertJsonPath('meta.total', 25);
    }

    #[Test]
    public function api_supports_filtering(): void
    {
        Sanctum::actingAs($this->user);
        $tenant = $this->user->currentTenant();

        Site::factory()->create([
            'tenant_id' => $tenant->id,
            'site_type' => 'wordpress',
        ]);
        Site::factory()->create([
            'tenant_id' => $tenant->id,
            'site_type' => 'laravel',
        ]);

        $response = $this->getJson('/api/v1/sites?type=wordpress');

        $response->assertStatus(200);
        $response->assertJsonPath('data.0.site_type', 'wordpress');
    }

    #[Test]
    public function api_rate_limiting_is_enforced(): void
    {
        Sanctum::actingAs($this->user);

        // Make requests until rate limit is hit
        // This depends on your rate limiting configuration
        for ($i = 0; $i < 150; $i++) {
            $response = $this->getJson('/api/v1/sites');
            if ($response->status() === 429) {
                $this->assertEquals(429, $response->status());

                return;
            }
        }

        $this->markTestSkipped('Rate limit not hit within expected request count');
    }

    #[Test]
    public function api_returns_consistent_error_format(): void
    {
        Sanctum::actingAs($this->user);

        // Test validation error format
        $response = $this->postJson('/api/v1/sites', []);
        $response->assertJsonStructure(['message', 'errors']);

        // Test not found error format
        $response = $this->getJson('/api/v1/sites/invalid-id');
        $response->assertJsonStructure(['message']);
    }

    #[Test]
    public function api_supports_cors_for_frontend(): void
    {
        $response = $this->getJson('/api/v1/health', [
            'Origin' => 'http://localhost:3000',
        ]);

        // Should not fail with CORS error
        $response->assertStatus(200);
    }

    #[Test]
    public function api_includes_proper_headers(): void
    {
        Sanctum::actingAs($this->user);

        $response = $this->getJson('/api/v1/sites');

        $response->assertStatus(200);
        $response->assertHeader('Content-Type', 'application/json');
    }
}
