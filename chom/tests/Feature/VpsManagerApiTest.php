<?php

namespace Tests\Feature;

use App\Models\Organization;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\User;
use App\Models\VpsServer;
use App\Services\VpsManagerService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Mockery;
use Tests\TestCase;

/**
 * VPS Manager API Feature Tests
 *
 * End-to-end tests for VPSManager API endpoints.
 * Verifies:
 * - Complete request/response flow
 * - Multi-tenancy isolation
 * - Authorization enforcement
 * - Integration with VpsManagerService
 */
class VpsManagerApiTest extends TestCase
{
    use RefreshDatabase;

    private Organization $orgA;
    private Organization $orgB;
    private Tenant $tenantA;
    private Tenant $tenantB;
    private User $userA;
    private User $userB;
    private Site $siteA;
    private Site $siteB;
    private VpsServer $vpsA;
    private VpsServer $vpsB;

    protected function setUp(): void
    {
        parent::setUp();

        // Create Organization A with tenant, user, VPS, and site
        $this->orgA = Organization::factory()->create(['name' => 'Organization A']);
        $this->tenantA = Tenant::factory()->create([
            'organization_id' => $this->orgA->id,
            'status' => 'active',
        ]);
        $this->userA = User::factory()->create([
            'organization_id' => $this->orgA->id,
            'role' => 'member',
        ]);
        $this->userA->tenants()->attach($this->tenantA);

        $this->vpsA = VpsServer::factory()->create([
            'status' => 'active',
            'hostname' => 'vps-a.example.com',
            'ip_address' => '192.168.1.10',
            'ssh_user' => 'root',
            'ssh_port' => 22,
        ]);

        $this->siteA = Site::factory()->create([
            'tenant_id' => $this->tenantA->id,
            'vps_id' => $this->vpsA->id,
            'domain' => 'site-a.example.com',
            'db_name' => 'site_a_db',
        ]);

        // Create Organization B with tenant, user, VPS, and site
        $this->orgB = Organization::factory()->create(['name' => 'Organization B']);
        $this->tenantB = Tenant::factory()->create([
            'organization_id' => $this->orgB->id,
            'status' => 'active',
        ]);
        $this->userB = User::factory()->create([
            'organization_id' => $this->orgB->id,
            'role' => 'member',
        ]);
        $this->userB->tenants()->attach($this->tenantB);

        $this->vpsB = VpsServer::factory()->create([
            'status' => 'active',
            'hostname' => 'vps-b.example.com',
            'ip_address' => '192.168.1.20',
        ]);

        $this->siteB = Site::factory()->create([
            'tenant_id' => $this->tenantB->id,
            'vps_id' => $this->vpsB->id,
            'domain' => 'site-b.example.com',
        ]);

        // Mock VpsManagerService to avoid actual SSH commands
        $this->mock(VpsManagerService::class, function ($mock) {
            $mock->shouldReceive('issueSSL')->andReturn([
                'success' => true,
                'output' => 'SSL certificate issued',
                'error_output' => '',
                'exit_code' => 0,
                'parsed' => ['issued' => true],
            ]);

            $mock->shouldReceive('renewSSL')->andReturn([
                'success' => true,
                'output' => 'SSL certificate renewed',
                'error_output' => '',
                'exit_code' => 0,
                'parsed' => ['renewed' => true],
            ]);

            $mock->shouldReceive('getSSLStatus')->andReturn([
                'success' => true,
                'output' => 'SSL status: active',
                'error_output' => '',
                'exit_code' => 0,
                'parsed' => ['status' => 'active'],
            ]);

            $mock->shouldReceive('exportDatabase')->andReturn([
                'success' => true,
                'output' => 'Database exported',
                'error_output' => '',
                'exit_code' => 0,
                'parsed' => ['export_path' => '/tmp/backup.sql'],
            ]);

            $mock->shouldReceive('optimizeDatabase')->andReturn([
                'success' => true,
                'output' => 'Database optimized',
                'error_output' => '',
                'exit_code' => 0,
                'parsed' => ['tables_optimized' => 10],
            ]);

            $mock->shouldReceive('clearCache')->andReturn([
                'success' => true,
                'output' => 'Cache cleared',
                'error_output' => '',
                'exit_code' => 0,
                'parsed' => ['cleared' => true],
            ]);

            $mock->shouldReceive('getVpsHealth')->andReturn([
                'success' => true,
                'output' => 'Health: OK',
                'error_output' => '',
                'exit_code' => 0,
                'parsed' => ['cpu_usage' => 30.5, 'memory_usage' => 55.2],
            ]);

            $mock->shouldReceive('getVpsStats')->andReturn([
                'success' => true,
                'output' => 'Stats retrieved',
                'error_output' => '',
                'exit_code' => 0,
                'parsed' => ['uptime_seconds' => 86400],
            ]);
        });
    }

    protected function tearDown(): void
    {
        Mockery::close();
        parent::tearDown();
    }

    /**
     * @test
     */
    public function user_can_issue_ssl_for_own_site()
    {
        Sanctum::actingAs($this->userA);

        $response = $this->postJson("/api/v1/sites/{$this->siteA->id}/ssl/issue");

        $response->assertStatus(200);
        $response->assertJson([
            'success' => true,
            'data' => [
                'site_id' => $this->siteA->id,
                'domain' => 'site-a.example.com',
                'status' => 'issued',
            ],
        ]);
    }

    /**
     * @test
     */
    public function user_cannot_issue_ssl_for_other_tenant_site()
    {
        Sanctum::actingAs($this->userA);

        $response = $this->postJson("/api/v1/sites/{$this->siteB->id}/ssl/issue");

        $response->assertStatus(404);
        $response->assertJson([
            'success' => false,
        ]);
    }

    /**
     * @test
     */
    public function user_can_renew_ssl_for_own_site()
    {
        Sanctum::actingAs($this->userA);

        $response = $this->postJson("/api/v1/sites/{$this->siteA->id}/ssl/renew");

        $response->assertStatus(200);
        $response->assertJson([
            'success' => true,
            'data' => [
                'status' => 'renewed',
            ],
        ]);
    }

    /**
     * @test
     */
    public function user_can_get_ssl_status_for_own_site()
    {
        Sanctum::actingAs($this->userA);

        $response = $this->getJson("/api/v1/sites/{$this->siteA->id}/ssl/status");

        $response->assertStatus(200);
        $response->assertJson([
            'success' => true,
        ]);
        $response->assertJsonStructure([
            'success',
            'data' => [
                'site_id',
                'domain',
                'ssl_status',
            ],
        ]);
    }

    /**
     * @test
     */
    public function user_can_export_database_for_own_site()
    {
        Sanctum::actingAs($this->userA);

        $response = $this->postJson("/api/v1/sites/{$this->siteA->id}/database/export");

        $response->assertStatus(200);
        $response->assertJson([
            'success' => true,
        ]);
        $response->assertJsonStructure([
            'success',
            'message',
            'data' => [
                'site_id',
                'domain',
                'export_details',
            ],
        ]);
    }

    /**
     * @test
     */
    public function user_can_optimize_database_for_own_site()
    {
        Sanctum::actingAs($this->userA);

        $response = $this->postJson("/api/v1/sites/{$this->siteA->id}/database/optimize");

        $response->assertStatus(200);
        $response->assertJson([
            'success' => true,
            'data' => [
                'site_id' => $this->siteA->id,
            ],
        ]);
    }

    /**
     * @test
     */
    public function user_can_clear_cache_for_own_site()
    {
        Sanctum::actingAs($this->userA);

        $response = $this->postJson("/api/v1/sites/{$this->siteA->id}/cache/clear");

        $response->assertStatus(200);
        $response->assertJson([
            'success' => true,
            'data' => [
                'site_id' => $this->siteA->id,
            ],
        ]);
    }

    /**
     * @test
     */
    public function user_can_get_vps_health_for_vps_with_own_sites()
    {
        Sanctum::actingAs($this->userA);

        $response = $this->getJson("/api/v1/vps/{$this->vpsA->id}/health");

        $response->assertStatus(200);
        $response->assertJson([
            'success' => true,
        ]);
        $response->assertJsonStructure([
            'success',
            'data' => [
                'vps_id',
                'hostname',
                'health',
            ],
        ]);
    }

    /**
     * @test
     */
    public function user_can_get_vps_stats_for_vps_with_own_sites()
    {
        Sanctum::actingAs($this->userA);

        $response = $this->getJson("/api/v1/vps/{$this->vpsA->id}/stats");

        $response->assertStatus(200);
        $response->assertJson([
            'success' => true,
        ]);
        $response->assertJsonStructure([
            'success',
            'data' => [
                'vps_id',
                'hostname',
                'stats',
            ],
        ]);
    }

    /**
     * @test
     */
    public function unauthenticated_requests_are_rejected()
    {
        $endpoints = [
            ['method' => 'post', 'uri' => "/api/v1/sites/{$this->siteA->id}/ssl/issue"],
            ['method' => 'post', 'uri' => "/api/v1/sites/{$this->siteA->id}/ssl/renew"],
            ['method' => 'get', 'uri' => "/api/v1/sites/{$this->siteA->id}/ssl/status"],
            ['method' => 'post', 'uri' => "/api/v1/sites/{$this->siteA->id}/database/export"],
            ['method' => 'post', 'uri' => "/api/v1/sites/{$this->siteA->id}/database/optimize"],
            ['method' => 'post', 'uri' => "/api/v1/sites/{$this->siteA->id}/cache/clear"],
            ['method' => 'get', 'uri' => "/api/v1/vps/{$this->vpsA->id}/health"],
            ['method' => 'get', 'uri' => "/api/v1/vps/{$this->vpsA->id}/stats"],
        ];

        foreach ($endpoints as $endpoint) {
            $response = $this->{$endpoint['method'] . 'Json'}($endpoint['uri']);
            $response->assertStatus(401);
        }
    }

    /**
     * @test
     */
    public function all_endpoints_enforce_tenant_isolation()
    {
        Sanctum::actingAs($this->userA);

        $siteEndpoints = [
            ['method' => 'post', 'uri' => "/api/v1/sites/{$this->siteB->id}/ssl/issue"],
            ['method' => 'post', 'uri' => "/api/v1/sites/{$this->siteB->id}/ssl/renew"],
            ['method' => 'get', 'uri' => "/api/v1/sites/{$this->siteB->id}/ssl/status"],
            ['method' => 'post', 'uri' => "/api/v1/sites/{$this->siteB->id}/database/export"],
            ['method' => 'post', 'uri' => "/api/v1/sites/{$this->siteB->id}/database/optimize"],
            ['method' => 'post', 'uri' => "/api/v1/sites/{$this->siteB->id}/cache/clear"],
        ];

        foreach ($siteEndpoints as $endpoint) {
            $response = $this->{$endpoint['method'] . 'Json'}($endpoint['uri']);
            $response->assertStatus(404);
        }

        // Verify siteB still exists
        $this->assertDatabaseHas('sites', ['id' => $this->siteB->id]);
    }

    /**
     * @test
     */
    public function viewer_role_cannot_perform_management_operations()
    {
        // Change userA to viewer role
        $this->userA->update(['role' => 'viewer']);
        Sanctum::actingAs($this->userA);

        $endpoints = [
            ['method' => 'post', 'uri' => "/api/v1/sites/{$this->siteA->id}/ssl/issue"],
            ['method' => 'post', 'uri' => "/api/v1/sites/{$this->siteA->id}/database/export"],
            ['method' => 'post', 'uri' => "/api/v1/sites/{$this->siteA->id}/cache/clear"],
        ];

        foreach ($endpoints as $endpoint) {
            $response = $this->{$endpoint['method'] . 'Json'}($endpoint['uri']);
            // Viewers should not be authorized for management operations
            $response->assertStatus(403);
        }
    }

    /**
     * @test
     */
    public function response_includes_proper_error_details_on_failure()
    {
        Sanctum::actingAs($this->userA);

        // Mock service to return failure
        $this->mock(VpsManagerService::class, function ($mock) {
            $mock->shouldReceive('issueSSL')->andReturn([
                'success' => false,
                'output' => '',
                'error_output' => 'Certificate validation failed',
                'exit_code' => 1,
                'parsed' => [],
            ]);
        });

        $response = $this->postJson("/api/v1/sites/{$this->siteA->id}/ssl/issue");

        $response->assertStatus(500);
        $response->assertJson([
            'success' => false,
            'error' => [
                'code' => 'SSL_ISSUE_FAILED',
                'message' => 'Failed to issue SSL certificate.',
            ],
        ]);
        $response->assertJsonStructure([
            'success',
            'error' => [
                'code',
                'message',
                'details' => [
                    'output',
                    'error_output',
                    'exit_code',
                ],
            ],
        ]);
    }
}
