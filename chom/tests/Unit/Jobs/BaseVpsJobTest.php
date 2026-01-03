<?php

namespace Tests\Unit\Jobs;

use App\Jobs\BaseVpsJob;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Log;
use Tests\TestCase;

class BaseVpsJobTest extends TestCase
{
    use RefreshDatabase;

    private TestableVpsJob $job;

    protected function setUp(): void
    {
        parent::setUp();

        $this->job = new TestableVpsJob();
    }

    public function test_it_validates_active_vps_server_successfully()
    {
        $vps = VpsServer::factory()->create([
            'status' => 'active',
            'health_status' => 'healthy',
            'hostname' => 'vps01.example.com',
        ]);

        $result = $this->job->publicValidateVpsServer($vps);

        $this->assertTrue($result);
    }

    public function test_it_validates_provisioning_vps_server_successfully()
    {
        $vps = VpsServer::factory()->create([
            'status' => 'provisioning',
            'health_status' => 'healthy',
        ]);

        $result = $this->job->publicValidateVpsServer($vps);

        $this->assertTrue($result);
    }

    public function test_it_throws_exception_for_inactive_vps_server()
    {
        $vps = VpsServer::factory()->create([
            'status' => 'inactive',
            'health_status' => 'healthy',
        ]);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('VPS server is not available for operations');

        $this->job->publicValidateVpsServer($vps);
    }

    public function test_it_throws_exception_for_maintenance_vps_server()
    {
        $vps = VpsServer::factory()->create([
            'status' => 'maintenance',
            'health_status' => 'healthy',
        ]);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('VPS server is not available for operations');

        $this->job->publicValidateVpsServer($vps);
    }

    public function test_it_throws_exception_for_unhealthy_vps_server()
    {
        $vps = VpsServer::factory()->create([
            'status' => 'active',
            'health_status' => 'unhealthy',
            'hostname' => 'vps01.example.com',
        ]);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('VPS server health check failed');

        $this->job->publicValidateVpsServer($vps);
    }

    public function test_it_logs_job_start_with_context()
    {
        Log::spy();

        $this->job->publicLogJobStart('Test Operation', [
            'test_id' => '123',
        ]);

        Log::shouldHaveReceived('channel')
            ->with('stack')
            ->once();
    }

    public function test_it_logs_job_success_with_execution_time()
    {
        Log::spy();

        $this->job->publicLogJobStart('Test Operation');
        usleep(10000);
        $this->job->publicLogJobSuccess('Test Operation');

        Log::shouldHaveReceived('channel')
            ->with('stack')
            ->twice();
    }

    public function test_it_logs_job_failure_with_exception_details()
    {
        Log::spy();

        $exception = new \RuntimeException('Test error', 500);

        $this->job->publicLogJobStart('Test Operation');
        $this->job->publicLogJobFailure('Test Operation', $exception);

        Log::shouldHaveReceived('channel')
            ->with('stack')
            ->twice();
    }

    public function test_it_categorizes_connection_timeout_error()
    {
        $exception = new \RuntimeException('Connection timed out after 30 seconds');

        $errorType = $this->job->publicCategorizeVpsError($exception);

        $this->assertEquals('connection_timeout', $errorType);
    }

    public function test_it_categorizes_authentication_failure_error()
    {
        $exception = new \RuntimeException('Authentication failed for user root');

        $errorType = $this->job->publicCategorizeVpsError($exception);

        $this->assertEquals('auth_failure', $errorType);
    }

    public function test_it_categorizes_permission_denied_error()
    {
        $exception = new \RuntimeException('Permission denied (publickey)');

        $errorType = $this->job->publicCategorizeVpsError($exception);

        $this->assertEquals('permission_denied', $errorType);
    }

    public function test_it_categorizes_host_key_verification_error()
    {
        $exception = new \RuntimeException('Host key verification failed');

        $errorType = $this->job->publicCategorizeVpsError($exception);

        $this->assertEquals('host_key_verification', $errorType);
    }

    public function test_it_categorizes_network_unreachable_error()
    {
        $exception = new \RuntimeException('Network unreachable');

        $errorType = $this->job->publicCategorizeVpsError($exception);

        $this->assertEquals('network_unreachable', $errorType);
    }

    public function test_it_categorizes_disk_full_error()
    {
        $exception = new \RuntimeException('No space left on device');

        $errorType = $this->job->publicCategorizeVpsError($exception);

        $this->assertEquals('disk_full', $errorType);
    }

    public function test_it_categorizes_unknown_error()
    {
        $exception = new \RuntimeException('Some random error');

        $errorType = $this->job->publicCategorizeVpsError($exception);

        $this->assertEquals('unknown', $errorType);
    }

    public function test_it_handles_vps_error_with_user_friendly_message()
    {
        $exception = new \RuntimeException('Connection timed out');

        try {
            $this->job->publicHandleVpsError($exception);
            $this->fail('Expected RuntimeException was not thrown');
        } catch (\RuntimeException $e) {
            $this->assertStringContainsString('Failed to connect to VPS server', $e->getMessage());
            $this->assertEquals($exception, $e->getPrevious());
        }
    }

    public function test_it_has_correct_retry_configuration()
    {
        $this->assertEquals(3, $this->job->tries);
        $this->assertEquals(300, $this->job->timeout);
        $this->assertEquals([60, 120, 300], $this->job->backoff);
    }

    public function test_it_calculates_execution_time()
    {
        $this->job->publicLogJobStart('Test');
        usleep(50000);

        $executionTime = $this->job->publicGetExecutionTime();

        $this->assertGreaterThan(0, $executionTime);
        $this->assertLessThan(100, $executionTime);
    }

    public function test_it_returns_zero_execution_time_when_not_started()
    {
        $executionTime = $this->job->publicGetExecutionTime();

        $this->assertEquals(0.0, $executionTime);
    }
}

class TestableVpsJob extends BaseVpsJob
{
    public function handle(): void
    {
    }

    public function publicValidateVpsServer(VpsServer $vps): bool
    {
        return $this->validateVpsServer($vps);
    }

    public function publicLogJobStart(string $operation, array $context = []): void
    {
        $this->logJobStart($operation, $context);
    }

    public function publicLogJobSuccess(string $operation, array $context = []): void
    {
        $this->logJobSuccess($operation, $context);
    }

    public function publicLogJobFailure(string $operation, \Throwable $e, array $context = []): void
    {
        $this->logJobFailure($operation, $e, $context);
    }

    public function publicCategorizeVpsError(\Throwable $e): string
    {
        return $this->categorizeVpsError($e);
    }

    public function publicHandleVpsError(\Throwable $e): void
    {
        $this->handleVpsError($e);
    }

    public function publicGetExecutionTime(): float
    {
        return $this->getExecutionTime();
    }
}
