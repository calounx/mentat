<?php

namespace Tests\Unit\Jobs;

use App\Events\Site\SiteProvisioned;
use App\Events\Site\SiteProvisioningFailed;
use App\Jobs\IssueSslCertificateJob;
use App\Jobs\ProvisionSiteJob;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\VpsServer;
use App\Services\Sites\Provisioners\ProvisionerFactory;
use App\Services\Sites\Provisioners\WordPressProvisioner;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class ProvisionSiteJobTest extends TestCase
{
    use RefreshDatabase;

    protected Site $site;
    protected VpsServer $vps;

    protected function setUp(): void
    {
        parent::setUp();

        $tenant = Tenant::factory()->create();
        $this->vps = VpsServer::factory()->create([
            'tenant_id' => $tenant->id,
        ]);
        $this->site = Site::factory()->create([
            'tenant_id' => $tenant->id,
            'vps_server_id' => $this->vps->id,
            'domain' => 'test.example.com',
            'site_type' => 'wordpress',
            'status' => 'pending',
            'ssl_enabled' => false,
        ]);
    }

    #[Test]
    public function it_can_be_dispatched_to_queue()
    {
        Queue::fake();

        dispatch(new ProvisionSiteJob($this->site));

        Queue::assertPushed(ProvisionSiteJob::class, function ($job) {
            return $job->site->id === $this->site->id;
        });
    }

    #[Test]
    public function it_has_correct_retry_configuration()
    {
        $job = new ProvisionSiteJob($this->site);

        $this->assertEquals(3, $job->tries);
        $this->assertEquals(60, $job->backoff);
    }

    #[Test]
    public function it_provisions_site_successfully()
    {
        Event::fake([SiteProvisioned::class]);

        $provisioner = $this->mock(WordPressProvisioner::class);
        $provisioner->shouldReceive('validate')
            ->once()
            ->with($this->site)
            ->andReturn(true);
        $provisioner->shouldReceive('provision')
            ->once()
            ->with($this->site, $this->vps)
            ->andReturn([
                'success' => true,
                'output' => 'WordPress site provisioned successfully',
            ]);

        $factory = $this->mock(ProvisionerFactory::class);
        $factory->shouldReceive('make')
            ->once()
            ->with('wordpress')
            ->andReturn($provisioner);

        $job = new ProvisionSiteJob($this->site);
        $job->handle($factory);

        // Verify site status was updated
        $this->assertEquals('active', $this->site->fresh()->status);

        // Verify event was dispatched
        Event::assertDispatched(SiteProvisioned::class, function ($event) {
            return $event->site->id === $this->site->id;
        });
    }

    #[Test]
    public function it_dispatches_ssl_job_if_ssl_enabled()
    {
        Queue::fake();
        Event::fake();

        $this->site->update(['ssl_enabled' => true]);

        $provisioner = $this->mock(WordPressProvisioner::class);
        $provisioner->shouldReceive('validate')->andReturn(true);
        $provisioner->shouldReceive('provision')->andReturn(['success' => true]);

        $factory = $this->mock(ProvisionerFactory::class);
        $factory->shouldReceive('make')->andReturn($provisioner);

        $job = new ProvisionSiteJob($this->site);
        $job->handle($factory);

        // Verify SSL job was dispatched
        Queue::assertPushed(IssueSslCertificateJob::class, function ($job) {
            return $job->site->id === $this->site->id;
        });
    }

    #[Test]
    public function it_does_not_dispatch_ssl_job_if_ssl_disabled()
    {
        Queue::fake();
        Event::fake();

        $provisioner = $this->mock(WordPressProvisioner::class);
        $provisioner->shouldReceive('validate')->andReturn(true);
        $provisioner->shouldReceive('provision')->andReturn(['success' => true]);

        $factory = $this->mock(ProvisionerFactory::class);
        $factory->shouldReceive('make')->andReturn($provisioner);

        $job = new ProvisionSiteJob($this->site);
        $job->handle($factory);

        // Verify SSL job was NOT dispatched
        Queue::assertNotPushed(IssueSslCertificateJob::class);
    }

    #[Test]
    public function it_handles_validation_failure()
    {
        Event::fake([SiteProvisioningFailed::class]);

        $provisioner = $this->mock(WordPressProvisioner::class);
        $provisioner->shouldReceive('validate')
            ->once()
            ->andReturn(false);
        $provisioner->shouldNotReceive('provision');

        $factory = $this->mock(ProvisionerFactory::class);
        $factory->shouldReceive('make')->andReturn($provisioner);

        $job = new ProvisionSiteJob($this->site);

        $this->expectException(\InvalidArgumentException::class);

        $job->handle($factory);

        $this->assertEquals('failed', $this->site->fresh()->status);
    }

    #[Test]
    public function it_handles_provisioning_failure()
    {
        Event::fake([SiteProvisioningFailed::class]);

        $provisioner = $this->mock(WordPressProvisioner::class);
        $provisioner->shouldReceive('validate')->andReturn(true);
        $provisioner->shouldReceive('provision')->andReturn([
            'success' => false,
            'output' => 'Failed to create database',
        ]);

        $factory = $this->mock(ProvisionerFactory::class);
        $factory->shouldReceive('make')->andReturn($provisioner);

        $job = new ProvisionSiteJob($this->site);
        $job->handle($factory);

        $this->assertEquals('failed', $this->site->fresh()->status);

        Event::assertDispatched(SiteProvisioningFailed::class, function ($event) {
            return $event->site->id === $this->site->id &&
                   str_contains($event->errorMessage, 'Failed to create database');
        });
    }

    #[Test]
    public function it_returns_early_if_no_vps_server()
    {
        Event::fake();

        $this->site->update(['vps_server_id' => null]);

        $factory = $this->mock(ProvisionerFactory::class);
        $factory->shouldNotReceive('make');

        $job = new ProvisionSiteJob($this->site);
        $job->handle($factory);

        $this->assertEquals('failed', $this->site->fresh()->status);

        Event::assertDispatched(SiteProvisioningFailed::class, function ($event) {
            return str_contains($event->errorMessage, 'No VPS server');
        });
    }

    #[Test]
    public function it_handles_exception_during_provisioning()
    {
        Event::fake();

        $provisioner = $this->mock(WordPressProvisioner::class);
        $provisioner->shouldReceive('validate')->andReturn(true);
        $provisioner->shouldReceive('provision')
            ->andThrow(new \Exception('Network timeout'));

        $factory = $this->mock(ProvisionerFactory::class);
        $factory->shouldReceive('make')->andReturn($provisioner);

        $job = new ProvisionSiteJob($this->site);

        $this->expectException(\Exception::class);

        $job->handle($factory);

        $this->assertEquals('failed', $this->site->fresh()->status);

        Event::assertDispatched(SiteProvisioningFailed::class);
    }

    #[Test]
    public function it_handles_job_failure_after_all_retries()
    {
        Event::fake();

        $job = new ProvisionSiteJob($this->site);
        $job->failed(new \Exception('Max retries exceeded'));

        $this->assertEquals('failed', $this->site->fresh()->status);

        Event::assertDispatched(SiteProvisioningFailed::class);
    }
}
