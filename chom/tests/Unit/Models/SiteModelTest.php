<?php

namespace Tests\Unit\Models;

use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\Tenant;
use App\Models\User;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class SiteModelTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function it_has_correct_fillable_attributes()
    {
        $fillable = [
            'tenant_id',
            'vps_id',
            'domain',
            'site_type',
            'php_version',
            'ssl_enabled',
            'ssl_expires_at',
            'status',
            'document_root',
            'db_name',
            'db_user',
            'storage_used_mb',
            'settings',
        ];

        $site = new Site();
        $this->assertEquals($fillable, $site->getFillable());
    }

    #[Test]
    public function it_hides_sensitive_attributes()
    {
        $site = Site::withoutGlobalScopes()->first() ?? Site::factory()->create([
            'db_user' => 'db_user_secret',
            'db_name' => 'db_name_secret',
            'document_root' => '/var/www/secret',
        ]);

        $array = $site->toArray();

        $this->assertArrayNotHasKey('db_user', $array);
        $this->assertArrayNotHasKey('db_name', $array);
        $this->assertArrayNotHasKey('document_root', $array);
    }

    #[Test]
    public function it_casts_attributes_correctly()
    {
        $site = Site::factory()->create([
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addDays(90),
            'settings' => ['auto_update' => true],
        ]);

        // Remove global scope for testing
        $site = Site::withoutGlobalScopes()->find($site->id);

        $this->assertTrue(is_bool($site->ssl_enabled));
        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $site->ssl_expires_at);
        $this->assertIsArray($site->settings);
    }

    #[Test]
    public function it_belongs_to_a_tenant()
    {
        $tenant = Tenant::factory()->create();
        $site = Site::factory()->create(['tenant_id' => $tenant->id]);

        $site = Site::withoutGlobalScopes()->find($site->id);

        $this->assertInstanceOf(Tenant::class, $site->tenant);
        $this->assertEquals($tenant->id, $site->tenant->id);
    }

    #[Test]
    public function it_belongs_to_a_vps_server()
    {
        $vpsServer = VpsServer::factory()->create();
        $site = Site::factory()->create(['vps_id' => $vpsServer->id]);

        $site = Site::withoutGlobalScopes()->find($site->id);

        $this->assertInstanceOf(VpsServer::class, $site->vpsServer);
        $this->assertEquals($vpsServer->id, $site->vpsServer->id);
    }

    #[Test]
    public function it_has_many_backups()
    {
        $site = Site::factory()->create();
        SiteBackup::factory()->count(5)->create(['site_id' => $site->id]);

        $site = Site::withoutGlobalScopes()->find($site->id);

        $this->assertInstanceOf(\Illuminate\Database\Eloquent\Collection::class, $site->backups);
        $this->assertCount(5, $site->backups);
        $this->assertInstanceOf(SiteBackup::class, $site->backups->first());
    }

    #[Test]
    public function it_checks_if_site_is_active()
    {
        $activeSite = Site::factory()->create(['status' => 'active']);
        $pendingSite = Site::factory()->create(['status' => 'pending']);

        $activeSite = Site::withoutGlobalScopes()->find($activeSite->id);
        $pendingSite = Site::withoutGlobalScopes()->find($pendingSite->id);

        $this->assertTrue($activeSite->isActive());
        $this->assertFalse($pendingSite->isActive());
    }

    #[Test]
    public function it_checks_if_ssl_is_expiring_soon()
    {
        $expiringSoon = Site::factory()->create([
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addDays(7),
        ]);

        $notExpiring = Site::factory()->create([
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addDays(30),
        ]);

        $sslDisabled = Site::factory()->create([
            'ssl_enabled' => false,
        ]);

        $expiringSoon = Site::withoutGlobalScopes()->find($expiringSoon->id);
        $notExpiring = Site::withoutGlobalScopes()->find($notExpiring->id);
        $sslDisabled = Site::withoutGlobalScopes()->find($sslDisabled->id);

        $this->assertTrue($expiringSoon->isSslExpiringSoon());
        $this->assertFalse($notExpiring->isSslExpiringSoon());
        $this->assertFalse($sslDisabled->isSslExpiringSoon());
    }

    #[Test]
    public function it_checks_if_ssl_has_expired()
    {
        $expired = Site::factory()->create([
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->subDays(1),
        ]);

        $notExpired = Site::factory()->create([
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addDays(30),
        ]);

        $expired = Site::withoutGlobalScopes()->find($expired->id);
        $notExpired = Site::withoutGlobalScopes()->find($notExpired->id);

        $this->assertTrue($expired->isSslExpired());
        $this->assertFalse($notExpired->isSslExpired());
    }

    #[Test]
    public function it_gets_site_url_with_correct_protocol()
    {
        $httpsSize = Site::factory()->create([
            'ssl_enabled' => true,
            'domain' => 'secure.example.com',
        ]);

        $httpSite = Site::factory()->create([
            'ssl_enabled' => false,
            'domain' => 'insecure.example.com',
        ]);

        $httpsSize = Site::withoutGlobalScopes()->find($httpsSize->id);
        $httpSite = Site::withoutGlobalScopes()->find($httpSite->id);

        $this->assertEquals('https://secure.example.com', $httpsSize->getUrl());
        $this->assertEquals('http://insecure.example.com', $httpSite->getUrl());
    }

    #[Test]
    public function it_scopes_active_sites()
    {
        Site::factory()->count(3)->create(['status' => 'active']);
        Site::factory()->count(2)->create(['status' => 'suspended']);

        $activeSites = Site::withoutGlobalScopes()->active()->get();

        $this->assertCount(3, $activeSites);
    }

    #[Test]
    public function it_scopes_wordpress_sites()
    {
        Site::factory()->count(4)->create(['site_type' => 'wordpress']);
        Site::factory()->count(2)->create(['site_type' => 'laravel']);

        $wordpressSites = Site::withoutGlobalScopes()->wordpress()->get();

        $this->assertCount(4, $wordpressSites);
    }

    #[Test]
    public function it_scopes_ssl_expiring_soon()
    {
        Site::factory()->count(2)->create([
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addDays(7),
        ]);

        Site::factory()->count(3)->create([
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addDays(30),
        ]);

        $expiringSites = Site::withoutGlobalScopes()->sslExpiringSoon(14)->get();

        $this->assertCount(2, $expiringSites);
    }

    #[Test]
    public function it_applies_tenant_scope_globally()
    {
        $user = User::factory()->create();
        $tenant = Tenant::factory()->create(['organization_id' => $user->organization_id]);
        $user->organization->update(['default_tenant_id' => $tenant->id]);

        Site::factory()->count(3)->create(['tenant_id' => $tenant->id]);
        Site::factory()->count(2)->create(); // Different tenant

        $this->actingAs($user);

        $sites = Site::all();

        $this->assertCount(3, $sites);
    }

    #[Test]
    public function it_uses_soft_deletes()
    {
        $site = Site::factory()->create();
        $siteId = $site->id;

        $site = Site::withoutGlobalScopes()->find($siteId);
        $site->delete();

        // Should not find with default query
        $this->assertNull(Site::withoutGlobalScopes()->find($siteId));

        // Should find with trashed
        $this->assertNotNull(Site::withoutGlobalScopes()->withTrashed()->find($siteId));
        $this->assertTrue(Site::withoutGlobalScopes()->withTrashed()->find($siteId)->trashed());
    }

    #[Test]
    public function it_uses_uuid_as_primary_key()
    {
        $site = Site::factory()->create();

        $this->assertIsString($site->id);
        $this->assertEquals(36, strlen($site->id));
        $this->assertMatchesRegularExpression(
            '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i',
            $site->id
        );
    }

    #[Test]
    public function it_has_timestamps()
    {
        $site = Site::factory()->create();

        $site = Site::withoutGlobalScopes()->find($site->id);

        $this->assertNotNull($site->created_at);
        $this->assertNotNull($site->updated_at);
        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $site->created_at);
        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $site->updated_at);
    }
}
