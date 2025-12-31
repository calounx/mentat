<?php

declare(strict_types=1);

namespace Tests\Integration;

use App\Models\Site;
use App\Models\User;
use App\Services\Sites\SiteCreationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\WithMockObservability;
use Tests\Concerns\WithMockVpsManager;
use Tests\Concerns\WithPerformanceTesting;
use Tests\TestCase;

/**
 * Integration test for complete site provisioning flow
 *
 * Tests the entire site provisioning workflow from user request through
 * VPS allocation, site deployment, SSL installation, and observability setup.
 *
 * @package Tests\Integration
 */
class SiteProvisioningFlowTest extends TestCase
{
    use RefreshDatabase;
    use WithMockVpsManager;
    use WithMockObservability;
    use WithPerformanceTesting;

    protected User $user;
    protected SiteCreationService $siteService;

    /**
     * Set up test environment
     *
     * @return void
     */
    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create([
            'subscription_tier' => 'professional',
        ]);

        $this->setUpVpsMocks();
        $this->setUpObservabilityMocks();

        $this->siteService = $this->app->make(SiteCreationService::class);
    }

    /**
     * Test complete site provisioning flow for HTML site
     *
     * @return void
     */
    public function test_complete_html_site_provisioning_flow(): void
    {
        // Arrange
        $this->mockSuccessfulVpsAllocation();
        $this->mockSuccessfulSshConnection();
        $this->mockSuccessfulSiteDeployment('example.com');
        $this->mockSuccessfulSslInstallation('example.com');
        $this->mockGrafanaDashboardCreation('example.com Site Dashboard');
        $this->mockPrometheusMetric('site_created_total', 1.0);

        $siteData = [
            'domain' => 'example.com',
            'type' => 'html',
            'git_repository' => 'https://github.com/user/repo.git',
        ];

        // Act
        $site = $this->assertBenchmark(
            fn() => $this->actingAs($this->user)
                ->post('/api/v1/sites', $siteData)
                ->json('data'),
            'site_creation'
        );

        // Assert
        $this->assertDatabaseHas('sites', [
            'domain' => 'example.com',
            'type' => 'html',
            'status' => 'active',
            'user_id' => $this->user->id,
        ]);

        $this->assertSshConnectionEstablished();
        $this->assertVpsAllocationCalled();
        $this->assertGrafanaDashboardCreated();
        $this->assertPrometheusMetricRecorded('site_created_total');

        $this->assertNotNull($site['monitoring_dashboard_url']);
        $this->assertEquals('active', $site['status']);
    }

    /**
     * Test Laravel site provisioning with database setup
     *
     * @return void
     */
    public function test_laravel_site_provisioning_with_database(): void
    {
        // Arrange
        $this->mockSuccessfulVpsAllocation();
        $this->mockSuccessfulSshConnection();
        $this->mockCommandExecution('mysql -e "CREATE DATABASE laravel_app"', 'Database created');
        $this->mockCommandExecution('composer install --no-dev --optimize-autoloader', 'Dependencies installed');
        $this->mockCommandExecution('php artisan migrate --force', 'Migrations ran');
        $this->mockSuccessfulSiteDeployment('laravel-app.com');
        $this->mockSuccessfulSslInstallation('laravel-app.com');

        $siteData = [
            'domain' => 'laravel-app.com',
            'type' => 'laravel',
            'git_repository' => 'https://github.com/user/laravel-app.git',
            'php_version' => '8.2',
            'database_name' => 'laravel_app',
        ];

        // Act
        $response = $this->actingAs($this->user)
            ->post('/api/v1/sites', $siteData);

        // Assert
        $response->assertStatus(201);

        $this->assertCommandExecuted('mysql -e "CREATE DATABASE laravel_app"');
        $this->assertCommandExecuted('composer install --no-dev --optimize-autoloader');
        $this->assertCommandExecuted('php artisan migrate --force');

        $site = Site::where('domain', 'laravel-app.com')->first();
        $this->assertNotNull($site->database_name);
        $this->assertEquals('8.2', $site->php_version);
    }

    /**
     * Test WordPress site provisioning with auto-configuration
     *
     * @return void
     */
    public function test_wordpress_site_provisioning_with_auto_config(): void
    {
        // Arrange
        $this->mockSuccessfulVpsAllocation();
        $this->mockSuccessfulSshConnection();
        $this->mockCommandExecution('wp core download', 'WordPress downloaded');
        $this->mockCommandExecution(
            'wp config create',
            'wp-config.php created'
        );
        $this->mockCommandExecution('wp core install', 'WordPress installed');
        $this->mockSuccessfulSiteDeployment('wordpress-site.com');
        $this->mockSuccessfulSslInstallation('wordpress-site.com');

        $siteData = [
            'domain' => 'wordpress-site.com',
            'type' => 'wordpress',
            'admin_email' => 'admin@wordpress-site.com',
            'site_title' => 'My WordPress Site',
        ];

        // Act
        $response = $this->actingAs($this->user)
            ->post('/api/v1/sites', $siteData);

        // Assert
        $response->assertStatus(201);

        $this->assertCommandExecuted('wp core download');
        $this->assertCommandExecuted('wp config create');
        $this->assertCommandExecuted('wp core install');

        $site = Site::where('domain', 'wordpress-site.com')->first();
        $this->assertEquals('wordpress', $site->type);
        $this->assertTrue($site->wp_cli_available);
    }

    /**
     * Test site provisioning with quota enforcement
     *
     * @return void
     */
    public function test_site_provisioning_respects_quota_limits(): void
    {
        // Arrange - Create sites up to quota limit
        $userWithBasicPlan = User::factory()->create([
            'subscription_tier' => 'basic', // Assume basic plan allows 3 sites
        ]);

        Site::factory()->count(3)->create([
            'user_id' => $userWithBasicPlan->id,
        ]);

        $siteData = [
            'domain' => 'exceeds-quota.com',
            'type' => 'html',
        ];

        // Act
        $response = $this->actingAs($userWithBasicPlan)
            ->post('/api/v1/sites', $siteData);

        // Assert
        $response->assertStatus(403);
        $response->assertJson([
            'message' => 'Site quota exceeded for your subscription tier',
        ]);

        $this->assertDatabaseMissing('sites', [
            'domain' => 'exceeds-quota.com',
        ]);
    }

    /**
     * Test site provisioning rollback on failure
     *
     * @return void
     */
    public function test_site_provisioning_rollback_on_deployment_failure(): void
    {
        // Arrange
        $this->mockSuccessfulVpsAllocation();
        $this->mockSuccessfulSshConnection();
        $this->mockCommandFailure('nginx -t', 'Configuration test failed', 1);

        $siteData = [
            'domain' => 'failing-site.com',
            'type' => 'html',
        ];

        // Act
        $response = $this->actingAs($this->user)
            ->post('/api/v1/sites', $siteData);

        // Assert
        $response->assertStatus(500);

        // Site should not exist or should be marked as failed
        $site = Site::where('domain', 'failing-site.com')->first();
        if ($site) {
            $this->assertEquals('failed', $site->status);
        }
    }

    /**
     * Test multi-tenant site isolation during provisioning
     *
     * @return void
     */
    public function test_multi_tenant_isolation_during_provisioning(): void
    {
        // Arrange
        $tenant1 = User::factory()->create();
        $tenant2 = User::factory()->create();

        $this->mockSuccessfulVpsAllocation('vps-tenant1');
        $this->mockSuccessfulSshConnection();
        $this->mockSuccessfulSiteDeployment('tenant1.com');
        $this->mockSuccessfulSslInstallation('tenant1.com');
        $this->mockGrafanaOrgCreation('Tenant 1 Org', 1);

        $site1Data = [
            'domain' => 'tenant1.com',
            'type' => 'html',
        ];

        // Act
        $site1Response = $this->actingAs($tenant1)
            ->post('/api/v1/sites', $site1Data);

        // Attempt to access tenant1's site as tenant2
        $site1 = $site1Response->json('data');
        $unauthorizedAccess = $this->actingAs($tenant2)
            ->get("/api/v1/sites/{$site1['id']}");

        // Assert
        $unauthorizedAccess->assertStatus(403);
        $unauthorizedAccess->assertJson([
            'message' => 'This action is unauthorized.',
        ]);
    }

    /**
     * Test site provisioning with custom environment variables
     *
     * @return void
     */
    public function test_site_provisioning_with_environment_variables(): void
    {
        // Arrange
        $this->mockSuccessfulVpsAllocation();
        $this->mockSuccessfulSshConnection();
        $this->mockSuccessfulSiteDeployment('env-test.com');

        $envVars = [
            'APP_ENV' => 'production',
            'APP_DEBUG' => 'false',
            'API_KEY' => 'secret-key-123',
        ];

        $siteData = [
            'domain' => 'env-test.com',
            'type' => 'laravel',
            'environment_variables' => $envVars,
        ];

        // Act
        $response = $this->actingAs($this->user)
            ->post('/api/v1/sites', $siteData);

        // Assert
        $response->assertStatus(201);

        $site = Site::where('domain', 'env-test.com')->first();
        $storedEnvVars = json_decode($site->environment_variables, true);

        $this->assertEquals('production', $storedEnvVars['APP_ENV']);
        $this->assertEquals('false', $storedEnvVars['APP_DEBUG']);
        // Sensitive data should be encrypted
        $this->assertNotEquals('secret-key-123', $storedEnvVars['API_KEY']);
    }

    /**
     * Test concurrent site provisioning
     *
     * @return void
     */
    public function test_concurrent_site_provisioning(): void
    {
        // Arrange
        $this->mockSuccessfulVpsAllocation();
        $this->mockSuccessfulSshConnection();

        $sites = [
            ['domain' => 'concurrent1.com', 'type' => 'html'],
            ['domain' => 'concurrent2.com', 'type' => 'html'],
            ['domain' => 'concurrent3.com', 'type' => 'html'],
        ];

        // Act
        $responses = [];
        foreach ($sites as $siteData) {
            $this->mockSuccessfulSiteDeployment($siteData['domain']);
            $this->mockSuccessfulSslInstallation($siteData['domain']);

            $responses[] = $this->actingAs($this->user)
                ->post('/api/v1/sites', $siteData);
        }

        // Assert
        foreach ($responses as $response) {
            $response->assertStatus(201);
        }

        foreach ($sites as $siteData) {
            $this->assertDatabaseHas('sites', [
                'domain' => $siteData['domain'],
                'status' => 'active',
            ]);
        }
    }

    /**
     * Test site provisioning with monitoring setup
     *
     * @return void
     */
    public function test_site_provisioning_includes_monitoring_setup(): void
    {
        // Arrange
        $this->mockSuccessfulVpsAllocation();
        $this->mockSuccessfulSshConnection();
        $this->mockSuccessfulSiteDeployment('monitored-site.com');
        $this->mockSuccessfulSslInstallation('monitored-site.com');
        $this->mockGrafanaDashboardCreation('monitored-site.com Dashboard', 42);
        $this->mockPrometheusMetric('site_created_total', 1.0, ['type' => 'html']);

        $siteData = [
            'domain' => 'monitored-site.com',
            'type' => 'html',
            'enable_monitoring' => true,
        ];

        // Act
        $response = $this->actingAs($this->user)
            ->post('/api/v1/sites', $siteData);

        // Assert
        $response->assertStatus(201);
        $site = $response->json('data');

        $this->assertNotNull($site['monitoring_dashboard_url']);
        $this->assertStringContainsString('/d/', $site['monitoring_dashboard_url']);
        $this->assertGrafanaDashboardCreated();
        $this->assertPrometheusMetricRecorded('site_created_total');
    }
}
