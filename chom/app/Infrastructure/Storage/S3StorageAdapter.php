<?php

declare(strict_types=1);

namespace App\Infrastructure\Storage;

use App\Contracts\Infrastructure\StorageInterface;
use DateTimeInterface;
use Illuminate\Support\Facades\Storage;
use RuntimeException;

/**
 * S3 Storage Adapter
 *
 * Implements storage using AWS S3 via Laravel Storage facade.
 * Suitable for cloud deployments with scalability requirements.
 *
 * Pattern: Adapter Pattern - adapts AWS S3 to storage interface
 * Integration: Works with any S3-compatible storage (AWS, MinIO, Wasabi, etc.)
 *
 * @package App\Infrastructure\Storage
 */
class S3StorageAdapter implements StorageInterface
{
    public function __construct(
        private readonly string $disk = 's3',
        private readonly string $visibility = 'private',
        private readonly ?string $region = null,
        private readonly ?string $bucket = null
    ) {
    }

    /**
     * {@inheritDoc}
     */
    public function store(string $path, $contents, array $options = []): bool
    {
        $visibility = $options['visibility'] ?? $this->visibility;
        $metadata = $options['metadata'] ?? [];

        $putOptions = [
            'visibility' => $visibility,
        ];

        if (!empty($metadata)) {
            $putOptions['Metadata'] = $metadata;
        }

        if (is_resource($contents)) {
            return Storage::disk($this->disk)->putStream($path, $contents, $putOptions);
        }

        return Storage::disk($this->disk)->put($path, $contents, $putOptions);
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
            'bucket' => $this->bucket,
            'region' => $this->region,
        ];
    }

    /**
     * Get S3 object URL with CloudFront support
     *
     * @param string $path
     * @param string|null $cloudFrontDomain
     * @return string
     */
    public function getCloudFrontUrl(string $path, ?string $cloudFrontDomain = null): string
    {
        if (!$cloudFrontDomain) {
            return $this->url($path);
        }

        return 'https://' . $cloudFrontDomain . '/' . ltrim($path, '/');
    }
}
