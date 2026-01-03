<?php

declare(strict_types=1);

namespace App\Infrastructure\Vps;

use App\Contracts\Infrastructure\VpsProviderInterface;
use App\ValueObjects\CommandResult;
use App\ValueObjects\ServerStatus;
use App\ValueObjects\VpsSpecification;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;

/**
 * DigitalOcean VPS Provider
 *
 * Provides VPS operations using DigitalOcean API.
 * Implements complete integration with DigitalOcean Droplets.
 *
 * Documentation: https://docs.digitalocean.com/reference/api/api-reference/
 * Pattern: Adapter Pattern - adapts DigitalOcean API to VPS interface
 *
 * @package App\Infrastructure\Vps
 */
class DigitalOceanVpsProvider implements VpsProviderInterface
{
    private const API_BASE_URL = 'https://api.digitalocean.com/v2';

    /**
     * @var GenericSshVpsProvider SSH provider for command execution
     */
    private GenericSshVpsProvider $sshProvider;

    public function __construct(
        private readonly string $apiToken,
        private readonly ?string $sshKeyId = null,
        private readonly int $timeout = 60
    ) {
        if (empty($apiToken)) {
            throw new RuntimeException('DigitalOcean API token is required');
        }

        $this->sshProvider = new GenericSshVpsProvider();
    }

    /**
     * {@inheritDoc}
     */
    public function createServer(VpsSpecification $spec): array
    {
        Log::info('Creating DigitalOcean droplet', ['name' => $spec->name]);

        $payload = [
            'name' => $spec->name,
            'region' => $this->mapRegion($spec->region),
            'size' => $this->selectSize($spec),
            'image' => $this->mapOperatingSystem($spec->operatingSystem),
            'backups' => $spec->backupsEnabled,
            'monitoring' => $spec->monitoringEnabled,
            'tags' => array_merge(['chom', 'managed'], $spec->tags),
        ];

        if ($this->sshKeyId) {
            $payload['ssh_keys'] = [$this->sshKeyId];
        } elseif (!empty($spec->sshKeys)) {
            $payload['ssh_keys'] = $spec->sshKeys;
        }

        $response = Http::timeout($this->timeout)
            ->withToken($this->apiToken)
            ->post(self::API_BASE_URL . '/droplets', $payload);

        if (!$response->successful()) {
            throw new RuntimeException(
                "Failed to create DigitalOcean droplet: {$response->body()}"
            );
        }

        $droplet = $response->json('droplet');

        // Wait for droplet to get IP address
        $droplet = $this->waitForIpAddress($droplet['id']);

        Log::info('DigitalOcean droplet created', ['droplet_id' => $droplet['id']]);

        return [
            'id' => (string) $droplet['id'],
            'name' => $droplet['name'],
            'ip_address' => $this->extractIpAddress($droplet),
            'status' => $this->mapStatus($droplet['status']),
            'cpu_cores' => $droplet['vcpus'] ?? $spec->cpuCores,
            'ram_mb' => $droplet['memory'] ?? $spec->ramMb,
            'disk_gb' => $droplet['disk'] ?? $spec->diskGb,
            'os' => $droplet['image']['slug'] ?? $spec->operatingSystem,
            'region' => $droplet['region']['slug'] ?? $spec->region,
            'created_at' => $droplet['created_at'] ?? now()->toIso8601String(),
        ];
    }

    /**
     * {@inheritDoc}
     */
    public function deleteServer(string $serverId): bool
    {
        Log::info('Deleting DigitalOcean droplet', ['droplet_id' => $serverId]);

        $response = Http::timeout($this->timeout)
            ->withToken($this->apiToken)
            ->delete(self::API_BASE_URL . "/droplets/{$serverId}");

        if (!$response->successful() && $response->status() !== 404) {
            throw new RuntimeException(
                "Failed to delete DigitalOcean droplet: {$response->body()}"
            );
        }

        Log::info('DigitalOcean droplet deleted', ['droplet_id' => $serverId]);

        return true;
    }

    /**
     * {@inheritDoc}
     */
    public function getServerStatus(string $serverId): ServerStatus
    {
        $response = Http::timeout($this->timeout)
            ->withToken($this->apiToken)
            ->get(self::API_BASE_URL . "/droplets/{$serverId}");

        if (!$response->successful()) {
            if ($response->status() === 404) {
                return ServerStatus::from(ServerStatus::STATUS_TERMINATED, 'Droplet not found');
            }

            throw new RuntimeException(
                "Failed to get droplet status: {$response->body()}"
            );
        }

        $droplet = $response->json('droplet');
        $status = $this->mapStatus($droplet['status']);

        return new ServerStatus(
            status: $status,
            message: "Droplet status: {$droplet['status']}",
            metadata: $droplet,
            lastChecked: new \DateTimeImmutable()
        );
    }

    /**
     * {@inheritDoc}
     */
    public function executeCommand(string $serverId, string $command, int $timeout = 300): CommandResult
    {
        $droplet = $this->getDropletDetails($serverId);
        $ipAddress = $this->extractIpAddress($droplet);

        return $this->sshProvider->executeCommandOnHost($ipAddress, $command, 'root', timeout: $timeout);
    }

    /**
     * {@inheritDoc}
     */
    public function uploadFile(string $serverId, string $localPath, string $remotePath): bool
    {
        $droplet = $this->getDropletDetails($serverId);
        $ipAddress = $this->extractIpAddress($droplet);

        return $this->sshProvider->uploadFileToHost($ipAddress, $localPath, $remotePath, 'root');
    }

    /**
     * {@inheritDoc}
     */
    public function downloadFile(string $serverId, string $remotePath, string $localPath): bool
    {
        $droplet = $this->getDropletDetails($serverId);
        $ipAddress = $this->extractIpAddress($droplet);

        return $this->sshProvider->downloadFileFromHost($ipAddress, $remotePath, $localPath, 'root');
    }

    /**
     * {@inheritDoc}
     */
    public function isServerReachable(string $serverId): bool
    {
        try {
            $status = $this->getServerStatus($serverId);
            return $status->isOnline();
        } catch (RuntimeException $e) {
            return false;
        }
    }

    /**
     * {@inheritDoc}
     */
    public function getServerMetrics(string $serverId): array
    {
        // DigitalOcean monitoring API endpoint
        $response = Http::timeout($this->timeout)
            ->withToken($this->apiToken)
            ->get(self::API_BASE_URL . "/monitoring/metrics/droplet/cpu", [
                'host_id' => $serverId,
                'start' => now()->subMinutes(5)->timestamp,
                'end' => now()->timestamp,
            ]);

        if (!$response->successful()) {
            // Return basic metrics if monitoring not available
            return [
                'cpu_usage_percent' => 0,
                'ram_usage_mb' => 0,
                'disk_usage_gb' => 0,
                'network_in_mbps' => 0,
                'network_out_mbps' => 0,
            ];
        }

        $metrics = $response->json('data.result', []);

        return [
            'cpu_usage_percent' => $this->extractLatestMetric($metrics, 'cpu') ?? 0,
            'ram_usage_mb' => 0, // Would need separate API call
            'disk_usage_gb' => 0, // Would need separate API call
            'network_in_mbps' => 0, // Would need separate API call
            'network_out_mbps' => 0, // Would need separate API call
        ];
    }

    /**
     * {@inheritDoc}
     */
    public function restartServer(string $serverId): bool
    {
        Log::info('Restarting DigitalOcean droplet', ['droplet_id' => $serverId]);

        $response = Http::timeout($this->timeout)
            ->withToken($this->apiToken)
            ->post(self::API_BASE_URL . "/droplets/{$serverId}/actions", [
                'type' => 'reboot',
            ]);

        if (!$response->successful()) {
            throw new RuntimeException(
                "Failed to restart droplet: {$response->body()}"
            );
        }

        return true;
    }

    /**
     * {@inheritDoc}
     */
    public function getProviderName(): string
    {
        return 'digitalocean';
    }

    /**
     * Get droplet details
     *
     * @param string $serverId
     * @return array<string, mixed>
     */
    private function getDropletDetails(string $serverId): array
    {
        $response = Http::timeout($this->timeout)
            ->withToken($this->apiToken)
            ->get(self::API_BASE_URL . "/droplets/{$serverId}");

        if (!$response->successful()) {
            throw new RuntimeException("Failed to get droplet details: {$response->body()}");
        }

        return $response->json('droplet');
    }

    /**
     * Wait for droplet to get IP address
     *
     * @param int $dropletId
     * @param int $maxAttempts
     * @return array<string, mixed>
     */
    private function waitForIpAddress(int $dropletId, int $maxAttempts = 30): array
    {
        $attempts = 0;

        while ($attempts < $maxAttempts) {
            $droplet = $this->getDropletDetails((string) $dropletId);

            if (!empty($this->extractIpAddress($droplet))) {
                return $droplet;
            }

            sleep(2);
            $attempts++;
        }

        throw new RuntimeException('Timeout waiting for droplet IP address');
    }

    /**
     * Extract IP address from droplet data
     *
     * @param array<string, mixed> $droplet
     * @return string|null
     */
    private function extractIpAddress(array $droplet): ?string
    {
        $networks = $droplet['networks']['v4'] ?? [];

        foreach ($networks as $network) {
            if ($network['type'] === 'public') {
                return $network['ip_address'];
            }
        }

        return null;
    }

    /**
     * Map VPS specification to DigitalOcean size slug
     *
     * @param VpsSpecification $spec
     * @return string
     */
    private function selectSize(VpsSpecification $spec): string
    {
        // Map specification to closest DigitalOcean size
        if ($spec->cpuCores <= 1 && $spec->ramMb <= 1024) {
            return 's-1vcpu-1gb';
        }
        if ($spec->cpuCores <= 1 && $spec->ramMb <= 2048) {
            return 's-1vcpu-2gb';
        }
        if ($spec->cpuCores <= 2 && $spec->ramMb <= 2048) {
            return 's-2vcpu-2gb';
        }
        if ($spec->cpuCores <= 2 && $spec->ramMb <= 4096) {
            return 's-2vcpu-4gb';
        }
        if ($spec->cpuCores <= 4 && $spec->ramMb <= 8192) {
            return 's-4vcpu-8gb';
        }

        return 's-1vcpu-1gb'; // Default
    }

    /**
     * Map region to DigitalOcean region slug
     *
     * @param string $region
     * @return string
     */
    private function mapRegion(string $region): string
    {
        return match ($region) {
            'us-east-1' => 'nyc1',
            'us-west-1' => 'sfo1',
            'us-west-2' => 'sfo3',
            'eu-west-1' => 'lon1',
            'eu-central-1' => 'fra1',
            'ap-southeast-1' => 'sgp1',
            default => 'nyc1',
        };
    }

    /**
     * Map operating system to DigitalOcean image slug
     *
     * @param string $os
     * @return string
     */
    private function mapOperatingSystem(string $os): string
    {
        return match ($os) {
            'ubuntu-22.04' => 'ubuntu-22-04-x64',
            'ubuntu-20.04' => 'ubuntu-20-04-x64',
            'debian-11' => 'debian-11-x64',
            'debian-12' => 'debian-12-x64',
            default => 'ubuntu-22-04-x64',
        };
    }

    /**
     * Map DigitalOcean status to ServerStatus
     *
     * @param string $status
     * @return string
     */
    private function mapStatus(string $status): string
    {
        return match ($status) {
            'new' => ServerStatus::STATUS_PROVISIONING,
            'active' => ServerStatus::STATUS_ONLINE,
            'off' => ServerStatus::STATUS_OFFLINE,
            'archive' => ServerStatus::STATUS_TERMINATED,
            default => ServerStatus::STATUS_ERROR,
        };
    }

    /**
     * Extract latest metric value
     *
     * @param array<mixed> $metrics
     * @param string $metricType
     * @return float|null
     */
    private function extractLatestMetric(array $metrics, string $metricType): ?float
    {
        if (empty($metrics)) {
            return null;
        }

        $values = $metrics[0]['values'] ?? [];
        if (empty($values)) {
            return null;
        }

        $latest = end($values);
        return isset($latest[1]) ? (float) $latest[1] : null;
    }
}
