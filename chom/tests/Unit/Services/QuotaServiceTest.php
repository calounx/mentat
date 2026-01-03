<?php

namespace Tests\Unit\Services;

use App\Events\QuotaExceeded;
use App\Events\QuotaWarning;
use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\Tenant;
use App\Repositories\BackupRepository;
use App\Repositories\SiteRepository;
use App\Repositories\TenantRepository;
use App\Services\QuotaService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Event;
use Mockery;
use Tests\TestCase;

class QuotaServiceTest extends TestCase
{
    use RefreshDatabase;

    private QuotaService $service;
    private $tenantRepo;
    private $siteRepo;
    private $backupRepo;

    protected function setUp(): void
    {
        parent::setUp();

        $this->tenantRepo = Mockery::mock(TenantRepository::class);
        $this->siteRepo = Mockery::mock(SiteRepository::class);
        $this->backupRepo = Mockery::mock(BackupRepository::class);

        $this->service = new QuotaService(
            $this->tenantRepo,
            $this->siteRepo,
            $this->backupRepo
        );

        Event::fake();
        Cache::flush();
    }

    protected function tearDown(): void
    {
        Mockery::close();
        parent::tearDown();
    }

    public function test_it_checks_site_quota_under_limit()
    {
        $tenant = Tenant::factory()->make([
            'id' => 'tenant-123',
            'tier' => 'professional',
        ]);

        $this->tenantRepo->shouldReceive('findById')
            ->once()
            ->andReturn($tenant);

        $this->siteRepo->shouldReceive('countByTenantId')
            ->once()
            ->with('tenant-123')
            ->andReturn(5);

        $result = $this->service->checkSiteQuota('tenant-123');

        $this->assertTrue($result['available']);
        $this->assertEquals(5, $result['current']);
        $this->assertEquals(20, $result['limit']);
        $this->assertEquals(25.0, $result['percentage']);

        Event::assertNotDispatched(QuotaWarning::class);
        Event::assertNotDispatched(QuotaExceeded::class);
    }

    public function test_it_checks_site_quota_at_warning_threshold()
    {
        $tenant = Tenant::factory()->make([
            'id' => 'tenant-123',
            'tier' => 'starter',
        ]);

        $this->tenantRepo->shouldReceive('findById')
            ->once()
            ->andReturn($tenant);

        $this->siteRepo->shouldReceive('countByTenantId')
            ->once()
            ->andReturn(4);

        $result = $this->service->checkSiteQuota('tenant-123');

        $this->assertTrue($result['available']);
        $this->assertEquals(4, $result['current']);
        $this->assertEquals(5, $result['limit']);
        $this->assertEquals(80.0, $result['percentage']);

        Event::assertDispatched(QuotaWarning::class);
    }

    public function test_it_checks_site_quota_exceeded()
    {
        $tenant = Tenant::factory()->make([
            'id' => 'tenant-123',
            'tier' => 'free',
        ]);

        $this->tenantRepo->shouldReceive('findById')
            ->once()
            ->andReturn($tenant);

        $this->siteRepo->shouldReceive('countByTenantId')
            ->once()
            ->andReturn(1);

        $result = $this->service->checkSiteQuota('tenant-123');

        $this->assertFalse($result['available']);
        $this->assertEquals(1, $result['current']);
        $this->assertEquals(1, $result['limit']);
        $this->assertEquals(100.0, $result['percentage']);

        Event::assertDispatched(QuotaExceeded::class);
    }

    public function test_it_checks_site_quota_unlimited_tier()
    {
        $tenant = Tenant::factory()->make([
            'id' => 'tenant-123',
            'tier' => 'enterprise',
        ]);

        $this->tenantRepo->shouldReceive('findById')
            ->once()
            ->andReturn($tenant);

        $this->siteRepo->shouldReceive('countByTenantId')
            ->once()
            ->andReturn(100);

        $result = $this->service->checkSiteQuota('tenant-123');

        $this->assertTrue($result['available']);
        $this->assertEquals(100, $result['current']);
        $this->assertEquals(-1, $result['limit']);
        $this->assertEquals('Unlimited', $result['limit_display']);
        $this->assertEquals(0, $result['percentage']);
    }

    public function test_it_checks_storage_quota_available()
    {
        $tenant = Tenant::factory()->make([
            'id' => 'tenant-123',
            'tier' => 'professional',
        ]);

        $this->tenantRepo->shouldReceive('findById')
            ->once()
            ->andReturn($tenant);

        $this->siteRepo->shouldReceive('getTotalStorageByTenantId')
            ->once()
            ->andReturn(10240);

        $result = $this->service->checkStorageQuota('tenant-123');

        $this->assertTrue($result['available']);
        $this->assertEquals(10240, $result['used_mb']);
        $this->assertEquals(10.0, $result['used_gb']);
        $this->assertEquals(102400, $result['limit_mb']);
        $this->assertEquals(100, $result['limit_gb']);
        $this->assertEquals('100 GB', $result['limit_display']);
    }

    public function test_it_checks_storage_quota_exceeded()
    {
        $tenant = Tenant::factory()->make([
            'id' => 'tenant-123',
            'tier' => 'free',
        ]);

        $this->tenantRepo->shouldReceive('findById')
            ->once()
            ->andReturn($tenant);

        $this->siteRepo->shouldReceive('getTotalStorageByTenantId')
            ->once()
            ->andReturn(1100);

        $result = $this->service->checkStorageQuota('tenant-123');

        $this->assertFalse($result['available']);
        $this->assertEquals(1100, $result['used_mb']);
        $this->assertEquals(1024, $result['limit_mb']);

        Event::assertDispatched(QuotaExceeded::class);
    }

    public function test_it_checks_backup_quota_available()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'tenant_id' => 'tenant-123',
        ]);

        $tenant = Tenant::factory()->make([
            'id' => 'tenant-123',
            'tier' => 'professional',
        ]);

        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->andReturn($site);

        $this->tenantRepo->shouldReceive('findById')
            ->once()
            ->andReturn($tenant);

        $this->backupRepo->shouldReceive('countBySiteId')
            ->once()
            ->andReturn(10);

        $result = $this->service->checkBackupQuota('site-123');

        $this->assertTrue($result['available']);
        $this->assertEquals(10, $result['current']);
        $this->assertEquals(20, $result['limit']);
        $this->assertEquals(50.0, $result['percentage']);
    }

    public function test_it_checks_backup_quota_exceeded()
    {
        $site = Site::factory()->make([
            'id' => 'site-123',
            'tenant_id' => 'tenant-123',
        ]);

        $tenant = Tenant::factory()->make([
            'id' => 'tenant-123',
            'tier' => 'free',
        ]);

        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->andReturn($site);

        $this->tenantRepo->shouldReceive('findById')
            ->once()
            ->andReturn($tenant);

        $this->backupRepo->shouldReceive('countBySiteId')
            ->once()
            ->andReturn(3);

        $result = $this->service->checkBackupQuota('site-123');

        $this->assertFalse($result['available']);
        $this->assertEquals(3, $result['current']);
        $this->assertEquals(3, $result['limit']);
    }

    public function test_it_returns_true_when_site_can_be_created()
    {
        $tenant = Tenant::factory()->make([
            'tier' => 'professional',
        ]);

        $this->tenantRepo->shouldReceive('findById')
            ->once()
            ->andReturn($tenant);

        $this->siteRepo->shouldReceive('countByTenantId')
            ->once()
            ->andReturn(5);

        $result = $this->service->canCreateSite('tenant-123');

        $this->assertTrue($result);
    }

    public function test_it_returns_false_when_site_cannot_be_created()
    {
        $tenant = Tenant::factory()->make([
            'tier' => 'free',
        ]);

        $this->tenantRepo->shouldReceive('findById')
            ->once()
            ->andReturn($tenant);

        $this->siteRepo->shouldReceive('countByTenantId')
            ->once()
            ->andReturn(1);

        $result = $this->service->canCreateSite('tenant-123');

        $this->assertFalse($result);
    }

    public function test_it_returns_true_when_backup_can_be_created()
    {
        $site = Site::factory()->make([
            'tenant_id' => 'tenant-123',
        ]);

        $tenant = Tenant::factory()->make([
            'tier' => 'professional',
        ]);

        $this->siteRepo->shouldReceive('findById')
            ->once()
            ->andReturn($site);

        $this->tenantRepo->shouldReceive('findById')
            ->once()
            ->andReturn($tenant);

        $this->backupRepo->shouldReceive('countBySiteId')
            ->once()
            ->andReturn(5);

        $result = $this->service->canCreateBackup('site-123');

        $this->assertTrue($result);
    }

    public function test_it_gets_tenant_usage_statistics()
    {
        $tenant = Tenant::factory()->make([
            'id' => 'tenant-123',
            'tier' => 'professional',
        ]);

        $sites = collect([
            Site::factory()->make(['id' => 'site-1']),
            Site::factory()->make(['id' => 'site-2']),
        ]);

        $this->tenantRepo->shouldReceive('findById')
            ->times(3)
            ->andReturn($tenant);

        $this->siteRepo->shouldReceive('countByTenantId')
            ->once()
            ->andReturn(2);

        $this->siteRepo->shouldReceive('getTotalStorageByTenantId')
            ->once()
            ->andReturn(5120);

        $this->siteRepo->shouldReceive('findByTenantId')
            ->once()
            ->andReturn($sites);

        $this->backupRepo->shouldReceive('countBySiteId')
            ->with('site-1')
            ->once()
            ->andReturn(5);

        $this->backupRepo->shouldReceive('countBySiteId')
            ->with('site-2')
            ->once()
            ->andReturn(3);

        $result = $this->service->getTenantUsage('tenant-123');

        $this->assertIsArray($result);
        $this->assertEquals('tenant-123', $result['tenant_id']);
        $this->assertEquals('professional', $result['tier']);
        $this->assertEquals(2, $result['sites']['current']);
        $this->assertEquals(5120, $result['storage']['used_mb']);
        $this->assertEquals(8, $result['backups']['total']);
    }

    public function test_it_caches_quota_checks()
    {
        $tenant = Tenant::factory()->make([
            'tier' => 'professional',
        ]);

        $this->tenantRepo->shouldReceive('findById')
            ->once()
            ->andReturn($tenant);

        $this->siteRepo->shouldReceive('countByTenantId')
            ->once()
            ->andReturn(5);

        $result1 = $this->service->checkSiteQuota('tenant-123');
        $result2 = $this->service->checkSiteQuota('tenant-123');

        $this->assertEquals($result1, $result2);
    }

    public function test_it_gets_quota_limits_by_tier()
    {
        $freeLimits = $this->service->getQuotaLimitsByTier('free');
        $this->assertEquals(1, $freeLimits['max_sites']);

        $proLimits = $this->service->getQuotaLimitsByTier('professional');
        $this->assertEquals(20, $proLimits['max_sites']);

        $enterpriseLimits = $this->service->getQuotaLimitsByTier('enterprise');
        $this->assertEquals(-1, $enterpriseLimits['max_sites']);
    }

    public function test_it_returns_starter_limits_for_unknown_tier()
    {
        $limits = $this->service->getQuotaLimitsByTier('unknown_tier');

        $this->assertEquals(5, $limits['max_sites']);
        $this->assertEquals(10, $limits['max_storage_gb']);
    }
}
