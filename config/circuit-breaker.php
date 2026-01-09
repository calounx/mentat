<?php

return [
    /*
    |--------------------------------------------------------------------------
    | Circuit Breaker Configuration
    |--------------------------------------------------------------------------
    |
    | Configure circuit breakers for external services to prevent cascading
    | failures. Circuit breakers automatically open when failure threshold
    | is reached, preventing further calls until the service recovers.
    |
    */

    'default_failure_threshold' => env('CIRCUIT_BREAKER_FAILURE_THRESHOLD', 5),
    'default_success_threshold' => env('CIRCUIT_BREAKER_SUCCESS_THRESHOLD', 2),
    'default_timeout' => env('CIRCUIT_BREAKER_TIMEOUT', 60),
    'default_half_open_timeout' => env('CIRCUIT_BREAKER_HALF_OPEN_TIMEOUT', 30),

    /*
    |--------------------------------------------------------------------------
    | Service-Specific Circuit Breakers
    |--------------------------------------------------------------------------
    |
    | Configure individual circuit breakers for each external service.
    | Each breaker can have custom thresholds and timeouts.
    |
    */

    'breakers' => [
        'prometheus' => [
            'enabled' => env('CIRCUIT_BREAKER_PROMETHEUS_ENABLED', true),
            'failure_threshold' => 3,
            'success_threshold' => 2,
            'timeout' => 30,
            'half_open_timeout' => 15,
        ],

        'grafana' => [
            'enabled' => env('CIRCUIT_BREAKER_GRAFANA_ENABLED', true),
            'failure_threshold' => 3,
            'success_threshold' => 2,
            'timeout' => 30,
            'half_open_timeout' => 15,
        ],

        'loki' => [
            'enabled' => env('CIRCUIT_BREAKER_LOKI_ENABLED', true),
            'failure_threshold' => 3,
            'success_threshold' => 2,
            'timeout' => 30,
            'half_open_timeout' => 15,
        ],

        'alertmanager' => [
            'enabled' => env('CIRCUIT_BREAKER_ALERTMANAGER_ENABLED', true),
            'failure_threshold' => 3,
            'success_threshold' => 2,
            'timeout' => 30,
            'half_open_timeout' => 15,
        ],

        'database' => [
            'enabled' => env('CIRCUIT_BREAKER_DATABASE_ENABLED', true),
            'failure_threshold' => 5,
            'success_threshold' => 2,
            'timeout' => 60,
            'half_open_timeout' => 30,
        ],

        'redis' => [
            'enabled' => env('CIRCUIT_BREAKER_REDIS_ENABLED', true),
            'failure_threshold' => 3,
            'success_threshold' => 2,
            'timeout' => 30,
            'half_open_timeout' => 15,
        ],

        'smtp' => [
            'enabled' => env('CIRCUIT_BREAKER_SMTP_ENABLED', true),
            'failure_threshold' => 5,
            'success_threshold' => 2,
            'timeout' => 120,
            'half_open_timeout' => 60,
        ],

        'vpsmanager' => [
            'enabled' => env('CIRCUIT_BREAKER_VPSMANAGER_ENABLED', true),
            'failure_threshold' => 3,
            'success_threshold' => 2,
            'timeout' => 60,
            'half_open_timeout' => 30,
        ],
    ],
];
