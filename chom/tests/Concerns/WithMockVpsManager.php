<?php

declare(strict_types=1);

namespace Tests\Concerns;

use App\Services\VPS\VpsAllocationService;
use App\Services\VPS\VpsCommandExecutor;
use App\Services\VPS\VpsConnectionManager;
use App\Services\VPS\VpsSiteManager;
use App\Services\VPS\VpsSslManager;
use Mockery;
use Mockery\MockInterface;

/**
 * Provides mock VPS manager services for testing
 *
 * This trait provides pre-configured mocks for all VPS-related services,
 * allowing tests to simulate VPS operations without actual server connections.
 *
 * @package Tests\Concerns
 */
trait WithMockVpsManager
{
    /**
     * Mock VPS allocation service
     */
    protected VpsAllocationService|MockInterface $mockVpsAllocation;

    /**
     * Mock VPS command executor
     */
    protected VpsCommandExecutor|MockInterface $mockVpsExecutor;

    /**
     * Mock VPS connection manager
     */
    protected VpsConnectionManager|MockInterface $mockVpsConnection;

    /**
     * Mock VPS site manager
     */
    protected VpsSiteManager|MockInterface $mockVpsSiteManager;

    /**
     * Mock VPS SSL manager
     */
    protected VpsSslManager|MockInterface $mockVpsSslManager;

    /**
     * Set up VPS mocks
     *
     * @return void
     */
    protected function setUpVpsMocks(): void
    {
        $this->mockVpsAllocation = Mockery::mock(VpsAllocationService::class);
        $this->mockVpsExecutor = Mockery::mock(VpsCommandExecutor::class);
        $this->mockVpsConnection = Mockery::mock(VpsConnectionManager::class);
        $this->mockVpsSiteManager = Mockery::mock(VpsSiteManager::class);
        $this->mockVpsSslManager = Mockery::mock(VpsSslManager::class);

        $this->app->instance(VpsAllocationService::class, $this->mockVpsAllocation);
        $this->app->instance(VpsCommandExecutor::class, $this->mockVpsExecutor);
        $this->app->instance(VpsConnectionManager::class, $this->mockVpsConnection);
        $this->app->instance(VpsSiteManager::class, $this->mockVpsSiteManager);
        $this->app->instance(VpsSslManager::class, $this->mockVpsSslManager);
    }

    /**
     * Mock successful VPS allocation
     *
     * @param string $vpsId
     * @param array $vpsData
     * @return void
     */
    protected function mockSuccessfulVpsAllocation(string $vpsId = 'vps-123', array $vpsData = []): void
    {
        $defaultData = [
            'id' => $vpsId,
            'ip_address' => '192.168.1.100',
            'hostname' => 'vps-host.example.com',
            'status' => 'active',
            'cpu_cores' => 4,
            'memory_gb' => 8,
            'disk_gb' => 100,
        ];

        $data = array_merge($defaultData, $vpsData);

        $this->mockVpsAllocation
            ->shouldReceive('allocateVps')
            ->andReturn((object) $data);
    }

    /**
     * Mock successful SSH connection
     *
     * @return void
     */
    protected function mockSuccessfulSshConnection(): void
    {
        $this->mockVpsConnection
            ->shouldReceive('connect')
            ->andReturn(true);

        $this->mockVpsConnection
            ->shouldReceive('isConnected')
            ->andReturn(true);

        $this->mockVpsConnection
            ->shouldReceive('disconnect')
            ->andReturnNull();
    }

    /**
     * Mock successful command execution
     *
     * @param string $expectedCommand
     * @param string $output
     * @param int $exitCode
     * @return void
     */
    protected function mockCommandExecution(
        string $expectedCommand,
        string $output = '',
        int $exitCode = 0
    ): void {
        $this->mockVpsExecutor
            ->shouldReceive('execute')
            ->with($expectedCommand)
            ->andReturn([
                'output' => $output,
                'exit_code' => $exitCode,
                'success' => $exitCode === 0,
            ]);
    }

    /**
     * Mock successful site deployment
     *
     * @param string $siteName
     * @return void
     */
    protected function mockSuccessfulSiteDeployment(string $siteName = 'example.com'): void
    {
        $this->mockVpsSiteManager
            ->shouldReceive('deploySite')
            ->with(Mockery::on(fn($site) => $site->domain === $siteName))
            ->andReturn([
                'success' => true,
                'site_path' => "/var/www/{$siteName}",
                'nginx_config' => "/etc/nginx/sites-available/{$siteName}",
                'php_fpm_pool' => "/etc/php/8.2/fpm/pool.d/{$siteName}.conf",
            ]);
    }

    /**
     * Mock successful SSL certificate installation
     *
     * @param string $domain
     * @return void
     */
    protected function mockSuccessfulSslInstallation(string $domain = 'example.com'): void
    {
        $this->mockVpsSslManager
            ->shouldReceive('installCertificate')
            ->with($domain)
            ->andReturn([
                'success' => true,
                'certificate_path' => "/etc/letsencrypt/live/{$domain}/fullchain.pem",
                'private_key_path' => "/etc/letsencrypt/live/{$domain}/privkey.pem",
                'expires_at' => now()->addDays(90),
            ]);
    }

    /**
     * Mock VPS connection failure
     *
     * @param string $errorMessage
     * @return void
     */
    protected function mockVpsConnectionFailure(string $errorMessage = 'Connection refused'): void
    {
        $this->mockVpsConnection
            ->shouldReceive('connect')
            ->andThrow(new \RuntimeException($errorMessage));
    }

    /**
     * Mock command execution failure
     *
     * @param string $expectedCommand
     * @param string $errorOutput
     * @param int $exitCode
     * @return void
     */
    protected function mockCommandFailure(
        string $expectedCommand,
        string $errorOutput = 'Command failed',
        int $exitCode = 1
    ): void {
        $this->mockVpsExecutor
            ->shouldReceive('execute')
            ->with($expectedCommand)
            ->andReturn([
                'output' => $errorOutput,
                'exit_code' => $exitCode,
                'success' => false,
            ]);
    }

    /**
     * Mock VPS health check
     *
     * @param bool $healthy
     * @param array $metrics
     * @return void
     */
    protected function mockVpsHealthCheck(bool $healthy = true, array $metrics = []): void
    {
        $defaultMetrics = [
            'cpu_usage' => 45.5,
            'memory_usage' => 62.3,
            'disk_usage' => 38.7,
            'uptime' => 86400,
            'load_average' => [0.5, 0.6, 0.7],
        ];

        $healthData = [
            'healthy' => $healthy,
            'metrics' => array_merge($defaultMetrics, $metrics),
            'timestamp' => now()->toIso8601String(),
        ];

        $vpsHealthService = Mockery::mock(\App\Services\VPS\VpsHealthService::class);
        $vpsHealthService
            ->shouldReceive('checkHealth')
            ->andReturn($healthData);

        $this->app->instance(\App\Services\VPS\VpsHealthService::class, $vpsHealthService);
    }

    /**
     * Assert VPS allocation was called
     *
     * @return void
     */
    protected function assertVpsAllocationCalled(): void
    {
        $this->mockVpsAllocation
            ->shouldHaveReceived('allocateVps')
            ->once();
    }

    /**
     * Assert SSH connection was established
     *
     * @return void
     */
    protected function assertSshConnectionEstablished(): void
    {
        $this->mockVpsConnection
            ->shouldHaveReceived('connect')
            ->once();
    }

    /**
     * Assert command was executed
     *
     * @param string $command
     * @return void
     */
    protected function assertCommandExecuted(string $command): void
    {
        $this->mockVpsExecutor
            ->shouldHaveReceived('execute')
            ->with($command)
            ->once();
    }
}
