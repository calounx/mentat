<?php

declare(strict_types=1);

namespace Tests\Unit\Queries;

use App\Queries\BackupSearchQuery;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class BackupSearchQueryTest extends TestCase
{
    use RefreshDatabase;

    private string $tenantId;
    private string $siteId;

    protected function setUp(): void
    {
        parent::setUp();

        $this->tenantId = (string) \Illuminate\Support\Str::uuid();
        $this->siteId = (string) \Illuminate\Support\Str::uuid();

        // Create test organization
        $orgId = (string) \Illuminate\Support\Str::uuid();
        DB::table('organizations')->insert([
            'id' => $orgId,
            'name' => 'Test Org',
            'slug' => 'test-org',
            'billing_email' => 'billing@test.com',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        // Create test tenant
        DB::table('tenants')->insert([
            'id' => $this->tenantId,
            'organization_id' => $orgId,
            'name' => 'Test Tenant',
            'slug' => 'test-tenant',
            'tier' => 'pro',
            'status' => 'active',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        // Create test VPS server
        $vpsId = (string) \Illuminate\Support\Str::uuid();
        DB::table('vps_servers')->insert([
            'id' => $vpsId,
            'hostname' => 'test-vps',
            'ip_address' => '192.168.1.1',
            'provider' => 'hetzner',
            'spec_cpu' => 4,
            'spec_memory_mb' => 8192,
            'spec_disk_gb' => 100,
            'status' => 'active',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        // Create test site
        DB::table('sites')->insert([
            'id' => $this->siteId,
            'tenant_id' => $this->tenantId,
            'vps_id' => $vpsId,
            'domain' => 'example.com',
            'site_type' => 'wordpress',
            'status' => 'active',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        // Create test backups
        DB::table('site_backups')->insert([
            [
                'id' => \Illuminate\Support\Str::uuid(),
                'site_id' => $this->siteId,
                'filename' => 'backup1.tar.gz',
                'backup_type' => 'full',
                'status' => 'completed',
                'size_bytes' => 1024 * 1024 * 100, // 100MB
                'size_mb' => 100,
                'created_at' => now()->subDays(5),
                'updated_at' => now()->subDays(5),
            ],
            [
                'id' => \Illuminate\Support\Str::uuid(),
                'site_id' => $this->siteId,
                'filename' => 'backup2.tar.gz',
                'backup_type' => 'database',
                'status' => 'completed',
                'size_bytes' => 1024 * 1024 * 50, // 50MB
                'size_mb' => 50,
                'created_at' => now()->subDays(3),
                'updated_at' => now()->subDays(3),
            ],
            [
                'id' => \Illuminate\Support\Str::uuid(),
                'site_id' => $this->siteId,
                'filename' => 'backup3.tar.gz',
                'backup_type' => 'files',
                'status' => 'failed',
                'size_bytes' => null,
                'size_mb' => null,
                'created_at' => now()->subDays(1),
                'updated_at' => now()->subDays(1),
            ],
        ]);
    }

    public function test_filters_by_site(): void
    {
        $results = BackupSearchQuery::make()
            ->forSite($this->siteId)
            ->get();

        $this->assertCount(3, $results);
    }

    public function test_filters_by_tenant(): void
    {
        $results = BackupSearchQuery::make()
            ->forTenant($this->tenantId)
            ->get();

        $this->assertCount(3, $results);
    }

    public function test_filters_by_status(): void
    {
        $results = BackupSearchQuery::make()
            ->forSite($this->siteId)
            ->withStatus('completed')
            ->get();

        $this->assertCount(2, $results);
    }

    public function test_filters_by_type(): void
    {
        $results = BackupSearchQuery::make()
            ->forSite($this->siteId)
            ->withType('full')
            ->get();

        $this->assertCount(1, $results);
    }

    public function test_filters_by_date_range(): void
    {
        $results = BackupSearchQuery::make()
            ->forSite($this->siteId)
            ->createdBetween(now()->subDays(4), now()->subDays(2))
            ->get();

        $this->assertCount(1, $results);
    }

    public function test_filters_by_minimum_size(): void
    {
        $results = BackupSearchQuery::make()
            ->forSite($this->siteId)
            ->minimumSize(1024 * 1024 * 75) // 75MB
            ->get();

        $this->assertCount(1, $results);
    }

    public function test_filters_by_maximum_size(): void
    {
        $results = BackupSearchQuery::make()
            ->forSite($this->siteId)
            ->maximumSize(1024 * 1024 * 75) // 75MB
            ->get();

        $this->assertCount(1, $results);
    }

    public function test_gets_oldest_backup(): void
    {
        $oldest = BackupSearchQuery::make()
            ->forSite($this->siteId)
            ->oldest();

        $this->assertNotNull($oldest);
        $this->assertEquals('backup1.tar.gz', $oldest->filename);
    }

    public function test_gets_latest_backup(): void
    {
        $latest = BackupSearchQuery::make()
            ->forSite($this->siteId)
            ->latest();

        $this->assertNotNull($latest);
        $this->assertEquals('backup3.tar.gz', $latest->filename);
    }

    public function test_calculates_total_size(): void
    {
        $totalSize = BackupSearchQuery::make()
            ->forSite($this->siteId)
            ->withStatus('completed')
            ->totalSize();

        $expectedSize = (1024 * 1024 * 100) + (1024 * 1024 * 50); // 150MB in bytes
        $this->assertEquals($expectedSize, $totalSize);
    }

    public function test_calculates_total_size_mb(): void
    {
        $totalSizeMb = BackupSearchQuery::make()
            ->forSite($this->siteId)
            ->withStatus('completed')
            ->totalSizeMb();

        $this->assertEquals(150, $totalSizeMb);
    }

    public function test_counts_by_status(): void
    {
        $counts = BackupSearchQuery::make()
            ->forSite($this->siteId)
            ->countByStatus();

        $this->assertEquals(2, $counts['completed'] ?? 0);
        $this->assertEquals(1, $counts['failed'] ?? 0);
    }

    public function test_counts_by_type(): void
    {
        $counts = BackupSearchQuery::make()
            ->forSite($this->siteId)
            ->countByType();

        $this->assertEquals(1, $counts['full'] ?? 0);
        $this->assertEquals(1, $counts['database'] ?? 0);
        $this->assertEquals(1, $counts['files'] ?? 0);
    }

    public function test_calculates_average_size(): void
    {
        $avgSize = BackupSearchQuery::make()
            ->forSite($this->siteId)
            ->withStatus('completed')
            ->averageSize();

        $expected = ((1024 * 1024 * 100) + (1024 * 1024 * 50)) / 2;
        $this->assertEquals($expected, $avgSize);
    }

    public function test_combines_multiple_filters(): void
    {
        $results = BackupSearchQuery::make()
            ->forSite($this->siteId)
            ->withStatus('completed')
            ->withType('full')
            ->minimumSize(1024 * 1024 * 50)
            ->get();

        $this->assertCount(1, $results);
    }

    public function test_paginates_results(): void
    {
        $paginator = BackupSearchQuery::make()
            ->forSite($this->siteId)
            ->paginate(2);

        $this->assertCount(2, $paginator->items());
        $this->assertEquals(3, $paginator->total());
    }

    public function test_counts_total(): void
    {
        $count = BackupSearchQuery::make()
            ->forSite($this->siteId)
            ->count();

        $this->assertEquals(3, $count);
    }

    public function test_constructor_pattern(): void
    {
        $query = new BackupSearchQuery(
            siteId: $this->siteId,
            status: 'completed'
        );

        $results = $query->get();

        $this->assertCount(2, $results);
    }

    public function test_fluent_builder_pattern(): void
    {
        $results = BackupSearchQuery::make()
            ->forSite($this->siteId)
            ->withStatus('completed')
            ->get();

        $this->assertCount(2, $results);
    }
}
