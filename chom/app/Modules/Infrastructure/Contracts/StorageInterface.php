<?php

declare(strict_types=1);

namespace App\Modules\Infrastructure\Contracts;

/**
 * Storage Service Contract
 *
 * Defines the contract for file storage operations.
 */
interface StorageInterface
{
    /**
     * Store a file.
     *
     * @param string $path File path
     * @param string $contents File contents
     * @param array $options Storage options
     * @return bool Success status
     */
    public function put(string $path, string $contents, array $options = []): bool;

    /**
     * Retrieve a file.
     *
     * @param string $path File path
     * @return string|null File contents
     */
    public function get(string $path): ?string;

    /**
     * Check if file exists.
     *
     * @param string $path File path
     * @return bool Exists status
     */
    public function exists(string $path): bool;

    /**
     * Delete a file.
     *
     * @param string $path File path
     * @return bool Success status
     */
    public function delete(string $path): bool;

    /**
     * Get file size.
     *
     * @param string $path File path
     * @return int File size in bytes
     */
    public function size(string $path): int;

    /**
     * Get file last modified time.
     *
     * @param string $path File path
     * @return int Unix timestamp
     */
    public function lastModified(string $path): int;

    /**
     * List files in directory.
     *
     * @param string $directory Directory path
     * @return array List of files
     */
    public function listFiles(string $directory): array;

    /**
     * Get public URL for file.
     *
     * @param string $path File path
     * @return string Public URL
     */
    public function url(string $path): string;

    /**
     * Generate temporary URL for file.
     *
     * @param string $path File path
     * @param int $expirationSeconds Expiration time in seconds
     * @return string Temporary URL
     */
    public function temporaryUrl(string $path, int $expirationSeconds): string;
}
