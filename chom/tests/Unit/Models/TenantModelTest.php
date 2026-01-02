<?php

namespace Tests\Unit\Models;

use App\Models\Operation;
use App\Models\Organization;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\TierLimit;
use App\Models\UsageRecord;
use App\Models\VpsAllocation;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class TenantModelTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function it_has_correct_fillable_attributes()
    {
        $fillable = [
            'organization_id',
            'name',
            'slug',
            'tier',
            'status',
            'settings',
            'metrics_retention_days',
            'cached_storage_mb',
            'cached_sites_count',
            'cached_at',
        ];

        $tenant = new Tenant();
        $this->assertEquals($fillable, $tenant->getFillable());
    }

    #[Test]
    public function it_casts_attributes_correctly()
    {
        $tenant = Tenant::factory()->create([
            'settings' => ['key' => 'value'],
            'cached_at' => now(),
        ]);

        $this->assertIsArray($tenant->settings);
        $this->assertEquals(['key' => 'value'], $tenant->settings);
        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $tenant->cached_at);
    }

    #[Test]
    public function it_belongs_to_an_organization()
    {
        $organization = Organization::factory()->create();
        $tenant = Tenant::factory()->create(['organization_id' => $organization->id]);

        $this->assertInstanceOf(Organization::class, $tenant->organization);
        $this->assertEquals($organization->id, $tenant->organization->id);
    }

    #[Test]
    public function it_has_many_sites()
    {
        $tenant = Tenant::factory()->create();
        Site::factory()->count(4)->create(['tenant_id' => $tenant->id]);

        $this->assertInstanceOf(\Illuminate\Database\Eloquent\Collection::class, $tenant->sites);
        $this->assertCount(4, $tenant->sites);
        $this->assertInstanceOf(Site::class, $tenant->sites->first());
    }

    #[Test]
    public function it_has_many_vps_allocations()
    {
        $tenant = Tenant::factory()->create();
        VpsAllocation::factory()->count(2)->create(['tenant_id' => $tenant->id]);

        $this->assertInstanceOf(\Illuminate\Database\Eloquent\Collection::class, $tenant->vpsAllocations);
        $this->assertCount(2, $tenant->vpsAllocations);
        $this->assertInstanceOf(VpsAllocation::class, $tenant->vpsAllocations->first());
    }

    #[Test]
    public function it_has_many_vps_servers_through_allocations()
    {
        $tenant = Tenant::factory()->create();
        $vpsServer1 = VpsServer::factory()->create();
        $vpsServer2 = VpsServer::factory()->create();

        VpsAllocation::factory()->create([
            'tenant_id' => $tenant->id,
            'vps_id' => $vpsServer1->id,
        ]);
        VpsAllocation::factory()->create([
            'tenant_id' => $tenant->id,
            'vps_id' => $vpsServer2->id,
        ]);

        $this->assertInstanceOf(\Illuminate\Database\Eloquent\Collection::class, $tenant->vpsServers);
        $this->assertCount(2, $tenant->vpsServers);
        $this->assertInstanceOf(VpsServer::class, $tenant->vpsServers->first());
    }

    #[Test]
    public function it_has_many_usage_records()
    {
        $tenant = Tenant::factory()->create();
        UsageRecord::factory()->count(5)->create(['tenant_id' => $tenant->id]);

        $this->assertInstanceOf(\Illuminate\Database\Eloquent\Collection::class, $tenant->usageRecords);
        $this->assertCount(5, $tenant->usageRecords);
        $this->assertInstanceOf(UsageRecord::class, $tenant->usageRecords->first());
    }

    #[Test]
    public function it_has_many_operations()
    {
        $tenant = Tenant::factory()->create();
        Operation::factory()->count(3)->create(['tenant_id' => $tenant->id]);

        $this->assertInstanceOf(\Illuminate\Database\Eloquent\Collection::class, $tenant->operations);
        $this->assertCount(3, $tenant->operations);
        $this->assertInstanceOf(Operation::class, $tenant->operations->first());
    }

    #[Test]
    public function it_has_tier_limits_relationship()
    {
        $tierLimit = TierLimit::factory()->create(['tier' => 'pro']);
        $tenant = Tenant::factory()->create(['tier' => 'pro']);

        $this->assertInstanceOf(TierLimit::class, $tenant->tierLimits);
        $this->assertEquals('pro', $tenant->tierLimits->tier);
    }

    #[Test]
    public function it_checks_if_tenant_is_active()
    {
        $activeTenant = Tenant::factory()->create(['status' => 'active']);
        $suspendedTenant = Tenant::factory()->create(['status' => 'suspended']);

        $this->assertTrue($activeTenant->isActive());
        $this->assertFalse($suspendedTenant->isActive());
    }

    #[Test]
    public function it_gets_max_sites_from_tier_limits()
    {
        $tierLimit = TierLimit::factory()->create([
            'tier' => 'pro',
            'max_sites' => 25,
        ]);
        $tenant = Tenant::factory()->create(['tier' => 'pro']);

        $this->assertEquals(25, $tenant->getMaxSites());
    }

    #[Test]
    public function it_returns_default_max_sites_when_no_tier_limits()
    {
        $tenant = Tenant::factory()->create(['tier' => 'nonexistent']);

        $this->assertEquals(5, $tenant->getMaxSites());
    }

    #[Test]
    public function it_checks_if_tenant_can_create_site()
    {
        $tierLimit = TierLimit::factory()->create([
            'tier' => 'starter',
            'max_sites' => 3,
        ]);
        $tenant = Tenant::factory()->create(['tier' => 'starter']);

        // No sites yet
        $this->assertTrue($tenant->canCreateSite());

        // Create 3 sites (at limit)
        Site::factory()->count(3)->create(['tenant_id' => $tenant->id]);
        $tenant->refresh();

        $this->assertFalse($tenant->canCreateSite());
    }

    #[Test]
    public function it_allows_unlimited_sites_when_max_sites_is_negative_one()
    {
        $tierLimit = TierLimit::factory()->create([
            'tier' => 'enterprise',
            'max_sites' => -1,
        ]);
        $tenant = Tenant::factory()->create(['tier' => 'enterprise']);

        Site::factory()->count(100)->create(['tenant_id' => $tenant->id]);

        $this->assertTrue($tenant->canCreateSite());
    }

    #[Test]
    public function it_gets_cached_site_count()
    {
        $tenant = Tenant::factory()->create([
            'cached_sites_count' => 10,
            'cached_at' => now(),
        ]);

        $this->assertEquals(10, $tenant->getSiteCount());
    }

    #[Test]
    public function it_updates_stale_cache_automatically()
    {
        $tenant = Tenant::factory()->create([
            'cached_sites_count' => 0,
            'cached_at' => now()->subMinutes(10), // Stale cache
        ]);

        Site::factory()->count(5)->create(['tenant_id' => $tenant->id]);

        // Should trigger cache update
        $count = $tenant->getSiteCount();

        $this->assertEquals(5, $count);
        $this->assertTrue($tenant->cached_at->diffInMinutes(now()) < 1);
    }

    #[Test]
    public function it_gets_cached_storage_used()
    {
        $tenant = Tenant::factory()->create([
            'cached_storage_mb' => 500,
            'cached_at' => now(),
        ]);

        $this->assertEquals(500, $tenant->getStorageUsedMb());
    }

    #[Test]
    public function it_updates_cached_stats()
    {
        $tenant = Tenant::factory()->create();
        Site::factory()->count(3)->create([
            'tenant_id' => $tenant->id,
            'storage_used_mb' => 100,
        ]);

        $tenant->updateCachedStats();
        $tenant->refresh();

        $this->assertEquals(3, $tenant->cached_sites_count);
        $this->assertEquals(300, $tenant->cached_storage_mb);
        $this->assertNotNull($tenant->cached_at);
    }

    #[Test]
    public function it_uses_uuid_as_primary_key()
    {
        $tenant = Tenant::factory()->create();

        $this->assertIsString($tenant->id);
        $this->assertEquals(36, strlen($tenant->id));
        $this->assertMatchesRegularExpression(
            '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i',
            $tenant->id
        );
    }

    #[Test]
    public function it_has_timestamps()
    {
        $tenant = Tenant::factory()->create();

        $this->assertNotNull($tenant->created_at);
        $this->assertNotNull($tenant->updated_at);
        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $tenant->created_at);
        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $tenant->updated_at);
    }
}
