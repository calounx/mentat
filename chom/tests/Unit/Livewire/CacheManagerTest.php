<?php

declare(strict_types=1);

namespace Tests\Unit\Livewire;

use App\Livewire\CacheManager;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Livewire\Livewire;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Tests\TestCase;

/**
 * CacheManagerTest
 *
 * Comprehensive test suite for the CacheManager Livewire component.
 * Tests cache clearing, statistics, confirmation modals, and access control.
 *
 * @package Tests\Unit\Livewire
 * @covers  \App\Livewire\CacheManager
 */
class CacheManagerTest extends TestCase
{
    use RefreshDatabase;

    private User $user;
    private Tenant $tenant;
    private Site $site;

    protected function setUp(): void
    {
        parent::setUp();

        // Create test data
        $this->tenant = Tenant::factory()->create([
            'status' => 'active',
        ]);

        $this->user = User::factory()->create();

        // Mock the tenant relationship
        $this->user->tenant = $this->tenant;

        $this->site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'domain' => 'test.com',
        ]);

        Http::fake();
    }

    /**
     * Test component mounts successfully with valid site and tenant
     */
    public function test_it_mounts_successfully_with_valid_site_and_tenant(): void
    {
        Http::fake([
            '*/api/v1/sites/*/cache/stats' => Http::response(['data' => [
                'stats' => [
                    'total_size' => '248 MB',
                    'hit_rate' => '87.3%',
                    'memory_usage' => '180 MB',
                    'keys_count' => 15432,
                ],
                'last_cleared' => '2 hours ago',
            ]], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(CacheManager::class, ['site' => $this->site])
            ->assertSet('siteId', $this->site->id)
            ->assertSet('processing', false)
            ->assertSet('showConfirmModal', false);
    }

    /**
     * Test component throws 401 when user is not authenticated
     */
    public function test_it_throws_401_when_unauthenticated(): void
    {
        $this->expectException(HttpException::class);
        $this->expectExceptionMessage('Unauthenticated.');

        Livewire::test(CacheManager::class, ['site' => $this->site]);
    }

    /**
     * Test component throws 403 when user has no tenant
     */
    public function test_it_throws_403_when_user_has_no_tenant(): void
    {
        $userWithoutTenant = User::factory()->create();

        $this->expectException(HttpException::class);
        $this->expectExceptionMessage('No active tenant found.');

        $this->actingAs($userWithoutTenant);

        Livewire::test(CacheManager::class, ['site' => $this->site]);
    }

    /**
     * Test component throws 403 when site doesn't belong to user's tenant
     */
    public function test_it_throws_403_when_site_belongs_to_different_tenant(): void
    {
        $otherTenant = Tenant::factory()->create();
        $otherSite = Site::factory()->create([
            'tenant_id' => $otherTenant->id,
        ]);

        $this->expectException(HttpException::class);
        $this->expectExceptionMessage('You do not have access to this site.');

        $this->actingAs($this->user);

        Livewire::test(CacheManager::class, ['site' => $otherSite]);
    }

    /**
     * Test refresh stats successfully
     */
    public function test_it_refreshes_stats_successfully(): void
    {
        $cacheStats = [
            'stats' => [
                'total_size' => '300 MB',
                'hit_rate' => '92.1%',
                'memory_usage' => '220 MB',
                'keys_count' => 20000,
            ],
            'last_cleared' => '1 hour ago',
        ];

        Http::fake([
            '*/api/v1/sites/*/cache/stats' => Http::response(['data' => $cacheStats], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(CacheManager::class, ['site' => $this->site])
            ->call('refreshStats')
            ->assertSet('cacheStats', $cacheStats['stats'])
            ->assertSet('lastCleared', $cacheStats['last_cleared']);
    }

    /**
     * Test prompt clear cache shows modal for 'all' type
     */
    public function test_it_shows_confirmation_modal_for_clear_all(): void
    {
        Http::fake([
            '*/api/v1/sites/*/cache/stats' => Http::response(['data' => [
                'stats' => [],
                'last_cleared' => null,
            ]], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(CacheManager::class, ['site' => $this->site])
            ->call('promptClearCache', 'all')
            ->assertSet('showConfirmModal', true)
            ->assertSet('clearType', 'all');
    }

    /**
     * Test prompt clear cache directly clears for non-'all' types
     */
    public function test_it_clears_cache_directly_for_specific_types(): void
    {
        Http::fake([
            '*/api/v1/sites/*/cache/stats' => Http::response(['data' => [
                'stats' => [],
                'last_cleared' => null,
            ]], 200),
            '*/api/v1/sites/*/cache/clear' => Http::response(['message' => 'Cache cleared'], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(CacheManager::class, ['site' => $this->site])
            ->call('promptClearCache', 'opcache')
            ->assertSet('showConfirmModal', false)
            ->assertSet('successMessage', 'OPcache cleared successfully.');
    }

    /**
     * Test clear all cache successfully
     */
    public function test_it_clears_all_cache_successfully(): void
    {
        Http::fake([
            '*/api/v1/sites/*/cache/stats' => Http::response(['data' => [
                'stats' => [],
                'last_cleared' => null,
            ]], 200),
            '*/api/v1/sites/*/cache/clear' => Http::response(['message' => 'Cache cleared'], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(CacheManager::class, ['site' => $this->site])
            ->call('clearCache', 'all')
            ->assertSet('processing', false)
            ->assertSet('successMessage', 'All cache cleared successfully.')
            ->assertSet('errorMessage', null);

        Http::assertSent(function ($request) {
            return $request->url() === config('app.api_url') . "/api/v1/sites/{$this->site->id}/cache/clear"
                && $request['type'] === 'all';
        });
    }

    /**
     * Test clear OPcache successfully
     */
    public function test_it_clears_opcache_successfully(): void
    {
        Http::fake([
            '*/api/v1/sites/*/cache/stats' => Http::response(['data' => [
                'stats' => [],
                'last_cleared' => null,
            ]], 200),
            '*/api/v1/sites/*/cache/clear' => Http::response(['message' => 'Cache cleared'], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(CacheManager::class, ['site' => $this->site])
            ->call('clearCache', 'opcache')
            ->assertSet('processing', false)
            ->assertSet('successMessage', 'OPcache cleared successfully.')
            ->assertSet('errorMessage', null);

        Http::assertSent(function ($request) {
            return $request['type'] === 'opcache';
        });
    }

    /**
     * Test clear Redis cache successfully
     */
    public function test_it_clears_redis_cache_successfully(): void
    {
        Http::fake([
            '*/api/v1/sites/*/cache/stats' => Http::response(['data' => [
                'stats' => [],
                'last_cleared' => null,
            ]], 200),
            '*/api/v1/sites/*/cache/clear' => Http::response(['message' => 'Cache cleared'], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(CacheManager::class, ['site' => $this->site])
            ->call('clearCache', 'redis')
            ->assertSet('processing', false)
            ->assertSet('successMessage', 'Redis cache cleared successfully.')
            ->assertSet('errorMessage', null);

        Http::assertSent(function ($request) {
            return $request['type'] === 'redis';
        });
    }

    /**
     * Test clear file cache successfully
     */
    public function test_it_clears_file_cache_successfully(): void
    {
        Http::fake([
            '*/api/v1/sites/*/cache/stats' => Http::response(['data' => [
                'stats' => [],
                'last_cleared' => null,
            ]], 200),
            '*/api/v1/sites/*/cache/clear' => Http::response(['message' => 'Cache cleared'], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(CacheManager::class, ['site' => $this->site])
            ->call('clearCache', 'file')
            ->assertSet('processing', false)
            ->assertSet('successMessage', 'File cache cleared successfully.')
            ->assertSet('errorMessage', null);

        Http::assertSent(function ($request) {
            return $request['type'] === 'file';
        });
    }

    /**
     * Test clear cache handles API error
     */
    public function test_it_handles_clear_cache_api_error(): void
    {
        Http::fake([
            '*/api/v1/sites/*/cache/stats' => Http::response(['data' => [
                'stats' => [],
                'last_cleared' => null,
            ]], 200),
            '*/api/v1/sites/*/cache/clear' => Http::response([
                'message' => 'Failed to clear cache',
            ], 500),
        ]);

        $this->actingAs($this->user);

        Livewire::test(CacheManager::class, ['site' => $this->site])
            ->call('clearCache', 'all')
            ->assertSet('processing', false)
            ->assertSet('errorMessage', 'Failed to clear cache')
            ->assertSet('successMessage', null);
    }

    /**
     * Test cancel clear cache
     */
    public function test_it_cancels_clear_cache_confirmation(): void
    {
        Http::fake([
            '*/api/v1/sites/*/cache/stats' => Http::response(['data' => [
                'stats' => [],
                'last_cleared' => null,
            ]], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(CacheManager::class, ['site' => $this->site])
            ->set('showConfirmModal', true)
            ->set('clearType', 'all')
            ->call('cancelClearCache')
            ->assertSet('showConfirmModal', false)
            ->assertSet('clearType', null);
    }

    /**
     * Test component loads cache stats on mount
     */
    public function test_it_loads_cache_stats_on_mount(): void
    {
        $statsData = [
            'stats' => [
                'total_size' => '512 MB',
                'hit_rate' => '95.5%',
                'memory_usage' => '400 MB',
                'keys_count' => 50000,
            ],
            'last_cleared' => '30 minutes ago',
        ];

        Http::fake([
            '*/api/v1/sites/*/cache/stats' => Http::response(['data' => $statsData], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(CacheManager::class, ['site' => $this->site])
            ->assertSet('cacheStats', $statsData['stats'])
            ->assertSet('lastCleared', $statsData['last_cleared']);
    }

    /**
     * Test component refreshes stats after clearing cache
     */
    public function test_it_refreshes_stats_after_clearing_cache(): void
    {
        $initialStats = [
            'stats' => [
                'total_size' => '500 MB',
                'hit_rate' => '90%',
                'memory_usage' => '400 MB',
                'keys_count' => 40000,
            ],
            'last_cleared' => '1 hour ago',
        ];

        $updatedStats = [
            'stats' => [
                'total_size' => '10 MB',
                'hit_rate' => '0%',
                'memory_usage' => '10 MB',
                'keys_count' => 0,
            ],
            'last_cleared' => 'Just now',
        ];

        Http::fake([
            '*/api/v1/sites/*/cache/stats' => Http::sequence()
                ->push(['data' => $initialStats], 200)
                ->push(['data' => $updatedStats], 200),
            '*/api/v1/sites/*/cache/clear' => Http::response(['message' => 'Cache cleared'], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(CacheManager::class, ['site' => $this->site])
            ->assertSet('cacheStats', $initialStats['stats'])
            ->call('clearCache', 'all')
            ->assertSet('cacheStats', $updatedStats['stats'])
            ->assertSet('lastCleared', $updatedStats['last_cleared']);
    }

    /**
     * Test component renders view successfully
     */
    public function test_it_renders_view_successfully(): void
    {
        Http::fake([
            '*/api/v1/sites/*/cache/stats' => Http::response(['data' => [
                'stats' => [],
                'last_cleared' => null,
            ]], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(CacheManager::class, ['site' => $this->site])
            ->assertViewIs('livewire.cache-manager');
    }
}
