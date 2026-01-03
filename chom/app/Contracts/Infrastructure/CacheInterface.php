<?php

declare(strict_types=1);

namespace App\Contracts\Infrastructure;

use Closure;

/**
 * Cache Interface
 *
 * Defines the contract for caching operations.
 * Provides abstraction over cache backends (Redis, Memcached, Array, File, etc.)
 *
 * Design Pattern: Proxy Pattern - provides caching layer
 * SOLID Principle: Liskov Substitution - implementations are interchangeable
 *
 * @package App\Contracts\Infrastructure
 */
interface CacheInterface
{
    /**
     * Get an item from the cache
     *
     * @param string $key Cache key
     * @param mixed $default Default value if key not found
     * @return mixed Cached value or default
     */
    public function get(string $key, $default = null);

    /**
     * Store an item in the cache
     *
     * @param string $key Cache key
     * @param mixed $value Value to cache
     * @param int|null $ttl Time to live in seconds (null = forever)
     * @return bool True if storage was successful
     */
    public function put(string $key, $value, ?int $ttl = null): bool;

    /**
     * Remove an item from the cache
     *
     * @param string $key Cache key
     * @return bool True if removal was successful
     */
    public function forget(string $key): bool;

    /**
     * Check if an item exists in the cache
     *
     * @param string $key Cache key
     * @return bool True if key exists
     */
    public function has(string $key): bool;

    /**
     * Get an item or store the result of a callback
     *
     * @param string $key Cache key
     * @param int|null $ttl Time to live in seconds
     * @param Closure $callback Callback to execute if key not found
     * @return mixed Cached or computed value
     */
    public function remember(string $key, ?int $ttl, Closure $callback);

    /**
     * Clear all items from the cache
     *
     * @return bool True if flush was successful
     */
    public function flush(): bool;

    /**
     * Get cache with tags support
     *
     * @param array<string> $tags Cache tags
     * @return self Cache instance scoped to tags
     */
    public function tags(array $tags): self;

    /**
     * Increment a numeric value
     *
     * @param string $key Cache key
     * @param int $value Increment amount
     * @return int New value
     */
    public function increment(string $key, int $value = 1): int;

    /**
     * Decrement a numeric value
     *
     * @param string $key Cache key
     * @param int $value Decrement amount
     * @return int New value
     */
    public function decrement(string $key, int $value = 1): int;

    /**
     * Store an item in the cache indefinitely
     *
     * @param string $key Cache key
     * @param mixed $value Value to cache
     * @return bool True if storage was successful
     */
    public function forever(string $key, $value): bool;

    /**
     * Get multiple items from the cache
     *
     * @param array<string> $keys Cache keys
     * @return array<string, mixed> Key-value pairs
     */
    public function many(array $keys): array;

    /**
     * Store multiple items in the cache
     *
     * @param array<string, mixed> $values Key-value pairs
     * @param int|null $ttl Time to live in seconds
     * @return bool True if storage was successful
     */
    public function putMany(array $values, ?int $ttl = null): bool;
}
