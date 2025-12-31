<?php

namespace Tests\Feature;

use App\Models\Operation;
use App\Models\Site;
use App\Models\UsageRecord;
use App\Models\VpsAllocation;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\WithTenantIsolation;
use Tests\TestCase;

/**
 * Integration tests for tenant isolation across the entire application.
 *
 * These tests verify that tenant boundaries are properly enforced
 * across all models, controllers, and business logic.
 */
class TenantIsolationIntegrationTest extends TestCase
{
    use RefreshDatabase, WithTenantIsolation;

    /**
     * Test complete isolation across all tenant-scoped models.
     */
    public function test_complete_isolation_across_all_models(): void
    {
        // Create two tenants
        [$tenant1, $tenant2] = $this->createMultipleTenants(2);

        // Create VPS servers (shared resource, not tenant-scoped)
        $vps1 = VpsServer::factory()->create(['allocation_mode' => 'shared']);
        $vps2 = VpsServer::factory()->create(['allocation_mode' => 'shared']);

        // Create data for tenant 1
        $site1 = Site::factory()->create([
            'tenant_id' => $tenant1['tenant']->id,
            'vps_id' => $vps1->id,
        ]);
        $operation1 = Operation::factory()->create([
            'tenant_id' => $tenant1['tenant']->id,
            'user_id' => $tenant1['user']->id,
        ]);
        $usage1 = UsageRecord::factory()->create([
            'tenant_id' => $tenant1['tenant']->id,
        ]);
        $allocation1 = VpsAllocation::factory()->create([
            'tenant_id' => $tenant1['tenant']->id,
            'vps_id' => $vps1->id,
        ]);

        // Create data for tenant 2
        $site2 = Site::factory()->create([
            'tenant_id' => $tenant2['tenant']->id,
            'vps_id' => $vps2->id,
        ]);
        $operation2 = Operation::factory()->create([
            'tenant_id' => $tenant2['tenant']->id,
            'user_id' => $tenant2['user']->id,
        ]);
        $usage2 = UsageRecord::factory()->create([
            'tenant_id' => $tenant2['tenant']->id,
        ]);
        $allocation2 = VpsAllocation::factory()->create([
            'tenant_id' => $tenant2['tenant']->id,
            'vps_id' => $vps2->id,
        ]);

        // Verify tenant 1 isolation
        $this->assertCanAccessSameTenant($tenant1['user'], $site1);
        $this->assertCanAccessSameTenant($tenant1['user'], $operation1);
        $this->assertCanAccessSameTenant($tenant1['user'], $usage1);
        $this->assertCanAccessSameTenant($tenant1['user'], $allocation1);

        $this->assertCannotAccessCrossTenant($tenant1['user'], $site2);
        $this->assertCannotAccessCrossTenant($tenant1['user'], $operation2);
        $this->assertCannotAccessCrossTenant($tenant1['user'], $usage2);
        $this->assertCannotAccessCrossTenant($tenant1['user'], $allocation2);

        // Verify tenant 2 isolation
        $this->assertCanAccessSameTenant($tenant2['user'], $site2);
        $this->assertCanAccessSameTenant($tenant2['user'], $operation2);
        $this->assertCanAccessSameTenant($tenant2['user'], $usage2);
        $this->assertCanAccessSameTenant($tenant2['user'], $allocation2);

        $this->assertCannotAccessCrossTenant($tenant2['user'], $site1);
        $this->assertCannotAccessCrossTenant($tenant2['user'], $operation1);
        $this->assertCannotAccessCrossTenant($tenant2['user'], $usage1);
        $this->assertCannotAccessCrossTenant($tenant2['user'], $allocation1);
    }

    /**
     * Test that Site model isolation works across complex queries.
     */
    public function test_site_model_isolation_with_complex_queries(): void
    {
        $crossTenantData = $this->createCrossTenantData(Site::class, [
            'status' => 'active',
        ]);

        $this->assertNoDataLeakage(Site::class, $crossTenantData);
    }

    /**
     * Test that Operation model isolation works across complex queries.
     */
    public function test_operation_model_isolation_with_complex_queries(): void
    {
        $tenantData = $this->createTenantWithUser();

        Operation::factory()->count(3)->create([
            'tenant_id' => $tenantData['tenant']->id,
            'user_id' => $tenantData['user']->id,
            'status' => 'pending',
        ]);

        $otherTenantData = $this->createTenantWithUser();
        Operation::factory()->count(5)->create([
            'tenant_id' => $otherTenantData['tenant']->id,
            'user_id' => $otherTenantData['user']->id,
            'status' => 'pending',
        ]);

        $this->actingAs($tenantData['user']);

        // Complex query with scopes
        $operations = Operation::pending()
            ->where('status', 'pending')
            ->orderBy('created_at', 'desc')
            ->get();

        $this->assertCount(3, $operations);
        foreach ($operations as $operation) {
            $this->assertEquals($tenantData['tenant']->id, $operation->tenant_id);
        }
    }

    /**
     * Test that UsageRecord model isolation works across complex queries.
     */
    public function test_usage_record_model_isolation_with_complex_queries(): void
    {
        $crossTenantData = $this->createCrossTenantData(UsageRecord::class, [
            'metric_type' => 'bandwidth',
        ]);

        $this->assertNoDataLeakage(UsageRecord::class, $crossTenantData);
    }

    /**
     * Test that VpsAllocation model isolation works across complex queries.
     */
    public function test_vps_allocation_model_isolation_with_complex_queries(): void
    {
        $vps1 = VpsServer::factory()->create();
        $vps2 = VpsServer::factory()->create();

        $crossTenantData = $this->createCrossTenantData(VpsAllocation::class, [
            'vps_id' => $vps1->id,
        ]);

        $this->assertNoDataLeakage(VpsAllocation::class, $crossTenantData);
    }

    /**
     * Test API endpoint isolation for site listing.
     */
    public function test_api_site_list_endpoint_enforces_isolation(): void
    {
        [$tenant1, $tenant2] = $this->createMultipleTenants(2);

        Site::factory()->count(3)->create(['tenant_id' => $tenant1['tenant']->id]);
        Site::factory()->count(2)->create(['tenant_id' => $tenant2['tenant']->id]);

        // Tenant 1 user should only see 3 sites
        $this->actingAs($tenant1['user']);
        $response = $this->getJson('/api/v1/sites');
        $response->assertOk();
        $this->assertCount(3, $response->json('data'));

        // Tenant 2 user should only see 2 sites
        $this->actingAs($tenant2['user']);
        $response = $this->getJson('/api/v1/sites');
        $response->assertOk();
        $this->assertCount(2, $response->json('data'));
    }

    /**
     * Test API endpoint isolation for site details.
     */
    public function test_api_site_show_endpoint_enforces_isolation(): void
    {
        [$tenant1, $tenant2] = $this->createMultipleTenants(2);

        $site1 = Site::factory()->create(['tenant_id' => $tenant1['tenant']->id]);
        $site2 = Site::factory()->create(['tenant_id' => $tenant2['tenant']->id]);

        // Tenant 1 can access their own site
        $this->assertEndpointEnforcesTenantIsolation(
            'get',
            "/api/v1/sites/{$site1->id}",
            $tenant1['user'],
            $tenant1['tenant']->id
        );

        // Tenant 1 cannot access tenant 2's site
        $this->assertEndpointRejectsCrossTenantAccess(
            'get',
            "/api/v1/sites/{$site2->id}",
            $tenant1['user']
        );
    }

    /**
     * Test that site creation is properly scoped to the authenticated tenant.
     */
    public function test_site_creation_is_scoped_to_authenticated_tenant(): void
    {
        $tenantData = $this->createTenantWithUser();
        VpsServer::factory()->create(['status' => 'active', 'allocation_mode' => 'shared']);

        $this->actingAs($tenantData['user']);

        $response = $this->postJson('/api/v1/sites', [
            'domain' => 'test-isolation.com',
            'site_type' => 'wordpress',
        ]);

        $response->assertStatus(201);

        $site = Site::where('domain', 'test-isolation.com')->first();
        $this->assertNotNull($site);
        $this->assertEquals($tenantData['tenant']->id, $site->tenant_id);
    }

    /**
     * Test that users with different roles see the same tenant-scoped data.
     */
    public function test_different_roles_see_same_tenant_scoped_data(): void
    {
        $tenantData = $this->createTenantWithUser();
        $users = $this->createUsersWithRoles($tenantData['tenant'], $tenantData['organization']);

        Site::factory()->count(5)->create(['tenant_id' => $tenantData['tenant']->id]);

        // All roles should see the same tenant data
        foreach ($users as $role => $user) {
            $this->actingAs($user);
            $sites = Site::all();
            $this->assertCount(5, $sites, "Role {$role} should see 5 sites");

            foreach ($sites as $site) {
                $this->assertEquals($tenantData['tenant']->id, $site->tenant_id);
            }
        }
    }

    /**
     * Test isolation during relationship loading.
     */
    public function test_isolation_during_relationship_loading(): void
    {
        [$tenant1, $tenant2] = $this->createMultipleTenants(2);

        $vps = VpsServer::factory()->create();

        Site::factory()->count(3)->create([
            'tenant_id' => $tenant1['tenant']->id,
            'vps_id' => $vps->id,
        ]);
        Site::factory()->count(2)->create([
            'tenant_id' => $tenant2['tenant']->id,
            'vps_id' => $vps->id,
        ]);

        // Tenant 1 user loading sites
        $this->actingAs($tenant1['user']);
        $tenant = $tenant1['tenant']->fresh();
        $sites = $tenant->sites()->get();

        $this->assertCount(3, $sites);
        foreach ($sites as $site) {
            $this->assertEquals($tenant1['tenant']->id, $site->tenant_id);
        }
    }

    /**
     * Test that aggregate queries respect tenant isolation.
     */
    public function test_aggregate_queries_respect_isolation(): void
    {
        [$tenant1, $tenant2] = $this->createMultipleTenants(2);

        Site::factory()->create(['tenant_id' => $tenant1['tenant']->id, 'storage_used_mb' => 100]);
        Site::factory()->create(['tenant_id' => $tenant1['tenant']->id, 'storage_used_mb' => 200]);
        Site::factory()->create(['tenant_id' => $tenant2['tenant']->id, 'storage_used_mb' => 500]);

        // Tenant 1's sum
        $this->assertIsolatedExecution(function () {
            return Site::sum('storage_used_mb');
        }, $tenant1['user'], $tenant1['tenant']);

        $this->actingAs($tenant1['user']);
        $this->assertEquals(300, Site::sum('storage_used_mb'));

        $this->actingAs($tenant2['user']);
        $this->assertEquals(500, Site::sum('storage_used_mb'));
    }

    /**
     * Test that batch operations respect tenant isolation.
     */
    public function test_batch_operations_respect_isolation(): void
    {
        [$tenant1, $tenant2] = $this->createMultipleTenants(2);

        Site::factory()->count(3)->create([
            'tenant_id' => $tenant1['tenant']->id,
            'status' => 'active',
        ]);
        Site::factory()->count(2)->create([
            'tenant_id' => $tenant2['tenant']->id,
            'status' => 'active',
        ]);

        // Tenant 1 batch update
        $this->actingAs($tenant1['user']);
        Site::where('status', 'active')->update(['status' => 'disabled']);

        // Verify only tenant 1 sites were updated
        $this->assertEquals(3, Site::where('status', 'disabled')->count());
        $this->assertEquals(0, Site::where('status', 'active')->count());

        // Verify tenant 2 sites were not affected
        $this->actingAs($tenant2['user']);
        $this->assertEquals(2, Site::where('status', 'active')->count());
        $this->assertEquals(0, Site::where('status', 'disabled')->count());
    }

    /**
     * Test that search and filtering maintain tenant isolation.
     */
    public function test_search_and_filtering_maintain_isolation(): void
    {
        [$tenant1, $tenant2] = $this->createMultipleTenants(2);

        Site::factory()->create([
            'tenant_id' => $tenant1['tenant']->id,
            'domain' => 'example.com',
            'status' => 'active',
        ]);
        Site::factory()->create([
            'tenant_id' => $tenant2['tenant']->id,
            'domain' => 'example.org',
            'status' => 'active',
        ]);

        // Tenant 1 search
        $this->actingAs($tenant1['user']);
        $response = $this->getJson('/api/v1/sites?search=example&status=active');
        $response->assertOk();
        $data = $response->json('data');
        $this->assertCount(1, $data);
        $this->assertEquals('example.com', $data[0]['domain']);
    }

    /**
     * Test isolation with soft deletes.
     */
    public function test_isolation_with_soft_deletes(): void
    {
        [$tenant1, $tenant2] = $this->createMultipleTenants(2);

        $site1 = Site::factory()->create(['tenant_id' => $tenant1['tenant']->id]);
        $site2 = Site::factory()->create(['tenant_id' => $tenant2['tenant']->id]);

        // Tenant 1 soft deletes their site
        $this->actingAs($tenant1['user']);
        $site1->delete();

        // Tenant 1 should not see the deleted site
        $this->assertCount(0, Site::all());
        $this->assertCount(1, Site::withTrashed()->get());

        // Tenant 2 should still see their active site
        $this->actingAs($tenant2['user']);
        $this->assertCount(1, Site::all());

        // Tenant 2 should not see tenant 1's trashed site even with withTrashed
        $this->assertCount(1, Site::withTrashed()->get());
    }

    /**
     * Test that concurrent requests from different tenants maintain isolation.
     */
    public function test_concurrent_tenant_requests_maintain_isolation(): void
    {
        [$tenant1, $tenant2] = $this->createMultipleTenants(2);

        Site::factory()->count(3)->create(['tenant_id' => $tenant1['tenant']->id]);
        Site::factory()->count(2)->create(['tenant_id' => $tenant2['tenant']->id]);

        // Simulate concurrent requests
        $this->actingAs($tenant1['user']);
        $sites1 = Site::all();

        $this->actingAs($tenant2['user']);
        $sites2 = Site::all();

        // Switch back to tenant 1
        $this->actingAs($tenant1['user']);
        $sites1Again = Site::all();

        $this->assertCount(3, $sites1);
        $this->assertCount(2, $sites2);
        $this->assertCount(3, $sites1Again);
    }

    /**
     * Test that model events respect tenant isolation.
     */
    public function test_model_events_respect_tenant_isolation(): void
    {
        $tenantData = $this->createTenantWithUser();
        $this->actingAs($tenantData['user']);

        $vps = VpsServer::factory()->create(['allocation_mode' => 'shared']);

        // Creating a site should be scoped to the authenticated tenant
        $site = Site::create([
            'tenant_id' => $tenantData['tenant']->id, // Even if we explicitly set it
            'vps_id' => $vps->id,
            'domain' => 'event-test.com',
            'site_type' => 'wordpress',
            'php_version' => '8.2',
            'status' => 'creating',
        ]);

        $this->assertEquals($tenantData['tenant']->id, $site->tenant_id);

        // Query should find it
        $found = Site::find($site->id);
        $this->assertNotNull($found);
    }
}
