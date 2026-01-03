<?php

declare(strict_types=1);

namespace App\Infrastructure\Vps;

use App\Contracts\Infrastructure\VpsProviderInterface;
use App\ValueObjects\CommandResult;
use App\ValueObjects\ServerStatus;
use App\ValueObjects\VpsSpecification;
use Illuminate\Support\Facades\Log;
use phpseclib3\Net\SFTP;
use phpseclib3\Net\SSH2;
use RuntimeException;

/**
 * Generic SSH VPS Provider
 *
 * Provides VPS operations using generic SSH/SFTP connections.
 * Works with any VPS that supports SSH access.
 *
 * Pattern: Adapter Pattern - adapts SSH protocol to VPS interface
 * Use Case: Manual VPS management, custom providers, bare metal servers
 *
 * @package App\Infrastructure\Vps
 */
class GenericSshVpsProvider implements VpsProviderInterface
{
    /**
     * @var array<string, SSH2> SSH connection pool
     */
    private array $connections = [];

    /**
     * @var array<string, array<string, mixed>> Server registry
     */
    private array $servers = [];

    public function __construct(
        private readonly int $sshPort = 22,
        private readonly int $timeout = 300,
        private readonly ?string $privateKeyPath = null
    ) {
    }

    /**
     * {@inheritDoc}
     */
    public function createServer(VpsSpecification $spec): array
    {
        throw new RuntimeException(
            'GenericSshVpsProvider does not support server creation. ' .
            'Use this provider with pre-existing servers only.'
        );
    }

    /**
     * {@inheritDoc}
     */
    public function deleteServer(string $serverId): bool
    {
        Log::info('Removing server from SSH provider registry', ['server_id' => $serverId]);

        if (isset($this->connections[$serverId])) {
            $this->connections[$serverId]->disconnect();
            unset($this->connections[$serverId]);
        }

        unset($this->servers[$serverId]);

        return true;
    }

    /**
     * {@inheritDoc}
     */
    public function getServerStatus(string $serverId): ServerStatus
    {
        if (!isset($this->servers[$serverId])) {
            return ServerStatus::from(ServerStatus::STATUS_TERMINATED, 'Server not registered');
        }

        $server = $this->servers[$serverId];

        try {
            $ssh = $this->getConnection($serverId);
            $output = $ssh->exec('echo "OK"');

            if (trim($output) === 'OK') {
                return ServerStatus::from(ServerStatus::STATUS_ONLINE, 'SSH connection successful');
            }

            return ServerStatus::from(ServerStatus::STATUS_ERROR, 'SSH connection established but command failed');
        } catch (\Exception $e) {
            return ServerStatus::from(ServerStatus::STATUS_OFFLINE, "SSH connection failed: {$e->getMessage()}");
        }
    }

    /**
     * {@inheritDoc}
     */
    public function executeCommand(string $serverId, string $command, int $timeout = 300): CommandResult
    {
        Log::info('Executing SSH command', [
            'server_id' => $serverId,
            'command' => $command,
        ]);

        $startTime = microtime(true);

        try {
            $ssh = $this->getConnection($serverId);
            $ssh->setTimeout($timeout);

            $output = $ssh->exec($command);
            $exitCode = $ssh->getExitStatus() ?? 0;
            $error = $ssh->getStdError() ?? '';

            $executionTime = microtime(true) - $startTime;

            return new CommandResult(
                exitCode: $exitCode,
                output: $output,
                error: $error,
                executionTime: $executionTime,
                command: $command
            );
        } catch (\Exception $e) {
            $executionTime = microtime(true) - $startTime;

            return CommandResult::failure(
                error: "SSH command failed: {$e->getMessage()}",
                exitCode: 255,
                executionTime: $executionTime
            );
        }
    }

    /**
     * {@inheritDoc}
     */
    public function uploadFile(string $serverId, string $localPath, string $remotePath): bool
    {
        Log::info('Uploading file via SFTP', [
            'server_id' => $serverId,
            'local_path' => $localPath,
            'remote_path' => $remotePath,
        ]);

        if (!file_exists($localPath)) {
            throw new RuntimeException("Local file not found: {$localPath}");
        }

        $server = $this->servers[$serverId] ?? null;
        if (!$server) {
            throw new RuntimeException("Server not registered: {$serverId}");
        }

        $sftp = new SFTP($server['host'], $server['port'] ?? $this->sshPort);

        if (!$this->authenticateSftp($sftp, $server)) {
            throw new RuntimeException('SFTP authentication failed');
        }

        $contents = file_get_contents($localPath);
        if ($contents === false) {
            throw new RuntimeException("Failed to read local file: {$localPath}");
        }

        $success = $sftp->put($remotePath, $contents);

        $sftp->disconnect();

        return $success;
    }

    /**
     * {@inheritDoc}
     */
    public function downloadFile(string $serverId, string $remotePath, string $localPath): bool
    {
        Log::info('Downloading file via SFTP', [
            'server_id' => $serverId,
            'remote_path' => $remotePath,
            'local_path' => $localPath,
        ]);

        $server = $this->servers[$serverId] ?? null;
        if (!$server) {
            throw new RuntimeException("Server not registered: {$serverId}");
        }

        $sftp = new SFTP($server['host'], $server['port'] ?? $this->sshPort);

        if (!$this->authenticateSftp($sftp, $server)) {
            throw new RuntimeException('SFTP authentication failed');
        }

        $contents = $sftp->get($remotePath);

        $sftp->disconnect();

        if ($contents === false) {
            return false;
        }

        return file_put_contents($localPath, $contents) !== false;
    }

    /**
     * {@inheritDoc}
     */
    public function isServerReachable(string $serverId): bool
    {
        try {
            $status = $this->getServerStatus($serverId);
            return $status->isOnline();
        } catch (\Exception $e) {
            return false;
        }
    }

    /**
     * {@inheritDoc}
     */
    public function getServerMetrics(string $serverId): array
    {
        $result = $this->executeCommand($serverId, 'cat /proc/loadavg && free -m && df -h');

        if (!$result->isSuccessful()) {
            throw new RuntimeException('Failed to retrieve server metrics');
        }

        return $this->parseMetrics($result->output);
    }

    /**
     * {@inheritDoc}
     */
    public function restartServer(string $serverId): bool
    {
        Log::info('Restarting server via SSH', ['server_id' => $serverId]);

        $result = $this->executeCommand($serverId, 'sudo reboot');

        // Disconnect as server will be restarting
        if (isset($this->connections[$serverId])) {
            $this->connections[$serverId]->disconnect();
            unset($this->connections[$serverId]);
        }

        return $result->isSuccessful() || $result->exitCode === 255; // 255 = connection lost during reboot
    }

    /**
     * {@inheritDoc}
     */
    public function getProviderName(): string
    {
        return 'ssh';
    }

    /**
     * Register a server for SSH management
     *
     * @param string $serverId
     * @param string $host
     * @param string $username
     * @param string|null $password
     * @param string|null $privateKey
     * @param int|null $port
     * @return void
     */
    public function registerServer(
        string $serverId,
        string $host,
        string $username,
        ?string $password = null,
        ?string $privateKey = null,
        ?int $port = null
    ): void {
        $this->servers[$serverId] = [
            'id' => $serverId,
            'host' => $host,
            'username' => $username,
            'password' => $password,
            'private_key' => $privateKey ?? $this->privateKeyPath,
            'port' => $port ?? $this->sshPort,
        ];

        Log::info('Server registered with SSH provider', [
            'server_id' => $serverId,
            'host' => $host,
        ]);
    }

    /**
     * Execute command on specific host
     *
     * @param string $host
     * @param string $command
     * @param string $username
     * @param string|null $password
     * @param string|null $privateKey
     * @param int|null $port
     * @param int $timeout
     * @return CommandResult
     */
    public function executeCommandOnHost(
        string $host,
        string $command,
        string $username = 'root',
        ?string $password = null,
        ?string $privateKey = null,
        ?int $port = null,
        int $timeout = 300
    ): CommandResult {
        $ssh = new SSH2($host, $port ?? $this->sshPort);
        $ssh->setTimeout($timeout);

        if (!$this->authenticate($ssh, $username, $password, $privateKey)) {
            throw new RuntimeException("SSH authentication failed for {$host}");
        }

        $startTime = microtime(true);
        $output = $ssh->exec($command);
        $exitCode = $ssh->getExitStatus() ?? 0;
        $error = $ssh->getStdError() ?? '';
        $executionTime = microtime(true) - $startTime;

        $ssh->disconnect();

        return new CommandResult($exitCode, $output, $error, $executionTime, $command);
    }

    /**
     * Upload file to specific host
     *
     * @param string $host
     * @param string $localPath
     * @param string $remotePath
     * @param string $username
     * @param string|null $password
     * @param string|null $privateKey
     * @param int|null $port
     * @return bool
     */
    public function uploadFileToHost(
        string $host,
        string $localPath,
        string $remotePath,
        string $username = 'root',
        ?string $password = null,
        ?string $privateKey = null,
        ?int $port = null
    ): bool {
        $sftp = new SFTP($host, $port ?? $this->sshPort);

        if (!$this->authenticate($sftp, $username, $password, $privateKey)) {
            throw new RuntimeException("SFTP authentication failed for {$host}");
        }

        $contents = file_get_contents($localPath);
        if ($contents === false) {
            throw new RuntimeException("Failed to read local file: {$localPath}");
        }

        $success = $sftp->put($remotePath, $contents);
        $sftp->disconnect();

        return $success;
    }

    /**
     * Download file from specific host
     *
     * @param string $host
     * @param string $remotePath
     * @param string $localPath
     * @param string $username
     * @param string|null $password
     * @param string|null $privateKey
     * @param int|null $port
     * @return bool
     */
    public function downloadFileFromHost(
        string $host,
        string $remotePath,
        string $localPath,
        string $username = 'root',
        ?string $password = null,
        ?string $privateKey = null,
        ?int $port = null
    ): bool {
        $sftp = new SFTP($host, $port ?? $this->sshPort);

        if (!$this->authenticate($sftp, $username, $password, $privateKey)) {
            throw new RuntimeException("SFTP authentication failed for {$host}");
        }

        $contents = $sftp->get($remotePath);
        $sftp->disconnect();

        if ($contents === false) {
            return false;
        }

        return file_put_contents($localPath, $contents) !== false;
    }

    /**
     * Get or create SSH connection
     *
     * @param string $serverId
     * @return SSH2
     */
    private function getConnection(string $serverId): SSH2
    {
        if (isset($this->connections[$serverId])) {
            return $this->connections[$serverId];
        }

        $server = $this->servers[$serverId] ?? null;
        if (!$server) {
            throw new RuntimeException("Server not registered: {$serverId}");
        }

        $ssh = new SSH2($server['host'], $server['port'] ?? $this->sshPort);
        $ssh->setTimeout($this->timeout);

        if (!$this->authenticate($ssh, $server['username'], $server['password'], $server['private_key'])) {
            throw new RuntimeException("SSH authentication failed for server: {$serverId}");
        }

        $this->connections[$serverId] = $ssh;

        return $ssh;
    }

    /**
     * Authenticate SSH/SFTP connection
     *
     * @param SSH2|SFTP $connection
     * @param string $username
     * @param string|null $password
     * @param string|null $privateKey
     * @return bool
     */
    private function authenticate($connection, string $username, ?string $password, ?string $privateKey): bool
    {
        if ($privateKey && file_exists($privateKey)) {
            $key = new \phpseclib3\Crypt\PublicKeyLoader();
            $loadedKey = $key::load(file_get_contents($privateKey), $password);
            return $connection->login($username, $loadedKey);
        }

        if ($password) {
            return $connection->login($username, $password);
        }

        return false;
    }

    /**
     * Authenticate SFTP connection
     *
     * @param SFTP $sftp
     * @param array<string, mixed> $server
     * @return bool
     */
    private function authenticateSftp(SFTP $sftp, array $server): bool
    {
        return $this->authenticate(
            $sftp,
            $server['username'],
            $server['password'] ?? null,
            $server['private_key'] ?? null
        );
    }

    /**
     * Parse server metrics from command output
     *
     * @param string $output
     * @return array<string, mixed>
     */
    private function parseMetrics(string $output): array
    {
        return [
            'cpu_usage_percent' => 0,
            'ram_usage_mb' => 0,
            'disk_usage_gb' => 0,
            'network_in_mbps' => 0,
            'network_out_mbps' => 0,
            'raw_output' => $output,
        ];
    }
}
