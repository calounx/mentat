<?php

declare(strict_types=1);

namespace App\Infrastructure\Cache;

use App\Contracts\Infrastructure\CacheInterface;
use Closure;

/**
 * Array Cache Adapter
 *
 * Implements in-memory caching using PHP arrays.
 * Useful for testing and single-request caching.
 *
 * Pattern: Adapter Pattern - adapts array storage to cache interface
 * Use Case: Testing, development, single-request caching
 *
 * @package App\Infrastructure\Cache
 */
class ArrayCacheAdapter implements CacheInterface
{
    /**
     * @var array<string, array{value: mixed, expires_at: int|null}> Cache storage
     */
    private array $cache = [];

    /**
     * @var array<string>|null Active cache tags
     */
    private ?array $activeTags = null;

    /**
     * {@inheritDoc}
     */
    public function get(string $key, $default = null)
    {
        if (!$this->has($key)) {
            return $default;
        }

        return $this->cache[$key]['value'];
    }

    /**
     * {@inheritDoc}
     */
    public function put(string $key, $value, ?int $ttl = null): bool
    {
        $expiresAt = $ttl !== null ? time() + $ttl : null;

        $this->cache[$key] = [
            'value' => $value,
            'expires_at' => $expiresAt,
            'tags' => $this->activeTags ?? [],
        ];

        return true;
    }

    /**
     * {@inheritDoc}
     */
    public function forget(string $key): bool
    {
        unset($this->cache[$key]);
        return true;
    }

    /**
     * {@inheritDoc}
     */
    public function has(string $key): bool
    {
        if (!isset($this->cache[$key])) {
            return false;
        }

        $item = $this->cache[$key];

        // Check if expired
        if ($item['expires_at'] !== null && $item['expires_at'] < time()) {
            unset($this->cache[$key]);
            return false;
        }

        // Check tags if active
        if ($this->activeTags !== null) {
            $itemTags = $item['tags'] ?? [];
            if (empty(array_intersect($this->activeTags, $itemTags))) {
                return false;
            }
        }

        return true;
    }

    /**
     * {@inheritDoc}
     */
    public function remember(string $key, ?int $ttl, Closure $callback)
    {
        if ($this->has($key)) {
            return $this->get($key);
        }

        $value = $callback();
        $this->put($key, $value, $ttl);

        return $value;
    }

    /**
     * {@inheritDoc}
     */
    public function flush(): bool
    {
        if ($this->activeTags !== null) {
            // Flush only items with matching tags
            foreach ($this->cache as $key => $item) {
                $itemTags = $item['tags'] ?? [];
                if (!empty(array_intersect($this->activeTags, $itemTags))) {
                    unset($this->cache[$key]);
                }
            }
        } else {
            $this->cache = [];
        }

        return true;
    }

    /**
     * {@inheritDoc}
     */
    public function tags(array $tags): self
    {
        $instance = clone $this;
        $instance->activeTags = $tags;
        return $instance;
    }

    /**
     * {@inheritDoc}
     */
    public function increment(string $key, int $value = 1): int
    {
        $current = $this->get($key, 0);
        $newValue = (int) $current + $value;
        $this->put($key, $newValue);

        return $newValue;
    }

    /**
     * {@inheritDoc}
     */
    public function decrement(string $key, int $value = 1): int
    {
        $current = $this->get($key, 0);
        $newValue = (int) $current - $value;
        $this->put($key, $newValue);

        return $newValue;
    }

    /**
     * {@inheritDoc}
     */
    public function forever(string $key, $value): bool
    {
        return $this->put($key, $value, null);
    }

    /**
     * {@inheritDoc}
     */
    public function many(array $keys): array
    {
        $result = [];

        foreach ($keys as $key) {
            $result[$key] = $this->get($key);
        }

        return $result;
    }

    /**
     * {@inheritDoc}
     */
    public function putMany(array $values, ?int $ttl = null): bool
    {
        foreach ($values as $key => $value) {
            $this->put($key, $value, $ttl);
        }

        return true;
    }

    /**
     * Get all cached items (for testing)
     *
     * @return array<string, mixed>
     */
    public function all(): array
    {
        $result = [];

        foreach ($this->cache as $key => $item) {
            if ($this->has($key)) {
                $result[$key] = $item['value'];
            }
        }

        return $result;
    }
}
