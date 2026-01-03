<?php

declare(strict_types=1);

namespace Tests\Unit\Queries;

use App\Queries\VpsServerQuery;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class VpsServerQueryTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        // Create test VPS servers
        DB::table('vps_servers')->insert([
            [
                'id' => \Illuminate\Support\Str::uuid(),
                'hostname' => 'vps1.example.com',
                'ip_address' => '192.168.1.1',
                'provider' => 'hetzner',
                'region' => 'us-east',
                'spec_cpu' => 4,
                'spec_memory_mb' => 8192,
                'spec_disk_gb' => 100,
                'status' => 'active',
                'allocation_type' => 'shared',
                'health_status' => 'healthy',
                'observability_configured' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ],
            [
                'id' => \Illuminate\Support\Str::uuid(),
                'hostname' => 'vps2.example.com',
                'ip_address' => '192.168.1.2',
                'provider' => 'digitalocean',
                'region' => 'eu-central',
                'spec_cpu' => 8,
                'spec_memory_mb' => 16384,
                'spec_disk_gb' => 200,
                'status' => 'active',
                'allocation_type' => 'dedicated',
                'health_status' => 'healthy',
                'observability_configured' => false,
                'created_at' => now(),
                'updated_at' => now(),
            ],
            [
                'id' => \Illuminate\Support\Str::uuid(),
                'hostname' => 'vps3.example.com',
                'ip_address' => '192.168.1.3',
                'provider' => 'hetzner',
                'region' => 'us-east',
                'spec_cpu' => 2,
                'spec_memory_mb' => 4096,
                'spec_disk_gb' => 50,
                'status' => 'maintenance',
                'allocation_type' => 'shared',
                'health_status' => 'degraded',
                'observability_configured' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ],
        ]);
    }

    public function test_filters_by_status(): void
    {
        $results = VpsServerQuery::make()
            ->withStatus('active')
            ->get();

        $this->assertCount(2, $results);
    }

    public function test_filters_by_region(): void
    {
        $results = VpsServerQuery::make()
            ->byRegion('us-east')
            ->get();

        $this->assertCount(2, $results);
    }

    public function test_filters_by_provider(): void
    {
        $results = VpsServerQuery::make()
            ->byProvider('hetzner')
            ->get();

        $this->assertCount(2, $results);
    }

    public function test_filters_by_allocation_type(): void
    {
        $results = VpsServerQuery::make()
            ->withAllocationType('shared')
            ->get();

        $this->assertCount(2, $results);
    }

    public function test_filters_by_health_status(): void
    {
        $results = VpsServerQuery::make()
            ->withHealthStatus('healthy')
            ->get();

        $this->assertCount(2, $results);
    }

    public function test_filters_by_minimum_cpu(): void
    {
        $results = VpsServerQuery::make()
            ->withMinimumCpu(4)
            ->get();

        $this->assertCount(2, $results);
    }

    public function test_filters_by_minimum_memory(): void
    {
        $results = VpsServerQuery::make()
            ->withMinimumMemory(8192)
            ->get();

        $this->assertCount(2, $results);
    }

    public function test_gets_available_servers(): void
    {
        $results = VpsServerQuery::make()
            ->available();

        $this->assertCount(2, $results);
    }

    public function test_gets_servers_with_observability(): void
    {
        $results = VpsServerQuery::make()
            ->withObservability();

        $this->assertCount(2, $results);
    }

    public function test_gets_servers_without_observability(): void
    {
        $results = VpsServerQuery::make()
            ->withoutObservability();

        $this->assertCount(1, $results);
    }

    public function test_counts_by_provider(): void
    {
        $counts = VpsServerQuery::make()->countByProvider();

        $this->assertEquals(2, $counts['hetzner'] ?? 0);
        $this->assertEquals(1, $counts['digitalocean'] ?? 0);
    }

    public function test_counts_by_region(): void
    {
        $counts = VpsServerQuery::make()->countByRegion();

        $this->assertEquals(2, $counts['us-east'] ?? 0);
        $this->assertEquals(1, $counts['eu-central'] ?? 0);
    }

    public function test_calculates_total_cpu_capacity(): void
    {
        $totalCpu = VpsServerQuery::make()
            ->withStatus('active')
            ->totalCpuCapacity();

        $this->assertEquals(12, $totalCpu); // 4 + 8
    }

    public function test_calculates_total_memory_capacity(): void
    {
        $totalMemory = VpsServerQuery::make()
            ->withStatus('active')
            ->totalMemoryCapacity();

        $this->assertEquals(24576, $totalMemory); // 8192 + 16384
    }

    public function test_calculates_total_disk_capacity(): void
    {
        $totalDisk = VpsServerQuery::make()
            ->withStatus('active')
            ->totalDiskCapacity();

        $this->assertEquals(300, $totalDisk); // 100 + 200
    }

    public function test_gets_health_check_summary(): void
    {
        $health = VpsServerQuery::make()->healthCheck();

        $this->assertIsArray($health);
        $this->assertArrayHasKey('total', $health);
        $this->assertArrayHasKey('by_health_status', $health);
        $this->assertArrayHasKey('healthy_percentage', $health);
        $this->assertEquals(3, $health['total']);
    }

    public function test_combines_multiple_filters(): void
    {
        $results = VpsServerQuery::make()
            ->withStatus('active')
            ->byRegion('us-east')
            ->byProvider('hetzner')
            ->withMinimumCpu(4)
            ->get();

        $this->assertCount(1, $results);
    }

    public function test_paginates_results(): void
    {
        $paginator = VpsServerQuery::make()->paginate(2);

        $this->assertCount(2, $paginator->items());
        $this->assertEquals(3, $paginator->total());
    }

    public function test_counts_total(): void
    {
        $count = VpsServerQuery::make()->count();

        $this->assertEquals(3, $count);
    }

    public function test_constructor_pattern(): void
    {
        $query = new VpsServerQuery(
            status: 'active',
            region: 'us-east'
        );

        $results = $query->get();

        $this->assertCount(1, $results);
    }

    public function test_fluent_builder_pattern(): void
    {
        $results = VpsServerQuery::make()
            ->withStatus('active')
            ->byRegion('us-east')
            ->get();

        $this->assertCount(1, $results);
    }
}
