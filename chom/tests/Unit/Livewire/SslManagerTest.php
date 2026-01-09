<?php

declare(strict_types=1);

namespace Tests\Unit\Livewire;

use App\Livewire\SslManager;
use App\Models\Organization;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\User;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * SSL Manager Unit Tests
 *
 * Tests the SslManager Livewire component for SSL certificate management.
 * Verifies tenant access control, API interactions, and user operations.
 */
class SslManagerTest extends TestCase
{
    use RefreshDatabase;

    private User $user;
    private Tenant $tenant;
    private Site $site;
    private VpsServer $vps;
    private Organization $organization;

    protected function setUp(): void
    {
        parent::setUp();

        // Create organization
        $this->organization = Organization::factory()->create();

        // Create tenant
        $this->tenant = Tenant::factory()->create([
            'organization_id' => $this->organization->id,
            'status' => 'active',
        ]);

        // Create user
        $this->user = User::factory()->create([
            'organization_id' => $this->organization->id,
        ]);
        $this->user->tenants()->attach($this->tenant);

        // Create VPS server
        $this->vps = VpsServer::factory()->create([
            'status' => 'active',
        ]);

        // Create site
        $this->site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vps->id,
            'domain' => 'example.com',
            'ssl_enabled' => false,
        ]);
    }

    /**
     * Test component can be mounted with valid site
     */
    public function test_component_mounts_with_valid_site(): void
    {
        Http::fake([
            '*/api/v1/sites/*/ssl/status' => Http::response([
                'data' => [
                    'domain' => 'example.com',
                    'status' => 'none',
                ],
            ], 200),
        ]);

        Livewire::actingAs($this->user)
            ->test(SslManager::class, ['site' => $this->site])
            ->assertSet('siteId', $this->site->id)
            ->assertStatus(200);
    }

    /**
     * Test component denies access for wrong tenant
     */
    public function test_component_denies_access_for_wrong_tenant(): void
    {
        // Create another tenant and site
        $otherTenant = Tenant::factory()->create([
            'organization_id' => Organization::factory()->create()->id,
            'status' => 'active',
        ]);

        $otherSite = Site::factory()->create([
            'tenant_id' => $otherTenant->id,
            'vps_id' => $this->vps->id,
        ]);

        // Try to access other tenant's site
        $this->expectException(\Symfony\Component\HttpKernel\Exception\HttpException::class);

        Livewire::actingAs($this->user)
            ->test(SslManager::class, ['site' => $otherSite]);
    }

    /**
     * Test refresh status fetches SSL data from API
     */
    public function test_refresh_status_fetches_ssl_data(): void
    {
        $sslData = [
            'domain' => 'example.com',
            'status' => 'valid',
            'issuer' => 'Let\'s Encrypt',
            'expires_at' => now()->addDays(60)->toISOString(),
            'days_remaining' => 60,
            'auto_renew_enabled' => true,
        ];

        Http::fake([
            '*/api/v1/sites/*/ssl/status' => Http::response([
                'data' => $sslData,
            ], 200),
        ]);

        Livewire::actingAs($this->user)
            ->test(SslManager::class, ['site' => $this->site])
            ->call('refreshStatus')
            ->assertSet('sslStatus', $sslData)
            ->assertSet('autoRenewEnabled', true)
            ->assertSet('errorMessage', null);
    }

    /**
     * Test refresh status handles API error
     */
    public function test_refresh_status_handles_api_error(): void
    {
        Http::fake([
            '*/api/v1/sites/*/ssl/status' => Http::response([
                'message' => 'API error occurred',
            ], 500),
        ]);

        Livewire::actingAs($this->user)
            ->test(SslManager::class, ['site' => $this->site])
            ->call('refreshStatus')
            ->assertSet('errorMessage', 'API error occurred');
    }

    /**
     * Test issue SSL certificate calls API correctly
     */
    public function test_issue_ssl_calls_api(): void
    {
        Http::fake([
            '*/api/v1/sites/*/ssl/status' => Http::response([
                'data' => ['domain' => 'example.com', 'status' => 'none'],
            ], 200),
            '*/api/v1/sites/*/ssl/issue' => Http::response([
                'data' => ['message' => 'SSL issuing'],
            ], 200),
        ]);

        Livewire::actingAs($this->user)
            ->test(SslManager::class, ['site' => $this->site])
            ->call('issueSSL')
            ->assertSet('processing', false)
            ->assertSet('successMessage', 'SSL certificate is being issued. This may take a few minutes.')
            ->assertDispatched('ssl-issued');

        Http::assertSent(function ($request) {
            return str_contains($request->url(), '/ssl/issue');
        });
    }

    /**
     * Test issue SSL handles error response
     */
    public function test_issue_ssl_handles_error(): void
    {
        Http::fake([
            '*/api/v1/sites/*/ssl/status' => Http::response([
                'data' => ['domain' => 'example.com', 'status' => 'none'],
            ], 200),
            '*/api/v1/sites/*/ssl/issue' => Http::response([
                'message' => 'Failed to issue certificate',
            ], 400),
        ]);

        Livewire::actingAs($this->user)
            ->test(SslManager::class, ['site' => $this->site])
            ->call('issueSSL')
            ->assertSet('processing', false)
            ->assertSet('errorMessage', 'Failed to issue certificate');
    }

    /**
     * Test renew SSL certificate calls API correctly
     */
    public function test_renew_ssl_calls_api(): void
    {
        Http::fake([
            '*/api/v1/sites/*/ssl/status' => Http::response([
                'data' => [
                    'domain' => 'example.com',
                    'status' => 'valid',
                    'expires_at' => now()->addDays(15)->toISOString(),
                ],
            ], 200),
            '*/api/v1/sites/*/ssl/renew' => Http::response([
                'data' => ['message' => 'SSL renewing'],
            ], 200),
        ]);

        Livewire::actingAs($this->user)
            ->test(SslManager::class, ['site' => $this->site])
            ->call('renewSSL')
            ->assertSet('processing', false)
            ->assertSet('successMessage', 'SSL certificate is being renewed. This may take a few minutes.')
            ->assertDispatched('ssl-renewed');

        Http::assertSent(function ($request) {
            return str_contains($request->url(), '/ssl/renew');
        });
    }

    /**
     * Test renew SSL handles error response
     */
    public function test_renew_ssl_handles_error(): void
    {
        Http::fake([
            '*/api/v1/sites/*/ssl/status' => Http::response([
                'data' => [
                    'domain' => 'example.com',
                    'status' => 'valid',
                ],
            ], 200),
            '*/api/v1/sites/*/ssl/renew' => Http::response([
                'message' => 'Failed to renew certificate',
            ], 500),
        ]);

        Livewire::actingAs($this->user)
            ->test(SslManager::class, ['site' => $this->site])
            ->call('renewSSL')
            ->assertSet('processing', false)
            ->assertSet('errorMessage', 'Failed to renew certificate');
    }

    /**
     * Test toggle auto-renew enables it correctly
     */
    public function test_toggle_auto_renew_enables(): void
    {
        Http::fake([
            '*/api/v1/sites/*/ssl/status' => Http::response([
                'data' => [
                    'domain' => 'example.com',
                    'status' => 'valid',
                    'auto_renew_enabled' => false,
                ],
            ], 200),
            '*/api/v1/sites/*/ssl/auto-renew' => Http::response([
                'data' => ['auto_renew_enabled' => true],
            ], 200),
        ]);

        Livewire::actingAs($this->user)
            ->test(SslManager::class, ['site' => $this->site])
            ->assertSet('autoRenewEnabled', false)
            ->call('toggleAutoRenew')
            ->assertSet('autoRenewEnabled', true)
            ->assertSet('successMessage', 'Auto-renewal enabled successfully.')
            ->assertDispatched('auto-renew-toggled');
    }

    /**
     * Test toggle auto-renew disables it correctly
     */
    public function test_toggle_auto_renew_disables(): void
    {
        Http::fake([
            '*/api/v1/sites/*/ssl/status' => Http::response([
                'data' => [
                    'domain' => 'example.com',
                    'status' => 'valid',
                    'auto_renew_enabled' => true,
                ],
            ], 200),
            '*/api/v1/sites/*/ssl/auto-renew' => Http::response([
                'data' => ['auto_renew_enabled' => false],
            ], 200),
        ]);

        Livewire::actingAs($this->user)
            ->test(SslManager::class, ['site' => $this->site])
            ->assertSet('autoRenewEnabled', true)
            ->call('toggleAutoRenew')
            ->assertSet('autoRenewEnabled', false)
            ->assertSet('successMessage', 'Auto-renewal disabled successfully.')
            ->assertDispatched('auto-renew-toggled');
    }

    /**
     * Test get status color returns correct colors
     */
    public function test_get_status_color_returns_correct_colors(): void
    {
        Http::fake([
            '*/api/v1/sites/*/ssl/status' => Http::response([
                'data' => [
                    'domain' => 'example.com',
                    'status' => 'valid',
                ],
            ], 200),
        ]);

        $component = Livewire::actingAs($this->user)
            ->test(SslManager::class, ['site' => $this->site]);

        // Valid status - green
        $component->set('sslStatus', ['status' => 'valid']);
        $this->assertEquals('green', $component->call('getStatusColor'));

        // Expiring soon - yellow
        $component->set('sslStatus', ['status' => 'expiring_soon']);
        $this->assertEquals('yellow', $component->call('getStatusColor'));

        // Expired - red
        $component->set('sslStatus', ['status' => 'expired']);
        $this->assertEquals('red', $component->call('getStatusColor'));

        // None - gray
        $component->set('sslStatus', ['status' => 'none']);
        $this->assertEquals('gray', $component->call('getStatusColor'));
    }

    /**
     * Test has certificate returns correct boolean
     */
    public function test_has_certificate_returns_correct_boolean(): void
    {
        Http::fake([
            '*/api/v1/sites/*/ssl/status' => Http::response([
                'data' => [
                    'domain' => 'example.com',
                    'status' => 'valid',
                ],
            ], 200),
        ]);

        $component = Livewire::actingAs($this->user)
            ->test(SslManager::class, ['site' => $this->site]);

        // With valid certificate
        $component->set('sslStatus', [
            'domain' => 'example.com',
            'status' => 'valid',
        ]);
        $this->assertTrue($component->call('hasCertificate'));

        // No certificate
        $component->set('sslStatus', [
            'domain' => 'example.com',
            'status' => 'none',
        ]);
        $this->assertFalse($component->call('hasCertificate'));

        // Null status
        $component->set('sslStatus', null);
        $this->assertFalse($component->call('hasCertificate'));
    }

    /**
     * Test can renew returns correct boolean
     */
    public function test_can_renew_returns_correct_boolean(): void
    {
        Http::fake([
            '*/api/v1/sites/*/ssl/status' => Http::response([
                'data' => [
                    'domain' => 'example.com',
                    'status' => 'valid',
                ],
            ], 200),
        ]);

        $component = Livewire::actingAs($this->user)
            ->test(SslManager::class, ['site' => $this->site]);

        // Valid certificate - can renew
        $component->set('sslStatus', [
            'domain' => 'example.com',
            'status' => 'valid',
        ]);
        $this->assertTrue($component->call('canRenew'));

        // Expiring soon - can renew
        $component->set('sslStatus', [
            'domain' => 'example.com',
            'status' => 'expiring_soon',
        ]);
        $this->assertTrue($component->call('canRenew'));

        // Expired - can renew
        $component->set('sslStatus', [
            'domain' => 'example.com',
            'status' => 'expired',
        ]);
        $this->assertTrue($component->call('canRenew'));

        // No certificate - cannot renew
        $component->set('sslStatus', [
            'domain' => 'example.com',
            'status' => 'none',
        ]);
        $this->assertFalse($component->call('canRenew'));
    }

    /**
     * Test component renders view correctly
     */
    public function test_component_renders_view(): void
    {
        Http::fake([
            '*/api/v1/sites/*/ssl/status' => Http::response([
                'data' => [
                    'domain' => 'example.com',
                    'status' => 'valid',
                    'issuer' => 'Let\'s Encrypt',
                    'expires_at' => now()->addDays(60)->toISOString(),
                    'days_remaining' => 60,
                ],
            ], 200),
        ]);

        Livewire::actingAs($this->user)
            ->test(SslManager::class, ['site' => $this->site])
            ->assertViewIs('livewire.ssl-manager')
            ->assertSee('SSL Certificate')
            ->assertSee('example.com')
            ->assertSee('Valid')
            ->assertSee('Let\'s Encrypt');
    }

    /**
     * Test component shows issue button when no certificate exists
     */
    public function test_shows_issue_button_when_no_certificate(): void
    {
        Http::fake([
            '*/api/v1/sites/*/ssl/status' => Http::response([
                'data' => [
                    'domain' => 'example.com',
                    'status' => 'none',
                ],
            ], 200),
        ]);

        Livewire::actingAs($this->user)
            ->test(SslManager::class, ['site' => $this->site])
            ->assertSee('Issue SSL Certificate');
    }

    /**
     * Test component shows renew button when certificate exists
     */
    public function test_shows_renew_button_when_certificate_exists(): void
    {
        Http::fake([
            '*/api/v1/sites/*/ssl/status' => Http::response([
                'data' => [
                    'domain' => 'example.com',
                    'status' => 'valid',
                    'issuer' => 'Let\'s Encrypt',
                    'expires_at' => now()->addDays(60)->toISOString(),
                    'days_remaining' => 60,
                ],
            ], 200),
        ]);

        Livewire::actingAs($this->user)
            ->test(SslManager::class, ['site' => $this->site])
            ->assertSee('Renew Certificate')
            ->assertSee('Auto-Renew');
    }
}
