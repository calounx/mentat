<?php

declare(strict_types=1);

namespace App\Modules\Infrastructure\Services;

use App\Modules\Infrastructure\Contracts\StorageInterface;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage as LaravelStorage;

/**
 * Storage Service
 *
 * Handles file storage operations with abstraction layer.
 */
class StorageService implements StorageInterface
{
    private const DEFAULT_DISK = 'local';

    private string $disk;

    public function __construct(?string $disk = null)
    {
        $this->disk = $disk ?? self::DEFAULT_DISK;
    }

    /**
     * Store a file.
     *
     * @param string $path File path
     * @param string $contents File contents
     * @param array $options Storage options
     * @return bool Success status
     */
    public function put(string $path, string $contents, array $options = []): bool
    {
        try {
            $result = LaravelStorage::disk($this->disk)->put($path, $contents, $options);

            Log::debug('File stored', [
                'path' => $path,
                'size' => strlen($contents),
            ]);

            return $result;
        } catch (\Exception $e) {
            Log::error('Failed to store file', [
                'path' => $path,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Retrieve a file.
     *
     * @param string $path File path
     * @return string|null File contents
     */
    public function get(string $path): ?string
    {
        try {
            return LaravelStorage::disk($this->disk)->get($path);
        } catch (\Exception $e) {
            Log::error('Failed to retrieve file', [
                'path' => $path,
                'error' => $e->getMessage(),
            ]);

            return null;
        }
    }

    /**
     * Check if file exists.
     *
     * @param string $path File path
     * @return bool Exists status
     */
    public function exists(string $path): bool
    {
        try {
            return LaravelStorage::disk($this->disk)->exists($path);
        } catch (\Exception $e) {
            Log::error('Failed to check file existence', [
                'path' => $path,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Delete a file.
     *
     * @param string $path File path
     * @return bool Success status
     */
    public function delete(string $path): bool
    {
        try {
            $result = LaravelStorage::disk($this->disk)->delete($path);

            Log::debug('File deleted', [
                'path' => $path,
            ]);

            return $result;
        } catch (\Exception $e) {
            Log::error('Failed to delete file', [
                'path' => $path,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Get file size.
     *
     * @param string $path File path
     * @return int File size in bytes
     */
    public function size(string $path): int
    {
        try {
            return LaravelStorage::disk($this->disk)->size($path);
        } catch (\Exception $e) {
            Log::error('Failed to get file size', [
                'path' => $path,
                'error' => $e->getMessage(),
            ]);

            return 0;
        }
    }

    /**
     * Get file last modified time.
     *
     * @param string $path File path
     * @return int Unix timestamp
     */
    public function lastModified(string $path): int
    {
        try {
            return LaravelStorage::disk($this->disk)->lastModified($path);
        } catch (\Exception $e) {
            Log::error('Failed to get last modified time', [
                'path' => $path,
                'error' => $e->getMessage(),
            ]);

            return 0;
        }
    }

    /**
     * List files in directory.
     *
     * @param string $directory Directory path
     * @return array List of files
     */
    public function listFiles(string $directory): array
    {
        try {
            return LaravelStorage::disk($this->disk)->files($directory);
        } catch (\Exception $e) {
            Log::error('Failed to list files', [
                'directory' => $directory,
                'error' => $e->getMessage(),
            ]);

            return [];
        }
    }

    /**
     * Get public URL for file.
     *
     * @param string $path File path
     * @return string Public URL
     */
    public function url(string $path): string
    {
        try {
            return LaravelStorage::disk($this->disk)->url($path);
        } catch (\Exception $e) {
            Log::error('Failed to generate URL', [
                'path' => $path,
                'error' => $e->getMessage(),
            ]);

            return '';
        }
    }

    /**
     * Generate temporary URL for file.
     *
     * @param string $path File path
     * @param int $expirationSeconds Expiration time in seconds
     * @return string Temporary URL
     */
    public function temporaryUrl(string $path, int $expirationSeconds): string
    {
        try {
            return LaravelStorage::disk($this->disk)->temporaryUrl(
                $path,
                now()->addSeconds($expirationSeconds)
            );
        } catch (\Exception $e) {
            Log::error('Failed to generate temporary URL', [
                'path' => $path,
                'error' => $e->getMessage(),
            ]);

            return '';
        }
    }
}
