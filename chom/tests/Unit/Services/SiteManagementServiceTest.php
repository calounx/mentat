<?php

namespace Tests\Unit\Services;

use App\Events\SiteDeleted;
use App\Events\SiteDisabled;
use App\Events\SiteEnabled;
use App\Events\SiteProvisioned;
use App\Events\SiteUpdated;
use App\Jobs\DeleteSiteJob;
use App\Jobs\IssueSslCertificateJob;
use App\Jobs\ProvisionSiteJob;
use App\Jobs\UpdatePHPVersionJob;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\VpsServer;
use App\Repositories\SiteRepository;
use App\Repositories\TenantRepository;
use App\Repositories\VpsServerRepository;
use App\Services\QuotaService;
use App\Services\SiteManagementService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Queue;
use Illuminate\Validation\ValidationException;
use Mockery;
use Tests\TestCase;

class SiteManagementServiceTest extends TestCase
{
    use RefreshDatabase;

    private SiteManagementService $service;
    private $siteRepo;
    private $tenantRepo;
    private $vpsRepo;
    private $quotaService;

    protected function setUp(): void
    {
        parent::setUp();

        $this->siteRepo = Mockery::mock(SiteRepository::class);
        $this->tenantRepo = Mockery::mock(TenantRepository::class);
        $this->vpsRepo = Mockery::mock(VpsServerRepository::class);
        $this->quotaService = Mockery::mock(QuotaService::class);

        $this->service = new SiteManagementService(
            $this->siteRepo,
            $this->tenantRepo,
            $this->vpsRepo,
            $this->quotaService
        );

        Event::fake();
        Queue::fake();
    }

    protected function tearDown(): void
    {
        Mockery::close();
        parent::tearDown();
    }

    public function test_it_provisions_site_successfully()
    {
        $tenant = Tenant::factory()->make([
            'id' => 'tenant-123',
            'tier' => 'professional',
            'status' => 'active',
        ]);

        $vps = VpsServer::factory()->make([
            'id' => 'vps-123',
            'status' => 'active',
        ]);

        $site = Site::factory()->make([
            'id' => 'site-123',
            'tenant_id' => 'tenant-123',
            'vps_id' => 'vps-123',
            'domain' => 'test.com',
        ]);

        $this->tenantRepo->shouldReceive('findById')
            ->once()
            ->with('tenant-123')
            ->andReturn($tenant);

        $tenant->shouldReceive('isActive')
            ->once()
            ->andReturn(true);

        $this->quotaService->shouldReceive('canCreateSite')
            ->once()
            ->with('tenant-123')
            ->andReturn(true);

        $this->vpsRepo->shouldReceive('findAvailableVps')
            ->once()
            ->andReturn($vps);

        $this->siteRepo->shouldReceive('create')
            ->once()
            ->andReturn($site);

        $result = $this->service->provisionSite([
            'domain' => 'test.com',
            'site_type' => 'wordpress',
            'php_version' => '8.2',
        ], 'tenant-123');

        $this->assertNotNull($result);
        $this->assertEquals('site-123', $result->id);

        Queue::assertPushed(ProvisionSiteJob::class);
        Event::assertDispatched(SiteProvisioned::class);
    }

    public function test_it_throws_exception_when_tenant_inactive()
    {
        $tenant = Tenant::factory()->make([
            'status' => 'suspended',
        ]);

        $this->tenantRepo->shouldReceive('findById')
            ->once()
            ->andReturn($tenant);

        $tenant->shouldReceive('isActive')
            ->once()
            ->andReturn(false);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Tenant not found or inactive');

        $this->service->provisionSite([
            'domain' => 'test.com',
        ], 'tenant-123');
    }

    public function test_it_throws_exception_when_quota_exceeded()
    {
        $tenant = Tenant::factory()->make([
            'tier' => 'free',
            'status' => 'active',
        ]);

        $this->tenantRepo->shouldReceive('findById')
            ->once()
            ->andReturn($tenant);

        $tenant->shouldReceive('isActive')
            ->once()
            ->andReturn(true);

        $this->quotaService->shouldReceive('canCreateSite')
            ->once()
            ->andReturn(false);

        $this->quotaService->shouldReceive('checkSiteQuota')
            ->once()
            ->andReturn(['current' => 1, 'limit' => 1]);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Site quota exceeded');

        $this->service->provisionSite([
            'domain' => 'test.com',
        ], 'tenant-123');
    }

    public function test_it_throws_exception_when_no_vps_available()
    {
        $tenant = Tenant::factory()->make([
            'tier' => 'professional',
            'status' => 'active',
        ]);

        $this->tenantRepo->shouldReceive('findById')
            ->once()
            ->andReturn($tenant);

        $tenant->shouldReceive('isActive')
            ->once()
            ->andReturn(true);

        $this->quotaService->shouldReceive('canCreateSite')
            ->once()
            ->andReturn(true);

        $this->vpsRepo->shouldReceive('findAvailableVps')
            ->once()
            ->andReturn(null);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('No available VPS servers');

        $this->service->provisionSite([
            'domain' => 'test.com',
        ], 'tenant-123');
    }

    public function test_it_validates_domain_format()
    {
        $tenant = Tenant::factory()->make([
            'status' => 'active',
        ]);

        $this->tenantRepo->shouldReceive('findById')
            ->once()
            ->andReturn($tenant);

        $tenant->shouldReceive('isActive')
            ->once()
            ->andReturn(true);

        $this->quotaService->shouldReceive('canCreateSite')
            ->once()
            ->andReturn(true);

        $this->expectException(ValidationException::class);

        $this->service->provisionSite([
            'domain' => 'invalid domain',
        ], 'tenant-123');
    }

    public function test_it_updates_site_configuration_successfully()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'settings' => ['cache_enabled' => false],
        ]);

        $updatedSite = Site::factory()->make([
            'id' => 'site-123',
            'settings' => ['cache_enabled' => true, 'compression' => 'gzip'],
        ]);

        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->with('site-123')
            ->andReturn($site);

        $this->siteRepo->shouldReceive('update')
            ->once()
            ->andReturn($updatedSite);

        $result = $this->service->updateSiteConfiguration('site-123', [
            'settings' => ['cache_enabled' => true, 'compression' => 'gzip'],
        ]);

        $this->assertNotNull($result);
        Event::assertDispatched(SiteUpdated::class);
    }

    public function test_it_throws_exception_when_updating_nonexistent_site()
    {
        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->andReturn(null);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Site not found');

        $this->service->updateSiteConfiguration('site-123', [
            'settings' => ['test' => 'value'],
        ]);
    }

    public function test_it_changes_php_version_successfully()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'php_version' => '8.1',
        ]);

        $this->siteRepo->shouldReceive('findById')
            ->twice()
            ->andReturn($site);

        $this->siteRepo->shouldReceive('update')
            ->once()
            ->with('site-123', ['status' => 'updating'])
            ->andReturn($site);

        $result = $this->service->changePHPVersion('site-123', '8.2');

        $this->assertNotNull($result);
        Queue::assertPushed(UpdatePHPVersionJob::class);
    }

    public function test_it_returns_same_site_when_php_version_unchanged()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'php_version' => '8.2',
        ]);

        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->andReturn($site);

        $result = $this->service->changePHPVersion('site-123', '8.2');

        $this->assertEquals($site, $result);
        Queue::assertNotPushed(UpdatePHPVersionJob::class);
    }

    public function test_it_throws_exception_for_invalid_php_version()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'php_version' => '8.1',
        ]);

        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->andReturn($site);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Unsupported PHP version');

        $this->service->changePHPVersion('site-123', '9.0');
    }

    public function test_it_enables_ssl_successfully()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'ssl_enabled' => false,
            'domain' => 'test.com',
        ]);

        $this->siteRepo->shouldReceive('findById')
            ->twice()
            ->andReturn($site);

        $result = $this->service->enableSSL('site-123');

        $this->assertNotNull($result);
        Queue::assertPushed(IssueSslCertificateJob::class);
    }

    public function test_it_returns_same_site_when_ssl_already_enabled()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'ssl_enabled' => true,
        ]);

        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->andReturn($site);

        $result = $this->service->enableSSL('site-123');

        $this->assertEquals($site, $result);
        Queue::assertNotPushed(IssueSslCertificateJob::class);
    }

    public function test_it_disables_site_successfully()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'status' => 'active',
        ]);

        $disabledSite = Site::factory()->make([
            'id' => 'site-123',
            'status' => 'disabled',
        ]);

        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->andReturn($site);

        $this->siteRepo->shouldReceive('update')
            ->once()
            ->with('site-123', ['status' => 'disabled'])
            ->andReturn($disabledSite);

        $result = $this->service->disableSite('site-123', 'Maintenance');

        $this->assertEquals('disabled', $result->status);
        Event::assertDispatched(SiteDisabled::class);
    }

    public function test_it_returns_same_site_when_already_disabled()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'status' => 'disabled',
        ]);

        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->andReturn($site);

        $result = $this->service->disableSite('site-123');

        $this->assertEquals($site, $result);
    }

    public function test_it_enables_site_successfully()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'status' => 'disabled',
        ]);

        $enabledSite = Site::factory()->make([
            'id' => 'site-123',
            'status' => 'active',
        ]);

        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->andReturn($site);

        $this->siteRepo->shouldReceive('update')
            ->once()
            ->with('site-123', ['status' => 'active'])
            ->andReturn($enabledSite);

        $result = $this->service->enableSite('site-123');

        $this->assertEquals('active', $result->status);
        Event::assertDispatched(SiteEnabled::class);
    }

    public function test_it_deletes_site_successfully()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'domain' => 'test.com',
            'status' => 'active',
        ]);

        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->andReturn($site);

        $this->siteRepo->shouldReceive('update')
            ->once()
            ->with('site-123', ['status' => 'deleting'])
            ->andReturn($site);

        $result = $this->service->deleteSite('site-123');

        $this->assertTrue($result);
        Queue::assertPushed(DeleteSiteJob::class);
        Event::assertDispatched(SiteDeleted::class);
    }

    public function test_it_throws_exception_when_deleting_nonexistent_site()
    {
        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->andReturn(null);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Site not found');

        $this->service->deleteSite('site-123');
    }

    public function test_it_gets_site_metrics_successfully()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'domain' => 'test.com',
            'status' => 'active',
            'php_version' => '8.2',
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addMonths(2),
            'storage_used_mb' => 512,
            'created_at' => now()->subDays(30),
        ]);

        $backupMock = Mockery::mock('stdClass');
        $backupMock->shouldReceive('count')->andReturn(5);
        $backupMock->shouldReceive('latest->first')->andReturnNull();

        $site->shouldReceive('backups')->andReturn($backupMock);
        $site->shouldReceive('isSslExpiringSoon')->andReturn(false);

        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->andReturn($site);

        $result = $this->service->getSiteMetrics('site-123');

        $this->assertIsArray($result);
        $this->assertEquals('site-123', $result['site_id']);
        $this->assertEquals('test.com', $result['domain']);
        $this->assertEquals('active', $result['status']);
        $this->assertEquals('8.2', $result['php_version']);
        $this->assertTrue($result['ssl_enabled']);
        $this->assertEquals(512, $result['storage_used_mb']);
        $this->assertEquals(0.5, $result['storage_used_gb']);
        $this->assertEquals(5, $result['backups_count']);
        $this->assertEquals(30, $result['uptime_days']);
    }
}
