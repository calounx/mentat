<?php

declare(strict_types=1);

namespace App\Services\Reliability\CircuitBreaker;

enum CircuitBreakerState: string
{
    case CLOSED = 'closed';
    case OPEN = 'open';
    case HALF_OPEN = 'half_open';

    public function isClosed(): bool
    {
        return $this === self::CLOSED;
    }

    public function isOpen(): bool
    {
        return $this === self::OPEN;
    }

    public function isHalfOpen(): bool
    {
        return $this === self::HALF_OPEN;
    }
}
