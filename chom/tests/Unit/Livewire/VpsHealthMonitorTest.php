<?php

namespace Tests\Unit\Livewire;

use App\Livewire\VpsHealthMonitor;
use App\Models\Organization;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\User;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Http;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * VPS Health Monitor Test
 *
 * Comprehensive unit tests for the VpsHealthMonitor Livewire component.
 * Tests authorization, data loading, rendering, and export functionality.
 */
class VpsHealthMonitorTest extends TestCase
{
    use RefreshDatabase;

    private Organization $org;
    private Tenant $tenant;
    private User $user;
    private VpsServer $vps;

    protected function setUp(): void
    {
        parent::setUp();

        // Create organization and tenant
        $this->org = Organization::factory()->create(['name' => 'Test Organization']);
        $this->tenant = Tenant::factory()->create([
            'organization_id' => $this->org->id,
            'status' => 'active',
        ]);

        // Create user with member role (minimum required)
        $this->user = User::factory()->create([
            'organization_id' => $this->org->id,
            'role' => 'member',
        ]);
        $this->user->tenants()->attach($this->tenant);

        // Create VPS server
        $this->vps = VpsServer::factory()->create([
            'hostname' => 'vps-01',
            'ip_address' => '192.168.1.100',
            'status' => 'active',
        ]);
    }

    /** @test */
    public function it_mounts_with_vps_server_and_verifies_authorization()
    {
        $this->actingAs($this->user);

        // Mock the Gate to allow viewHealth
        Gate::shouldReceive('authorize')
            ->once()
            ->with('viewHealth', \Mockery::type(VpsServer::class))
            ->andReturn(true);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $component->assertSet('vpsId', $this->vps->id);
        $component->assertSet('vps', $this->vps);
        $component->assertSet('refreshInterval', 30);
    }

    /** @test */
    public function it_throws_authorization_exception_when_user_lacks_permission()
    {
        // Create a user without permission (viewer role)
        $viewer = User::factory()->create([
            'organization_id' => $this->org->id,
            'role' => 'viewer',
        ]);
        $viewer->tenants()->attach($this->tenant);

        $this->actingAs($viewer);

        $this->expectException(\Illuminate\Auth\Access\AuthorizationException::class);

        Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);
    }

    /** @test */
    public function it_loads_health_data_from_api_successfully()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')->andReturn(true);

        $mockHealthData = [
            'status' => 'healthy',
            'services' => [
                'nginx' => true,
                'php-fpm' => true,
                'mariadb' => true,
                'redis' => true,
            ],
            'resources' => [
                'cpu_percent' => 34,
                'memory_percent' => 62,
                'disk_percent' => 48,
                'load_average' => [1.2, 0.8, 0.6],
            ],
            'uptime_seconds' => 3888000,
            'sites_count' => 12,
        ];

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response($mockHealthData, 200),
            '*/api/v1/vps/*/stats' => Http::response([], 200),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $component->assertSet('healthData', $mockHealthData);
        $component->assertSet('error', null);
        $component->assertSet('processing', false);
    }

    /** @test */
    public function it_handles_api_failure_gracefully()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')->andReturn(true);

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response('Server Error', 500),
            '*/api/v1/vps/*/stats' => Http::response('Server Error', 500),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $component->assertSet('error', 'Failed to fetch health data: 500');
        $component->assertSet('healthData', null);
    }

    /** @test */
    public function it_loads_statistics_data_from_api_successfully()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')->andReturn(true);

        $mockStatsData = [
            'cpu_usage' => [
                '00:00' => 20,
                '06:00' => 35,
                '12:00' => 50,
                '18:00' => 30,
            ],
            'memory_usage' => [
                '00:00' => 55,
                '06:00' => 60,
                '12:00' => 65,
                '18:00' => 62,
            ],
            'disk_io' => [
                'read' => '500 MB/s',
                'write' => '300 MB/s',
                'iops' => 1500,
            ],
            'network' => [
                'inbound' => '1.2 GB',
                'outbound' => '800 MB',
                'connections' => 450,
            ],
        ];

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response([], 200),
            '*/api/v1/vps/*/stats' => Http::response($mockStatsData, 200),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $component->assertSet('stats', $mockStatsData);
        $component->assertSet('error', null);
    }

    /** @test */
    public function it_refreshes_both_health_and_stats_data()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')->andReturn(true);

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response(['status' => 'healthy'], 200),
            '*/api/v1/vps/*/stats' => Http::response(['cpu_usage' => []], 200),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response(['status' => 'warning'], 200),
            '*/api/v1/vps/*/stats' => Http::response(['cpu_usage' => ['new' => 'data']], 200),
        ]);

        $component->call('refresh');

        $component->assertSet('healthData.status', 'warning');
        $component->assertSet('stats.cpu_usage.new', 'data');
    }

    /** @test */
    public function it_returns_correct_health_status_for_healthy_state()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')->andReturn(true);

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response(['status' => 'healthy'], 200),
            '*/api/v1/vps/*/stats' => Http::response([], 200),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $healthStatus = $component->instance()->getHealthStatusAttribute();

        $this->assertEquals('Healthy', $healthStatus['status']);
        $this->assertEquals('green', $healthStatus['color']);
        $this->assertEquals('check-circle', $healthStatus['icon']);
    }

    /** @test */
    public function it_returns_correct_health_status_for_warning_state()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')->andReturn(true);

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response(['status' => 'warning'], 200),
            '*/api/v1/vps/*/stats' => Http::response([], 200),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $healthStatus = $component->instance()->getHealthStatusAttribute();

        $this->assertEquals('Warning', $healthStatus['status']);
        $this->assertEquals('yellow', $healthStatus['color']);
        $this->assertEquals('exclamation-triangle', $healthStatus['icon']);
    }

    /** @test */
    public function it_returns_correct_health_status_for_critical_state()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')->andReturn(true);

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response(['status' => 'critical'], 200),
            '*/api/v1/vps/*/stats' => Http::response([], 200),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $healthStatus = $component->instance()->getHealthStatusAttribute();

        $this->assertEquals('Critical', $healthStatus['status']);
        $this->assertEquals('red', $healthStatus['color']);
        $this->assertEquals('x-circle', $healthStatus['icon']);
    }

    /** @test */
    public function it_formats_uptime_correctly_for_days()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')->andReturn(true);

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response([], 200),
            '*/api/v1/vps/*/stats' => Http::response([], 200),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $uptime = $component->instance()->formatUptime(3888000); // 45 days

        $this->assertEquals('45 days', $uptime);
    }

    /** @test */
    public function it_formats_uptime_correctly_for_hours()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')->andReturn(true);

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response([], 200),
            '*/api/v1/vps/*/stats' => Http::response([], 200),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $uptime = $component->instance()->formatUptime(7200); // 2 hours

        $this->assertEquals('2 hours', $uptime);
    }

    /** @test */
    public function it_returns_sites_for_current_tenant_only()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')->andReturn(true);

        // Create sites for current tenant
        Site::factory()->count(3)->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vps->id,
        ]);

        // Create sites for another tenant (should not be included)
        $otherTenant = Tenant::factory()->create(['organization_id' => $this->org->id]);
        Site::factory()->count(2)->create([
            'tenant_id' => $otherTenant->id,
            'vps_id' => $this->vps->id,
        ]);

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response([], 200),
            '*/api/v1/vps/*/stats' => Http::response([], 200),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $sites = $component->instance()->getSitesProperty();

        $this->assertCount(3, $sites);
        $this->assertTrue($sites->every(fn($site) => $site->tenant_id === $this->tenant->id));
    }

    /** @test */
    public function it_generates_alerts_for_high_disk_usage()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')->andReturn(true);

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response([
                'status' => 'warning',
                'resources' => [
                    'disk_percent' => 85,
                ],
            ], 200),
            '*/api/v1/vps/*/stats' => Http::response([], 200),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $alerts = $component->instance()->getAlertsProperty();

        $this->assertGreaterThan(0, count($alerts));
        $this->assertTrue(
            collect($alerts)->contains(fn($alert) => str_contains($alert['message'], 'Disk usage'))
        );
    }

    /** @test */
    public function it_generates_alerts_for_high_memory_usage()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')->andReturn(true);

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response([
                'status' => 'warning',
                'resources' => [
                    'memory_percent' => 90,
                ],
            ], 200),
            '*/api/v1/vps/*/stats' => Http::response([], 200),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $alerts = $component->instance()->getAlertsProperty();

        $this->assertGreaterThan(0, count($alerts));
        $this->assertTrue(
            collect($alerts)->contains(fn($alert) => str_contains($alert['message'], 'Memory usage'))
        );
    }

    /** @test */
    public function it_generates_critical_alerts_for_down_services()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')->andReturn(true);

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response([
                'status' => 'critical',
                'services' => [
                    'nginx' => true,
                    'php-fpm' => false,
                    'mariadb' => true,
                    'redis' => false,
                ],
            ], 200),
            '*/api/v1/vps/*/stats' => Http::response([], 200),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $alerts = $component->instance()->getAlertsProperty();

        $this->assertGreaterThan(0, count($alerts));

        $criticalAlerts = collect($alerts)->filter(fn($alert) => $alert['severity'] === 'critical');
        $this->assertGreaterThan(0, $criticalAlerts->count());

        // Should have alerts for both php-fpm and redis being down
        $this->assertTrue(
            $criticalAlerts->contains(fn($alert) => str_contains($alert['message'], 'Php-fpm'))
        );
        $this->assertTrue(
            $criticalAlerts->contains(fn($alert) => str_contains($alert['message'], 'Redis'))
        );
    }

    /** @test */
    public function it_exports_pdf_with_authorization_check()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')
            ->twice() // Once for mount, once for exportPdf
            ->with('viewHealth', \Mockery::type(VpsServer::class))
            ->andReturn(true);

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response(['status' => 'healthy'], 200),
            '*/api/v1/vps/*/stats' => Http::response([], 200),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $response = $component->call('exportPdf');

        $this->assertInstanceOf(\Symfony\Component\HttpFoundation\StreamedResponse::class, $response);
    }

    /** @test */
    public function it_exports_csv_with_authorization_check()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')
            ->twice() // Once for mount, once for exportCsv
            ->with('viewHealth', \Mockery::type(VpsServer::class))
            ->andReturn(true);

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response(['status' => 'healthy'], 200),
            '*/api/v1/vps/*/stats' => Http::response([], 200),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $response = $component->call('exportCsv');

        $this->assertInstanceOf(\Symfony\Component\HttpFoundation\StreamedResponse::class, $response);
    }

    /** @test */
    public function it_renders_view_successfully()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')->andReturn(true);

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response(['status' => 'healthy'], 200),
            '*/api/v1/vps/*/stats' => Http::response([], 200),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $component->assertViewIs('livewire.vps-health-monitor');
        $component->assertViewHas('healthStatus');
        $component->assertViewHas('sites');
        $component->assertViewHas('alerts');
    }

    /** @test */
    public function it_displays_error_message_in_view()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')->andReturn(true);

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response('Error', 500),
            '*/api/v1/vps/*/stats' => Http::response('Error', 500),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $component->assertSee('Failed to fetch health data: 500');
    }

    /** @test */
    public function it_displays_vps_hostname_and_ip_in_view()
    {
        $this->actingAs($this->user);

        Gate::shouldReceive('authorize')->andReturn(true);

        Http::fake([
            '*/api/v1/vps/*/health' => Http::response([], 200),
            '*/api/v1/vps/*/stats' => Http::response([], 200),
        ]);

        $component = Livewire::test(VpsHealthMonitor::class, ['vps' => $this->vps]);

        $component->assertSee('vps-01');
        $component->assertSee('192.168.1.100');
    }
}
