<?php

declare(strict_types=1);

namespace App\Contracts\Infrastructure;

use App\ValueObjects\CommandResult;
use App\ValueObjects\ServerStatus;
use App\ValueObjects\VpsSpecification;

/**
 * VPS Provider Interface
 *
 * Defines the contract for VPS provider operations.
 * Implementations provide abstraction over different VPS providers
 * (DigitalOcean, Vultr, AWS, Local, etc.)
 *
 * Design Pattern: Strategy Pattern - different providers implement the same interface
 * SOLID Principle: Interface Segregation - focused interface for VPS operations
 *
 * @package App\Contracts\Infrastructure
 */
interface VpsProviderInterface
{
    /**
     * Create a new VPS server with the given specification
     *
     * @param VpsSpecification $spec Server specification
     * @return array<string, mixed> Server details including 'id', 'ip_address', 'status'
     * @throws \RuntimeException If server creation fails
     */
    public function createServer(VpsSpecification $spec): array;

    /**
     * Delete a VPS server
     *
     * @param string $serverId Server identifier
     * @return bool True if deletion was successful
     * @throws \RuntimeException If server deletion fails
     */
    public function deleteServer(string $serverId): bool;

    /**
     * Get the current status of a VPS server
     *
     * @param string $serverId Server identifier
     * @return ServerStatus Server status object
     * @throws \RuntimeException If status check fails
     */
    public function getServerStatus(string $serverId): ServerStatus;

    /**
     * Execute a command on the VPS server
     *
     * @param string $serverId Server identifier
     * @param string $command Command to execute
     * @param int $timeout Command timeout in seconds
     * @return CommandResult Command execution result
     * @throws \RuntimeException If command execution fails
     */
    public function executeCommand(string $serverId, string $command, int $timeout = 300): CommandResult;

    /**
     * Upload a file to the VPS server
     *
     * @param string $serverId Server identifier
     * @param string $localPath Local file path
     * @param string $remotePath Remote destination path
     * @return bool True if upload was successful
     * @throws \RuntimeException If file upload fails
     */
    public function uploadFile(string $serverId, string $localPath, string $remotePath): bool;

    /**
     * Download a file from the VPS server
     *
     * @param string $serverId Server identifier
     * @param string $remotePath Remote file path
     * @param string $localPath Local destination path
     * @return bool True if download was successful
     * @throws \RuntimeException If file download fails
     */
    public function downloadFile(string $serverId, string $remotePath, string $localPath): bool;

    /**
     * Check if the VPS server is reachable
     *
     * @param string $serverId Server identifier
     * @return bool True if server is reachable
     */
    public function isServerReachable(string $serverId): bool;

    /**
     * Get server metrics (CPU, RAM, disk, network)
     *
     * @param string $serverId Server identifier
     * @return array<string, mixed> Server metrics
     * @throws \RuntimeException If metrics retrieval fails
     */
    public function getServerMetrics(string $serverId): array;

    /**
     * Restart the VPS server
     *
     * @param string $serverId Server identifier
     * @return bool True if restart was successful
     * @throws \RuntimeException If server restart fails
     */
    public function restartServer(string $serverId): bool;

    /**
     * Get provider name
     *
     * @return string Provider identifier (e.g., 'digitalocean', 'vultr', 'local')
     */
    public function getProviderName(): string;
}
