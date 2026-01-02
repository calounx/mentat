<?php

namespace Tests\Feature\Commands;

use App\Models\Tenant;
use App\Models\VpsServer;
use App\Services\Secrets\SecretsRotationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Artisan;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class RotateSecretsCommandTest extends TestCase
{
    use RefreshDatabase;

    protected VpsServer $vps;

    protected function setUp(): void
    {
        parent::setUp();

        $tenant = Tenant::factory()->create();
        $this->vps = VpsServer::factory()->create([
            'tenant_id' => $tenant->id,
            'key_rotated_at' => now()->subDays(100), // Overdue
        ]);
    }

    #[Test]
    public function it_requires_option_to_run()
    {
        $exitCode = Artisan::call('secrets:rotate');

        $this->assertEquals(1, $exitCode);

        $output = Artisan::output();
        $this->assertStringContainsString('Please specify --all or --vps=ID', $output);
    }

    #[Test]
    public function it_performs_dry_run()
    {
        $exitCode = Artisan::call('secrets:rotate', ['--dry-run' => true]);

        $this->assertEquals(0, $exitCode);

        $output = Artisan::output();
        $this->assertStringContainsString('CHOM Security: Secrets Rotation', $output);
    }

    #[Test]
    public function it_shows_servers_needing_rotation_in_dry_run()
    {
        Artisan::call('secrets:rotate', ['--dry-run' => true]);
        $output = Artisan::output();

        $this->assertStringContainsString('VPS servers requiring key rotation', $output);
    }

    #[Test]
    public function it_shows_no_rotation_needed_when_all_current()
    {
        $this->vps->update(['key_rotated_at' => now()]);

        Artisan::call('secrets:rotate', ['--dry-run' => true]);
        $output = Artisan::output();

        $this->assertStringContainsString('No VPS servers require key rotation', $output);
    }

    #[Test]
    public function it_can_rotate_specific_vps()
    {
        $rotationService = $this->mock(SecretsRotationService::class);
        $rotationService->shouldReceive('rotateVpsCredentials')
            ->once()
            ->with(\Mockery::on(fn($vps) => $vps->id === $this->vps->id))
            ->andReturn([
                'success' => true,
                'rotated_at' => now()->toIso8601String(),
                'next_rotation_due' => now()->addDays(90)->toIso8601String(),
                'overlap_period_ends' => now()->addHours(24)->toIso8601String(),
            ]);

        $exitCode = Artisan::call('secrets:rotate', [
            '--vps' => $this->vps->id,
            '--force' => true,
        ]);

        $this->assertEquals(0, $exitCode);

        $output = Artisan::output();
        $this->assertStringContainsString('Credentials rotated successfully', $output);
    }

    #[Test]
    public function it_handles_non_existent_vps()
    {
        $exitCode = Artisan::call('secrets:rotate', [
            '--vps' => 999999,
        ]);

        $this->assertEquals(1, $exitCode);

        $output = Artisan::output();
        $this->assertStringContainsString('not found', $output);
    }

    #[Test]
    public function it_handles_rotation_failure()
    {
        $rotationService = $this->mock(SecretsRotationService::class);
        $rotationService->shouldReceive('rotateVpsCredentials')
            ->once()
            ->andThrow(new \Exception('SSH connection failed'));

        $exitCode = Artisan::call('secrets:rotate', [
            '--vps' => $this->vps->id,
            '--force' => true,
        ]);

        $this->assertEquals(1, $exitCode);

        $output = Artisan::output();
        $this->assertStringContainsString('Rotation failed', $output);
    }

    #[Test]
    public function it_can_rotate_all_due_credentials()
    {
        $rotationService = $this->mock(SecretsRotationService::class);
        $rotationService->shouldReceive('getServersNeedingRotation')
            ->once()
            ->andReturn(collect([$this->vps]));
        $rotationService->shouldReceive('rotateAllDueCredentials')
            ->once()
            ->andReturn([
                'total' => 1,
                'successful' => 1,
                'failed' => 0,
                'errors' => [],
            ]);

        $exitCode = Artisan::call('secrets:rotate', ['--all' => true]);

        $this->assertEquals(0, $exitCode);

        $output = Artisan::output();
        $this->assertStringContainsString('Rotation Summary', $output);
        $this->assertStringContainsString('All credential rotations completed successfully', $output);
    }

    #[Test]
    public function it_reports_failed_rotations()
    {
        $rotationService = $this->mock(SecretsRotationService::class);
        $rotationService->shouldReceive('getServersNeedingRotation')
            ->once()
            ->andReturn(collect([$this->vps]));
        $rotationService->shouldReceive('rotateAllDueCredentials')
            ->once()
            ->andReturn([
                'total' => 1,
                'successful' => 0,
                'failed' => 1,
                'errors' => [[
                    'vps_id' => $this->vps->id,
                    'vps_name' => $this->vps->name,
                    'error' => 'Connection timeout',
                ]],
            ]);

        $exitCode = Artisan::call('secrets:rotate', ['--all' => true]);

        $this->assertEquals(1, $exitCode);

        $output = Artisan::output();
        $this->assertStringContainsString('Failed rotations', $output);
        $this->assertStringContainsString('Connection timeout', $output);
    }
}
