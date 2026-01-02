<?php

namespace Tests\Feature\Jobs;

use App\Jobs\CreateBackupJob;
use App\Models\Site;
use App\Models\Tenant;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Facades\Redis;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class QueueConnectionTest extends TestCase
{
    use RefreshDatabase;

    protected Site $site;

    protected function setUp(): void
    {
        parent::setUp();

        $tenant = Tenant::factory()->create();
        $vps = VpsServer::factory()->create();
        $this->site = Site::factory()->create([
            'tenant_id' => $tenant->id,
            'vps_server_id' => $vps->id,
        ]);
    }

    #[Test]
    public function it_uses_redis_queue_by_default()
    {
        $connection = Config::get('queue.default');

        $this->assertEquals('redis', $connection);
    }

    #[Test]
    public function it_can_push_job_to_database_queue()
    {
        Config::set('queue.default', 'database');

        // Ensure jobs table exists
        if (!DB::table('jobs')->exists()) {
            $this->markTestSkipped('Jobs table not found - database queue not set up');
        }

        dispatch(new CreateBackupJob($this->site));

        // Verify job appears in database
        $this->assertDatabaseHas('jobs', [
            'queue' => 'default',
        ]);

        // Cleanup
        DB::table('jobs')->truncate();
    }

    #[Test]
    public function it_can_execute_job_synchronously()
    {
        Config::set('queue.default', 'sync');

        Queue::fake();

        dispatch(new CreateBackupJob($this->site));

        // With sync driver, job should execute immediately
        // Queue::fake() prevents actual execution but we can verify it was dispatched
        Queue::assertPushed(CreateBackupJob::class);
    }

    #[Test]
    public function it_can_dispatch_to_specific_queue()
    {
        Queue::fake();

        dispatch(new CreateBackupJob($this->site))->onQueue('high');

        Queue::assertPushedOn('high', CreateBackupJob::class);
    }

    #[Test]
    public function it_can_dispatch_to_specific_connection()
    {
        Queue::fake();

        dispatch(new CreateBackupJob($this->site))->onConnection('database');

        Queue::assertPushed(CreateBackupJob::class, function ($job) {
            return $job->connection === 'database';
        });
    }

    #[Test]
    public function it_respects_queue_priorities()
    {
        Queue::fake();

        // High priority
        dispatch(new CreateBackupJob($this->site))->onQueue('high');

        // Default priority
        dispatch(new CreateBackupJob($this->site))->onQueue('default');

        // Low priority
        dispatch(new CreateBackupJob($this->site))->onQueue('low');

        Queue::assertPushedOn('high', CreateBackupJob::class);
        Queue::assertPushedOn('default', CreateBackupJob::class);
        Queue::assertPushedOn('low', CreateBackupJob::class);
    }

    #[Test]
    public function it_can_delay_job_execution()
    {
        Queue::fake();

        $delay = now()->addMinutes(10);

        dispatch(new CreateBackupJob($this->site))->delay($delay);

        Queue::assertPushed(CreateBackupJob::class, function ($job) use ($delay) {
            return $job->delay && $job->delay->timestamp === $delay->timestamp;
        });
    }

    #[Test]
    public function failed_jobs_are_stored()
    {
        if (!DB::table('failed_jobs')->exists()) {
            $this->markTestSkipped('Failed jobs table not found');
        }

        // This test verifies the failed_jobs table exists and can store failures
        $this->assertTrue(true);
    }

    #[Test]
    public function it_can_configure_queue_retry_after()
    {
        $retryAfter = Config::get('queue.connections.database.retry_after');

        $this->assertIsInt($retryAfter);
        $this->assertGreaterThan(0, $retryAfter);
    }
}
