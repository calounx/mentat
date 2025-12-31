<?php

namespace Tests\Unit;

use App\Models\Operation;
use App\Models\Organization;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\User;
use App\Models\UsageRecord;
use App\Models\VpsAllocation;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TenantScopeTest extends TestCase
{
    use RefreshDatabase;

    private User $userTenant1;
    private User $userTenant2;
    private Tenant $tenant1;
    private Tenant $tenant2;

    protected function setUp(): void
    {
        parent::setUp();

        // Create two organizations and tenants
        $org1 = Organization::factory()->create();
        $org2 = Organization::factory()->create();

        $this->tenant1 = Tenant::factory()->create(['organization_id' => $org1->id]);
        $this->tenant2 = Tenant::factory()->create(['organization_id' => $org2->id]);

        $org1->update(['default_tenant_id' => $this->tenant1->id]);
        $org2->update(['default_tenant_id' => $this->tenant2->id]);

        // Create users for each tenant
        $this->userTenant1 = User::factory()->create([
            'organization_id' => $org1->id,
            'role' => 'owner',
        ]);
        $this->userTenant2 = User::factory()->create([
            'organization_id' => $org2->id,
            'role' => 'owner',
        ]);
    }

    /**
     * Test that Site model automatically filters by tenant.
     */
    public function test_site_model_filters_by_authenticated_tenant(): void
    {
        // Create sites for both tenants
        $siteTenant1A = Site::factory()->create(['tenant_id' => $this->tenant1->id, 'domain' => 'site1a.com']);
        $siteTenant1B = Site::factory()->create(['tenant_id' => $this->tenant1->id, 'domain' => 'site1b.com']);
        $siteTenant2A = Site::factory()->create(['tenant_id' => $this->tenant2->id, 'domain' => 'site2a.com']);
        $siteTenant2B = Site::factory()->create(['tenant_id' => $this->tenant2->id, 'domain' => 'site2b.com']);

        // Authenticate as tenant 1 user
        $this->actingAs($this->userTenant1);

        // Query should only return tenant 1 sites
        $sites = Site::all();
        $this->assertCount(2, $sites);
        $this->assertTrue($sites->contains($siteTenant1A));
        $this->assertTrue($sites->contains($siteTenant1B));
        $this->assertFalse($sites->contains($siteTenant2A));
        $this->assertFalse($sites->contains($siteTenant2B));

        // Authenticate as tenant 2 user
        $this->actingAs($this->userTenant2);

        // Query should only return tenant 2 sites
        $sites = Site::all();
        $this->assertCount(2, $sites);
        $this->assertTrue($sites->contains($siteTenant2A));
        $this->assertTrue($sites->contains($siteTenant2B));
        $this->assertFalse($sites->contains($siteTenant1A));
        $this->assertFalse($sites->contains($siteTenant1B));
    }

    /**
     * Test that Site model scope works with where clauses.
     */
    public function test_site_model_scope_works_with_where_clauses(): void
    {
        Site::factory()->create(['tenant_id' => $this->tenant1->id, 'status' => 'active']);
        Site::factory()->create(['tenant_id' => $this->tenant1->id, 'status' => 'disabled']);
        Site::factory()->create(['tenant_id' => $this->tenant2->id, 'status' => 'active']);

        $this->actingAs($this->userTenant1);

        $activeSites = Site::where('status', 'active')->get();
        $this->assertCount(1, $activeSites);
        $this->assertEquals($this->tenant1->id, $activeSites->first()->tenant_id);
    }

    /**
     * Test that Site model scope works with find().
     */
    public function test_site_model_scope_works_with_find(): void
    {
        $siteTenant1 = Site::factory()->create(['tenant_id' => $this->tenant1->id]);
        $siteTenant2 = Site::factory()->create(['tenant_id' => $this->tenant2->id]);

        // Authenticate as tenant 1
        $this->actingAs($this->userTenant1);

        // Can find own site
        $found = Site::find($siteTenant1->id);
        $this->assertNotNull($found);
        $this->assertEquals($siteTenant1->id, $found->id);

        // Cannot find other tenant's site
        $notFound = Site::find($siteTenant2->id);
        $this->assertNull($notFound);
    }

    /**
     * Test that Site model scope works with first().
     */
    public function test_site_model_scope_works_with_first(): void
    {
        Site::factory()->create(['tenant_id' => $this->tenant2->id, 'domain' => 'first.com']);
        Site::factory()->create(['tenant_id' => $this->tenant1->id, 'domain' => 'second.com']);

        $this->actingAs($this->userTenant1);

        $first = Site::orderBy('domain')->first();
        $this->assertNotNull($first);
        $this->assertEquals('second.com', $first->domain);
        $this->assertEquals($this->tenant1->id, $first->tenant_id);
    }

    /**
     * Test that Operation model automatically filters by tenant.
     */
    public function test_operation_model_filters_by_authenticated_tenant(): void
    {
        // Create operations for both tenants
        $opTenant1A = Operation::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'user_id' => $this->userTenant1->id,
            'operation_type' => 'site_create',
        ]);
        $opTenant1B = Operation::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'user_id' => $this->userTenant1->id,
            'operation_type' => 'site_delete',
        ]);
        $opTenant2A = Operation::factory()->create([
            'tenant_id' => $this->tenant2->id,
            'user_id' => $this->userTenant2->id,
            'operation_type' => 'site_create',
        ]);

        // Authenticate as tenant 1 user
        $this->actingAs($this->userTenant1);

        // Query should only return tenant 1 operations
        $operations = Operation::all();
        $this->assertCount(2, $operations);
        $this->assertTrue($operations->contains($opTenant1A));
        $this->assertTrue($operations->contains($opTenant1B));
        $this->assertFalse($operations->contains($opTenant2A));

        // Authenticate as tenant 2 user
        $this->actingAs($this->userTenant2);

        // Query should only return tenant 2 operations
        $operations = Operation::all();
        $this->assertCount(1, $operations);
        $this->assertTrue($operations->contains($opTenant2A));
        $this->assertFalse($operations->contains($opTenant1A));
    }

    /**
     * Test that Operation model scope works with custom scopes.
     */
    public function test_operation_model_scope_works_with_custom_scopes(): void
    {
        Operation::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'user_id' => $this->userTenant1->id,
            'status' => 'pending',
        ]);
        Operation::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'user_id' => $this->userTenant1->id,
            'status' => 'completed',
        ]);
        Operation::factory()->create([
            'tenant_id' => $this->tenant2->id,
            'user_id' => $this->userTenant2->id,
            'status' => 'pending',
        ]);

        $this->actingAs($this->userTenant1);

        $pending = Operation::pending()->get();
        $this->assertCount(1, $pending);
        $this->assertEquals($this->tenant1->id, $pending->first()->tenant_id);
    }

    /**
     * Test that UsageRecord model automatically filters by tenant.
     */
    public function test_usage_record_model_filters_by_authenticated_tenant(): void
    {
        // Create usage records for both tenants
        $urTenant1A = UsageRecord::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'metric_type' => 'bandwidth',
            'quantity' => 100,
        ]);
        $urTenant1B = UsageRecord::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'metric_type' => 'storage',
            'quantity' => 50,
        ]);
        $urTenant2A = UsageRecord::factory()->create([
            'tenant_id' => $this->tenant2->id,
            'metric_type' => 'bandwidth',
            'quantity' => 200,
        ]);

        // Authenticate as tenant 1 user
        $this->actingAs($this->userTenant1);

        // Query should only return tenant 1 usage records
        $usageRecords = UsageRecord::all();
        $this->assertCount(2, $usageRecords);
        $this->assertTrue($usageRecords->contains($urTenant1A));
        $this->assertTrue($usageRecords->contains($urTenant1B));
        $this->assertFalse($usageRecords->contains($urTenant2A));

        // Authenticate as tenant 2 user
        $this->actingAs($this->userTenant2);

        // Query should only return tenant 2 usage records
        $usageRecords = UsageRecord::all();
        $this->assertCount(1, $usageRecords);
        $this->assertTrue($usageRecords->contains($urTenant2A));
    }

    /**
     * Test that UsageRecord model scope works with custom scopes.
     */
    public function test_usage_record_model_scope_works_with_custom_scopes(): void
    {
        UsageRecord::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'metric_type' => 'bandwidth',
        ]);
        UsageRecord::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'metric_type' => 'storage',
        ]);
        UsageRecord::factory()->create([
            'tenant_id' => $this->tenant2->id,
            'metric_type' => 'bandwidth',
        ]);

        $this->actingAs($this->userTenant1);

        $bandwidth = UsageRecord::forMetric('bandwidth')->get();
        $this->assertCount(1, $bandwidth);
        $this->assertEquals($this->tenant1->id, $bandwidth->first()->tenant_id);
    }

    /**
     * Test that VpsAllocation model automatically filters by tenant.
     */
    public function test_vps_allocation_model_filters_by_authenticated_tenant(): void
    {
        $vps1 = VpsServer::factory()->create();
        $vps2 = VpsServer::factory()->create();

        // Create allocations for both tenants
        $allocTenant1 = VpsAllocation::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'vps_id' => $vps1->id,
        ]);
        $allocTenant2 = VpsAllocation::factory()->create([
            'tenant_id' => $this->tenant2->id,
            'vps_id' => $vps2->id,
        ]);

        // Authenticate as tenant 1 user
        $this->actingAs($this->userTenant1);

        // Query should only return tenant 1 allocations
        $allocations = VpsAllocation::all();
        $this->assertCount(1, $allocations);
        $this->assertTrue($allocations->contains($allocTenant1));
        $this->assertFalse($allocations->contains($allocTenant2));

        // Authenticate as tenant 2 user
        $this->actingAs($this->userTenant2);

        // Query should only return tenant 2 allocations
        $allocations = VpsAllocation::all();
        $this->assertCount(1, $allocations);
        $this->assertTrue($allocations->contains($allocTenant2));
        $this->assertFalse($allocations->contains($allocTenant1));
    }

    /**
     * Test that count queries respect tenant scope.
     */
    public function test_count_queries_respect_tenant_scope(): void
    {
        Site::factory()->count(3)->create(['tenant_id' => $this->tenant1->id]);
        Site::factory()->count(2)->create(['tenant_id' => $this->tenant2->id]);

        $this->actingAs($this->userTenant1);
        $this->assertEquals(3, Site::count());

        $this->actingAs($this->userTenant2);
        $this->assertEquals(2, Site::count());
    }

    /**
     * Test that aggregate queries respect tenant scope.
     */
    public function test_aggregate_queries_respect_tenant_scope(): void
    {
        Site::factory()->create(['tenant_id' => $this->tenant1->id, 'storage_used_mb' => 100]);
        Site::factory()->create(['tenant_id' => $this->tenant1->id, 'storage_used_mb' => 200]);
        Site::factory()->create(['tenant_id' => $this->tenant2->id, 'storage_used_mb' => 500]);

        $this->actingAs($this->userTenant1);
        $this->assertEquals(300, Site::sum('storage_used_mb'));

        $this->actingAs($this->userTenant2);
        $this->assertEquals(500, Site::sum('storage_used_mb'));
    }

    /**
     * Test that exists queries respect tenant scope.
     */
    public function test_exists_queries_respect_tenant_scope(): void
    {
        $siteTenant1 = Site::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'domain' => 'unique-tenant1.com',
        ]);
        $siteTenant2 = Site::factory()->create([
            'tenant_id' => $this->tenant2->id,
            'domain' => 'unique-tenant2.com',
        ]);

        $this->actingAs($this->userTenant1);
        $this->assertTrue(Site::where('domain', 'unique-tenant1.com')->exists());
        $this->assertFalse(Site::where('domain', 'unique-tenant2.com')->exists());

        $this->actingAs($this->userTenant2);
        $this->assertTrue(Site::where('domain', 'unique-tenant2.com')->exists());
        $this->assertFalse(Site::where('domain', 'unique-tenant1.com')->exists());
    }

    /**
     * Test that relationships respect tenant scope.
     */
    public function test_relationships_respect_tenant_scope(): void
    {
        $vps = VpsServer::factory()->create();

        $siteTenant1 = Site::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'vps_id' => $vps->id,
        ]);
        $siteTenant2 = Site::factory()->create([
            'tenant_id' => $this->tenant2->id,
            'vps_id' => $vps->id,
        ]);

        $this->actingAs($this->userTenant1);

        // When loading sites through relationship from tenant, scope should apply
        $tenant1Sites = $this->tenant1->sites;
        $this->assertCount(1, $tenant1Sites);
        $this->assertTrue($tenant1Sites->contains($siteTenant1));
    }

    /**
     * Test that pagination respects tenant scope.
     */
    public function test_pagination_respects_tenant_scope(): void
    {
        Site::factory()->count(15)->create(['tenant_id' => $this->tenant1->id]);
        Site::factory()->count(10)->create(['tenant_id' => $this->tenant2->id]);

        $this->actingAs($this->userTenant1);
        $paginated = Site::paginate(10);
        $this->assertEquals(15, $paginated->total());
        $this->assertEquals(10, $paginated->count());

        $this->actingAs($this->userTenant2);
        $paginated = Site::paginate(10);
        $this->assertEquals(10, $paginated->total());
        $this->assertEquals(10, $paginated->count());
    }

    /**
     * Test that scope doesn't apply when user is not authenticated.
     */
    public function test_scope_does_not_apply_when_user_not_authenticated(): void
    {
        Site::factory()->create(['tenant_id' => $this->tenant1->id]);
        Site::factory()->create(['tenant_id' => $this->tenant2->id]);

        // When not authenticated, all sites should be visible (no scope applied)
        $sites = Site::all();
        $this->assertCount(2, $sites);
    }

    /**
     * Test that scope doesn't apply when user has no tenant.
     */
    public function test_scope_does_not_apply_when_user_has_no_tenant(): void
    {
        $userNoTenant = User::factory()->create(['organization_id' => null]);

        Site::factory()->create(['tenant_id' => $this->tenant1->id]);
        Site::factory()->create(['tenant_id' => $this->tenant2->id]);

        $this->actingAs($userNoTenant);

        // When user has no tenant, all sites should be visible
        $sites = Site::all();
        $this->assertCount(2, $sites);
    }

    /**
     * Test that update queries respect tenant scope.
     */
    public function test_update_queries_respect_tenant_scope(): void
    {
        $siteTenant1 = Site::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'status' => 'active',
        ]);
        $siteTenant2 = Site::factory()->create([
            'tenant_id' => $this->tenant2->id,
            'status' => 'active',
        ]);

        $this->actingAs($this->userTenant1);

        // Mass update should only affect tenant 1 sites
        Site::where('status', 'active')->update(['status' => 'disabled']);

        $siteTenant1->refresh();
        $siteTenant2->refresh();

        $this->assertEquals('disabled', $siteTenant1->status);
        $this->assertEquals('active', $siteTenant2->status); // Should remain unchanged
    }

    /**
     * Test that delete queries respect tenant scope.
     */
    public function test_delete_queries_respect_tenant_scope(): void
    {
        $siteTenant1 = Site::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'domain' => 'delete-test-1.com',
        ]);
        $siteTenant2 = Site::factory()->create([
            'tenant_id' => $this->tenant2->id,
            'domain' => 'delete-test-2.com',
        ]);

        $this->actingAs($this->userTenant1);

        // Mass delete should only affect tenant 1 sites
        Site::where('domain', 'like', 'delete-test-%')->delete();

        $this->assertSoftDeleted('sites', ['id' => $siteTenant1->id]);
        $this->assertDatabaseHas('sites', [
            'id' => $siteTenant2->id,
            'deleted_at' => null,
        ]);
    }

    /**
     * Test that withoutGlobalScope allows bypassing tenant scope.
     */
    public function test_without_global_scope_allows_bypassing_tenant_filter(): void
    {
        Site::factory()->create(['tenant_id' => $this->tenant1->id]);
        Site::factory()->create(['tenant_id' => $this->tenant2->id]);

        $this->actingAs($this->userTenant1);

        // With scope: should see only tenant 1
        $this->assertCount(1, Site::all());

        // Without scope: should see all
        $this->assertCount(2, Site::withoutGlobalScope('tenant')->get());
    }

    /**
     * Test tenant isolation prevents data leakage through complex queries.
     */
    public function test_complex_queries_cannot_leak_tenant_data(): void
    {
        $siteTenant1 = Site::factory()->create([
            'tenant_id' => $this->tenant1->id,
            'domain' => 'tenant1.com',
            'status' => 'active',
        ]);
        $siteTenant2 = Site::factory()->create([
            'tenant_id' => $this->tenant2->id,
            'domain' => 'tenant2.com',
            'status' => 'active',
        ]);

        $this->actingAs($this->userTenant1);

        // Complex query with OR conditions
        $sites = Site::where('status', 'active')
            ->where(function ($query) {
                $query->where('domain', 'tenant1.com')
                    ->orWhere('domain', 'tenant2.com');
            })
            ->get();

        // Should still only return tenant 1's site
        $this->assertCount(1, $sites);
        $this->assertEquals('tenant1.com', $sites->first()->domain);
    }

    /**
     * Test that tenant scope persists across query builder chains.
     */
    public function test_tenant_scope_persists_across_query_chains(): void
    {
        Site::factory()->create(['tenant_id' => $this->tenant1->id, 'status' => 'active', 'site_type' => 'wordpress']);
        Site::factory()->create(['tenant_id' => $this->tenant1->id, 'status' => 'disabled', 'site_type' => 'wordpress']);
        Site::factory()->create(['tenant_id' => $this->tenant2->id, 'status' => 'active', 'site_type' => 'wordpress']);

        $this->actingAs($this->userTenant1);

        $sites = Site::where('status', 'active')
            ->where('site_type', 'wordpress')
            ->orderBy('domain')
            ->get();

        $this->assertCount(1, $sites);
        foreach ($sites as $site) {
            $this->assertEquals($this->tenant1->id, $site->tenant_id);
        }
    }
}
