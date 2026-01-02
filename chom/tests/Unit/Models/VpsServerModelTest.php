<?php

namespace Tests\Unit\Models;

use App\Models\Site;
use App\Models\Tenant;
use App\Models\VpsAllocation;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class VpsServerModelTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function it_has_correct_fillable_attributes()
    {
        $fillable = [
            'hostname',
            'ip_address',
            'provider',
            'provider_id',
            'region',
            'spec_cpu',
            'spec_memory_mb',
            'spec_disk_gb',
            'status',
            'allocation_type',
            'vpsmanager_version',
            'observability_configured',
            'ssh_key_id',
            'ssh_private_key',
            'ssh_public_key',
            'key_rotated_at',
            'last_health_check_at',
            'health_status',
        ];

        $vpsServer = new VpsServer();
        $this->assertEquals($fillable, $vpsServer->getFillable());
    }

    #[Test]
    public function it_hides_sensitive_attributes()
    {
        $vpsServer = VpsServer::factory()->create([
            'ssh_key_id' => 'key_123',
            'provider_id' => 'provider_456',
            'ssh_private_key' => 'private_key_secret',
            'ssh_public_key' => 'public_key_secret',
        ]);

        $array = $vpsServer->toArray();

        $this->assertArrayNotHasKey('ssh_key_id', $array);
        $this->assertArrayNotHasKey('provider_id', $array);
        $this->assertArrayNotHasKey('ssh_private_key', $array);
        $this->assertArrayNotHasKey('ssh_public_key', $array);
    }

    #[Test]
    public function it_casts_attributes_correctly()
    {
        $vpsServer = VpsServer::factory()->create([
            'observability_configured' => true,
            'last_health_check_at' => now(),
            'key_rotated_at' => now(),
        ]);

        $this->assertTrue(is_bool($vpsServer->observability_configured));
        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $vpsServer->last_health_check_at);
        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $vpsServer->key_rotated_at);
    }

    #[Test]
    public function it_encrypts_ssh_keys()
    {
        $vpsServer = VpsServer::factory()->create([
            'ssh_private_key' => 'my-private-key',
            'ssh_public_key' => 'my-public-key',
        ]);

        // Reload from database
        $vpsServer->refresh();

        // The values should be decrypted automatically
        $this->assertEquals('my-private-key', $vpsServer->ssh_private_key);
        $this->assertEquals('my-public-key', $vpsServer->ssh_public_key);

        // Raw database values should be encrypted
        $rawPrivate = \DB::table('vps_servers')->where('id', $vpsServer->id)->value('ssh_private_key');
        $rawPublic = \DB::table('vps_servers')->where('id', $vpsServer->id)->value('ssh_public_key');

        $this->assertNotEquals('my-private-key', $rawPrivate);
        $this->assertNotEquals('my-public-key', $rawPublic);
    }

    #[Test]
    public function it_has_many_sites()
    {
        $vpsServer = VpsServer::factory()->create();
        Site::factory()->count(6)->create(['vps_id' => $vpsServer->id]);

        $this->assertInstanceOf(\Illuminate\Database\Eloquent\Collection::class, $vpsServer->sites);
        $this->assertCount(6, $vpsServer->sites);
        $this->assertInstanceOf(Site::class, $vpsServer->sites->first());
    }

    #[Test]
    public function it_has_many_allocations()
    {
        $vpsServer = VpsServer::factory()->create();
        VpsAllocation::factory()->count(3)->create(['vps_id' => $vpsServer->id]);

        $this->assertInstanceOf(\Illuminate\Database\Eloquent\Collection::class, $vpsServer->allocations);
        $this->assertCount(3, $vpsServer->allocations);
        $this->assertInstanceOf(VpsAllocation::class, $vpsServer->allocations->first());
    }

    #[Test]
    public function it_has_many_tenants_through_allocations()
    {
        $vpsServer = VpsServer::factory()->create();
        $tenant1 = Tenant::factory()->create();
        $tenant2 = Tenant::factory()->create();

        VpsAllocation::factory()->create([
            'vps_id' => $vpsServer->id,
            'tenant_id' => $tenant1->id,
        ]);
        VpsAllocation::factory()->create([
            'vps_id' => $vpsServer->id,
            'tenant_id' => $tenant2->id,
        ]);

        $this->assertInstanceOf(\Illuminate\Database\Eloquent\Collection::class, $vpsServer->tenants);
        $this->assertCount(2, $vpsServer->tenants);
        $this->assertInstanceOf(Tenant::class, $vpsServer->tenants->first());
    }

    #[Test]
    public function it_checks_if_vps_is_available()
    {
        $available = VpsServer::factory()->create([
            'status' => 'active',
            'health_status' => 'healthy',
        ]);

        $inactive = VpsServer::factory()->create([
            'status' => 'inactive',
            'health_status' => 'healthy',
        ]);

        $unhealthy = VpsServer::factory()->create([
            'status' => 'active',
            'health_status' => 'unhealthy',
        ]);

        $this->assertTrue($available->isAvailable());
        $this->assertFalse($inactive->isAvailable());
        $this->assertFalse($unhealthy->isAvailable());
    }

    #[Test]
    public function it_calculates_available_memory()
    {
        $vpsServer = VpsServer::factory()->create([
            'spec_memory_mb' => 8192,
        ]);

        VpsAllocation::factory()->create([
            'vps_id' => $vpsServer->id,
            'memory_mb_allocated' => 2048,
        ]);
        VpsAllocation::factory()->create([
            'vps_id' => $vpsServer->id,
            'memory_mb_allocated' => 1024,
        ]);

        $available = $vpsServer->getAvailableMemoryMb();

        $this->assertEquals(5120, $available); // 8192 - 2048 - 1024
    }

    #[Test]
    public function it_gets_site_count()
    {
        $vpsServer = VpsServer::factory()->create();
        Site::factory()->count(7)->create(['vps_id' => $vpsServer->id]);

        $this->assertEquals(7, $vpsServer->getSiteCount());
    }

    #[Test]
    public function it_calculates_utilization_percentage()
    {
        $vpsServer = VpsServer::factory()->create([
            'spec_memory_mb' => 4096,
        ]);

        VpsAllocation::factory()->create([
            'vps_id' => $vpsServer->id,
            'memory_mb_allocated' => 2048,
        ]);

        $utilization = $vpsServer->getUtilizationPercent();

        $this->assertEquals(50.0, $utilization);
    }

    #[Test]
    public function it_checks_if_vps_is_shared()
    {
        $shared = VpsServer::factory()->create(['allocation_type' => 'shared']);
        $dedicated = VpsServer::factory()->create(['allocation_type' => 'dedicated']);

        $this->assertTrue($shared->isShared());
        $this->assertFalse($dedicated->isShared());
    }

    #[Test]
    public function it_scopes_active_vps_servers()
    {
        VpsServer::factory()->count(4)->create(['status' => 'active']);
        VpsServer::factory()->count(2)->create(['status' => 'inactive']);

        $activeServers = VpsServer::active()->get();

        $this->assertCount(4, $activeServers);
    }

    #[Test]
    public function it_scopes_shared_vps_servers()
    {
        VpsServer::factory()->count(5)->create(['allocation_type' => 'shared']);
        VpsServer::factory()->count(3)->create(['allocation_type' => 'dedicated']);

        $sharedServers = VpsServer::shared()->get();

        $this->assertCount(5, $sharedServers);
    }

    #[Test]
    public function it_scopes_healthy_vps_servers()
    {
        VpsServer::factory()->count(3)->create(['health_status' => 'healthy']);
        VpsServer::factory()->count(2)->create(['health_status' => 'unknown']);
        VpsServer::factory()->count(1)->create(['health_status' => 'unhealthy']);

        $healthyServers = VpsServer::healthy()->get();

        $this->assertCount(5, $healthyServers); // healthy + unknown
    }

    #[Test]
    public function it_uses_uuid_as_primary_key()
    {
        $vpsServer = VpsServer::factory()->create();

        $this->assertIsString($vpsServer->id);
        $this->assertEquals(36, strlen($vpsServer->id));
        $this->assertMatchesRegularExpression(
            '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i',
            $vpsServer->id
        );
    }

    #[Test]
    public function it_has_timestamps()
    {
        $vpsServer = VpsServer::factory()->create();

        $this->assertNotNull($vpsServer->created_at);
        $this->assertNotNull($vpsServer->updated_at);
        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $vpsServer->created_at);
        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $vpsServer->updated_at);
    }
}
