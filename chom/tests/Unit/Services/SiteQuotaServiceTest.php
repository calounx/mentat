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
 *
 * @package Tests\Unit\Services
 */
class SiteQuotaServiceTest extends TestCase
{
    use RefreshDatabase;

    protected SiteQuotaService $service;

    protected function setUp(): void
    {
        parent::setUp();
        $this->service = new SiteQuotaService();
    }

    /**
     * Test basic tier quota enforcement
     *
     * @return void
     */
    public function test_basic_tier_has_limited_quota(): void
    {
        $user = User::factory()->create(['subscription_tier' => 'basic']);
        Site::factory()->count(3)->create(['user_id' => $user->id]);

        $this->assertFalse($this->service->canCreateSite($user));
        $this->assertEquals(3, $this->service->getSiteLimit($user));
        $this->assertEquals(0, $this->service->getRemainingQuota($user));
    }

    /**
     * Test professional tier has higher quota
     *
     * @return void
     */
    public function test_professional_tier_has_higher_quota(): void
    {
        $user = User::factory()->create(['subscription_tier' => 'professional']);
        Site::factory()->count(5)->create(['user_id' => $user->id]);

        $this->assertTrue($this->service->canCreateSite($user));
        $this->assertGreaterThan(5, $this->service->getSiteLimit($user));
    }

    /**
     * Test quota calculation is accurate
     *
     * @return void
     */
    public function test_quota_calculation_is_accurate(): void
    {
        $user = User::factory()->create(['subscription_tier' => 'basic']);
        Site::factory()->count(2)->create(['user_id' => $user->id]);

        $this->assertEquals(1, $this->service->getRemainingQuota($user));
        $this->assertTrue($this->service->canCreateSite($user));
    }

    /**
     * Test deleted sites don't count toward quota
     *
     * @return void
     */
    public function test_deleted_sites_do_not_count_toward_quota(): void
    {
        $user = User::factory()->create(['subscription_tier' => 'basic']);
        Site::factory()->count(2)->create(['user_id' => $user->id]);
        Site::factory()->count(2)->create([
            'user_id' => $user->id,
            'deleted_at' => now(),
        ]);

        $this->assertEquals(2, $this->service->getCurrentSiteCount($user));
        $this->assertTrue($this->service->canCreateSite($user));
    }
}
