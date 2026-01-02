<?php

namespace Tests\Unit\Jobs;

use App\Jobs\IssueSslCertificateJob;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\VpsServer;
use App\Services\Integration\VPSManagerBridge;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class IssueSslCertificateJobTest extends TestCase
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
            'ssl_enabled' => false,
            'ssl_expires_at' => null,
        ]);
    }

    #[Test]
    public function it_can_be_dispatched_to_queue()
    {
        Queue::fake();

        dispatch(new IssueSslCertificateJob($this->site));

        Queue::assertPushed(IssueSslCertificateJob::class, function ($job) {
            return $job->site->id === $this->site->id;
        });
    }

    #[Test]
    public function it_has_correct_retry_configuration()
    {
        $job = new IssueSslCertificateJob($this->site);

        $this->assertEquals(3, $job->tries);
        $this->assertEquals(120, $job->backoff);
    }

    #[Test]
    public function it_issues_ssl_certificate_successfully()
    {
        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldReceive('issueSSL')
            ->once()
            ->with($this->vps, 'test.example.com')
            ->andReturn([
                'success' => true,
                'data' => [
                    'expires_at' => now()->addDays(90)->toIso8601String(),
                ],
            ]);

        $job = new IssueSslCertificateJob($this->site);
        $job->handle($vpsManager);

        $site = $this->site->fresh();
        $this->assertTrue($site->ssl_enabled);
        $this->assertNotNull($site->ssl_expires_at);
        $this->assertTrue($site->ssl_expires_at->greaterThan(now()->addDays(89)));
    }

    #[Test]
    public function it_sets_default_expiry_if_not_provided()
    {
        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldReceive('issueSSL')
            ->once()
            ->andReturn([
                'success' => true,
                'data' => [],
            ]);

        $job = new IssueSslCertificateJob($this->site);
        $job->handle($vpsManager);

        $site = $this->site->fresh();
        $this->assertTrue($site->ssl_enabled);
        // Default Let's Encrypt expiry is 90 days
        $this->assertTrue($site->ssl_expires_at->greaterThan(now()->addDays(89)));
        $this->assertTrue($site->ssl_expires_at->lessThan(now()->addDays(91)));
    }

    #[Test]
    public function it_handles_ssl_issuance_failure_gracefully()
    {
        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldReceive('issueSSL')
            ->once()
            ->andReturn([
                'success' => false,
                'output' => 'Domain not pointed to server',
            ]);

        $job = new IssueSslCertificateJob($this->site);
        $job->handle($vpsManager);

        // Site should remain without SSL but not fail
        $site = $this->site->fresh();
        $this->assertFalse($site->ssl_enabled);
        $this->assertNull($site->ssl_expires_at);
    }

    #[Test]
    public function it_returns_early_if_no_vps_server()
    {
        $this->site->update(['vps_server_id' => null]);

        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldNotReceive('issueSSL');

        $job = new IssueSslCertificateJob($this->site);
        $job->handle($vpsManager);

        $this->assertFalse($this->site->fresh()->ssl_enabled);
    }

    #[Test]
    public function it_throws_exception_on_unexpected_error()
    {
        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldReceive('issueSSL')
            ->once()
            ->andThrow(new \Exception('Certbot not installed'));

        $job = new IssueSslCertificateJob($this->site);

        $this->expectException(\Exception::class);
        $this->expectExceptionMessage('Certbot not installed');

        $job->handle($vpsManager);
    }

    #[Test]
    public function it_handles_job_failure_gracefully()
    {
        $job = new IssueSslCertificateJob($this->site);
        $job->failed(new \Exception('SSL issuance failed'));

        // Site should remain active even if SSL failed
        // This is tested by not throwing an exception
        $this->assertTrue(true);
    }

    #[Test]
    public function it_can_renew_existing_certificate()
    {
        $this->site->update([
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addDays(30), // Expiring soon
        ]);

        $vpsManager = $this->mock(VPSManagerBridge::class);
        $vpsManager->shouldReceive('issueSSL')
            ->once()
            ->andReturn([
                'success' => true,
                'data' => [
                    'expires_at' => now()->addDays(90)->toIso8601String(),
                ],
            ]);

        $job = new IssueSslCertificateJob($this->site);
        $job->handle($vpsManager);

        $site = $this->site->fresh();
        $this->assertTrue($site->ssl_enabled);
        $this->assertTrue($site->ssl_expires_at->greaterThan(now()->addDays(89)));
    }
}
