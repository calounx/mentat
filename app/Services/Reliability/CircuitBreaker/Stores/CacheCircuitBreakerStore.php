<?php

declare(strict_types=1);

namespace App\Services\Reliability\CircuitBreaker\Stores;

use App\Services\Reliability\CircuitBreaker\CircuitBreakerState;
use Carbon\Carbon;
use Illuminate\Support\Facades\Cache;

class CacheCircuitBreakerStore implements CircuitBreakerStore
{
    private const TTL = 3600; // 1 hour

    private function key(string $name, string $suffix): string
    {
        return "circuit_breaker:{$name}:{$suffix}";
    }

    public function getState(string $name): CircuitBreakerState
    {
        $state = Cache::get($this->key($name, 'state'), 'closed');
        return CircuitBreakerState::from($state);
    }

    public function setState(string $name, CircuitBreakerState $state): void
    {
        Cache::put($this->key($name, 'state'), $state->value, self::TTL);
        Cache::put($this->key($name, 'state_changed_at'), now()->toIso8601String(), self::TTL);
    }

    public function getFailureCount(string $name): int
    {
        return (int) Cache::get($this->key($name, 'failure_count'), 0);
    }

    public function incrementFailureCount(string $name): int
    {
        $key = $this->key($name, 'failure_count');
        $count = $this->getFailureCount($name) + 1;
        Cache::put($key, $count, self::TTL);
        Cache::put($this->key($name, 'last_failure_at'), now()->toIso8601String(), self::TTL);
        return $count;
    }

    public function resetFailureCount(string $name): void
    {
        Cache::forget($this->key($name, 'failure_count'));
    }

    public function getSuccessCount(string $name): int
    {
        return (int) Cache::get($this->key($name, 'success_count'), 0);
    }

    public function incrementSuccessCount(string $name): int
    {
        $key = $this->key($name, 'success_count');
        $count = $this->getSuccessCount($name) + 1;
        Cache::put($key, $count, self::TTL);
        return $count;
    }

    public function resetSuccessCount(string $name): void
    {
        Cache::forget($this->key($name, 'success_count'));
    }

    public function getNextAttemptAt(string $name): ?Carbon
    {
        $timestamp = Cache::get($this->key($name, 'next_attempt_at'));
        return $timestamp ? Carbon::parse($timestamp) : null;
    }

    public function setNextAttemptAt(string $name, ?Carbon $time): void
    {
        if ($time) {
            Cache::put($this->key($name, 'next_attempt_at'), $time->toIso8601String(), self::TTL);
        } else {
            Cache::forget($this->key($name, 'next_attempt_at'));
        }
    }
}
