<?php

declare(strict_types=1);

namespace App\Modules\Backup\Contracts;

/**
 * Backup Storage Service Contract
 *
 * Defines the contract for backup storage operations.
 */
interface BackupStorageInterface
{
    /**
     * Store a backup file.
     *
     * @param string $path Local file path
     * @param string $destination Storage destination path
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function store(string $path, string $destination): bool;

    /**
     * Retrieve a backup file.
     *
     * @param string $path Storage path
     * @param string $destination Local destination path
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function retrieve(string $path, string $destination): bool;

    /**
     * Delete a backup file.
     *
     * @param string $path Storage path
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function delete(string $path): bool;

    /**
     * Check if backup file exists.
     *
     * @param string $path Storage path
     * @return bool Exists status
     */
    public function exists(string $path): bool;

    /**
     * Get file size.
     *
     * @param string $path Storage path
     * @return int File size in bytes
     * @throws \RuntimeException
     */
    public function getSize(string $path): int;

    /**
     * Calculate file checksum.
     *
     * @param string $path Storage path
     * @return string MD5 checksum
     * @throws \RuntimeException
     */
    public function getChecksum(string $path): string;
}
