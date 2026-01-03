<?php

declare(strict_types=1);

namespace Tests\Unit\Queries;

use App\Queries\SiteSearchQuery;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class SiteSearchQueryTest extends TestCase
{
    use RefreshDatabase;

    private string $tenantId;

    protected function setUp(): void
    {
        parent::setUp();

        $this->tenantId = (string) \Illuminate\Support\Str::uuid();

        // Create test organization
        DB::table('organizations')->insert([
            'id' => \Illuminate\Support\Str::uuid(),
            'name' => 'Test Org',
            'slug' => 'test-org',
            'billing_email' => 'billing@test.com',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        // Create test tenant
        $orgId = DB::table('organizations')->first()->id;
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

        // Create test sites
        DB::table('sites')->insert([
            [
                'id' => \Illuminate\Support\Str::uuid(),
                'tenant_id' => $this->tenantId,
                'vps_id' => $vpsId,
                'domain' => 'example.com',
                'site_type' => 'wordpress',
                'php_version' => '8.2',
                'ssl_enabled' => true,
                'status' => 'active',
                'storage_used_mb' => 500,
                'created_at' => now(),
                'updated_at' => now(),
            ],
            [
                'id' => \Illuminate\Support\Str::uuid(),
                'tenant_id' => $this->tenantId,
                'vps_id' => $vpsId,
                'domain' => 'test.com',
                'site_type' => 'laravel',
                'php_version' => '8.3',
                'ssl_enabled' => false,
                'status' => 'active',
                'storage_used_mb' => 300,
                'created_at' => now(),
                'updated_at' => now(),
            ],
            [
                'id' => \Illuminate\Support\Str::uuid(),
                'tenant_id' => $this->tenantId,
                'vps_id' => $vpsId,
                'domain' => 'disabled.com',
                'site_type' => 'wordpress',
                'php_version' => '8.2',
                'ssl_enabled' => true,
                'status' => 'disabled',
                'storage_used_mb' => 200,
                'created_at' => now(),
                'updated_at' => now(),
            ],
        ]);
    }

    public function test_filters_by_tenant(): void
    {
        $results = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->get();

        $this->assertCount(3, $results);
    }

    public function test_filters_by_status(): void
    {
        $results = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->withStatus('active')
            ->get();

        $this->assertCount(2, $results);
    }

    public function test_filters_by_site_type(): void
    {
        $results = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->withType('wordpress')
            ->get();

        $this->assertCount(2, $results);
    }

    public function test_filters_by_php_version(): void
    {
        $results = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->withPhpVersion('8.2')
            ->get();

        $this->assertCount(2, $results);
    }

    public function test_filters_by_ssl_enabled(): void
    {
        $results = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->sslEnabled()
            ->get();

        $this->assertCount(2, $results);
    }

    public function test_filters_by_ssl_disabled(): void
    {
        $results = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->sslDisabled()
            ->get();

        $this->assertCount(1, $results);
    }

    public function test_searches_by_domain(): void
    {
        $results = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->search('example')
            ->get();

        $this->assertCount(1, $results);
        $this->assertEquals('example.com', $results->first()->domain);
    }

    public function test_combines_multiple_filters(): void
    {
        $results = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->withStatus('active')
            ->withType('wordpress')
            ->sslEnabled()
            ->get();

        $this->assertCount(1, $results);
        $this->assertEquals('example.com', $results->first()->domain);
    }

    public function test_counts_total(): void
    {
        $count = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->count();

        $this->assertEquals(3, $count);
    }

    public function test_checks_existence(): void
    {
        $exists = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->withStatus('active')
            ->exists();

        $this->assertTrue($exists);

        $notExists = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->withStatus('creating')
            ->exists();

        $this->assertFalse($notExists);
    }

    public function test_calculates_total_storage(): void
    {
        $totalStorage = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->totalStorageUsed();

        $this->assertEquals(1000, $totalStorage);
    }

    public function test_counts_by_status(): void
    {
        $counts = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->countByStatus();

        $this->assertEquals(2, $counts['active'] ?? 0);
        $this->assertEquals(1, $counts['disabled'] ?? 0);
    }

    public function test_counts_by_type(): void
    {
        $counts = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->countByType();

        $this->assertEquals(2, $counts['wordpress'] ?? 0);
        $this->assertEquals(1, $counts['laravel'] ?? 0);
    }

    public function test_counts_by_php_version(): void
    {
        $counts = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->countByPhpVersion();

        $this->assertEquals(2, $counts['8.2'] ?? 0);
        $this->assertEquals(1, $counts['8.3'] ?? 0);
    }

    public function test_paginates_results(): void
    {
        $paginator = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->paginate(2);

        $this->assertCount(2, $paginator->items());
        $this->assertEquals(3, $paginator->total());
    }

    public function test_sorts_by_field(): void
    {
        $results = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->sortBy('domain', 'asc')
            ->get();

        $this->assertEquals('disabled.com', $results->first()->domain);
    }

    public function test_generates_sql(): void
    {
        $query = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->withStatus('active');

        $sql = $query->toSql();

        $this->assertStringContainsString('SELECT', $sql);
        $this->assertStringContainsString('sites', $sql);
    }

    public function test_constructor_pattern(): void
    {
        $query = new SiteSearchQuery(
            tenantId: $this->tenantId,
            status: 'active',
            siteType: 'wordpress'
        );

        $results = $query->get();

        $this->assertCount(1, $results);
    }

    public function test_fluent_builder_pattern(): void
    {
        $results = SiteSearchQuery::make()
            ->forTenant($this->tenantId)
            ->withStatus('active')
            ->withType('wordpress')
            ->get();

        $this->assertCount(1, $results);
    }
}
