<?php

declare(strict_types=1);

namespace App\Infrastructure\Cache;

use App\Contracts\Infrastructure\CacheInterface;
use Closure;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Redis;

/**
 * Redis Cache Adapter
 *
 * Implements caching using Redis via Laravel Cache facade.
 * Provides high-performance caching with tags support.
 *
 * Pattern: Adapter Pattern - adapts Redis to cache interface
 * Performance: In-memory caching with persistence options
 *
 * @package App\Infrastructure\Cache
 */
class RedisCacheAdapter implements CacheInterface
{
    /**
     * @var array<string>|null Active cache tags
     */
    private ?array $activeTags = null;

    public function __construct(
        private readonly string $connection = 'redis',
        private readonly ?string $prefix = null
    ) {
    }

    /**
     * {@inheritDoc}
     */
    public function get(string $key, $default = null)
    {
        $key = $this->prefixKey($key);

        if ($this->activeTags) {
            return Cache::tags($this->activeTags)->get($key, $default);
        }

        return Cache::store($this->connection)->get($key, $default);
    }

    /**
     * {@inheritDoc}
     */
    public function put(string $key, $value, ?int $ttl = null): bool
    {
        $key = $this->prefixKey($key);

        if ($this->activeTags) {
            return Cache::tags($this->activeTags)->put($key, $value, $ttl);
        }

        if ($ttl === null) {
            return Cache::store($this->connection)->forever($key, $value);
        }

        return Cache::store($this->connection)->put($key, $value, $ttl);
    }

    /**
     * {@inheritDoc}
     */
    public function forget(string $key): bool
    {
        $key = $this->prefixKey($key);

        if ($this->activeTags) {
            return Cache::tags($this->activeTags)->forget($key);
        }

        return Cache::store($this->connection)->forget($key);
    }

    /**
     * {@inheritDoc}
     */
    public function has(string $key): bool
    {
        $key = $this->prefixKey($key);

        if ($this->activeTags) {
            return Cache::tags($this->activeTags)->has($key);
        }

        return Cache::store($this->connection)->has($key);
    }

    /**
     * {@inheritDoc}
     */
    public function remember(string $key, ?int $ttl, Closure $callback)
    {
        $key = $this->prefixKey($key);

        if ($this->activeTags) {
            return Cache::tags($this->activeTags)->remember($key, $ttl, $callback);
        }

        return Cache::store($this->connection)->remember($key, $ttl, $callback);
    }

    /**
     * {@inheritDoc}
     */
    public function flush(): bool
    {
        if ($this->activeTags) {
            Cache::tags($this->activeTags)->flush();
            return true;
        }

        return Cache::store($this->connection)->flush();
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
        $key = $this->prefixKey($key);

        if ($this->activeTags) {
            return Cache::tags($this->activeTags)->increment($key, $value);
        }

        return Cache::store($this->connection)->increment($key, $value);
    }

    /**
     * {@inheritDoc}
     */
    public function decrement(string $key, int $value = 1): int
    {
        $key = $this->prefixKey($key);

        if ($this->activeTags) {
            return Cache::tags($this->activeTags)->decrement($key, $value);
        }

        return Cache::store($this->connection)->decrement($key, $value);
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
        $prefixedKeys = array_map(fn($key) => $this->prefixKey($key), $keys);

        if ($this->activeTags) {
            return Cache::tags($this->activeTags)->many($prefixedKeys);
        }

        return Cache::store($this->connection)->many($prefixedKeys);
    }

    /**
     * {@inheritDoc}
     */
    public function putMany(array $values, ?int $ttl = null): bool
    {
        $prefixedValues = [];
        foreach ($values as $key => $value) {
            $prefixedValues[$this->prefixKey($key)] = $value;
        }

        if ($this->activeTags) {
            return Cache::tags($this->activeTags)->putMany($prefixedValues, $ttl);
        }

        return Cache::store($this->connection)->putMany($prefixedValues, $ttl);
    }

    /**
     * Prefix cache key
     *
     * @param string $key
     * @return string
     */
    private function prefixKey(string $key): string
    {
        if (!$this->prefix) {
            return $key;
        }

        return $this->prefix . ':' . $key;
    }

    /**
     * Get Redis connection
     *
     * @return \Illuminate\Redis\Connections\Connection
     */
    public function getRedisConnection()
    {
        return Redis::connection($this->connection);
    }
}
