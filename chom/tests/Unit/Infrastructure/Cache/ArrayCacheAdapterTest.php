<?php

declare(strict_types=1);

namespace Tests\Unit\Infrastructure\Cache;

use App\Infrastructure\Cache\ArrayCacheAdapter;
use PHPUnit\Framework\TestCase;

/**
 * Array Cache Adapter Tests
 *
 * Tests ArrayCacheAdapter implementation.
 *
 * @package Tests\Unit\Infrastructure\Cache
 */
class ArrayCacheAdapterTest extends TestCase
{
    private ArrayCacheAdapter $cache;

    protected function setUp(): void
    {
        parent::setUp();
        $this->cache = new ArrayCacheAdapter();
    }

    public function test_stores_and_retrieves_value(): void
    {
        $this->cache->put('key', 'value');

        $this->assertSame('value', $this->cache->get('key'));
    }

    public function test_returns_default_for_missing_key(): void
    {
        $this->assertNull($this->cache->get('missing'));
        $this->assertSame('default', $this->cache->get('missing', 'default'));
    }

    public function test_checks_key_existence(): void
    {
        $this->cache->put('exists', 'value');

        $this->assertTrue($this->cache->has('exists'));
        $this->assertFalse($this->cache->has('missing'));
    }

    public function test_forgets_key(): void
    {
        $this->cache->put('key', 'value');
        $this->cache->forget('key');

        $this->assertFalse($this->cache->has('key'));
    }

    public function test_increments_value(): void
    {
        $this->cache->put('counter', 5);

        $newValue = $this->cache->increment('counter', 3);

        $this->assertSame(8, $newValue);
        $this->assertSame(8, $this->cache->get('counter'));
    }

    public function test_decrements_value(): void
    {
        $this->cache->put('counter', 10);

        $newValue = $this->cache->decrement('counter', 3);

        $this->assertSame(7, $newValue);
        $this->assertSame(7, $this->cache->get('counter'));
    }

    public function test_remembers_value(): void
    {
        $callCount = 0;
        $callback = function () use (&$callCount) {
            $callCount++;
            return 'computed';
        };

        $value1 = $this->cache->remember('key', 60, $callback);
        $value2 = $this->cache->remember('key', 60, $callback);

        $this->assertSame('computed', $value1);
        $this->assertSame('computed', $value2);
        $this->assertSame(1, $callCount); // Callback called only once
    }

    public function test_stores_forever(): void
    {
        $this->cache->forever('permanent', 'value');

        $this->assertTrue($this->cache->has('permanent'));
        $this->assertSame('value', $this->cache->get('permanent'));
    }

    public function test_flushes_cache(): void
    {
        $this->cache->put('key1', 'value1');
        $this->cache->put('key2', 'value2');

        $this->cache->flush();

        $this->assertFalse($this->cache->has('key1'));
        $this->assertFalse($this->cache->has('key2'));
    }

    public function test_gets_multiple_values(): void
    {
        $this->cache->put('key1', 'value1');
        $this->cache->put('key2', 'value2');

        $values = $this->cache->many(['key1', 'key2', 'key3']);

        $this->assertSame('value1', $values['key1']);
        $this->assertSame('value2', $values['key2']);
        $this->assertNull($values['key3']);
    }

    public function test_puts_multiple_values(): void
    {
        $this->cache->putMany([
            'key1' => 'value1',
            'key2' => 'value2',
        ], 60);

        $this->assertSame('value1', $this->cache->get('key1'));
        $this->assertSame('value2', $this->cache->get('key2'));
    }

    public function test_supports_tags(): void
    {
        $taggedCache = $this->cache->tags(['users', 'posts']);
        $taggedCache->put('key', 'value');

        $this->assertTrue($taggedCache->has('key'));
    }

    public function test_flushes_tagged_cache(): void
    {
        $this->cache->tags(['users'])->put('user1', 'data1');
        $this->cache->tags(['posts'])->put('post1', 'data1');

        $this->cache->tags(['users'])->flush();

        $this->assertFalse($this->cache->tags(['users'])->has('user1'));
        $this->assertTrue($this->cache->tags(['posts'])->has('post1'));
    }
}
