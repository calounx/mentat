<?php

declare(strict_types=1);

namespace Tests\Unit\Livewire;

use App\Livewire\DatabaseManager;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Livewire\Livewire;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Tests\TestCase;

/**
 * DatabaseManagerTest
 *
 * Comprehensive test suite for the DatabaseManager Livewire component.
 * Tests database export, optimization, download, and access control.
 *
 * @package Tests\Unit\Livewire
 * @covers  \App\Livewire\DatabaseManager
 */
class DatabaseManagerTest extends TestCase
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
            '*/api/v1/sites/*/database/info' => Http::response(['data' => [
                'name' => 'test_db',
                'size' => '100 MB',
                'tables_count' => 25,
            ]], 200),
            '*/api/v1/sites/*/database/exports*' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/optimizations*' => Http::response(['data' => []], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(DatabaseManager::class, ['site' => $this->site])
            ->assertSet('siteId', $this->site->id)
            ->assertSet('processing', false)
            ->assertSet('exportType', 'full');
    }

    /**
     * Test component throws 401 when user is not authenticated
     */
    public function test_it_throws_401_when_unauthenticated(): void
    {
        $this->expectException(HttpException::class);
        $this->expectExceptionMessage('Unauthenticated.');

        Livewire::test(DatabaseManager::class, ['site' => $this->site]);
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

        Livewire::test(DatabaseManager::class, ['site' => $this->site]);
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

        Livewire::test(DatabaseManager::class, ['site' => $otherSite]);
    }

    /**
     * Test export database successfully
     */
    public function test_it_exports_database_successfully(): void
    {
        Http::fake([
            '*/api/v1/sites/*/database/info' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/export' => Http::response([
                'message' => 'Export started',
                'data' => ['id' => 'export-123'],
            ], 200),
            '*/api/v1/sites/*/database/exports*' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/optimizations*' => Http::response(['data' => []], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(DatabaseManager::class, ['site' => $this->site])
            ->set('exportType', 'full')
            ->call('exportDatabase')
            ->assertSet('processing', false)
            ->assertSet('successMessage', 'Database export started successfully. You will be notified when it completes.')
            ->assertSet('errorMessage', null);

        Http::assertSent(function ($request) {
            return $request->url() === config('app.api_url') . "/api/v1/sites/{$this->site->id}/database/export"
                && $request['type'] === 'full';
        });
    }

    /**
     * Test export database handles API error
     */
    public function test_it_handles_export_database_api_error(): void
    {
        Http::fake([
            '*/api/v1/sites/*/database/info' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/export' => Http::response([
                'message' => 'Export failed',
            ], 500),
            '*/api/v1/sites/*/database/exports*' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/optimizations*' => Http::response(['data' => []], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(DatabaseManager::class, ['site' => $this->site])
            ->call('exportDatabase')
            ->assertSet('processing', false)
            ->assertSet('errorMessage', 'Export failed')
            ->assertSet('successMessage', null);
    }

    /**
     * Test optimize database successfully
     */
    public function test_it_optimizes_database_successfully(): void
    {
        Http::fake([
            '*/api/v1/sites/*/database/info' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/optimize' => Http::response([
                'message' => 'Optimization started',
            ], 200),
            '*/api/v1/sites/*/database/exports*' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/optimizations*' => Http::response(['data' => []], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(DatabaseManager::class, ['site' => $this->site])
            ->call('optimizeDatabase')
            ->assertSet('processing', false)
            ->assertSet('successMessage', 'Database optimization started successfully.')
            ->assertSet('errorMessage', null);

        Http::assertSent(function ($request) {
            return $request->url() === config('app.api_url') . "/api/v1/sites/{$this->site->id}/database/optimize";
        });
    }

    /**
     * Test optimize database handles API error
     */
    public function test_it_handles_optimize_database_api_error(): void
    {
        Http::fake([
            '*/api/v1/sites/*/database/info' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/optimize' => Http::response([
                'message' => 'Optimization failed',
            ], 500),
            '*/api/v1/sites/*/database/exports*' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/optimizations*' => Http::response(['data' => []], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(DatabaseManager::class, ['site' => $this->site])
            ->call('optimizeDatabase')
            ->assertSet('processing', false)
            ->assertSet('errorMessage', 'Optimization failed')
            ->assertSet('successMessage', null);
    }

    /**
     * Test load database info successfully
     */
    public function test_it_loads_database_info_successfully(): void
    {
        Http::fake([
            '*/api/v1/sites/*/database/info' => Http::response(['data' => [
                'name' => 'wordpress_db',
                'size' => '256 MB',
                'tables_count' => 42,
            ]], 200),
            '*/api/v1/sites/*/database/exports*' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/optimizations*' => Http::response(['data' => []], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(DatabaseManager::class, ['site' => $this->site])
            ->assertSet('databaseInfo', [
                'name' => 'wordpress_db',
                'size' => '256 MB',
                'tables_count' => 42,
            ]);
    }

    /**
     * Test load history successfully
     */
    public function test_it_loads_history_successfully(): void
    {
        $exportHistory = [
            ['id' => 'export-1', 'type' => 'export', 'status' => 'completed', 'created_at' => '2024-01-01 10:00:00'],
            ['id' => 'export-2', 'type' => 'export', 'status' => 'pending', 'created_at' => '2024-01-01 09:00:00'],
        ];

        $optimizationHistory = [
            ['id' => 'opt-1', 'type' => 'optimization', 'status' => 'completed', 'created_at' => '2024-01-01 08:00:00'],
        ];

        Http::fake([
            '*/api/v1/sites/*/database/info' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/exports*' => Http::response(['data' => $exportHistory], 200),
            '*/api/v1/sites/*/database/optimizations*' => Http::response(['data' => $optimizationHistory], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(DatabaseManager::class, ['site' => $this->site])
            ->assertSet('exportHistory', $exportHistory)
            ->assertSet('optimizationHistory', $optimizationHistory);
    }

    /**
     * Test download export method
     */
    public function test_it_downloads_export_successfully(): void
    {
        Http::fake([
            '*/api/v1/sites/*/database/info' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/exports/export-123/download' => Http::response('SQL DUMP DATA', 200),
            '*/api/v1/sites/*/database/exports*' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/optimizations*' => Http::response(['data' => []], 200),
        ]);

        $this->actingAs($this->user);

        $component = Livewire::test(DatabaseManager::class, ['site' => $this->site]);

        $response = $component->call('downloadExport', 'export-123')->response;

        // Note: In a real test, you would check the response headers and content
        // This is a simplified test that verifies the method can be called
        Http::assertSent(function ($request) {
            return str_contains($request->url(), 'database/exports/export-123/download');
        });
    }

    /**
     * Test download export handles API error
     */
    public function test_it_handles_download_export_api_error(): void
    {
        Http::fake([
            '*/api/v1/sites/*/database/info' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/exports/export-123/download' => Http::response([
                'message' => 'Export not found',
            ], 404),
            '*/api/v1/sites/*/database/exports*' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/optimizations*' => Http::response(['data' => []], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(DatabaseManager::class, ['site' => $this->site])
            ->call('downloadExport', 'export-123')
            ->assertSet('errorMessage', 'Failed to download export.');
    }

    /**
     * Test export type can be changed
     */
    public function test_it_can_change_export_type(): void
    {
        Http::fake([
            '*/api/v1/sites/*/database/info' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/exports*' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/optimizations*' => Http::response(['data' => []], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(DatabaseManager::class, ['site' => $this->site])
            ->set('exportType', 'structure_only')
            ->assertSet('exportType', 'structure_only')
            ->set('exportType', 'data_only')
            ->assertSet('exportType', 'data_only');
    }

    /**
     * Test component renders view successfully
     */
    public function test_it_renders_view_successfully(): void
    {
        Http::fake([
            '*/api/v1/sites/*/database/info' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/exports*' => Http::response(['data' => []], 200),
            '*/api/v1/sites/*/database/optimizations*' => Http::response(['data' => []], 200),
        ]);

        $this->actingAs($this->user);

        Livewire::test(DatabaseManager::class, ['site' => $this->site])
            ->assertViewIs('livewire.database-manager');
    }
}
