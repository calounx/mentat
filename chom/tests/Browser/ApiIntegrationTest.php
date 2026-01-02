<?php

namespace Tests\Browser;

use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\DatabaseMigrations;
use Illuminate\Support\Facades\Http;
use Laravel\Dusk\Browser;
use Tests\DuskTestCase;

/**
 * E2E Test Suite: API Integration
 *
 * Covers complete API workflows including:
 * - Register via API endpoint
 * - Login and get token
 * - Create site via API
 * - Create backup via API
 * - List backups via API
 * - Download backup via API
 * - Restore backup via API
 * - VPS CRUD via API
 */
class ApiIntegrationTest extends DuskTestCase
{
    use DatabaseMigrations;

    protected string $apiUrl;

    protected function setUp(): void
    {
        parent::setUp();
        $this->apiUrl = config('app.url').'/api/v1';
    }

    /**
     * Test 1: Register via API endpoint.
     *
     * @test
     */
    public function can_register_via_api(): void
    {
        $response = $this->postJson('/api/v1/auth/register', [
            'name' => 'API Test User',
            'email' => 'api-test@example.com',
            'password' => 'SecurePassword123!',
            'password_confirmation' => 'SecurePassword123!',
            'organization_name' => 'API Test Org',
        ]);

        $response->assertStatus(201)
            ->assertJsonStructure([
                'user' => ['id', 'name', 'email', 'organization_id'],
                'organization' => ['id', 'name', 'slug'],
                'token',
            ]);

        // Verify user was created
        $this->assertDatabaseHas('users', [
            'email' => 'api-test@example.com',
            'name' => 'API Test User',
            'role' => 'owner',
        ]);

        // Verify organization was created
        $this->assertDatabaseHas('organizations', [
            'name' => 'API Test Org',
        ]);
    }

    /**
     * Test 2: Login and get token.
     *
     * @test
     */
    public function can_login_and_get_token(): void
    {
        $user = $this->createUser([
            'email' => 'login-api@example.com',
            'password' => bcrypt('password123'),
        ]);

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => 'login-api@example.com',
            'password' => 'password123',
        ]);

        $response->assertStatus(200)
            ->assertJsonStructure([
                'user' => ['id', 'name', 'email'],
                'token',
                'token_type',
                'expires_at',
            ]);

        $token = $response->json('token');
        $this->assertNotEmpty($token);

        // Verify token works for authenticated requests
        $meResponse = $this->withHeaders([
            'Authorization' => "Bearer {$token}",
        ])->getJson('/api/v1/auth/me');

        $meResponse->assertStatus(200)
            ->assertJson([
                'id' => $user->id,
                'email' => 'login-api@example.com',
            ]);
    }

    /**
     * Test 3: Create site via API.
     *
     * @test
     */
    public function can_create_site_via_api(): void
    {
        $user = $this->createUser();
        $token = $this->createApiToken($user);

        $vps = VpsServer::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'status' => 'active',
        ]);

        $response = $this->withHeaders([
            'Authorization' => "Bearer {$token}",
        ])->postJson('/api/v1/sites', [
            'domain' => 'api-created-site.com',
            'site_type' => 'wordpress',
            'vps_id' => $vps->id,
            'php_version' => '8.2',
            'ssl_enabled' => true,
        ]);

        $response->assertStatus(201)
            ->assertJsonStructure([
                'site' => ['id', 'domain', 'site_type', 'php_version', 'ssl_enabled'],
                'operation' => ['id', 'status', 'operation_type'],
            ]);

        // Verify site was created
        $this->assertDatabaseHas('sites', [
            'tenant_id' => $user->currentTenant()->id,
            'domain' => 'api-created-site.com',
            'site_type' => 'wordpress',
            'php_version' => '8.2',
            'ssl_enabled' => true,
        ]);
    }

    /**
     * Test 4: Create backup via API.
     *
     * @test
     */
    public function can_create_backup_via_api(): void
    {
        $user = $this->createUser();
        $token = $this->createApiToken($user);

        $site = Site::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'domain' => 'backup-test.com',
        ]);

        $response = $this->withHeaders([
            'Authorization' => "Bearer {$token}",
        ])->postJson('/api/v1/backups', [
            'site_id' => $site->id,
            'backup_type' => 'full',
            'description' => 'API-created backup',
        ]);

        $response->assertStatus(201)
            ->assertJsonStructure([
                'backup' => ['id', 'site_id', 'backup_type', 'description', 'status'],
                'operation' => ['id', 'status'],
            ]);

        // Verify backup was created
        $this->assertDatabaseHas('site_backups', [
            'site_id' => $site->id,
            'backup_type' => 'full',
            'description' => 'API-created backup',
        ]);
    }

    /**
     * Test 5: List backups via API.
     *
     * @test
     */
    public function can_list_backups_via_api(): void
    {
        $user = $this->createUser();
        $token = $this->createApiToken($user);

        $site = Site::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
        ]);

        // Create multiple backups
        SiteBackup::factory()->count(3)->create([
            'site_id' => $site->id,
            'status' => 'completed',
        ]);

        $response = $this->withHeaders([
            'Authorization' => "Bearer {$token}",
        ])->getJson('/api/v1/backups');

        $response->assertStatus(200)
            ->assertJsonStructure([
                'data' => [
                    '*' => ['id', 'site_id', 'backup_type', 'status', 'created_at'],
                ],
                'meta' => ['total', 'per_page', 'current_page'],
            ]);

        $this->assertCount(3, $response->json('data'));
    }

    /**
     * Test 6: Download backup via API.
     *
     * @test
     */
    public function can_download_backup_via_api(): void
    {
        $user = $this->createUser();
        $token = $this->createApiToken($user);

        $site = Site::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
        ]);

        $backup = SiteBackup::factory()->create([
            'site_id' => $site->id,
            'status' => 'completed',
            'file_path' => '/backups/test-backup.tar.gz',
            'file_size_mb' => 100,
        ]);

        $response = $this->withHeaders([
            'Authorization' => "Bearer {$token}",
        ])->get("/api/v1/backups/{$backup->id}/download");

        $response->assertStatus(200);
        $response->assertHeader('Content-Type', 'application/x-gzip');
        $response->assertHeader('Content-Disposition');

        // Verify download was logged
        $this->assertDatabaseHas('audit_logs', [
            'user_id' => $user->id,
            'action' => 'backup_download',
            'resource_type' => 'SiteBackup',
            'resource_id' => $backup->id,
        ]);
    }

    /**
     * Test 7: Restore backup via API.
     *
     * @test
     */
    public function can_restore_backup_via_api(): void
    {
        $user = $this->createUser();
        $token = $this->createApiToken($user);

        $site = Site::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
        ]);

        $backup = SiteBackup::factory()->create([
            'site_id' => $site->id,
            'status' => 'completed',
            'backup_type' => 'full',
        ]);

        $response = $this->withHeaders([
            'Authorization' => "Bearer {$token}",
        ])->postJson("/api/v1/backups/{$backup->id}/restore");

        $response->assertStatus(202)
            ->assertJsonStructure([
                'message',
                'operation' => ['id', 'status', 'operation_type'],
            ]);

        // Verify restore operation was created
        $this->assertDatabaseHas('operations', [
            'user_id' => $user->id,
            'operation_type' => 'backup_restore',
        ]);

        // Verify audit log
        $this->assertDatabaseHas('audit_logs', [
            'user_id' => $user->id,
            'action' => 'backup_restore',
            'resource_type' => 'SiteBackup',
            'resource_id' => $backup->id,
        ]);
    }

    /**
     * Test 8: VPS CRUD via API.
     *
     * @test
     */
    public function can_perform_vps_crud_via_api(): void
    {
        $user = $this->createUser();
        $token = $this->createApiToken($user);

        // CREATE VPS
        $createResponse = $this->withHeaders([
            'Authorization' => "Bearer {$token}",
        ])->postJson('/api/v1/vps', [
            'name' => 'API VPS Server',
            'ip_address' => '192.168.1.200',
            'ssh_port' => 22,
            'ssh_user' => 'root',
            'provider' => 'digitalocean',
            'cpu_cores' => 4,
            'ram_mb' => 8192,
            'disk_gb' => 160,
        ]);

        $createResponse->assertStatus(201)
            ->assertJsonStructure([
                'vps' => ['id', 'name', 'ip_address', 'status'],
            ]);

        $vpsId = $createResponse->json('vps.id');

        // Verify VPS was created
        $this->assertDatabaseHas('vps_servers', [
            'id' => $vpsId,
            'name' => 'API VPS Server',
            'ip_address' => '192.168.1.200',
        ]);

        // READ VPS
        $readResponse = $this->withHeaders([
            'Authorization' => "Bearer {$token}",
        ])->getJson("/api/v1/vps/{$vpsId}");

        $readResponse->assertStatus(200)
            ->assertJson([
                'id' => $vpsId,
                'name' => 'API VPS Server',
                'ip_address' => '192.168.1.200',
            ]);

        // UPDATE VPS
        $updateResponse = $this->withHeaders([
            'Authorization' => "Bearer {$token}",
        ])->patchJson("/api/v1/vps/{$vpsId}", [
            'name' => 'Updated API VPS',
            'cpu_cores' => 8,
            'ram_mb' => 16384,
        ]);

        $updateResponse->assertStatus(200)
            ->assertJson([
                'vps' => [
                    'id' => $vpsId,
                    'name' => 'Updated API VPS',
                    'cpu_cores' => 8,
                    'ram_mb' => 16384,
                ],
            ]);

        // Verify update
        $this->assertDatabaseHas('vps_servers', [
            'id' => $vpsId,
            'name' => 'Updated API VPS',
            'cpu_cores' => 8,
            'ram_mb' => 16384,
        ]);

        // DELETE VPS
        $deleteResponse = $this->withHeaders([
            'Authorization' => "Bearer {$token}",
        ])->deleteJson("/api/v1/vps/{$vpsId}");

        $deleteResponse->assertStatus(200)
            ->assertJson([
                'message' => 'VPS server deleted successfully',
            ]);

        // Verify VPS was soft-deleted
        $this->assertSoftDeleted('vps_servers', [
            'id' => $vpsId,
        ]);
    }

    /**
     * Test: API rate limiting.
     *
     * @test
     */
    public function api_enforces_rate_limiting(): void
    {
        $user = $this->createUser();
        $token = $this->createApiToken($user);

        // Make many requests to trigger rate limit
        $responses = [];
        for ($i = 0; $i < 110; $i++) {
            $responses[] = $this->withHeaders([
                'Authorization' => "Bearer {$token}",
            ])->getJson('/api/v1/auth/me');
        }

        // Check that some requests were rate limited
        $rateLimitedCount = collect($responses)->filter(function ($response) {
            return $response->status() === 429;
        })->count();

        $this->assertGreaterThan(0, $rateLimitedCount);
    }

    /**
     * Test: API authentication failures.
     *
     * @test
     */
    public function api_rejects_unauthenticated_requests(): void
    {
        $response = $this->getJson('/api/v1/sites');

        $response->assertStatus(401)
            ->assertJson([
                'message' => 'Unauthenticated.',
            ]);
    }

    /**
     * Test: API token refresh.
     *
     * @test
     */
    public function can_refresh_api_token(): void
    {
        $user = $this->createUser();
        $token = $this->createApiToken($user);

        $response = $this->withHeaders([
            'Authorization' => "Bearer {$token}",
        ])->postJson('/api/v1/auth/refresh');

        $response->assertStatus(200)
            ->assertJsonStructure([
                'token',
                'token_type',
                'expires_at',
            ]);

        $newToken = $response->json('token');
        $this->assertNotEquals($token, $newToken);

        // Verify new token works
        $meResponse = $this->withHeaders([
            'Authorization' => "Bearer {$newToken}",
        ])->getJson('/api/v1/auth/me');

        $meResponse->assertStatus(200);
    }

    /**
     * Test: API pagination.
     *
     * @test
     */
    public function api_returns_paginated_results(): void
    {
        $user = $this->createUser();
        $token = $this->createApiToken($user);

        // Create 25 sites
        Site::factory()->count(25)->create([
            'tenant_id' => $user->currentTenant()->id,
        ]);

        // Request first page
        $response = $this->withHeaders([
            'Authorization' => "Bearer {$token}",
        ])->getJson('/api/v1/sites?page=1&per_page=10');

        $response->assertStatus(200)
            ->assertJsonStructure([
                'data',
                'meta' => ['total', 'per_page', 'current_page', 'last_page'],
                'links' => ['first', 'last', 'prev', 'next'],
            ]);

        $this->assertCount(10, $response->json('data'));
        $this->assertEquals(25, $response->json('meta.total'));
        $this->assertEquals(3, $response->json('meta.last_page'));
    }

    /**
     * Test: API filtering and searching.
     *
     * @test
     */
    public function api_supports_filtering_and_searching(): void
    {
        $user = $this->createUser();
        $token = $this->createApiToken($user);

        // Create sites with different types
        Site::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'domain' => 'wordpress-site.com',
            'site_type' => 'wordpress',
        ]);

        Site::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'domain' => 'laravel-app.com',
            'site_type' => 'laravel',
        ]);

        // Filter by site type
        $response = $this->withHeaders([
            'Authorization' => "Bearer {$token}",
        ])->getJson('/api/v1/sites?site_type=wordpress');

        $response->assertStatus(200);
        $this->assertCount(1, $response->json('data'));
        $this->assertEquals('wordpress', $response->json('data.0.site_type'));

        // Search by domain
        $searchResponse = $this->withHeaders([
            'Authorization' => "Bearer {$token}",
        ])->getJson('/api/v1/sites?search=laravel');

        $searchResponse->assertStatus(200);
        $this->assertCount(1, $searchResponse->json('data'));
        $this->assertStringContainsString('laravel', $searchResponse->json('data.0.domain'));
    }
}
