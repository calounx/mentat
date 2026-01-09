<?php

declare(strict_types=1);

namespace Tests\Unit\Services;

use App\Contracts\Infrastructure\VpsProviderInterface;
use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\VpsServer;
use App\Services\HealthCheckService;
use App\ValueObjects\CommandResult;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Mockery;
use Tests\TestCase;

class HealthCheckServiceTest extends TestCase
{
    use RefreshDatabase;

    private HealthCheckService $service;
    private $vpsProvider;

    protected function setUp(): void
    {
        parent::setUp();

        $this->vpsProvider = Mockery::mock(VpsProviderInterface::class);
        $this->service = new HealthCheckService($this->vpsProvider);
    }

    protected function tearDown(): void
    {
        Mockery::close();
        parent::tearDown();
    }

    public function test_it_detects_no_incoherencies_in_healthy_system()
    {
        // Create a healthy system with no issues
        $vps = VpsServer::factory()->create([
            'status' => 'active',
            'site_count' => 2,
        ]);

        Site::factory()->count(2)->create([
            'vps_id' => $vps->id,
            'status' => 'active',
        ]);

        $results = $this->service->detectIncoherencies(quickCheck: true);

        $this->assertIsArray($results);
        $this->assertEquals(0, $results['summary']['total_issues']);
        $this->assertEquals(0, $results['orphaned_backups']->count());
        $this->assertEquals(0, $results['incorrect_vps_counts']->count());
    }

    public function test_it_finds_orphaned_backups()
    {
        $site = Site::factory()->create([
            'status' => 'active',
        ]);

        // Create backup for existing site
        $validBackup = SiteBackup::factory()->create([
            'site_id' => $site->id,
        ]);

        // Create orphaned backup with non-existent site ID
        $orphanedBackup = SiteBackup::factory()->create([
            'site_id' => 'non-existent-site-id',
        ]);

        $results = $this->service->findOrphanedBackups();

        $this->assertEquals(1, $results->count());
        $this->assertEquals($orphanedBackup->id, $results->first()['backup']->id);
    }

    public function test_it_validates_vps_site_counts()
    {
        // VPS with correct count
        $correctVps = VpsServer::factory()->create([
            'status' => 'active',
            'site_count' => 2,
        ]);

        Site::factory()->count(2)->create([
            'vps_id' => $correctVps->id,
            'status' => 'active',
        ]);

        // VPS with incorrect count
        $incorrectVps = VpsServer::factory()->create([
            'status' => 'active',
            'site_count' => 5, // Says 5 but actually has 3
        ]);

        Site::factory()->count(3)->create([
            'vps_id' => $incorrectVps->id,
            'status' => 'active',
        ]);

        $results = $this->service->validateVpsSiteCounts();

        $this->assertEquals(1, $results->count());

        $mismatch = $results->first();
        $this->assertEquals($incorrectVps->id, $mismatch['vps']->id);
        $this->assertEquals(5, $mismatch['recorded_count']);
        $this->assertEquals(3, $mismatch['actual_count']);
        $this->assertEquals(-2, $mismatch['difference']);
    }

    public function test_it_finds_ssl_certificates_expiring_soon()
    {
        // Site with SSL not expiring soon
        Site::factory()->create([
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addMonths(3),
        ]);

        // Site with SSL expiring in 10 days
        $expiringSite = Site::factory()->create([
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addDays(10),
        ]);

        // Site with SSL already expired
        $expiredSite = Site::factory()->create([
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->subDays(1),
        ]);

        // Site without SSL
        Site::factory()->create([
            'ssl_enabled' => false,
        ]);

        $results = $this->service->findSslExpiringSoon(30);

        // Should only find the one expiring in 10 days
        $this->assertEquals(1, $results->count());
        $this->assertEquals($expiringSite->id, $results->first()['site']->id);
        $this->assertEquals(10, $results->first()['days_until_expiry']);
    }

    public function test_it_finds_orphaned_database_sites()
    {
        $vps = VpsServer::factory()->create([
            'status' => 'active',
        ]);

        // Site that exists in DB and on disk (mocked)
        $existingSite = Site::factory()->create([
            'vps_id' => $vps->id,
            'status' => 'active',
            'domain' => 'existing.com',
        ]);

        // Site that exists in DB but not on disk (orphaned)
        $orphanedSite = Site::factory()->create([
            'vps_id' => $vps->id,
            'status' => 'active',
            'domain' => 'orphaned.com',
        ]);

        // Mock VPS provider to return directory exists for one site but not the other
        $this->vpsProvider->shouldReceive('executeCommand')
            ->with($vps->id, Mockery::pattern('/test -d.*existing\.com/'), 30)
            ->andReturn(new CommandResult(
                exitCode: 0,
                output: 'EXISTS',
                error: '',
                executionTime: 0.1,
                command: 'test'
            ));

        $this->vpsProvider->shouldReceive('executeCommand')
            ->with($vps->id, Mockery::pattern('/test -d.*orphaned\.com/'), 30)
            ->andReturn(new CommandResult(
                exitCode: 0,
                output: 'NOT_FOUND',
                error: '',
                executionTime: 0.1,
                command: 'test'
            ));

        $results = $this->service->findOrphanedDatabaseSites();

        $this->assertEquals(1, $results->count());
        $this->assertEquals($orphanedSite->id, $results->first()['site']->id);
        $this->assertEquals('orphaned.com', $results->first()['site']->domain);
    }

    public function test_it_finds_orphaned_disk_sites()
    {
        $vps = VpsServer::factory()->create([
            'status' => 'active',
        ]);

        // Site that exists in both DB and disk
        $existingSite = Site::factory()->create([
            'vps_id' => $vps->id,
            'domain' => 'existing.com',
        ]);

        // Mock VPS provider to return site directories
        // One exists in DB (existing.com), one doesn't (orphaned.com)
        $this->vpsProvider->shouldReceive('executeCommand')
            ->with($vps->id, Mockery::pattern('/find.*www/'), 60)
            ->andReturn(new CommandResult(
                exitCode: 0,
                output: "/var/www/existing.com\n/var/www/orphaned.com",
                error: '',
                executionTime: 0.2,
                command: 'find'
            ));

        $results = $this->service->findOrphanedDiskSites();

        $this->assertEquals(1, $results->count());
        $this->assertEquals('orphaned.com', $results->first()['domain']);
        $this->assertEquals('/var/www/orphaned.com', $results->first()['path']);
    }

    public function test_it_handles_quick_check_mode()
    {
        $vps = VpsServer::factory()->create([
            'status' => 'active',
            'site_count' => 1,
        ]);

        Site::factory()->create([
            'vps_id' => $vps->id,
            'status' => 'active',
        ]);

        // Quick check should not make any SSH calls
        $this->vpsProvider->shouldNotReceive('executeCommand');

        $results = $this->service->detectIncoherencies(quickCheck: true);

        // Quick check should still run database checks
        $this->assertIsArray($results);
        $this->assertArrayHasKey('orphaned_backups', $results);
        $this->assertArrayHasKey('incorrect_vps_counts', $results);

        // But should skip disk checks
        $this->assertEquals(0, $results['orphaned_database_sites']->count());
        $this->assertEquals(0, $results['orphaned_disk_sites']->count());

        // Summary should indicate quick check
        $this->assertEquals('quick', $results['summary']['check_type']);
    }

    public function test_it_handles_full_check_mode()
    {
        $vps = VpsServer::factory()->create([
            'status' => 'active',
            'site_count' => 0,
        ]);

        // Mock SSH calls for disk checks
        $this->vpsProvider->shouldReceive('executeCommand')
            ->with($vps->id, Mockery::pattern('/find.*www/'), 60)
            ->andReturn(new CommandResult(
                exitCode: 0,
                output: '',
                error: '',
                executionTime: 0.2,
                command: 'find'
            ));

        $results = $this->service->detectIncoherencies(quickCheck: false);

        // Full check should include all checks
        $this->assertIsArray($results);
        $this->assertArrayHasKey('orphaned_database_sites', $results);
        $this->assertArrayHasKey('orphaned_disk_sites', $results);
        $this->assertArrayHasKey('orphaned_backups', $results);
        $this->assertArrayHasKey('incorrect_vps_counts', $results);

        // Summary should indicate full check
        $this->assertEquals('full', $results['summary']['check_type']);
    }

    public function test_it_includes_execution_time_in_results()
    {
        $results = $this->service->detectIncoherencies(quickCheck: true);

        $this->assertArrayHasKey('summary', $results);
        $this->assertArrayHasKey('execution_time_ms', $results['summary']);
        $this->assertIsFloat($results['summary']['execution_time_ms']);
        $this->assertGreaterThan(0, $results['summary']['execution_time_ms']);
    }

    public function test_it_handles_vps_connection_failures_gracefully()
    {
        $vps = VpsServer::factory()->create([
            'status' => 'active',
        ]);

        $site = Site::factory()->create([
            'vps_id' => $vps->id,
            'status' => 'active',
            'domain' => 'test.com',
        ]);

        // Mock VPS provider to throw exception
        $this->vpsProvider->shouldReceive('executeCommand')
            ->andThrow(new \RuntimeException('SSH connection failed'));

        // Should not throw, but log and continue
        $results = $this->service->findOrphanedDatabaseSites();

        // Should return empty results for failed connections
        $this->assertEquals(0, $results->count());
    }

    public function test_it_excludes_system_directories_from_orphaned_disk_sites()
    {
        $vps = VpsServer::factory()->create([
            'status' => 'active',
        ]);

        // Mock VPS provider to return system directories
        $this->vpsProvider->shouldReceive('executeCommand')
            ->with($vps->id, Mockery::pattern('/find.*www/'), 60)
            ->andReturn(new CommandResult(
                exitCode: 0,
                output: "/var/www/html\n/var/www/default\n/var/www/localhost\n/var/www/realsite.com",
                error: '',
                executionTime: 0.2,
                command: 'find'
            ));

        $results = $this->service->findOrphanedDiskSites();

        // Should only find realsite.com, not system directories
        $this->assertEquals(1, $results->count());
        $this->assertEquals('realsite.com', $results->first()['domain']);
    }

    public function test_it_only_checks_active_sites_for_orphaned_database_check()
    {
        $vps = VpsServer::factory()->create([
            'status' => 'active',
        ]);

        // Create sites with various statuses
        $activeSite = Site::factory()->create([
            'vps_id' => $vps->id,
            'status' => 'active',
            'domain' => 'active.com',
        ]);

        $deletingSite = Site::factory()->create([
            'vps_id' => $vps->id,
            'status' => 'deleting',
            'domain' => 'deleting.com',
        ]);

        $disabledSite = Site::factory()->create([
            'vps_id' => $vps->id,
            'status' => 'disabled',
            'domain' => 'disabled.com',
        ]);

        // Should only check active and creating sites
        $this->vpsProvider->shouldReceive('executeCommand')
            ->once() // Only for active site
            ->with($vps->id, Mockery::pattern('/test -d.*active\.com/'), 30)
            ->andReturn(new CommandResult(
                exitCode: 0,
                output: 'NOT_FOUND',
                error: '',
                executionTime: 0.1,
                command: 'test'
            ));

        $results = $this->service->findOrphanedDatabaseSites();

        $this->assertEquals(1, $results->count());
        $this->assertEquals('active.com', $results->first()['site']->domain);
    }
}
