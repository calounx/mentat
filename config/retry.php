<?php

return [
    /*
    |--------------------------------------------------------------------------
    | Retry Configuration
    |--------------------------------------------------------------------------
    |
    | Configure retry policies for operations that may experience transient
    | failures. Uses exponential backoff with optional jitter to prevent
    | thundering herd problems.
    |
    */

    'default_max_attempts' => env('RETRY_MAX_ATTEMPTS', 3),
    'default_initial_delay_ms' => env('RETRY_INITIAL_DELAY_MS', 100),
    'default_max_delay_ms' => env('RETRY_MAX_DELAY_MS', 10000),
    'default_multiplier' => env('RETRY_MULTIPLIER', 2.0),
    'default_use_jitter' => env('RETRY_USE_JITTER', true),

    /*
    |--------------------------------------------------------------------------
    | Service-Specific Retry Policies
    |--------------------------------------------------------------------------
    |
    | Configure individual retry policies for each service or operation type.
    | Transient failures are common in distributed systems, so aggressive
    | retries are appropriate for most services.
    |
    */

    'policies' => [
        'prometheus' => [
            'enabled' => env('RETRY_PROMETHEUS_ENABLED', true),
            'max_attempts' => 3,
            'initial_delay_ms' => 100,
            'max_delay_ms' => 2000,
            'multiplier' => 2.0,
            'use_jitter' => true,
            'retryable_exceptions' => [
                \Illuminate\Http\Client\ConnectionException::class,
                \Illuminate\Http\Client\RequestException::class,
            ],
        ],

        'grafana' => [
            'enabled' => env('RETRY_GRAFANA_ENABLED', true),
            'max_attempts' => 3,
            'initial_delay_ms' => 100,
            'max_delay_ms' => 2000,
            'multiplier' => 2.0,
            'use_jitter' => true,
            'retryable_exceptions' => [
                \Illuminate\Http\Client\ConnectionException::class,
                \Illuminate\Http\Client\RequestException::class,
            ],
        ],

        'loki' => [
            'enabled' => env('RETRY_LOKI_ENABLED', true),
            'max_attempts' => 3,
            'initial_delay_ms' => 100,
            'max_delay_ms' => 2000,
            'multiplier' => 2.0,
            'use_jitter' => true,
            'retryable_exceptions' => [
                \Illuminate\Http\Client\ConnectionException::class,
                \Illuminate\Http\Client\RequestException::class,
            ],
        ],

        'alertmanager' => [
            'enabled' => env('RETRY_ALERTMANAGER_ENABLED', true),
            'max_attempts' => 3,
            'initial_delay_ms' => 100,
            'max_delay_ms' => 2000,
            'multiplier' => 2.0,
            'use_jitter' => true,
            'retryable_exceptions' => [
                \Illuminate\Http\Client\ConnectionException::class,
                \Illuminate\Http\Client\RequestException::class,
            ],
        ],

        'database' => [
            'enabled' => env('RETRY_DATABASE_ENABLED', true),
            'max_attempts' => 5,
            'initial_delay_ms' => 50,
            'max_delay_ms' => 5000,
            'multiplier' => 2.0,
            'use_jitter' => true,
            'retryable_exceptions' => [
                \Illuminate\Database\QueryException::class,
                \PDOException::class,
            ],
        ],

        'redis' => [
            'enabled' => env('RETRY_REDIS_ENABLED', true),
            'max_attempts' => 3,
            'initial_delay_ms' => 50,
            'max_delay_ms' => 2000,
            'multiplier' => 2.0,
            'use_jitter' => true,
            'retryable_exceptions' => [
                \RedisException::class,
                \Predis\Connection\ConnectionException::class,
            ],
        ],

        'smtp' => [
            'enabled' => env('RETRY_SMTP_ENABLED', true),
            'max_attempts' => 3,
            'initial_delay_ms' => 500,
            'max_delay_ms' => 10000,
            'multiplier' => 2.0,
            'use_jitter' => true,
            'retryable_exceptions' => [
                \Swift_TransportException::class,
                \Symfony\Component\Mailer\Exception\TransportException::class,
            ],
        ],

        'vpsmanager' => [
            'enabled' => env('RETRY_VPSMANAGER_ENABLED', true),
            'max_attempts' => 3,
            'initial_delay_ms' => 200,
            'max_delay_ms' => 5000,
            'multiplier' => 2.0,
            'use_jitter' => true,
            'retryable_exceptions' => [
                \Illuminate\Http\Client\ConnectionException::class,
                \Illuminate\Http\Client\RequestException::class,
            ],
        ],

        'http' => [
            'enabled' => env('RETRY_HTTP_ENABLED', true),
            'max_attempts' => 3,
            'initial_delay_ms' => 100,
            'max_delay_ms' => 3000,
            'multiplier' => 2.0,
            'use_jitter' => true,
            'retryable_exceptions' => [
                \Illuminate\Http\Client\ConnectionException::class,
                \Illuminate\Http\Client\RequestException::class,
            ],
        ],

        'ssh' => [
            'enabled' => env('RETRY_SSH_ENABLED', true),
            'max_attempts' => 3,
            'initial_delay_ms' => 500,
            'max_delay_ms' => 5000,
            'multiplier' => 2.0,
            'use_jitter' => true,
            'retryable_exceptions' => [],
        ],
    ],
];
