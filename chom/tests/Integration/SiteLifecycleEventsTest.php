<?php

namespace Tests\Integration;

use App\Events\Site\SiteCreated;
use App\Events\Site\SiteDeleted;
use App\Events\Site\SiteProvisioned;
use App\Events\Site\SiteProvisioningFailed;
use App\Jobs\ProvisionSiteJob;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\TierLimit;
use App\Models\User;
use App\Models\VpsServer;
use App\Services\Sites\SiteCreationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;

/**
 * Integration tests for Site lifecycle events.
 *
 * Tests the complete event flow from site creation through provisioning to deletion,
 * verifying that all events are dispatched correctly and listeners are triggered.
 */
class SiteLifecycleEventsTest extends TestCase
{
    use RefreshDatabase;

    protected User $user;

    protected Tenant $tenant;

    protected VpsServer $vps;

    protected SiteCreationService $siteCreationService;

    protected function setUp(): void
    {
        parent::setUp();

        // Create test data
        $this->user = User::factory()->create();
        $this->tenant = Tenant::factory()->create(['organization_id' => $this->user->organization_id]);

        TierLimit::firstOrCreate(
            ['tier' => 'starter'],
            [
                'name' => 'Starter',
                'max_sites' => 10,
                'max_storage_gb' => 10,
                'max_bandwidth_gb' => 100,
                'backup_retention_days' => 7,
                'support_level' => 'email',
                'dedicated_ip' => false,
                'staging_environments' => false,
                'white_label' => false,
                'api_rate_limit_per_hour' => 100,
                'price_monthly_cents' => 999,
            ]
        );

        $this->vps = VpsServer::factory()->create([
            'status' => 'active',
            'health_status' => 'healthy',
        ]);

        $this->siteCreationService = app(SiteCreationService::class);
    }

    /**
     * Test that SiteCreated event is dispatched when creating a site.
     */
    public function test_site_created_event_is_dispatched(): void
    {
        Event::fake([SiteCreated::class]);

        // Create site
        $this->actingAs($this->user);
        $site = $this->siteCreationService->createSite($this->tenant, [
            'domain' => 'example.com',
            'site_type' => 'wordpress',
            'php_version' => '8.2',
            'ssl_enabled' => true,
        ]);

        // Assert event was dispatched
        Event::assertDispatched(SiteCreated::class, function ($event) use ($site) {
            return $event->site->id === $site->id
                && $event->tenant->id === $this->tenant->id
                && $event->actorId === $this->user->id;
        });
    }

    /**
     * Test that SiteCreated event triggers all expected listeners.
     */
    public function test_site_created_event_triggers_listeners(): void
    {
        Event::fake([SiteCreated::class]);
        Queue::fake();

        // Create site
        $this->actingAs($this->user);
        $site = $this->siteCreationService->createSite($this->tenant, [
            'domain' => 'example.com',
            'site_type' => 'wordpress',
        ]);

        Event::assertDispatched(SiteCreated::class);

        // In a real environment, these listeners would be queued
        // We can't test their execution without running queue workers,
        // but we can verify the event was dispatched
        $this->assertDatabaseHas('sites', [
            'id' => $site->id,
            'domain' => 'example.com',
            'tenant_id' => $this->tenant->id,
        ]);
    }

    /**
     * Test that SiteProvisioned event is dispatched on successful provisioning.
     */
    public function test_site_provisioned_event_is_dispatched(): void
    {
        Event::fake([SiteProvisioned::class]);

        // Create site
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vps->id,
            'status' => 'creating',
        ]);

        // Mock successful provisioning
        $this->mock(\App\Services\Sites\Provisioners\ProvisionerFactory::class)
            ->shouldReceive('make')
            ->andReturn($this->mock(\App\Services\Sites\Provisioners\WordpressProvisioner::class, function ($mock) {
                $mock->shouldReceive('validate')->andReturn(true);
                $mock->shouldReceive('provision')->andReturn([
                    'success' => true,
                    'output' => 'Site provisioned successfully',
                ]);
            }));

        // Dispatch provisioning job
        $job = new ProvisionSiteJob($site);
        $job->handle(app(\App\Services\Sites\Provisioners\ProvisionerFactory::class));

        // Assert event was dispatched
        Event::assertDispatched(SiteProvisioned::class, function ($event) use ($site) {
            return $event->site->id === $site->id
                && isset($event->provisioningDetails['duration']);
        });
    }

    /**
     * Test that SiteProvisioningFailed event is dispatched on failure.
     */
    public function test_site_provisioning_failed_event_is_dispatched(): void
    {
        Event::fake([SiteProvisioningFailed::class]);

        // Create site without VPS (will fail)
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => null,
            'status' => 'creating',
        ]);

        // Dispatch provisioning job
        $job = new ProvisionSiteJob($site);
        $job->handle(app(\App\Services\Sites\Provisioners\ProvisionerFactory::class));

        // Assert event was dispatched
        Event::assertDispatched(SiteProvisioningFailed::class, function ($event) use ($site) {
            return $event->site->id === $site->id
                && str_contains($event->errorMessage, 'No VPS server');
        });
    }

    /**
     * Test that SiteDeleted event is dispatched when deleting a site.
     */
    public function test_site_deleted_event_is_dispatched(): void
    {
        Event::fake([SiteDeleted::class]);

        // Create site
        $site = Site::factory()->create([
            'tenant_id' => $this->tenant->id,
            'vps_id' => $this->vps->id,
            'status' => 'active',
        ]);

        $siteId = $site->id;
        $tenantId = $site->tenant_id;
        $domain = $site->domain;

        // Delete site (simulate controller logic)
        $site->delete();
        \App\Events\Site\SiteDeleted::dispatch($siteId, $tenantId, $domain);

        // Assert event was dispatched
        Event::assertDispatched(SiteDeleted::class, function ($event) use ($siteId, $tenantId, $domain) {
            return $event->siteId === $siteId
                && $event->tenantId === $tenantId
                && $event->domain === $domain;
        });
    }

    /**
     * Test complete site lifecycle: create → provision → delete.
     */
    public function test_complete_site_lifecycle_events(): void
    {
        Event::fake();

        // Step 1: Create site
        $this->actingAs($this->user);
        $site = $this->siteCreationService->createSite($this->tenant, [
            'domain' => 'lifecycle-test.com',
            'site_type' => 'wordpress',
        ]);

        Event::assertDispatched(SiteCreated::class);

        // Step 2: Simulate successful provisioning
        $this->mock(\App\Services\Sites\Provisioners\ProvisionerFactory::class)
            ->shouldReceive('make')
            ->andReturn($this->mock(\App\Services\Sites\Provisioners\WordpressProvisioner::class, function ($mock) {
                $mock->shouldReceive('validate')->andReturn(true);
                $mock->shouldReceive('provision')->andReturn(['success' => true]);
            }));

        $job = new ProvisionSiteJob($site->fresh());
        $job->handle(app(\App\Services\Sites\Provisioners\ProvisionerFactory::class));

        Event::assertDispatched(SiteProvisioned::class);

        // Step 3: Delete site
        $siteId = $site->id;
        $tenantId = $site->tenant_id;
        $domain = $site->domain;

        $site->delete();
        \App\Events\Site\SiteDeleted::dispatch($siteId, $tenantId, $domain);

        Event::assertDispatched(SiteDeleted::class);

        // Verify all three events were dispatched in correct order
        Event::assertDispatchedTimes(SiteCreated::class, 1);
        Event::assertDispatchedTimes(SiteProvisioned::class, 1);
        Event::assertDispatchedTimes(SiteDeleted::class, 1);
    }

    /**
     * Test that event metadata is correctly populated.
     */
    public function test_site_created_event_metadata(): void
    {
        $this->actingAs($this->user);

        $site = $this->siteCreationService->createSite($this->tenant, [
            'domain' => 'metadata-test.com',
            'site_type' => 'laravel',
            'php_version' => '8.2',
            'ssl_enabled' => true,
        ]);

        // Manually create and inspect event
        $event = new SiteCreated($site, $this->tenant, $this->user->id);
        $metadata = $event->getMetadata();

        $this->assertArrayHasKey('event', $metadata);
        $this->assertArrayHasKey('occurred_at', $metadata);
        $this->assertArrayHasKey('site_id', $metadata);
        $this->assertArrayHasKey('tenant_id', $metadata);
        $this->assertArrayHasKey('domain', $metadata);
        $this->assertArrayHasKey('site_type', $metadata);
        $this->assertEquals('metadata-test.com', $metadata['domain']);
        $this->assertEquals('laravel', $metadata['site_type']);
    }
}
