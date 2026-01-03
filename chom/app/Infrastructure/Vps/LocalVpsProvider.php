<?php

declare(strict_types=1);

namespace App\Infrastructure\Vps;

use App\Contracts\Infrastructure\VpsProviderInterface;
use App\ValueObjects\CommandResult;
use App\ValueObjects\ServerStatus;
use App\ValueObjects\VpsSpecification;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Process;
use RuntimeException;

/**
 * Local VPS Provider
 *
 * Provides VPS operations for local development using Docker or local SSH.
 * Useful for testing and development without requiring actual cloud resources.
 *
 * Implementation: Uses Docker containers as "virtual" VPS instances
 * Pattern: Adapter Pattern - adapts Docker to VPS interface
 *
 * @package App\Infrastructure\Vps
 */
class LocalVpsProvider implements VpsProviderInterface
{
    /**
     * @var array<string, array<string, mixed>> In-memory server registry
     */
    private array $servers = [];

    /**
     * @var string Docker network name
     */
    private string $networkName = 'chom-vps-network';

    public function __construct(
        private readonly string $sshUser = 'root',
        private readonly int $sshPort = 22,
        private readonly bool $useDocker = true
    ) {
        $this->initializeDockerNetwork();
    }

    /**
     * {@inheritDoc}
     */
    public function createServer(VpsSpecification $spec): array
    {
        Log::info('Creating local VPS server', ['name' => $spec->name]);

        if ($this->useDocker) {
            return $this->createDockerContainer($spec);
        }

        // Simulate server creation for testing
        $serverId = 'local-' . uniqid();
        $ipAddress = '127.0.0.' . rand(1, 254);

        $server = [
            'id' => $serverId,
            'name' => $spec->name,
            'ip_address' => $ipAddress,
            'status' => ServerStatus::STATUS_ONLINE,
            'cpu_cores' => $spec->cpuCores,
            'ram_mb' => $spec->ramMb,
            'disk_gb' => $spec->diskGb,
            'os' => $spec->operatingSystem,
            'region' => $spec->region,
            'created_at' => now()->toIso8601String(),
        ];

        $this->servers[$serverId] = $server;

        Log::info('Local VPS server created', ['server_id' => $serverId]);

        return $server;
    }

    /**
     * {@inheritDoc}
     */
    public function deleteServer(string $serverId): bool
    {
        Log::info('Deleting local VPS server', ['server_id' => $serverId]);

        if ($this->useDocker && str_starts_with($serverId, 'docker-')) {
            return $this->deleteDockerContainer($serverId);
        }

        if (!isset($this->servers[$serverId])) {
            throw new RuntimeException("Server not found: {$serverId}");
        }

        unset($this->servers[$serverId]);

        Log::info('Local VPS server deleted', ['server_id' => $serverId]);

        return true;
    }

    /**
     * {@inheritDoc}
     */
    public function getServerStatus(string $serverId): ServerStatus
    {
        if ($this->useDocker && str_starts_with($serverId, 'docker-')) {
            return $this->getDockerContainerStatus($serverId);
        }

        if (!isset($this->servers[$serverId])) {
            return ServerStatus::from(ServerStatus::STATUS_TERMINATED, 'Server not found');
        }

        $server = $this->servers[$serverId];

        return new ServerStatus(
            status: $server['status'],
            message: 'Server is running locally',
            metadata: $server,
            lastChecked: new \DateTimeImmutable()
        );
    }

    /**
     * {@inheritDoc}
     */
    public function executeCommand(string $serverId, string $command, int $timeout = 300): CommandResult
    {
        Log::info('Executing command on local VPS', [
            'server_id' => $serverId,
            'command' => $command,
        ]);

        $startTime = microtime(true);

        if ($this->useDocker && str_starts_with($serverId, 'docker-')) {
            $containerName = $this->getContainerName($serverId);
            $result = Process::timeout($timeout)->run("docker exec {$containerName} /bin/bash -c " . escapeshellarg($command));
        } else {
            // Execute locally for testing
            $result = Process::timeout($timeout)->run($command);
        }

        $executionTime = microtime(true) - $startTime;

        $commandResult = new CommandResult(
            exitCode: $result->exitCode(),
            output: $result->output(),
            error: $result->errorOutput(),
            executionTime: $executionTime,
            command: $command
        );

        Log::info('Command executed on local VPS', [
            'server_id' => $serverId,
            'exit_code' => $commandResult->exitCode,
            'execution_time' => $executionTime,
        ]);

        return $commandResult;
    }

    /**
     * {@inheritDoc}
     */
    public function uploadFile(string $serverId, string $localPath, string $remotePath): bool
    {
        Log::info('Uploading file to local VPS', [
            'server_id' => $serverId,
            'local_path' => $localPath,
            'remote_path' => $remotePath,
        ]);

        if (!file_exists($localPath)) {
            throw new RuntimeException("Local file not found: {$localPath}");
        }

        if ($this->useDocker && str_starts_with($serverId, 'docker-')) {
            $containerName = $this->getContainerName($serverId);
            $result = Process::run("docker cp {$localPath} {$containerName}:{$remotePath}");
            return $result->successful();
        }

        // For testing, just copy to a temp location
        $destination = sys_get_temp_dir() . '/' . basename($remotePath);
        return copy($localPath, $destination);
    }

    /**
     * {@inheritDoc}
     */
    public function downloadFile(string $serverId, string $remotePath, string $localPath): bool
    {
        Log::info('Downloading file from local VPS', [
            'server_id' => $serverId,
            'remote_path' => $remotePath,
            'local_path' => $localPath,
        ]);

        if ($this->useDocker && str_starts_with($serverId, 'docker-')) {
            $containerName = $this->getContainerName($serverId);
            $result = Process::run("docker cp {$containerName}:{$remotePath} {$localPath}");
            return $result->successful();
        }

        // For testing, copy from temp location
        $source = sys_get_temp_dir() . '/' . basename($remotePath);
        if (file_exists($source)) {
            return copy($source, $localPath);
        }

        return false;
    }

    /**
     * {@inheritDoc}
     */
    public function isServerReachable(string $serverId): bool
    {
        if ($this->useDocker && str_starts_with($serverId, 'docker-')) {
            $containerName = $this->getContainerName($serverId);
            $result = Process::run("docker inspect -f '{{.State.Running}}' {$containerName}");
            return trim($result->output()) === 'true';
        }

        return isset($this->servers[$serverId]);
    }

    /**
     * {@inheritDoc}
     */
    public function getServerMetrics(string $serverId): array
    {
        if ($this->useDocker && str_starts_with($serverId, 'docker-')) {
            return $this->getDockerContainerMetrics($serverId);
        }

        if (!isset($this->servers[$serverId])) {
            throw new RuntimeException("Server not found: {$serverId}");
        }

        // Return simulated metrics for testing
        return [
            'cpu_usage_percent' => rand(5, 80),
            'ram_usage_mb' => rand(100, 1000),
            'disk_usage_gb' => rand(1, 50),
            'network_in_mbps' => rand(1, 100),
            'network_out_mbps' => rand(1, 100),
            'uptime_seconds' => rand(100, 86400),
        ];
    }

    /**
     * {@inheritDoc}
     */
    public function restartServer(string $serverId): bool
    {
        Log::info('Restarting local VPS server', ['server_id' => $serverId]);

        if ($this->useDocker && str_starts_with($serverId, 'docker-')) {
            $containerName = $this->getContainerName($serverId);
            $result = Process::run("docker restart {$containerName}");
            return $result->successful();
        }

        if (!isset($this->servers[$serverId])) {
            throw new RuntimeException("Server not found: {$serverId}");
        }

        // Simulate restart
        $this->servers[$serverId]['status'] = ServerStatus::STATUS_REBOOTING;
        sleep(1);
        $this->servers[$serverId]['status'] = ServerStatus::STATUS_ONLINE;

        return true;
    }

    /**
     * {@inheritDoc}
     */
    public function getProviderName(): string
    {
        return 'local';
    }

    /**
     * Create Docker container as VPS
     *
     * @param VpsSpecification $spec
     * @return array<string, mixed>
     */
    private function createDockerContainer(VpsSpecification $spec): array
    {
        $containerName = 'chom-vps-' . uniqid();
        $image = $this->getDockerImage($spec->operatingSystem);

        $cpuLimit = $spec->cpuCores;
        $memoryLimit = $spec->ramMb . 'm';

        $command = sprintf(
            'docker run -d --name %s --network %s --cpus=%s --memory=%s %s /bin/bash -c "tail -f /dev/null"',
            $containerName,
            $this->networkName,
            $cpuLimit,
            $memoryLimit,
            $image
        );

        $result = Process::run($command);

        if (!$result->successful()) {
            throw new RuntimeException("Failed to create Docker container: {$result->errorOutput()}");
        }

        $containerId = trim($result->output());
        $serverId = 'docker-' . substr($containerId, 0, 12);

        // Get container IP
        $ipResult = Process::run("docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' {$containerName}");
        $ipAddress = trim($ipResult->output());

        return [
            'id' => $serverId,
            'name' => $spec->name,
            'container_name' => $containerName,
            'container_id' => $containerId,
            'ip_address' => $ipAddress ?: '172.17.0.' . rand(2, 254),
            'status' => ServerStatus::STATUS_ONLINE,
            'cpu_cores' => $spec->cpuCores,
            'ram_mb' => $spec->ramMb,
            'disk_gb' => $spec->diskGb,
            'os' => $spec->operatingSystem,
            'region' => 'local',
            'created_at' => now()->toIso8601String(),
        ];
    }

    /**
     * Delete Docker container
     *
     * @param string $serverId
     * @return bool
     */
    private function deleteDockerContainer(string $serverId): bool
    {
        $containerName = $this->getContainerName($serverId);
        $result = Process::run("docker rm -f {$containerName}");
        return $result->successful();
    }

    /**
     * Get Docker container status
     *
     * @param string $serverId
     * @return ServerStatus
     */
    private function getDockerContainerStatus(string $serverId): ServerStatus
    {
        $containerName = $this->getContainerName($serverId);
        $result = Process::run("docker inspect -f '{{.State.Status}}' {$containerName}");

        if (!$result->successful()) {
            return ServerStatus::from(ServerStatus::STATUS_TERMINATED, 'Container not found');
        }

        $dockerStatus = trim($result->output());
        $status = match ($dockerStatus) {
            'running' => ServerStatus::STATUS_ONLINE,
            'paused' => ServerStatus::STATUS_MAINTENANCE,
            'restarting' => ServerStatus::STATUS_REBOOTING,
            'exited', 'dead' => ServerStatus::STATUS_OFFLINE,
            default => ServerStatus::STATUS_ERROR,
        };

        return ServerStatus::from($status, "Container status: {$dockerStatus}");
    }

    /**
     * Get Docker container metrics
     *
     * @param string $serverId
     * @return array<string, mixed>
     */
    private function getDockerContainerMetrics(string $serverId): array
    {
        $containerName = $this->getContainerName($serverId);
        $result = Process::run("docker stats {$containerName} --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}'");

        if (!$result->successful()) {
            throw new RuntimeException("Failed to get container metrics: {$result->errorOutput()}");
        }

        $stats = explode('|', trim($result->output()));

        return [
            'cpu_usage_percent' => floatval(str_replace('%', '', $stats[0] ?? '0')),
            'ram_usage_mb' => $this->parseMemoryUsage($stats[1] ?? '0'),
            'disk_usage_gb' => 0,
            'network_in_mbps' => $this->parseNetworkIO($stats[2] ?? '0 / 0', true),
            'network_out_mbps' => $this->parseNetworkIO($stats[2] ?? '0 / 0', false),
            'uptime_seconds' => 0,
        ];
    }

    /**
     * Initialize Docker network if not exists
     */
    private function initializeDockerNetwork(): void
    {
        if (!$this->useDocker) {
            return;
        }

        $result = Process::run("docker network inspect {$this->networkName}");
        if (!$result->successful()) {
            Process::run("docker network create {$this->networkName}");
        }
    }

    /**
     * Get Docker image for OS
     *
     * @param string $os
     * @return string
     */
    private function getDockerImage(string $os): string
    {
        return match (true) {
            str_contains($os, 'ubuntu-22') => 'ubuntu:22.04',
            str_contains($os, 'ubuntu-20') => 'ubuntu:20.04',
            str_contains($os, 'debian') => 'debian:bullseye',
            str_contains($os, 'alpine') => 'alpine:latest',
            default => 'ubuntu:22.04',
        };
    }

    /**
     * Get container name from server ID
     *
     * @param string $serverId
     * @return string
     */
    private function getContainerName(string $serverId): string
    {
        // For docker-based servers, try to find container by ID
        $containerId = str_replace('docker-', '', $serverId);
        $result = Process::run("docker ps -aqf id={$containerId}");

        if ($result->successful() && !empty(trim($result->output()))) {
            return trim($result->output());
        }

        return 'chom-vps-' . $serverId;
    }

    /**
     * Parse memory usage string
     *
     * @param string $memUsage
     * @return float
     */
    private function parseMemoryUsage(string $memUsage): float
    {
        // Format: "123.4MiB / 1GiB"
        if (preg_match('/([0-9.]+)([A-Za-z]+)/', $memUsage, $matches)) {
            $value = floatval($matches[1]);
            $unit = strtoupper($matches[2]);

            return match ($unit) {
                'GIB', 'GB' => $value * 1024,
                'MIB', 'MB' => $value,
                'KIB', 'KB' => $value / 1024,
                default => $value,
            };
        }

        return 0.0;
    }

    /**
     * Parse network I/O string
     *
     * @param string $netIO
     * @param bool $input
     * @return float
     */
    private function parseNetworkIO(string $netIO, bool $input): float
    {
        // Format: "1.23MB / 4.56MB"
        $parts = explode('/', $netIO);
        $value = trim($input ? $parts[0] : ($parts[1] ?? '0'));

        if (preg_match('/([0-9.]+)([A-Za-z]+)/', $value, $matches)) {
            $num = floatval($matches[1]);
            $unit = strtoupper($matches[2]);

            return match ($unit) {
                'GB' => $num * 1024,
                'MB' => $num,
                'KB' => $num / 1024,
                default => $num,
            };
        }

        return 0.0;
    }
}
