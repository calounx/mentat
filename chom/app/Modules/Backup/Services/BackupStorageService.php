<?php

declare(strict_types=1);

namespace App\Modules\Backup\Services;

use App\Modules\Backup\Contracts\BackupStorageInterface;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

/**
 * Backup Storage Service
 *
 * Handles backup file storage operations using Laravel Storage.
 */
class BackupStorageService implements BackupStorageInterface
{
    private const DISK = 'backups';

    /**
     * Store a backup file.
     *
     * @param string $path Local file path
     * @param string $destination Storage destination path
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function store(string $path, string $destination): bool
    {
        try {
            if (!file_exists($path)) {
                throw new \RuntimeException("Source file not found: {$path}");
            }

            $contents = file_get_contents($path);

            if ($contents === false) {
                throw new \RuntimeException("Failed to read source file: {$path}");
            }

            $result = Storage::disk(self::DISK)->put($destination, $contents);

            if (!$result) {
                throw new \RuntimeException("Failed to store backup to: {$destination}");
            }

            Log::info('Backup stored successfully', [
                'source' => $path,
                'destination' => $destination,
                'size' => filesize($path),
            ]);

            return true;
        } catch (\Exception $e) {
            Log::error('Backup storage failed', [
                'source' => $path,
                'destination' => $destination,
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to store backup: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Retrieve a backup file.
     *
     * @param string $path Storage path
     * @param string $destination Local destination path
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function retrieve(string $path, string $destination): bool
    {
        try {
            if (!$this->exists($path)) {
                throw new \RuntimeException("Backup file not found: {$path}");
            }

            $contents = Storage::disk(self::DISK)->get($path);

            if ($contents === null) {
                throw new \RuntimeException("Failed to retrieve backup: {$path}");
            }

            $result = file_put_contents($destination, $contents);

            if ($result === false) {
                throw new \RuntimeException("Failed to write to destination: {$destination}");
            }

            Log::info('Backup retrieved successfully', [
                'source' => $path,
                'destination' => $destination,
                'size' => $result,
            ]);

            return true;
        } catch (\Exception $e) {
            Log::error('Backup retrieval failed', [
                'source' => $path,
                'destination' => $destination,
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to retrieve backup: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Delete a backup file.
     *
     * @param string $path Storage path
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function delete(string $path): bool
    {
        try {
            if (!$this->exists($path)) {
                Log::warning('Attempted to delete non-existent backup', [
                    'path' => $path,
                ]);
                return true;
            }

            $result = Storage::disk(self::DISK)->delete($path);

            if (!$result) {
                throw new \RuntimeException("Failed to delete backup: {$path}");
            }

            Log::info('Backup deleted successfully', [
                'path' => $path,
            ]);

            return true;
        } catch (\Exception $e) {
            Log::error('Backup deletion failed', [
                'path' => $path,
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to delete backup: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Check if backup file exists.
     *
     * @param string $path Storage path
     * @return bool Exists status
     */
    public function exists(string $path): bool
    {
        try {
            return Storage::disk(self::DISK)->exists($path);
        } catch (\Exception $e) {
            Log::error('Backup existence check failed', [
                'path' => $path,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Get file size.
     *
     * @param string $path Storage path
     * @return int File size in bytes
     * @throws \RuntimeException
     */
    public function getSize(string $path): int
    {
        try {
            if (!$this->exists($path)) {
                throw new \RuntimeException("Backup file not found: {$path}");
            }

            return Storage::disk(self::DISK)->size($path);
        } catch (\Exception $e) {
            Log::error('Failed to get backup size', [
                'path' => $path,
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to get backup size: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Calculate file checksum.
     *
     * @param string $path Storage path
     * @return string MD5 checksum
     * @throws \RuntimeException
     */
    public function getChecksum(string $path): string
    {
        try {
            if (!$this->exists($path)) {
                throw new \RuntimeException("Backup file not found: {$path}");
            }

            $fullPath = Storage::disk(self::DISK)->path($path);

            if (!file_exists($fullPath)) {
                throw new \RuntimeException("Physical file not found: {$fullPath}");
            }

            $checksum = md5_file($fullPath);

            if ($checksum === false) {
                throw new \RuntimeException("Failed to calculate checksum for: {$path}");
            }

            return $checksum;
        } catch (\Exception $e) {
            Log::error('Failed to calculate backup checksum', [
                'path' => $path,
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to calculate checksum: ' . $e->getMessage(), 0, $e);
        }
    }
}
