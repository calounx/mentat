<?php

declare(strict_types=1);

namespace Tests\Unit\Services;

use App\Models\Site;
use App\Models\User;
use App\Services\Sites\SiteQuotaService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Unit tests for Site Quota Service
 */
class SiteQuotaServiceTest extends TestCase
{
    use RefreshDatabase;

    protected SiteQuotaService $service;

    protected function setUp(): void
    {
        parent::setUp();
        $this->service = new SiteQuotaService;
    }

    /**
     * Test basic tier quota enforcement
     */
    public function test_basic_tier_has_limited_quota(): void
    {
        $user = User::factory()->create();
        $tenant = $user->currentTenant();
        Site::factory()->count(3)->create(['tenant_id' => $tenant->id]);

        $this->assertFalse($this->service->canCreateSite($tenant));
        $this->assertEquals(3, $this->service->getSiteLimit($tenant));
        $this->assertEquals(0, $this->service->getRemainingQuota($tenant));
    }

    /**
     * Test professional tier has higher quota
     */
    public function test_professional_tier_has_higher_quota(): void
    {
        $user = User::factory()->create();
        $tenant = $user->currentTenant();
        Site::factory()->count(5)->create(['tenant_id' => $tenant->id]);

        $this->assertTrue($this->service->canCreateSite($tenant));
        $this->assertGreaterThan(5, $this->service->getSiteLimit($tenant));
    }

    /**
     * Test quota calculation is accurate
     */
    public function test_quota_calculation_is_accurate(): void
    {
        $user = User::factory()->create();
        $tenant = $user->currentTenant();
        Site::factory()->count(2)->create(['tenant_id' => $tenant->id]);

        $this->assertEquals(1, $this->service->getRemainingQuota($tenant));
        $this->assertTrue($this->service->canCreateSite($tenant));
    }

    /**
     * Test deleted sites don't count toward quota
     */
    public function test_deleted_sites_do_not_count_toward_quota(): void
    {
        $user = User::factory()->create();
        $tenant = $user->currentTenant();
        Site::factory()->count(2)->create(['tenant_id' => $tenant->id]);
        Site::factory()->count(2)->create([
            'tenant_id' => $tenant->id,
            'deleted_at' => now(),
        ]);

        $this->assertEquals(2, $this->service->getCurrentSiteCount($tenant));
        $this->assertTrue($this->service->canCreateSite($tenant));
    }
}
