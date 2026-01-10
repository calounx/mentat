<?php

return [
    /*
    |--------------------------------------------------------------------------
    | Metrics Configuration
    |--------------------------------------------------------------------------
    |
    | Configuration for Prometheus metrics endpoint and collection.
    |
    */

    'metrics' => [
        'endpoint' => [
            // Enable/disable the /metrics endpoint
            'enabled' => env('METRICS_ENDPOINT_ENABLED', true),

            // IP whitelist for metrics endpoint access
            // Add Prometheus server IPs here
            'ip_whitelist' => explode(',', env('METRICS_IP_WHITELIST', '127.0.0.1,::1')),
        ],

        'collection' => [
            // Enable/disable automatic metrics collection
            'enabled' => env('METRICS_COLLECTION_ENABLED', true),

            // Redis key prefix for metrics storage
            'redis_prefix' => env('METRICS_REDIS_PREFIX', 'metrics:'),

            // Metrics retention in seconds (default: 5 minutes)
            'ttl' => env('METRICS_TTL', 300),
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Tracing Configuration
    |--------------------------------------------------------------------------
    |
    | Configuration for distributed tracing with Jaeger.
    |
    */

    'tracing' => [
        'enabled' => env('TRACING_ENABLED', false),
        'jaeger_host' => env('JAEGER_AGENT_HOST', 'localhost'),
        'jaeger_port' => env('JAEGER_AGENT_PORT', 6831),
        'service_name' => env('APP_NAME', 'chom'),
    ],

    /*
    |--------------------------------------------------------------------------
    | Logging Configuration
    |--------------------------------------------------------------------------
    |
    | Configuration for structured logging and log shipping.
    |
    */

    'logging' => [
        'loki' => [
            'enabled' => env('LOKI_ENABLED', false),
            'endpoint' => env('LOKI_ENDPOINT', 'http://localhost:3100'),
            'tenant_id' => env('LOKI_TENANT_ID', 'default'),
        ],
    ],
];
