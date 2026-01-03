<?php

declare(strict_types=1);

namespace App\Infrastructure\Storage;

use App\Contracts\Infrastructure\StorageInterface;
use DateTimeInterface;
use Illuminate\Support\Facades\Storage;
use RuntimeException;

/**
 * Local Storage Adapter
 *
 * Implements storage using local filesystem via Laravel Storage facade.
 * Suitable for local development and single-server deployments.
 *
 * Pattern: Adapter Pattern - adapts Laravel Storage to storage interface
 *
 * @package App\Infrastructure\Storage
 */
class LocalStorageAdapter implements StorageInterface
{
    public function __construct(
        private readonly string $disk = 'local',
        private readonly string $visibility = 'private'
    ) {
    }

    /**
     * {@inheritDoc}
     */
    public function store(string $path, $contents, array $options = []): bool
    {
        $visibility = $options['visibility'] ?? $this->visibility;

        if (is_resource($contents)) {
            return Storage::disk($this->disk)->putStream($path, $contents, $visibility);
        }

        return Storage::disk($this->disk)->put($path, $contents, $visibility);
    }

    /**
     * {@inheritDoc}
     */
    public function get(string $path): ?string
    {
        if (!$this->exists($path)) {
            return null;
        }

        return Storage::disk($this->disk)->get($path);
    }

    /**
     * {@inheritDoc}
     */
    public function exists(string $path): bool
    {
        return Storage::disk($this->disk)->exists($path);
    }

    /**
     * {@inheritDoc}
     */
    public function delete(string $path): bool
    {
        return Storage::disk($this->disk)->delete($path);
    }

    /**
     * {@inheritDoc}
     */
    public function size(string $path): int
    {
        if (!$this->exists($path)) {
            throw new RuntimeException("File not found: {$path}");
        }

        return Storage::disk($this->disk)->size($path);
    }

    /**
     * {@inheritDoc}
     */
    public function url(string $path): string
    {
        return Storage::disk($this->disk)->url($path);
    }

    /**
     * {@inheritDoc}
     */
    public function temporaryUrl(string $path, DateTimeInterface $expiration): string
    {
        return Storage::disk($this->disk)->temporaryUrl($path, $expiration);
    }

    /**
     * {@inheritDoc}
     */
    public function copy(string $from, string $to): bool
    {
        return Storage::disk($this->disk)->copy($from, $to);
    }

    /**
     * {@inheritDoc}
     */
    public function move(string $from, string $to): bool
    {
        return Storage::disk($this->disk)->move($from, $to);
    }

    /**
     * {@inheritDoc}
     */
    public function listFiles(string $directory, bool $recursive = false): array
    {
        if ($recursive) {
            return Storage::disk($this->disk)->allFiles($directory);
        }

        return Storage::disk($this->disk)->files($directory);
    }

    /**
     * {@inheritDoc}
     */
    public function getMetadata(string $path): array
    {
        if (!$this->exists($path)) {
            throw new RuntimeException("File not found: {$path}");
        }

        return [
            'size' => $this->size($path),
            'type' => Storage::disk($this->disk)->mimeType($path),
            'last_modified' => Storage::disk($this->disk)->lastModified($path),
            'visibility' => Storage::disk($this->disk)->getVisibility($path),
            'path' => $path,
        ];
    }
}
