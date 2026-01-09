<?php

declare(strict_types=1);

namespace App\Services;

use App\Models\Site;
use App\Models\VpsServer;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Process;

/**
 * VPS Manager Service
 *
 * Encapsulates SSH command execution logic for VPSManager operations.
 * VPSManager is a bash-based CLI tool at /opt/vpsmanager/bin/vpsmanager
 * that runs on remote VPS servers.
 *
 * @package App\Services
 */
class VpsManagerService
{
    /**
     * VPSManager binary path on remote servers
     */
    private const VPSMANAGER_PATH = '/opt/vpsmanager/bin/vpsmanager';

    /**
     * Command execution timeout in seconds
     */
    private const DEFAULT_TIMEOUT = 120;

    /**
     * SSH command timeout in seconds
     */
    private const SSH_TIMEOUT = 300;

    /**
     * Execute a VPSManager command on a remote VPS server.
     *
     * @param VpsServer $vps The VPS server to execute command on
     * @param string $command VPSManager command (e.g., 'ssl:issue', 'database:export')
     * @param array $args Command arguments
     * @param int|null $timeout Optional timeout in seconds
     * @return array Command result with output, exit_code, and success status
     * @throws \RuntimeException If command execution fails
     */
    public function executeCommand(
        VpsServer $vps,
        string $command,
        array $args = [],
        ?int $timeout = null
    ): array {
        try {
            $timeout = $timeout ?? self::DEFAULT_TIMEOUT;

            // Build the full command
            $fullCommand = $this->buildCommand($vps, $command, $args);

            Log::info('Executing VPSManager command', [
                'vps_id' => $vps->id,
                'vps_hostname' => $vps->hostname,
                'command' => $command,
                'args' => $args,
                'timeout' => $timeout,
            ]);

            // Execute via SSH
            $result = Process::timeout($timeout)
                ->run($fullCommand);

            $output = $result->output();
            $errorOutput = $result->errorOutput();
            $exitCode = $result->exitCode();
            $successful = $result->successful();

            Log::info('VPSManager command executed', [
                'vps_id' => $vps->id,
                'command' => $command,
                'exit_code' => $exitCode,
                'successful' => $successful,
                'output_length' => strlen($output),
            ]);

            if (!$successful) {
                Log::warning('VPSManager command failed', [
                    'vps_id' => $vps->id,
                    'command' => $command,
                    'exit_code' => $exitCode,
                    'output' => $output,
                    'error_output' => $errorOutput,
                ]);
            }

            return [
                'success' => $successful,
                'output' => $output,
                'error_output' => $errorOutput,
                'exit_code' => $exitCode,
                'parsed' => $this->parseCommandOutput($output, $command),
            ];
        } catch (\Exception $e) {
            Log::error('VPSManager command execution failed', [
                'vps_id' => $vps->id,
                'command' => $command,
                'args' => $args,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            throw new \RuntimeException(
                "Failed to execute VPSManager command '{$command}': {$e->getMessage()}",
                0,
                $e
            );
        }
    }

    /**
     * Issue SSL certificate for a site.
     *
     * @param Site $site
     * @return array Command result
     */
    public function issueSSL(Site $site): array
    {
        $vps = $site->vpsServer;
        if (!$vps) {
            throw new \RuntimeException('Site has no associated VPS server');
        }

        return $this->executeCommand($vps, 'ssl:issue', [$site->domain]);
    }

    /**
     * Renew SSL certificate for a site.
     *
     * @param Site $site
     * @return array Command result
     */
    public function renewSSL(Site $site): array
    {
        $vps = $site->vpsServer;
        if (!$vps) {
            throw new \RuntimeException('Site has no associated VPS server');
        }

        return $this->executeCommand($vps, 'ssl:renew', [$site->domain]);
    }

    /**
     * Get SSL certificate status for a site.
     *
     * @param Site $site
     * @return array Command result with SSL status information
     */
    public function getSSLStatus(Site $site): array
    {
        $vps = $site->vpsServer;
        if (!$vps) {
            throw new \RuntimeException('Site has no associated VPS server');
        }

        return $this->executeCommand($vps, 'ssl:status', [$site->domain]);
    }

    /**
     * Export database for a site.
     *
     * @param Site $site
     * @return array Command result
     */
    public function exportDatabase(Site $site): array
    {
        $vps = $site->vpsServer;
        if (!$vps) {
            throw new \RuntimeException('Site has no associated VPS server');
        }

        return $this->executeCommand(
            $vps,
            'database:export',
            [$site->db_name ?? $site->domain],
            self::SSH_TIMEOUT // Database exports may take longer
        );
    }

    /**
     * Optimize database for a site.
     *
     * @param Site $site
     * @return array Command result
     */
    public function optimizeDatabase(Site $site): array
    {
        $vps = $site->vpsServer;
        if (!$vps) {
            throw new \RuntimeException('Site has no associated VPS server');
        }

        return $this->executeCommand($vps, 'database:optimize', [$site->db_name ?? $site->domain]);
    }

    /**
     * Clear cache for a site.
     *
     * @param Site $site
     * @return array Command result
     */
    public function clearCache(Site $site): array
    {
        $vps = $site->vpsServer;
        if (!$vps) {
            throw new \RuntimeException('Site has no associated VPS server');
        }

        return $this->executeCommand($vps, 'cache:clear', [$site->domain]);
    }

    /**
     * Get VPS health status.
     *
     * @param VpsServer $vps
     * @return array Command result with health metrics
     */
    public function getVpsHealth(VpsServer $vps): array
    {
        return $this->executeCommand($vps, 'monitor:health', []);
    }

    /**
     * Get VPS statistics.
     *
     * @param VpsServer $vps
     * @return array Command result with system statistics
     */
    public function getVpsStats(VpsServer $vps): array
    {
        return $this->executeCommand($vps, 'monitor:stats', []);
    }

    /**
     * Build the full SSH command to execute VPSManager.
     *
     * @param VpsServer $vps
     * @param string $command
     * @param array $args
     * @return string The full SSH command
     */
    private function buildCommand(VpsServer $vps, string $command, array $args): string
    {
        // Get SSH connection details
        $sshUser = $vps->ssh_user ?? 'root';
        $sshPort = $vps->ssh_port ?? 22;
        $ipAddress = $vps->ip_address;

        // Escape all arguments
        $escapedArgs = array_map('escapeshellarg', $args);
        $argsString = implode(' ', $escapedArgs);

        // Build the VPSManager command
        $vpsManagerCommand = trim(self::VPSMANAGER_PATH . ' ' . $command . ' ' . $argsString);

        // Build the full SSH command
        $sshCommand = sprintf(
            'ssh -p %d -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=60 %s@%s %s',
            $sshPort,
            escapeshellarg($sshUser),
            escapeshellarg($ipAddress),
            escapeshellarg("sudo $vpsManagerCommand")
        );

        return $sshCommand;
    }

    /**
     * Parse command output based on command type.
     *
     * @param string $output Raw command output
     * @param string $command Command name
     * @return array Parsed structured data
     */
    public function parseCommandOutput(string $output, string $command): array
    {
        try {
            // Try to parse as JSON first (VPSManager may output JSON)
            $decoded = json_decode($output, true);
            if (json_last_error() === JSON_ERROR_NONE && is_array($decoded)) {
                return $decoded;
            }

            // Parse based on command type
            return match (true) {
                str_starts_with($command, 'ssl:') => $this->parseSSLOutput($output),
                str_starts_with($command, 'database:') => $this->parseDatabaseOutput($output),
                str_starts_with($command, 'cache:') => $this->parseCacheOutput($output),
                str_starts_with($command, 'monitor:') => $this->parseMonitorOutput($output),
                default => ['raw_output' => $output],
            };
        } catch (\Exception $e) {
            Log::warning('Failed to parse command output', [
                'command' => $command,
                'error' => $e->getMessage(),
            ]);

            return ['raw_output' => $output];
        }
    }

    /**
     * Parse SSL command output.
     *
     * @param string $output
     * @return array
     */
    private function parseSSLOutput(string $output): array
    {
        $parsed = ['raw_output' => $output];

        // Look for common SSL status patterns
        if (preg_match('/certificate.*valid.*until.*(\d{4}-\d{2}-\d{2})/i', $output, $matches)) {
            $parsed['expires_at'] = $matches[1];
        }

        if (preg_match('/status.*:.*(\w+)/i', $output, $matches)) {
            $parsed['status'] = strtolower($matches[1]);
        }

        if (str_contains(strtolower($output), 'success') || str_contains(strtolower($output), 'issued')) {
            $parsed['issued'] = true;
        }

        return $parsed;
    }

    /**
     * Parse database command output.
     *
     * @param string $output
     * @return array
     */
    private function parseDatabaseOutput(string $output): array
    {
        $parsed = ['raw_output' => $output];

        // Look for file path in export output
        if (preg_match('/exported.*to.*[\'"]?([\/\w\-\.]+\.sql)[\'"]?/i', $output, $matches)) {
            $parsed['export_path'] = $matches[1];
        }

        // Look for size information
        if (preg_match('/(\d+(?:\.\d+)?)\s*(MB|GB|KB)/i', $output, $matches)) {
            $parsed['size'] = $matches[1] . ' ' . $matches[2];
        }

        // Look for optimization results
        if (preg_match('/optimized.*(\d+).*tables?/i', $output, $matches)) {
            $parsed['tables_optimized'] = (int) $matches[1];
        }

        return $parsed;
    }

    /**
     * Parse cache command output.
     *
     * @param string $output
     * @return array
     */
    private function parseCacheOutput(string $output): array
    {
        $parsed = ['raw_output' => $output];

        if (str_contains(strtolower($output), 'cleared') || str_contains(strtolower($output), 'success')) {
            $parsed['cleared'] = true;
        }

        // Look for cache types cleared
        $cacheTypes = ['redis', 'memcached', 'opcache', 'file'];
        foreach ($cacheTypes as $type) {
            if (str_contains(strtolower($output), $type)) {
                $parsed['cache_types'][] = $type;
            }
        }

        return $parsed;
    }

    /**
     * Parse monitor command output.
     *
     * @param string $output
     * @return array
     */
    private function parseMonitorOutput(string $output): array
    {
        $parsed = ['raw_output' => $output];

        // Look for common metrics
        if (preg_match('/cpu.*:.*(\d+(?:\.\d+)?)\s*%/i', $output, $matches)) {
            $parsed['cpu_usage'] = (float) $matches[1];
        }

        if (preg_match('/memory.*:.*(\d+(?:\.\d+)?)\s*%/i', $output, $matches)) {
            $parsed['memory_usage'] = (float) $matches[1];
        }

        if (preg_match('/disk.*:.*(\d+(?:\.\d+)?)\s*%/i', $output, $matches)) {
            $parsed['disk_usage'] = (float) $matches[1];
        }

        if (preg_match('/load.*:.*(\d+\.\d+)/i', $output, $matches)) {
            $parsed['load_average'] = (float) $matches[1];
        }

        if (preg_match('/uptime.*:.*(\d+)/i', $output, $matches)) {
            $parsed['uptime_seconds'] = (int) $matches[1];
        }

        return $parsed;
    }
}
