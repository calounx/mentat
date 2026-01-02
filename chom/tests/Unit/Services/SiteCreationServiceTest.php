<?php

declare(strict_types=1);

namespace Tests\Unit\Services;

use App\Models\Site;
use App\Models\User;
use App\Services\Sites\SiteCreationService;
use App\Services\Sites\SiteQuotaService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Mockery;
use Tests\Concerns\WithMockVpsManager;
use Tests\TestCase;

/**
 * Unit tests for Site Creation Service
 */
class SiteCreationServiceTest extends TestCase
{
    use RefreshDatabase;
    use WithMockVpsManager;

    protected SiteCreationService $service;

    protected User $user;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create();
        $this->setUpVpsMocks();

        $this->service = $this->app->make(SiteCreationService::class);
    }

    /**
     * Test successful site creation
     */
    public function test_creates_site_successfully(): void
    {
        // Arrange
        $this->mockSuccessfulVpsAllocation();
        $this->mockSuccessfulSshConnection();
        $this->mockSuccessfulSiteDeployment('test.com');

        $data = [
            'domain' => 'test.com',
            'site_type' => 'html',
        ];

        // Act
        $site = $this->service->create($data);

        // Assert
        $this->assertInstanceOf(Site::class, $site);
        $this->assertEquals('test.com', $site->domain);
        $this->assertEquals('html', $site->type);
        $this->assertEquals($this->user->id, $site->user_id);
    }

    /**
     * Test site creation checks quota
     */
    public function test_creation_checks_quota_before_proceeding(): void
    {
        // Arrange
        $quotaService = Mockery::mock(SiteQuotaService::class);
        $quotaService->shouldReceive('canCreateSite')
            ->with($this->user)
            ->once()
            ->andReturn(false);

        $this->app->instance(SiteQuotaService::class, $quotaService);

        // Act & Assert
        $this->expectException(\Exception::class);
        $this->expectExceptionMessage('quota');

        $this->service->createSite($this->user->currentTenant(), [
            'domain' => 'test.com',
            'site_type' => 'html',
        ]);
    }

    /**
     * Test site creation allocates VPS
     */
    public function test_creation_allocates_vps(): void
    {
        // Arrange
        $this->mockSuccessfulVpsAllocation('vps-123');

        // Act
        $this->service->createSite($this->user->currentTenant(), [
            'domain' => 'test.com',
            'site_type' => 'html',
        ]);

        // Assert
        $this->assertVpsAllocationCalled();
    }

    /**
     * Test rollback on failure
     */
    public function test_rolls_back_on_deployment_failure(): void
    {
        // Arrange
        $this->mockSuccessfulVpsAllocation();
        $this->mockVpsConnectionFailure('Connection failed');

        // Act & Assert
        try {
            $this->service->createSite($this->user->currentTenant(), [
                'domain' => 'test.com',
                'site_type' => 'html',
            ]);

            $this->fail('Expected exception not thrown');
        } catch (\Exception $e) {
            // Site should not exist
            $this->assertDatabaseMissing('sites', [
                'domain' => 'test.com',
            ]);
        }
    }

    /**
     * Test validation of site data
     */
    public function test_validates_site_data(): void
    {
        $this->expectException(\InvalidArgumentException::class);

        $this->service->createSite($this->user->currentTenant(), [
            'domain' => '', // Invalid
            'site_type' => 'html',
        ]);
    }

    /**
     * Test site creation sets up monitoring
     */
    public function test_creation_sets_up_monitoring(): void
    {
        // Arrange
        $this->mockSuccessfulVpsAllocation();
        $this->mockSuccessfulSshConnection();
        $this->mockSuccessfulSiteDeployment('monitored.com');

        // Act
        $site = $this->service->createSite($this->user->currentTenant(), [
            'domain' => 'monitored.com',
            'site_type' => 'html',
            'enable_monitoring' => true,
        ]);

        // Assert
        $this->assertNotNull($site->monitoring_enabled);
    }
}
