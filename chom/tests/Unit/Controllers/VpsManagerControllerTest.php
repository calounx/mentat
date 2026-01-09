<?php

namespace Tests\Unit\Controllers;

use App\Http\Controllers\Api\V1\VpsManagerController;
use App\Models\Organization;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\User;
use App\Models\VpsServer;
use App\Repositories\SiteRepository;
use App\Repositories\VpsServerRepository;
use App\Services\VpsManagerService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Laravel\Sanctum\Sanctum;
use Mockery;
use Tests\TestCase;

/**
 * VpsManagerController Unit Tests
 *
 * Tests controller methods with focus on:
 * - Multi-tenancy security
 * - Authorization via policies
 * - VpsManagerService integration
 * - Error handling and logging
 */
class VpsManagerControllerTest extends TestCase
{
    use RefreshDatabase;

    private VpsManagerController $controller;
    private VpsManagerService $vpsManagerService;
    private SiteRepository $siteRepository;
    private VpsServerRepository $vpsServerRepository;
    private User $user;
    private Tenant $tenant;
    private Site $site;
    private VpsServer $vps;
    private Tenant $otherTenant;
    private Site $otherSite;

    protected function setUp(): void
    {
        parent::setUp();

        // Create test organization and tenant
        $org = Organization::factory()->create();
        $this->tenant = Tenant::factory()->create([
            'organization_id' => $org->id,
            'tier' => 'professional',
            'status' => 'active',
        ]);

        $this->user = User::factory()->create([
            'organization_id' => $org->id,
            'current_tenant_id' => $this->tenant->id,
            'role' => 'member',
        ]);

        // Create VPS and site
        $this->vps = VpsServer::factory()->create([
            'status' => 'active',
            'hostname' => 'vps1.example.com',
            'ip_address' => '192.168.1.100',
            'ssh_user' => 'root',
            'ssh_port' => 22,
        ]);

        $this->site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vps->id,
            'domain' => 'test-site.com',
            'db_name' => 'test_db',
        ]);

        // Create other tenant and site for cross-tenant tests
        $otherOrg = Organization::factory()->create();
        $this->otherTenant = Tenant::factory()->create([
            'organization_id' => $otherOrg->id,
            'status' => 'active',
        ]);

        $otherVps = VpsServer::factory()->create(['status' => 'active']);
        $this->otherSite = Site::factory()->create([
            'tenant_id' => $this->otherTenant->id,
            'vps_id' => $otherVps->id,
        ]);

        // Initialize repositories and services
        $this->siteRepository = new SiteRepository(new Site());
        $this->vpsServerRepository = new VpsServerRepository(new VpsServer());
        $this->vpsManagerService = Mockery::mock(VpsManagerService::class);

        $this->controller = new VpsManagerController(
            $this->vpsManagerService,
            $this->siteRepository,
            $this->vpsServerRepository
        );
    }

    protected function tearDown(): void
    {
        Mockery::close();
        parent::tearDown();
    }

    // ============================================================================
    // SSL Issue Tests
    // ============================================================================

    public function test_issue_ssl_succeeds_for_valid_site()
    {
        Sanctum::actingAs($this->user);

        $this->vpsManagerService->shouldReceive('issueSSL')
            ->once()
            ->with(Mockery::on(function ($site) {
                return $site->id === $this->site->id;
            }))
            ->andReturn([
                'success' => true,
                'output' => 'SSL certificate issued successfully',
                'error_output' => '',
                'exit_code' => 0,
                'parsed' => ['issued' => true, 'status' => 'active'],
            ]);

        $request = Request::create("/api/v1/sites/{$this->site->id}/ssl/issue", 'POST');
        $request->setUserResolver(fn() => $this->user);

        $response = $this->controller->issueSSL($request, $this->site->id);

        $this->assertEquals(200, $response->getStatusCode());
        $data = json_decode($response->getContent(), true);
        $this->assertTrue($data['success']);
        $this->assertEquals($this->site->id, $data['data']['site_id']);
        $this->assertEquals('issued', $data['data']['status']);
    }

    public function test_issue_ssl_fails_for_cross_tenant_access()
    {
        Sanctum::actingAs($this->user);

        $request = Request::create("/api/v1/sites/{$this->otherSite->id}/ssl/issue", 'POST');
        $request->setUserResolver(fn() => $this->user);

        $this->expectException(\Symfony\Component\HttpKernel\Exception\NotFoundHttpException::class);

        $this->controller->issueSSL($request, $this->otherSite->id);
    }

    public function test_issue_ssl_returns_error_when_command_fails()
    {
        Sanctum::actingAs($this->user);

        $this->vpsManagerService->shouldReceive('issueSSL')
            ->once()
            ->andReturn([
                'success' => false,
                'output' => '',
                'error_output' => 'Certificate issuance failed',
                'exit_code' => 1,
                'parsed' => [],
            ]);

        $request = Request::create("/api/v1/sites/{$this->site->id}/ssl/issue", 'POST');
        $request->setUserResolver(fn() => $this->user);

        $response = $this->controller->issueSSL($request, $this->site->id);

        $this->assertEquals(500, $response->getStatusCode());
        $data = json_decode($response->getContent(), true);
        $this->assertFalse($data['success']);
        $this->assertEquals('SSL_ISSUE_FAILED', $data['error']['code']);
    }

    // ============================================================================
    // SSL Renew Tests
    // ============================================================================

    public function test_renew_ssl_succeeds_for_valid_site()
    {
        Sanctum::actingAs($this->user);

        $this->vpsManagerService->shouldReceive('renewSSL')
            ->once()
            ->andReturn([
                'success' => true,
                'output' => 'SSL certificate renewed',
                'error_output' => '',
                'exit_code' => 0,
                'parsed' => ['renewed' => true],
            ]);

        $request = Request::create("/api/v1/sites/{$this->site->id}/ssl/renew", 'POST');
        $request->setUserResolver(fn() => $this->user);

        $response = $this->controller->renewSSL($request, $this->site->id);

        $this->assertEquals(200, $response->getStatusCode());
        $data = json_decode($response->getContent(), true);
        $this->assertTrue($data['success']);
        $this->assertEquals('renewed', $data['data']['status']);
    }

    public function test_renew_ssl_fails_for_cross_tenant_access()
    {
        Sanctum::actingAs($this->user);

        $request = Request::create("/api/v1/sites/{$this->otherSite->id}/ssl/renew", 'POST');
        $request->setUserResolver(fn() => $this->user);

        $this->expectException(\Symfony\Component\HttpKernel\Exception\NotFoundHttpException::class);

        $this->controller->renewSSL($request, $this->otherSite->id);
    }

    // ============================================================================
    // SSL Status Tests
    // ============================================================================

    public function test_get_ssl_status_succeeds_for_valid_site()
    {
        Sanctum::actingAs($this->user);

        $this->vpsManagerService->shouldReceive('getSSLStatus')
            ->once()
            ->andReturn([
                'success' => true,
                'output' => 'SSL status retrieved',
                'error_output' => '',
                'exit_code' => 0,
                'parsed' => [
                    'status' => 'valid',
                    'expires_at' => '2026-01-01',
                ],
            ]);

        $request = Request::create("/api/v1/sites/{$this->site->id}/ssl/status", 'GET');
        $request->setUserResolver(fn() => $this->user);

        $response = $this->controller->getSSLStatus($request, $this->site->id);

        $this->assertEquals(200, $response->getStatusCode());
        $data = json_decode($response->getContent(), true);
        $this->assertTrue($data['success']);
        $this->assertArrayHasKey('ssl_status', $data['data']);
    }

    public function test_get_ssl_status_fails_for_cross_tenant_access()
    {
        Sanctum::actingAs($this->user);

        $request = Request::create("/api/v1/sites/{$this->otherSite->id}/ssl/status", 'GET');
        $request->setUserResolver(fn() => $this->user);

        $this->expectException(\Symfony\Component\HttpKernel\Exception\NotFoundHttpException::class);

        $this->controller->getSSLStatus($request, $this->otherSite->id);
    }

    // ============================================================================
    // Database Export Tests
    // ============================================================================

    public function test_export_database_succeeds_for_valid_site()
    {
        Sanctum::actingAs($this->user);

        $this->vpsManagerService->shouldReceive('exportDatabase')
            ->once()
            ->andReturn([
                'success' => true,
                'output' => 'Database exported to /path/to/backup.sql',
                'error_output' => '',
                'exit_code' => 0,
                'parsed' => [
                    'export_path' => '/path/to/backup.sql',
                    'size' => '50 MB',
                ],
            ]);

        $request = Request::create("/api/v1/sites/{$this->site->id}/database/export", 'POST');
        $request->setUserResolver(fn() => $this->user);

        $response = $this->controller->exportDatabase($request, $this->site->id);

        $this->assertEquals(200, $response->getStatusCode());
        $data = json_decode($response->getContent(), true);
        $this->assertTrue($data['success']);
        $this->assertArrayHasKey('export_details', $data['data']);
    }

    public function test_export_database_fails_for_cross_tenant_access()
    {
        Sanctum::actingAs($this->user);

        $request = Request::create("/api/v1/sites/{$this->otherSite->id}/database/export", 'POST');
        $request->setUserResolver(fn() => $this->user);

        $this->expectException(\Symfony\Component\HttpKernel\Exception\NotFoundHttpException::class);

        $this->controller->exportDatabase($request, $this->otherSite->id);
    }

    // ============================================================================
    // Database Optimize Tests
    // ============================================================================

    public function test_optimize_database_succeeds_for_valid_site()
    {
        Sanctum::actingAs($this->user);

        $this->vpsManagerService->shouldReceive('optimizeDatabase')
            ->once()
            ->andReturn([
                'success' => true,
                'output' => 'Database optimized: 5 tables',
                'error_output' => '',
                'exit_code' => 0,
                'parsed' => ['tables_optimized' => 5],
            ]);

        $request = Request::create("/api/v1/sites/{$this->site->id}/database/optimize", 'POST');
        $request->setUserResolver(fn() => $this->user);

        $response = $this->controller->optimizeDatabase($request, $this->site->id);

        $this->assertEquals(200, $response->getStatusCode());
        $data = json_decode($response->getContent(), true);
        $this->assertTrue($data['success']);
        $this->assertArrayHasKey('optimization_details', $data['data']);
    }

    public function test_optimize_database_returns_error_when_command_fails()
    {
        Sanctum::actingAs($this->user);

        $this->vpsManagerService->shouldReceive('optimizeDatabase')
            ->once()
            ->andReturn([
                'success' => false,
                'output' => '',
                'error_output' => 'Database optimization failed',
                'exit_code' => 1,
                'parsed' => [],
            ]);

        $request = Request::create("/api/v1/sites/{$this->site->id}/database/optimize", 'POST');
        $request->setUserResolver(fn() => $this->user);

        $response = $this->controller->optimizeDatabase($request, $this->site->id);

        $this->assertEquals(500, $response->getStatusCode());
        $data = json_decode($response->getContent(), true);
        $this->assertFalse($data['success']);
        $this->assertEquals('DATABASE_OPTIMIZE_FAILED', $data['error']['code']);
    }

    // ============================================================================
    // Cache Clear Tests
    // ============================================================================

    public function test_clear_cache_succeeds_for_valid_site()
    {
        Sanctum::actingAs($this->user);

        $this->vpsManagerService->shouldReceive('clearCache')
            ->once()
            ->andReturn([
                'success' => true,
                'output' => 'Cache cleared successfully',
                'error_output' => '',
                'exit_code' => 0,
                'parsed' => [
                    'cleared' => true,
                    'cache_types' => ['redis', 'opcache'],
                ],
            ]);

        $request = Request::create("/api/v1/sites/{$this->site->id}/cache/clear", 'POST');
        $request->setUserResolver(fn() => $this->user);

        $response = $this->controller->clearCache($request, $this->site->id);

        $this->assertEquals(200, $response->getStatusCode());
        $data = json_decode($response->getContent(), true);
        $this->assertTrue($data['success']);
        $this->assertArrayHasKey('cache_details', $data['data']);
    }

    public function test_clear_cache_fails_for_cross_tenant_access()
    {
        Sanctum::actingAs($this->user);

        $request = Request::create("/api/v1/sites/{$this->otherSite->id}/cache/clear", 'POST');
        $request->setUserResolver(fn() => $this->user);

        $this->expectException(\Symfony\Component\HttpKernel\Exception\NotFoundHttpException::class);

        $this->controller->clearCache($request, $this->otherSite->id);
    }

    // ============================================================================
    // VPS Health Tests
    // ============================================================================

    public function test_get_vps_health_succeeds_for_valid_vps()
    {
        Sanctum::actingAs($this->user);

        // User must have at least one site on the VPS to view health
        Gate::shouldReceive('authorize')
            ->once()
            ->with('view', Mockery::type(VpsServer::class))
            ->andReturn(true);

        $this->vpsManagerService->shouldReceive('getVpsHealth')
            ->once()
            ->andReturn([
                'success' => true,
                'output' => 'Health check passed',
                'error_output' => '',
                'exit_code' => 0,
                'parsed' => [
                    'cpu_usage' => 45.2,
                    'memory_usage' => 62.5,
                    'disk_usage' => 35.0,
                ],
            ]);

        $request = Request::create("/api/v1/vps/{$this->vps->id}/health", 'GET');
        $request->setUserResolver(fn() => $this->user);

        $response = $this->controller->getVpsHealth($request, $this->vps->id);

        $this->assertEquals(200, $response->getStatusCode());
        $data = json_decode($response->getContent(), true);
        $this->assertTrue($data['success']);
        $this->assertArrayHasKey('health', $data['data']);
    }

    public function test_get_vps_health_returns_404_for_nonexistent_vps()
    {
        Sanctum::actingAs($this->user);

        $request = Request::create('/api/v1/vps/non-existent-id/health', 'GET');
        $request->setUserResolver(fn() => $this->user);

        $response = $this->controller->getVpsHealth($request, 'non-existent-id');

        $this->assertEquals(404, $response->getStatusCode());
        $data = json_decode($response->getContent(), true);
        $this->assertFalse($data['success']);
    }

    // ============================================================================
    // VPS Stats Tests
    // ============================================================================

    public function test_get_vps_stats_succeeds_for_valid_vps()
    {
        Sanctum::actingAs($this->user);

        Gate::shouldReceive('authorize')
            ->once()
            ->with('view', Mockery::type(VpsServer::class))
            ->andReturn(true);

        $this->vpsManagerService->shouldReceive('getVpsStats')
            ->once()
            ->andReturn([
                'success' => true,
                'output' => 'Stats retrieved',
                'error_output' => '',
                'exit_code' => 0,
                'parsed' => [
                    'cpu_usage' => 30.5,
                    'memory_usage' => 55.2,
                    'disk_usage' => 42.1,
                    'load_average' => 1.25,
                    'uptime_seconds' => 86400,
                ],
            ]);

        $request = Request::create("/api/v1/vps/{$this->vps->id}/stats", 'GET');
        $request->setUserResolver(fn() => $this->user);

        $response = $this->controller->getVpsStats($request, $this->vps->id);

        $this->assertEquals(200, $response->getStatusCode());
        $data = json_decode($response->getContent(), true);
        $this->assertTrue($data['success']);
        $this->assertArrayHasKey('stats', $data['data']);
    }

    public function test_get_vps_stats_returns_404_for_nonexistent_vps()
    {
        Sanctum::actingAs($this->user);

        $request = Request::create('/api/v1/vps/non-existent-id/stats', 'GET');
        $request->setUserResolver(fn() => $this->user);

        $response = $this->controller->getVpsStats($request, 'non-existent-id');

        $this->assertEquals(404, $response->getStatusCode());
        $data = json_decode($response->getContent(), true);
        $this->assertFalse($data['success']);
    }

    // ============================================================================
    // Multi-Method Security Tests
    // ============================================================================

    public function test_all_site_methods_enforce_tenant_isolation_consistently()
    {
        Sanctum::actingAs($this->user);

        $methods = [
            ['method' => 'issueSSL', 'verb' => 'POST'],
            ['method' => 'renewSSL', 'verb' => 'POST'],
            ['method' => 'getSSLStatus', 'verb' => 'GET'],
            ['method' => 'exportDatabase', 'verb' => 'POST'],
            ['method' => 'optimizeDatabase', 'verb' => 'POST'],
            ['method' => 'clearCache', 'verb' => 'POST'],
        ];

        foreach ($methods as $methodInfo) {
            $request = Request::create(
                "/api/v1/sites/{$this->otherSite->id}/test",
                $methodInfo['verb']
            );
            $request->setUserResolver(fn() => $this->user);

            try {
                $this->controller->{$methodInfo['method']}($request, $this->otherSite->id);
                $this->fail("{$methodInfo['method']}() should have thrown NotFoundHttpException");
            } catch (\Symfony\Component\HttpKernel\Exception\NotFoundHttpException $e) {
                $this->assertTrue(true);
            }
        }

        // Verify other tenant's site still exists
        $this->assertDatabaseHas('sites', [
            'id' => $this->otherSite->id,
        ]);
    }
}
