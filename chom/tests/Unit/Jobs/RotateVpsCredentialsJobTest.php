<?php

namespace Tests\Unit\Jobs;

use App\Jobs\RotateVpsCredentialsJob;
use App\Models\Tenant;
use App\Models\VpsServer;
use App\Services\Secrets\SecretsRotationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class RotateVpsCredentialsJobTest extends TestCase
{
    use RefreshDatabase;

    protected VpsServer $vps;

    protected function setUp(): void
    {
        parent::setUp();

        $tenant = Tenant::factory()->create();
        $this->vps = VpsServer::factory()->create([
            'tenant_id' => $tenant->id,
            'name' => 'production-server',
        ]);
    }

    #[Test]
    public function it_can_be_dispatched_to_queue()
    {
        Queue::fake();

        dispatch(new RotateVpsCredentialsJob($this->vps));

        Queue::assertPushed(RotateVpsCredentialsJob::class, function ($job) {
            return $job->vps->id === $this->vps->id;
        });
    }

    #[Test]
    public function it_has_correct_configuration()
    {
        $job = new RotateVpsCredentialsJob($this->vps);

        $this->assertEquals(3, $job->tries);
        $this->assertEquals(300, $job->timeout);
        $this->assertEquals('high', $job->queue);
    }

    #[Test]
    public function it_is_dispatched_to_high_priority_queue()
    {
        Queue::fake();

        dispatch(new RotateVpsCredentialsJob($this->vps));

        Queue::assertPushedOn('high', RotateVpsCredentialsJob::class);
    }

    #[Test]
    public function it_rotates_credentials_successfully()
    {
        $rotationService = $this->mock(SecretsRotationService::class);
        $rotationService->shouldReceive('rotateVpsCredentials')
            ->once()
            ->with($this->vps)
            ->andReturn([
                'success' => true,
                'rotated_at' => now()->toIso8601String(),
                'next_rotation_due' => now()->addDays(90)->toIso8601String(),
            ]);

        $job = new RotateVpsCredentialsJob($this->vps, 'rotate');
        $job->handle($rotationService);

        // Job should complete without exceptions
        $this->assertTrue(true);
    }

    #[Test]
    public function it_cleans_up_old_key()
    {
        $rotationService = $this->mock(SecretsRotationService::class);
        $rotationService->shouldReceive('cleanupOldKey')
            ->once()
            ->with($this->vps);

        $job = new RotateVpsCredentialsJob($this->vps, 'cleanup_old_key');
        $job->handle($rotationService);

        $this->assertTrue(true);
    }

    #[Test]
    public function it_throws_exception_on_rotation_failure()
    {
        $rotationService = $this->mock(SecretsRotationService::class);
        $rotationService->shouldReceive('rotateVpsCredentials')
            ->once()
            ->andThrow(new \Exception('SSH connection failed'));

        $job = new RotateVpsCredentialsJob($this->vps);

        $this->expectException(\Exception::class);
        $this->expectExceptionMessage('SSH connection failed');

        $job->handle($rotationService);
    }

    #[Test]
    public function it_handles_job_failure_after_all_retries()
    {
        $job = new RotateVpsCredentialsJob($this->vps);
        $exception = new \Exception('Max retries exceeded');

        // Should not throw exception - just logs critical error
        $job->failed($exception);

        $this->assertTrue(true);
    }

    #[Test]
    public function it_can_be_serialized_and_unserialized()
    {
        $job = new RotateVpsCredentialsJob($this->vps, 'cleanup_old_key');

        $serialized = serialize($job);
        $unserialized = unserialize($serialized);

        $this->assertInstanceOf(RotateVpsCredentialsJob::class, $unserialized);
        $this->assertEquals($this->vps->id, $unserialized->vps->id);
        $this->assertEquals('cleanup_old_key', $unserialized->action);
    }

    #[Test]
    public function it_defaults_to_rotate_action()
    {
        $job = new RotateVpsCredentialsJob($this->vps);

        $this->assertEquals('rotate', $job->action);
    }
}
