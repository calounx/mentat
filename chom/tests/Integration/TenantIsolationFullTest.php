<?php

declare(strict_types=1);

namespace Tests\Integration;

use App\Models\Site;
use App\Models\User;
use App\Models\Backup;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\WithSecurityTesting;
use Tests\TestCase;

/**
 * End-to-end tenant isolation testing
 *
 * Ensures complete data isolation between tenants across all application layers.
 *
 * @package Tests\Integration
 */
class TenantIsolationFullTest extends TestCase
{
    use RefreshDatabase;
    use WithSecurityTesting;

    protected User $tenant1;
    protected User $tenant2;

    protected function setUp(): void
    {
        parent::setUp();

        $this->tenant1 = User::factory()->create(['name' => 'Tenant 1']);
        $this->tenant2 = User::factory()->create(['name' => 'Tenant 2']);
    }

    /**
     * Test tenant cannot access another tenant's sites
     *
     * @return void
     */
    public function test_tenant_cannot_access_other_tenants_sites(): void
    {
        // Arrange
        $tenant1Site = Site::factory()->create(['user_id' => $this->tenant1->id]);
        $tenant2Site = Site::factory()->create(['user_id' => $this->tenant2->id]);

        // Act & Assert
        $response = $this->actingAs($this->tenant1)
            ->get("/api/v1/sites/{$tenant2Site->id}");

        $response->assertStatus(403);
    }

    /**
     * Test database queries are automatically scoped to tenant
     *
     * @return void
     */
    public function test_database_queries_scoped_to_tenant(): void
    {
        // Arrange
        Site::factory()->count(5)->create(['user_id' => $this->tenant1->id]);
        Site::factory()->count(3)->create(['user_id' => $this->tenant2->id]);

        // Act
        $response = $this->actingAs($this->tenant1)
            ->get('/api/v1/sites');

        // Assert
        $sites = $response->json('data');
        $this->assertCount(5, $sites);

        foreach ($sites as $site) {
            $this->assertEquals($this->tenant1->id, $site['user_id']);
        }
    }

    /**
     * Test tenant cannot access other tenant's backups
     *
     * @return void
     */
    public function test_tenant_cannot_access_other_tenants_backups(): void
    {
        // Arrange
        $tenant1Site = Site::factory()->create(['user_id' => $this->tenant1->id]);
        $tenant2Site = Site::factory()->create(['user_id' => $this->tenant2->id]);

        $tenant2Backup = Backup::factory()->create(['site_id' => $tenant2Site->id]);

        // Act
        $response = $this->actingAs($this->tenant1)
            ->get("/api/v1/backups/{$tenant2Backup->id}");

        // Assert
        $response->assertStatus(403);
    }

    /**
     * Test observability data is isolated per tenant
     *
     * @return void
     */
    public function test_observability_data_isolated_per_tenant(): void
    {
        // Arrange
        $tenant1Site = Site::factory()->create([
            'user_id' => $this->tenant1->id,
            'grafana_org_id' => 1,
        ]);

        $tenant2Site = Site::factory()->create([
            'user_id' => $this->tenant2->id,
            'grafana_org_id' => 2,
        ]);

        // Act - Tenant 1 accesses their metrics
        $response1 = $this->actingAs($this->tenant1)
            ->get("/api/v1/sites/{$tenant1Site->id}/metrics");

        // Act - Tenant 2 cannot access Tenant 1's metrics
        $response2 = $this->actingAs($this->tenant2)
            ->get("/api/v1/sites/{$tenant1Site->id}/metrics");

        // Assert
        $response1->assertStatus(200);
        $response2->assertStatus(403);
    }

    /**
     * Test all endpoints enforce tenant isolation
     *
     * @return void
     */
    public function test_all_endpoints_enforce_tenant_isolation(): void
    {
        $tenant2Site = Site::factory()->create(['user_id' => $this->tenant2->id]);

        $endpoints = [
            ['GET', "/api/v1/sites/{$tenant2Site->id}"],
            ['PUT', "/api/v1/sites/{$tenant2Site->id}"],
            ['DELETE', "/api/v1/sites/{$tenant2Site->id}"],
            ['GET', "/api/v1/sites/{$tenant2Site->id}/metrics"],
            ['POST', "/api/v1/sites/{$tenant2Site->id}/backups"],
        ];

        foreach ($endpoints as [$method, $uri]) {
            $response = $this->actingAs($this->tenant1)->call($method, $uri);
            $this->assertEquals(403, $response->status(), "Failed for {$method} {$uri}");
        }
    }
}
