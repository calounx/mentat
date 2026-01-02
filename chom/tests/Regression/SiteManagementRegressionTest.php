<?php

namespace Tests\Regression;

use App\Models\Site;
use App\Models\Tenant;
use App\Models\User;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class SiteManagementRegressionTest extends TestCase
{
    use RefreshDatabase;

    protected User $user;
    protected Tenant $tenant;
    protected VpsServer $vpsServer;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create();
        $this->tenant = $this->user->currentTenant();
        $this->vpsServer = VpsServer::factory()->create();
    }

    #[Test]
    public function site_can_be_created(): void
    {
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'domain' => 'example.com',
            'site_type' => 'wordpress',
        ]);

        $this->assertDatabaseHas('sites', [
            'domain' => 'example.com',
            'site_type' => 'wordpress',
        ]);
    }

    #[Test]
    public function site_belongs_to_tenant(): void
    {
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
        ]);

        $this->assertEquals($this->tenant->id, $site->tenant_id);
        $this->assertInstanceOf(Tenant::class, $site->tenant);
    }

    #[Test]
    public function site_belongs_to_vps_server(): void
    {
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vpsServer->id,
        ]);

        $this->assertEquals($this->vpsServer->id, $site->vps_id);
        $this->assertInstanceOf(VpsServer::class, $site->vpsServer);
    }

    #[Test]
    public function site_can_have_different_types(): void
    {
        $wordpress = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'site_type' => 'wordpress',
        ]);

        $laravel = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'site_type' => 'laravel',
        ]);

        $html = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'site_type' => 'html',
        ]);

        $this->assertEquals('wordpress', $wordpress->site_type);
        $this->assertEquals('laravel', $laravel->site_type);
        $this->assertEquals('html', $html->site_type);
    }

    #[Test]
    public function site_has_ssl_configuration(): void
    {
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addDays(90),
        ]);

        $this->assertTrue($site->ssl_enabled);
        $this->assertNotNull($site->ssl_expires_at);
    }

    #[Test]
    public function site_can_detect_expiring_ssl(): void
    {
        $expiringSoon = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addDays(10),
        ]);

        $notExpiring = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addDays(30),
        ]);

        $this->assertTrue($expiringSoon->isSslExpiringSoon());
        $this->assertFalse($notExpiring->isSslExpiringSoon());
    }

    #[Test]
    public function site_can_detect_expired_ssl(): void
    {
        $expired = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->subDays(1),
        ]);

        $valid = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addDays(30),
        ]);

        $this->assertTrue($expired->isSslExpired());
        $this->assertFalse($valid->isSslExpired());
    }

    #[Test]
    public function site_generates_correct_url(): void
    {
        $https = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'domain' => 'secure.example.com',
            'ssl_enabled' => true,
        ]);

        $http = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'domain' => 'insecure.example.com',
            'ssl_enabled' => false,
        ]);

        $this->assertEquals('https://secure.example.com', $https->getUrl());
        $this->assertEquals('http://insecure.example.com', $http->getUrl());
    }

    #[Test]
    public function site_has_status_tracking(): void
    {
        $active = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'status' => 'active',
        ]);

        $inactive = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'status' => 'inactive',
        ]);

        $this->assertTrue($active->isActive());
        $this->assertFalse($inactive->isActive());
    }

    #[Test]
    public function site_can_be_soft_deleted(): void
    {
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
        ]);

        $siteId = $site->id;
        $site->delete();

        $this->assertSoftDeleted('sites', ['id' => $siteId]);
        $this->assertNotNull(Site::withTrashed()->find($siteId)->deleted_at);
    }

    #[Test]
    public function site_has_backups_relationship(): void
    {
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
        ]);

        $this->assertInstanceOf(
            \Illuminate\Database\Eloquent\Relations\HasMany::class,
            $site->backups()
        );
    }

    #[Test]
    public function site_stores_settings_as_json(): void
    {
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'settings' => [
                'cache_enabled' => true,
                'max_upload_size' => '100M',
                'php_memory_limit' => '256M',
            ],
        ]);

        $this->assertEquals(true, $site->settings['cache_enabled']);
        $this->assertEquals('100M', $site->settings['max_upload_size']);
        $this->assertEquals('256M', $site->settings['php_memory_limit']);
    }

    #[Test]
    public function site_tracks_storage_usage(): void
    {
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'storage_used_mb' => 1500,
        ]);

        $this->assertEquals(1500, $site->storage_used_mb);
    }

    #[Test]
    public function active_sites_scope_works(): void
    {
        Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'status' => 'active',
        ]);
        Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'status' => 'active',
        ]);
        Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'status' => 'inactive',
        ]);

        $activeSites = Site::withoutGlobalScopes()->active()->count();

        $this->assertEquals(2, $activeSites);
    }

    #[Test]
    public function wordpress_sites_scope_works(): void
    {
        Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'site_type' => 'wordpress',
        ]);
        Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'site_type' => 'wordpress',
        ]);
        Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'site_type' => 'laravel',
        ]);

        $wordpressSites = Site::withoutGlobalScopes()->wordpress()->count();

        $this->assertEquals(2, $wordpressSites);
    }

    #[Test]
    public function ssl_expiring_soon_scope_works(): void
    {
        Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addDays(7),
        ]);
        Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addDays(10),
        ]);
        Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addDays(30),
        ]);

        $expiringSites = Site::withoutGlobalScopes()->sslExpiringSoon()->count();

        $this->assertEquals(2, $expiringSites);
    }

    #[Test]
    public function user_can_list_sites_via_api(): void
    {
        Sanctum::actingAs($this->user);

        Site::factory(3)->create([
            'tenant_id' => $this->tenant->id,
        ]);

        $response = $this->getJson('/api/v1/sites');

        $response->assertStatus(200);
        $response->assertJsonCount(3, 'data');
    }

    #[Test]
    public function user_can_create_site_via_api(): void
    {
        Sanctum::actingAs($this->user);

        $response = $this->postJson('/api/v1/sites', [
            'domain' => 'newsite.example.com',
            'site_type' => 'wordpress',
            'php_version' => '8.2',
        ]);

        $response->assertStatus(201);
        $this->assertDatabaseHas('sites', [
            'domain' => 'newsite.example.com',
            'site_type' => 'wordpress',
        ]);
    }

    #[Test]
    public function user_can_view_site_details_via_api(): void
    {
        Sanctum::actingAs($this->user);

        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'domain' => 'testsite.example.com',
        ]);

        $response = $this->getJson("/api/v1/sites/{$site->id}");

        $response->assertStatus(200);
        $response->assertJson([
            'id' => $site->id,
            'domain' => 'testsite.example.com',
        ]);
    }

    #[Test]
    public function user_can_update_site_via_api(): void
    {
        Sanctum::actingAs($this->user);

        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'domain' => 'oldname.example.com',
        ]);

        $response = $this->putJson("/api/v1/sites/{$site->id}", [
            'domain' => 'newname.example.com',
        ]);

        $response->assertStatus(200);
        $this->assertDatabaseHas('sites', [
            'id' => $site->id,
            'domain' => 'newname.example.com',
        ]);
    }

    #[Test]
    public function user_can_delete_site_via_api(): void
    {
        Sanctum::actingAs($this->user);

        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
        ]);

        $response = $this->deleteJson("/api/v1/sites/{$site->id}");

        $response->assertStatus(200);
        $this->assertSoftDeleted('sites', ['id' => $site->id]);
    }
}
