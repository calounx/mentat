<?php

declare(strict_types=1);

namespace App\Contracts\Infrastructure;

use DateTimeInterface;

/**
 * Storage Interface
 *
 * Defines the contract for file storage operations.
 * Provides abstraction over storage backends (Local, S3, DigitalOcean Spaces, etc.)
 *
 * Design Pattern: Adapter Pattern - adapts different storage providers
 * SOLID Principle: Open/Closed - open for extension, closed for modification
 *
 * @package App\Contracts\Infrastructure
 */
interface StorageInterface
{
    /**
     * Store a file or content
     *
     * @param string $path Storage path
     * @param string|resource $contents File contents or stream
     * @param array<string, mixed> $options Storage options (e.g., visibility, metadata)
     * @return bool True if storage was successful
     * @throws \RuntimeException If storage fails
     */
    public function store(string $path, $contents, array $options = []): bool;

    /**
     * Get file contents
     *
     * @param string $path Storage path
     * @return string|null File contents or null if not found
     * @throws \RuntimeException If retrieval fails
     */
    public function get(string $path): ?string;

    /**
     * Check if file exists
     *
     * @param string $path Storage path
     * @return bool True if file exists
     */
    public function exists(string $path): bool;

    /**
     * Delete a file
     *
     * @param string $path Storage path
     * @return bool True if deletion was successful
     * @throws \RuntimeException If deletion fails
     */
    public function delete(string $path): bool;

    /**
     * Get file size in bytes
     *
     * @param string $path Storage path
     * @return int File size in bytes
     * @throws \RuntimeException If file not found or size retrieval fails
     */
    public function size(string $path): int;

    /**
     * Get public URL for a file
     *
     * @param string $path Storage path
     * @return string Public URL
     * @throws \RuntimeException If URL generation fails
     */
    public function url(string $path): string;

    /**
     * Get temporary URL for a file
     *
     * @param string $path Storage path
     * @param DateTimeInterface $expiration URL expiration time
     * @return string Temporary URL
     * @throws \RuntimeException If URL generation fails
     */
    public function temporaryUrl(string $path, DateTimeInterface $expiration): string;

    /**
     * Copy a file
     *
     * @param string $from Source path
     * @param string $to Destination path
     * @return bool True if copy was successful
     * @throws \RuntimeException If copy fails
     */
    public function copy(string $from, string $to): bool;

    /**
     * Move a file
     *
     * @param string $from Source path
     * @param string $to Destination path
     * @return bool True if move was successful
     * @throws \RuntimeException If move fails
     */
    public function move(string $from, string $to): bool;

    /**
     * List files in a directory
     *
     * @param string $directory Directory path
     * @param bool $recursive List recursively
     * @return array<string> List of file paths
     * @throws \RuntimeException If listing fails
     */
    public function listFiles(string $directory, bool $recursive = false): array;

    /**
     * Get file metadata
     *
     * @param string $path Storage path
     * @return array<string, mixed> File metadata (size, type, modified, etc.)
     * @throws \RuntimeException If metadata retrieval fails
     */
    public function getMetadata(string $path): array;
}
