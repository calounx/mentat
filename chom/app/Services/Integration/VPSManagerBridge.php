<?php

namespace App\Services\Integration;

use App\Models\VpsServer;
use App\Models\Site;
use App\Services\VPS\VpsConnectionPool;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Crypt;
use phpseclib3\Net\SSH2;
use phpseclib3\Crypt\PublicKeyLoader;

class VPSManagerBridge
{
    private ?SSH2 $ssh = null;
    private string $vpsmanagerPath = '/opt/vpsmanager/bin/vpsmanager';
    private int $timeout = 120; // seconds
    private ?VpsConnectionPool $connectionPool = null;
    private bool $useConnectionPool = true;

    /**
     * Constructor - initialize connection pool
     */
    public function __construct(VpsConnectionPool $connectionPool = null)
    {
        $this->connectionPool = $connectionPool ?? app(VpsConnectionPool::class);
    }

    /**
     * Connect to a VPS server via SSH.
     * Uses connection pooling when enabled for 2-3 second performance improvement.
     */
    public function connect(VpsServer $vps): void
    {
        // If connection pooling is enabled, use pooled connection
        if ($this->useConnectionPool && $this->connectionPool) {
            $this->ssh = $this->connectionPool->getConnection($vps);
            return;
        }

        // Fall back to traditional connection
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
     * When using connection pool, connections are kept alive for reuse.
     */
    public function disconnect(): void
    {
        // When using connection pooling, don't disconnect
        // Connections are managed by the pool
        if ($this->useConnectionPool && $this->connectionPool) {
            $this->ssh = null;
            return;
        }

        // Traditional disconnect
        if ($this->ssh) {
            $this->ssh->disconnect();
            $this->ssh = null;
        }
    }

    /**
     * Disable connection pooling for this instance.
     * Useful for long-running operations.
     */
    public function disableConnectionPooling(): void
    {
        $this->useConnectionPool = false;
    }

    /**
     * Enable connection pooling for this instance.
     */
    public function enableConnectionPooling(): void
    {
        $this->useConnectionPool = true;
    }

    /**
     * Execute a VPSManager command on the remote VPS.
     */
    public function execute(VpsServer $vps, string $command, array $args = []): array
    {
        $this->connect($vps);

        // Build command with arguments
        $fullCommand = $this->vpsmanagerPath . ' ' . $command;

        foreach ($args as $key => $value) {
            if (is_bool($value)) {
                if ($value) {
                    $fullCommand .= " --{$key}";
                }
            } elseif (is_numeric($key)) {
                // Positional argument
                $fullCommand .= ' ' . escapeshellarg($value);
            } else {
                $fullCommand .= " --{$key}=" . escapeshellarg($value);
            }
        }

        // Always request JSON output
        $fullCommand .= ' --format=json 2>&1';

        Log::info('VPSManager command', [
            'vps' => $vps->hostname,
            'command' => $command,
            'full_command' => $fullCommand,
        ]);

        $output = $this->ssh->exec($fullCommand);
        $exitCode = $this->ssh->getExitStatus() ?? 0;

        $this->disconnect();

        $result = [
            'success' => $exitCode === 0,
            'exit_code' => $exitCode,
            'output' => $output,
            'data' => null,
        ];

        // Try to parse JSON output
        if (!empty($output)) {
            $jsonData = $this->parseJsonOutput($output);
            if ($jsonData !== null) {
                $result['data'] = $jsonData;
            }
        }

        Log::info('VPSManager result', [
            'vps' => $vps->hostname,
            'command' => $command,
            'success' => $result['success'],
            'exit_code' => $exitCode,
        ]);

        return $result;
    }

    /**
     * Parse JSON from command output.
     */
    private function parseJsonOutput(string $output): ?array
    {
        // Find JSON in output (may have non-JSON lines before/after)
        if (preg_match('/\{[\s\S]*\}|\[[\s\S]*\]/', $output, $matches)) {
            $json = json_decode($matches[0], true);
            if (json_last_error() === JSON_ERROR_NONE) {
                return $json;
            }
        }
        return null;
    }

    /**
     * Create a WordPress site.
     */
    public function createWordPressSite(VpsServer $vps, string $domain, array $options = []): array
    {
        $args = [
            $domain,
            'type' => 'wordpress',
            'php-version' => $options['php_version'] ?? '8.2',
        ];

        if (!empty($options['admin_email'])) {
            $args['admin-email'] = $options['admin_email'];
        }

        if (!empty($options['admin_user'])) {
            $args['admin-user'] = $options['admin_user'];
        }

        return $this->execute($vps, 'site:create', $args);
    }

    /**
     * Create an HTML site.
     */
    public function createHtmlSite(VpsServer $vps, string $domain): array
    {
        return $this->execute($vps, 'site:create', [
            $domain,
            'type' => 'html',
        ]);
    }

    /**
     * Delete a site.
     */
    public function deleteSite(VpsServer $vps, string $domain, bool $force = false): array
    {
        $args = [$domain];
        if ($force) {
            $args['force'] = true;
        }

        return $this->execute($vps, 'site:delete', $args);
    }

    /**
     * Enable a site.
     */
    public function enableSite(VpsServer $vps, string $domain): array
    {
        return $this->execute($vps, 'site:enable', [$domain]);
    }

    /**
     * Disable a site.
     */
    public function disableSite(VpsServer $vps, string $domain): array
    {
        return $this->execute($vps, 'site:disable', [$domain]);
    }

    /**
     * List all sites on a VPS.
     */
    public function listSites(VpsServer $vps): array
    {
        return $this->execute($vps, 'site:list');
    }

    /**
     * Get site info.
     */
    public function getSiteInfo(VpsServer $vps, string $domain): array
    {
        return $this->execute($vps, 'site:info', [$domain]);
    }

    /**
     * Issue SSL certificate for a domain.
     */
    public function issueSSL(VpsServer $vps, string $domain): array
    {
        return $this->execute($vps, 'ssl:issue', [$domain]);
    }

    /**
     * Renew SSL certificates.
     */
    public function renewSSL(VpsServer $vps, ?string $domain = null): array
    {
        $args = [];
        if ($domain) {
            $args[] = $domain;
        }

        return $this->execute($vps, 'ssl:renew', $args);
    }

    /**
     * Get SSL status for a domain.
     */
    public function getSSLStatus(VpsServer $vps, string $domain): array
    {
        return $this->execute($vps, 'ssl:status', [$domain]);
    }

    /**
     * Create a backup.
     */
    public function createBackup(VpsServer $vps, string $domain, array $components = []): array
    {
        $args = ['site' => $domain];

        if (!empty($components)) {
            $args['components'] = implode(',', $components);
        }

        return $this->execute($vps, 'backup:create', $args);
    }

    /**
     * List backups for a site.
     */
    public function listBackups(VpsServer $vps, string $domain): array
    {
        return $this->execute($vps, 'backup:list', ['site' => $domain]);
    }

    /**
     * Restore a backup.
     */
    public function restoreBackup(VpsServer $vps, string $backupId): array
    {
        return $this->execute($vps, 'backup:restore', [$backupId]);
    }

    /**
     * Export database.
     */
    public function exportDatabase(VpsServer $vps, string $domain): array
    {
        return $this->execute($vps, 'database:export', ['site' => $domain]);
    }

    /**
     * Optimize database.
     */
    public function optimizeDatabase(VpsServer $vps, string $domain): array
    {
        return $this->execute($vps, 'database:optimize', ['site' => $domain]);
    }

    /**
     * Run health check on VPS.
     */
    public function healthCheck(VpsServer $vps): array
    {
        return $this->execute($vps, 'monitor:health');
    }

    /**
     * Get VPS dashboard status.
     */
    public function getDashboard(VpsServer $vps): array
    {
        return $this->execute($vps, 'monitor:dashboard');
    }

    /**
     * Clear cache for a site.
     */
    public function clearCache(VpsServer $vps, string $domain): array
    {
        return $this->execute($vps, 'cache:clear', ['site' => $domain]);
    }

    /**
     * Run security audit.
     */
    public function securityAudit(VpsServer $vps): array
    {
        return $this->execute($vps, 'security:audit');
    }

    /**
     * Get VPSManager version.
     */
    public function getVersion(VpsServer $vps): array
    {
        return $this->execute($vps, '--version', []);
    }

    /**
     * Check if VPSManager is installed and accessible.
     */
    public function isVPSManagerInstalled(VpsServer $vps): bool
    {
        try {
            $result = $this->getVersion($vps);
            return $result['success'];
        } catch (\Exception $e) {
            Log::warning('VPSManager check failed', [
                'vps' => $vps->hostname,
                'error' => $e->getMessage(),
            ]);
            return false;
        }
    }

    /**
     * Allowed commands for executeRaw with strict whitelist.
     */
    private const ALLOWED_RAW_COMMANDS = [
        'uptime',
        'df -h',
        'free -m',
        'cat /etc/os-release',
        'hostname',
        'whoami',
        'date',
        'cat /proc/loadavg',
    ];

    /**
     * Execute a whitelisted SSH command.
     * Only allows commands from the strict whitelist for security.
     *
     * @throws \InvalidArgumentException If command is not in the whitelist
     */
    public function executeRaw(VpsServer $vps, string $command): array
    {
        // Strict command whitelist validation
        $normalizedCommand = trim($command);

        if (!in_array($normalizedCommand, self::ALLOWED_RAW_COMMANDS, true)) {
            Log::warning('Blocked unauthorized raw SSH command attempt', [
                'vps' => $vps->hostname,
                'command' => $command,
            ]);

            throw new \InvalidArgumentException(
                'Command not allowed. Only whitelisted commands are permitted for raw execution.'
            );
        }

        $this->connect($vps);

        Log::info('Raw SSH command (whitelisted)', ['vps' => $vps->hostname, 'command' => $normalizedCommand]);

        $output = $this->ssh->exec($normalizedCommand . ' 2>&1');
        $exitCode = $this->ssh->getExitStatus() ?? 0;

        $this->disconnect();

        return [
            'success' => $exitCode === 0,
            'exit_code' => $exitCode,
            'output' => $output,
        ];
    }

    /**
     * Validate SSH key file permissions.
     * SSH keys should have 0600 permissions (read/write only for owner).
     *
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
     * Test SSH connection to VPS.
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
}
