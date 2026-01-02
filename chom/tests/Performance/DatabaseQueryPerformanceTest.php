<?php

declare(strict_types=1);

namespace Tests\Performance;

use App\Models\Site;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\WithPerformanceTesting;
use Tests\TestCase;

/**
 * Database query performance tests
 */
class DatabaseQueryPerformanceTest extends TestCase
{
    use RefreshDatabase;
    use WithPerformanceTesting;

    /**
     * Test dashboard loads with optimal queries
     */
    public function test_dashboard_loads_within_performance_threshold(): void
    {
        $user = User::factory()->create();
        Site::factory()->count(10)->create(['tenant_id' => $user->currentTenant()->id]);

        $this->startQueryTracking();

        $this->assertBenchmark(
            fn () => $this->actingAs($user)->get('/dashboard'),
            'dashboard_load'
        );

        $this->assertMaxQueries(5, 'Dashboard should use eager loading');
    }

    /**
     * Test no N+1 queries in site listing
     */
    public function test_site_listing_has_no_n1_queries(): void
    {
        $user = User::factory()->create();

        $this->assertNoN1Queries(
            fn ($count) => Site::factory()->count($count)->create(['tenant_id' => $user->currentTenant()->id]),
            fn ($sites) => $this->actingAs($user)->get('/api/v1/sites')
        );
    }

    /**
     * Test queries use indexes
     */
    public function test_site_search_uses_indexes(): void
    {
        $this->assertQueryUsesIndex(
            'SELECT * FROM sites WHERE user_id = ? AND domain LIKE ?',
            [1, '%test%']
        );
    }
}
