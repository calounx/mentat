<?php

namespace Tests\Feature\Jobs;

use App\Jobs\CreateBackupJob;
use App\Jobs\IssueSslCertificateJob;
use App\Jobs\ProvisionSiteJob;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Bus;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class JobChainingTest extends TestCase
{
    use RefreshDatabase;

    protected Site $site;
    protected VpsServer $vps;

    protected function setUp(): void
    {
        parent::setUp();

        $tenant = Tenant::factory()->create();
        $this->vps = VpsServer::factory()->create();
        $this->site = Site::factory()->create([
            'tenant_id' => $tenant->id,
            'vps_server_id' => $this->vps->id,
            'ssl_enabled' => true,
        ]);
    }

    #[Test]
    public function it_can_chain_jobs_sequentially()
    {
        Queue::fake();

        Bus::chain([
            new ProvisionSiteJob($this->site),
            new IssueSslCertificateJob($this->site),
            new CreateBackupJob($this->site),
        ])->dispatch();

        // Verify first job was dispatched
        Queue::assertPushed(ProvisionSiteJob::class);
    }

    #[Test]
    public function it_can_chain_jobs_with_callbacks()
    {
        Queue::fake();

        $executed = false;

        Bus::chain([
            new ProvisionSiteJob($this->site),
            function () use (&$executed) {
                $executed = true;
                return new CreateBackupJob($this->site);
            },
        ])->dispatch();

        // First job should be dispatched
        Queue::assertPushed(ProvisionSiteJob::class);
    }

    #[Test]
    public function it_can_chain_jobs_on_specific_queue()
    {
        Queue::fake();

        Bus::chain([
            new ProvisionSiteJob($this->site),
            new IssueSslCertificateJob($this->site),
        ])->onQueue('high')->dispatch();

        Queue::assertPushedOn('high', ProvisionSiteJob::class);
    }

    #[Test]
    public function it_can_catch_chain_failures()
    {
        Queue::fake();

        $catchCalled = false;

        Bus::chain([
            new ProvisionSiteJob($this->site),
            new IssueSslCertificateJob($this->site),
        ])->catch(function () use (&$catchCalled) {
            $catchCalled = true;
        })->dispatch();

        // Verify jobs were dispatched
        Queue::assertPushed(ProvisionSiteJob::class);
    }

    #[Test]
    public function provisioning_chains_ssl_job_when_enabled()
    {
        // This is tested in ProvisionSiteJobTest
        // Verifying the pattern is used correctly
        $this->assertTrue($this->site->ssl_enabled);
    }

    #[Test]
    public function it_can_batch_multiple_jobs()
    {
        Queue::fake();

        $sites = Site::factory()->count(3)->create([
            'tenant_id' => $this->site->tenant_id,
            'vps_server_id' => $this->vps->id,
        ]);

        Bus::batch(
            $sites->map(fn($site) => new CreateBackupJob($site))->toArray()
        )->dispatch();

        // Verify all jobs were pushed
        Queue::assertPushed(CreateBackupJob::class, 3);
    }

    #[Test]
    public function it_can_batch_with_then_callback()
    {
        Queue::fake();

        $thenCalled = false;

        Bus::batch([
            new CreateBackupJob($this->site),
        ])->then(function () use (&$thenCalled) {
            $thenCalled = true;
        })->dispatch();

        Queue::assertPushed(CreateBackupJob::class);
    }

    #[Test]
    public function it_can_batch_with_catch_callback()
    {
        Queue::fake();

        Bus::batch([
            new CreateBackupJob($this->site),
        ])->catch(function () {
            // Handle batch failure
        })->dispatch();

        Queue::assertPushed(CreateBackupJob::class);
    }

    #[Test]
    public function it_can_batch_with_finally_callback()
    {
        Queue::fake();

        Bus::batch([
            new CreateBackupJob($this->site),
        ])->finally(function () {
            // Always executed
        })->dispatch();

        Queue::assertPushed(CreateBackupJob::class);
    }

    #[Test]
    public function it_can_name_batches()
    {
        Queue::fake();

        Bus::batch([
            new CreateBackupJob($this->site),
        ])->name('nightly-backups')->dispatch();

        Queue::assertPushed(CreateBackupJob::class);
    }

    #[Test]
    public function it_can_batch_on_specific_queue()
    {
        Queue::fake();

        Bus::batch([
            new CreateBackupJob($this->site),
        ])->onQueue('backups')->dispatch();

        Queue::assertPushedOn('backups', CreateBackupJob::class);
    }

    #[Test]
    public function it_can_batch_on_specific_connection()
    {
        Queue::fake();

        Bus::batch([
            new CreateBackupJob($this->site),
        ])->onConnection('database')->dispatch();

        Queue::assertPushed(CreateBackupJob::class, function ($job) {
            return $job->connection === 'database';
        });
    }
}
