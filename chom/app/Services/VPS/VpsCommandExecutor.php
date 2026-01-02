<?php

namespace App\Services\VPS;

use App\Models\VpsServer;
use Illuminate\Support\Facades\Log;

/**
 * VPS Command Executor.
 *
 * Executes VPSManager commands on VPS servers.
 * Follows Single Responsibility Principle - only handles command execution.
 */
class VpsCommandExecutor
{
    private string $vpsmanagerPath = '/opt/vpsmanager/bin/vpsmanager';

    /**
     * Allowed commands for raw execution with strict whitelist.
     * Only these commands can be executed directly via SSH.
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

    public function __construct(
        private VpsConnectionManager $connectionManager
    ) {}

    /**
     * Execute a VPSManager command on the remote VPS.
     *
     * @param  VpsServer  $vps  The VPS server
     * @param  string  $command  The VPSManager command (e.g., 'site:create')
     * @param  array  $args  Command arguments
     * @return array Result with 'success', 'exit_code', 'output', and optional 'data'
     *
     * @throws \RuntimeException If execution fails
     */
    public function execute(VpsServer $vps, string $command, array $args = []): array
    {
        $this->connectionManager->connect($vps);

        // Build command with arguments
        $fullCommand = $this->buildCommand($command, $args);

        Log::info('VPSManager command', [
            'vps' => $vps->hostname,
            'command' => $command,
            'full_command' => $fullCommand,
        ]);

        $ssh = $this->connectionManager->getConnection();
        if (! $ssh) {
            throw new \RuntimeException('No active SSH connection');
        }

        $output = $ssh->exec($fullCommand);
        $exitCode = $ssh->getExitStatus() ?? 0;

        $this->connectionManager->disconnect();

        $result = [
            'success' => $exitCode === 0,
            'exit_code' => $exitCode,
            'output' => $output,
            'data' => null,
        ];

        // Try to parse JSON output
        if (! empty($output)) {
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
     * Execute a whitelisted SSH command.
     * Only allows commands from the strict whitelist for security.
     *
     * @param  VpsServer  $vps  The VPS server
     * @param  string  $command  The command to execute
     * @return array Result with 'success', 'exit_code', 'output'
     *
     * @throws \InvalidArgumentException If command is not in the whitelist
     */
    public function executeRaw(VpsServer $vps, string $command): array
    {
        // Strict command whitelist validation
        $normalizedCommand = trim($command);

        if (! $this->validateCommand($normalizedCommand)) {
            Log::warning('Blocked unauthorized raw SSH command attempt', [
                'vps' => $vps->hostname,
                'command' => $command,
            ]);

            throw new \InvalidArgumentException(
                'Command not allowed. Only whitelisted commands are permitted for raw execution.'
            );
        }

        $this->connectionManager->connect($vps);

        Log::info('Raw SSH command (whitelisted)', [
            'vps' => $vps->hostname,
            'command' => $normalizedCommand,
        ]);

        $ssh = $this->connectionManager->getConnection();
        if (! $ssh) {
            throw new \RuntimeException('No active SSH connection');
        }

        $output = $ssh->exec($normalizedCommand.' 2>&1');
        $exitCode = $ssh->getExitStatus() ?? 0;

        $this->connectionManager->disconnect();

        return [
            'success' => $exitCode === 0,
            'exit_code' => $exitCode,
            'output' => $output,
        ];
    }

    /**
     * Validate if a command is allowed for raw execution.
     */
    public function validateCommand(string $command): bool
    {
        return in_array($command, self::ALLOWED_RAW_COMMANDS, true);
    }

    /**
     * Get list of allowed raw commands.
     */
    public function getAllowedCommands(): array
    {
        return self::ALLOWED_RAW_COMMANDS;
    }

    /**
     * Build full command string with arguments.
     */
    private function buildCommand(string $command, array $args): string
    {
        $fullCommand = $this->vpsmanagerPath.' '.$command;

        foreach ($args as $key => $value) {
            if (is_bool($value)) {
                if ($value) {
                    $fullCommand .= " --{$key}";
                }
            } elseif (is_numeric($key)) {
                // Positional argument
                $fullCommand .= ' '.escapeshellarg($value);
            } else {
                $fullCommand .= " --{$key}=".escapeshellarg($value);
            }
        }

        // Always request JSON output
        $fullCommand .= ' --format=json 2>&1';

        return $fullCommand;
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
     * Set the VPSManager binary path.
     */
    public function setVpsManagerPath(string $path): void
    {
        $this->vpsmanagerPath = $path;
    }

    /**
     * Get the VPSManager binary path.
     */
    public function getVpsManagerPath(): string
    {
        return $this->vpsmanagerPath;
    }
}
