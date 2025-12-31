<?php

namespace App\Services\VPS;

use App\Models\VpsServer;
use Illuminate\Support\Facades\Log;
use phpseclib3\Net\SSH2;
use phpseclib3\Crypt\PublicKeyLoader;

/**
 * VPS Connection Manager.
 *
 * Handles SSH connections to VPS servers.
 * Follows Single Responsibility Principle - only manages connections.
 */
class VpsConnectionManager
{
    private ?SSH2 $ssh = null;
    private int $timeout = 120; // seconds

    /**
     * Connect to a VPS server via SSH.
     *
     * @param VpsServer $vps The VPS server to connect to
     * @throws \RuntimeException If connection fails
     */
    public function connect(VpsServer $vps): void
    {
        $this->disconnect();

        $this->ssh = new SSH2($vps->ip_address, 22);
        $this->ssh->setTimeout($this->timeout);

        // Load SSH key
        $keyPath = config('chom.ssh_key_path', storage_path('app/ssh/chom_deploy_key'));

        if (!file_exists($keyPath)) {
            throw new \RuntimeException("SSH key not found at: {$keyPath}");
        }

        // Validate SSH key permissions (should be 0600 for security)
        $this->validateSshKeyPermissions($keyPath);

        $key = PublicKeyLoader::load(file_get_contents($keyPath));

        if (!$this->ssh->login('root', $key)) {
            throw new \RuntimeException("SSH authentication failed for VPS: {$vps->hostname}");
        }

        Log::info('SSH connected', ['vps' => $vps->hostname, 'ip' => $vps->ip_address]);
    }

    /**
     * Disconnect from current VPS.
     */
    public function disconnect(): void
    {
        if ($this->ssh) {
            $this->ssh->disconnect();
            $this->ssh = null;
        }
    }

    /**
     * Test SSH connection to VPS.
     *
     * @param VpsServer $vps
     * @return bool True if connection successful, false otherwise
     */
    public function testConnection(VpsServer $vps): bool
    {
        try {
            $this->connect($vps);
            $this->disconnect();
            return true;
        } catch (\Exception $e) {
            Log::warning('SSH connection test failed', [
                'vps' => $vps->hostname,
                'error' => $e->getMessage(),
            ]);
            return false;
        }
    }

    /**
     * Get the active SSH connection.
     *
     * @return SSH2|null
     */
    public function getConnection(): ?SSH2
    {
        return $this->ssh;
    }

    /**
     * Check if currently connected.
     *
     * @return bool
     */
    public function isConnected(): bool
    {
        return $this->ssh !== null && $this->ssh->isConnected();
    }

    /**
     * Set connection timeout in seconds.
     *
     * @param int $seconds
     */
    public function setTimeout(int $seconds): void
    {
        $this->timeout = $seconds;

        if ($this->ssh) {
            $this->ssh->setTimeout($seconds);
        }
    }

    /**
     * Validate SSH key file permissions.
     * SSH keys should have 0600 permissions (read/write only for owner).
     *
     * @param string $keyPath
     * @throws \RuntimeException If permissions are too permissive
     */
    private function validateSshKeyPermissions(string $keyPath): void
    {
        $perms = fileperms($keyPath) & 0777;

        // Allow 0600 (owner read/write) or 0400 (owner read only)
        if ($perms !== 0600 && $perms !== 0400) {
            Log::error('SSH key has insecure permissions', [
                'path' => $keyPath,
                'permissions' => sprintf('0%o', $perms),
                'expected' => '0600 or 0400',
            ]);

            throw new \RuntimeException(
                "SSH key at {$keyPath} has insecure permissions (" . sprintf('0%o', $perms) . "). " .
                "Expected 0600 or 0400. Run: chmod 600 {$keyPath}"
            );
        }
    }

    /**
     * Destructor - ensure connection is closed.
     */
    public function __destruct()
    {
        $this->disconnect();
    }
}
