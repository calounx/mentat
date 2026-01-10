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
        // Enable/disable metrics collection globally
        'enabled' => env('METRICS_ENABLED', true),

        // Metric naming configuration
        'namespace' => env('METRICS_NAMESPACE', 'chom'),
        'subsystem' => env('METRICS_SUBSYSTEM', 'laravel'),

        // Histogram buckets for different metric types
        'buckets' => [
            'http_duration' => [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
            'db_query_duration' => [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1],
            'queue_job_duration' => [0.1, 0.5, 1, 2.5, 5, 10, 30, 60, 120],
            'vps_operation_duration' => [1, 5, 10, 30, 60, 120, 300, 600],
        ],

        'endpoint' => [
            // Enable/disable the /metrics endpoint
            'enabled' => env('METRICS_ENDPOINT_ENABLED', true),

            // Endpoint path
            'path' => env('METRICS_ENDPOINT_PATH', '/prometheus/metrics'),

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
        'driver' => env('TRACING_DRIVER', 'jaeger'),
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

        'performance' => [
            // Slow request threshold in milliseconds
            'slow_request_threshold_ms' => env('SLOW_REQUEST_THRESHOLD_MS', 500),

            // Slow query threshold in milliseconds
            'slow_query_threshold_ms' => env('SLOW_QUERY_THRESHOLD_MS', 100),
        ],
    ],
];
