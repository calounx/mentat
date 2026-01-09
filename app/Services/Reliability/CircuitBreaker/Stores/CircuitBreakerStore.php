<?php

declare(strict_types=1);

namespace App\Services\Reliability\CircuitBreaker\Stores;

use App\Services\Reliability\CircuitBreaker\CircuitBreakerState;
use Carbon\Carbon;

interface CircuitBreakerStore
{
    public function getState(string $name): CircuitBreakerState;

    public function setState(string $name, CircuitBreakerState $state): void;

    public function getFailureCount(string $name): int;

    public function incrementFailureCount(string $name): int;

    public function resetFailureCount(string $name): void;

    public function getSuccessCount(string $name): int;

    public function incrementSuccessCount(string $name): int;

    public function resetSuccessCount(string $name): void;

    public function getNextAttemptAt(string $name): ?Carbon;

    public function setNextAttemptAt(string $name, ?Carbon $time): void;
}
