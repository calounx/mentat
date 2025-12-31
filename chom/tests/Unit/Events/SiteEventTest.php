<?php

namespace Tests\Unit\Events;

use App\Events\Site\SiteCreated;
use App\Events\Site\SiteDeleted;
use App\Events\Site\SiteProvisioned;
use App\Events\Site\SiteProvisioningFailed;
use App\Models\Site;
use App\Models\Tenant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SiteEventTest extends TestCase
{
    use RefreshDatabase;

    public function test_site_created_event_contains_required_data(): void
    {
        $tenant = Tenant::factory()->create();
        $site = Site::factory()->create(['tenant_id' => $tenant->id]);

        $event = new SiteCreated($site, $tenant, 'test-user-id');

        $this->assertSame($site->id, $event->site->id);
        $this->assertSame($tenant->id, $event->tenant->id);
        $this->assertEquals('test-user-id', $event->actorId);
        $this->assertEquals('user', $event->actorType);

        $metadata = $event->getMetadata();
        $this->assertArrayHasKey('site_id', $metadata);
        $this->assertArrayHasKey('domain', $metadata);
        $this->assertArrayHasKey('site_type', $metadata);
        $this->assertEquals($site->domain, $metadata['domain']);
    }

    public function test_site_created_event_has_correct_name(): void
    {
        $tenant = Tenant::factory()->create();
        $site = Site::factory()->create(['tenant_id' => $tenant->id]);

        $event = new SiteCreated($site, $tenant);

        $this->assertEquals('SiteCreated', $event->getEventName());
    }

    public function test_site_provisioned_event_includes_duration(): void
    {
        $site = Site::factory()->create();

        $event = new SiteProvisioned($site, ['duration' => 45.2]);

        $metadata = $event->getMetadata();
        $this->assertEquals(45.2, $metadata['duration_seconds']);
        $this->assertEquals('system', $event->actorType);
    }

    public function test_site_provisioned_event_includes_site_data(): void
    {
        $site = Site::factory()->create([
            'domain' => 'test.example.com',
            'site_type' => 'wordpress',
        ]);

        $event = new SiteProvisioned($site);

        $metadata = $event->getMetadata();
        $this->assertEquals($site->id, $metadata['site_id']);
        $this->assertEquals('test.example.com', $metadata['domain']);
        $this->assertEquals('wordpress', $metadata['site_type']);
    }

    public function test_site_provisioning_failed_event_includes_error(): void
    {
        $site = Site::factory()->create();

        $event = new SiteProvisioningFailed(
            $site,
            'Connection timeout',
            'stack trace here...'
        );

        $this->assertEquals('Connection timeout', $event->errorMessage);
        $this->assertEquals('stack trace here...', $event->errorTrace);

        $metadata = $event->getMetadata();
        $this->assertEquals('Connection timeout', $metadata['error']);
        $this->assertTrue($metadata['has_trace']);
    }

    public function test_site_provisioning_failed_event_works_without_trace(): void
    {
        $site = Site::factory()->create();

        $event = new SiteProvisioningFailed($site, 'Error message');

        $this->assertNull($event->errorTrace);

        $metadata = $event->getMetadata();
        $this->assertFalse($metadata['has_trace']);
    }

    public function test_site_deleted_event_uses_primitive_data(): void
    {
        $event = new SiteDeleted(
            'site-uuid-123',
            'tenant-uuid-456',
            'example.com',
            'user-uuid-789'
        );

        $this->assertEquals('site-uuid-123', $event->siteId);
        $this->assertEquals('tenant-uuid-456', $event->tenantId);
        $this->assertEquals('example.com', $event->domain);
        $this->assertEquals('user-uuid-789', $event->actorId);

        $metadata = $event->getMetadata();
        $this->assertEquals('site-uuid-123', $metadata['site_id']);
        $this->assertEquals('tenant-uuid-456', $metadata['tenant_id']);
        $this->assertEquals('example.com', $metadata['domain']);
    }

    public function test_all_site_events_have_occurred_at_timestamp(): void
    {
        $tenant = Tenant::factory()->create();
        $site = Site::factory()->create(['tenant_id' => $tenant->id]);

        $events = [
            new SiteCreated($site, $tenant),
            new SiteProvisioned($site),
            new SiteProvisioningFailed($site, 'Error'),
            new SiteDeleted($site->id, $tenant->id, $site->domain),
        ];

        foreach ($events as $event) {
            $this->assertInstanceOf(\DateTimeInterface::class, $event->occurredAt);
            $this->assertNotNull($event->occurredAt);

            $metadata = $event->getMetadata();
            $this->assertArrayHasKey('occurred_at', $metadata);
        }
    }

    public function test_site_events_track_actor_information(): void
    {
        $tenant = Tenant::factory()->create();
        $site = Site::factory()->create(['tenant_id' => $tenant->id]);

        // User-triggered event
        $userEvent = new SiteCreated($site, $tenant, 'user-123');
        $this->assertEquals('user-123', $userEvent->actorId);
        $this->assertEquals('user', $userEvent->actorType);

        // System-triggered event
        $systemEvent = new SiteProvisioned($site);
        $this->assertEquals('system', $systemEvent->actorType);
    }
}
