<?php

declare(strict_types=1);

return [
    /*
    |--------------------------------------------------------------------------
    | Observability Configuration
    |--------------------------------------------------------------------------
    |
    | Configure monitoring, metrics, tracing, and logging for the application.
    |
    */

    'enabled' => env('OBSERVABILITY_ENABLED', true),

    /*
    |--------------------------------------------------------------------------
    | Metrics Configuration
    |--------------------------------------------------------------------------
    */
    'metrics' => [
        'enabled' => env('METRICS_ENABLED', true),
        'namespace' => env('METRICS_NAMESPACE', 'chom'),
        'subsystem' => env('METRICS_SUBSYSTEM', 'laravel'),

        // Metrics endpoint configuration
        'endpoint' => [
            'enabled' => env('METRICS_ENDPOINT_ENABLED', true),
            'path' => env('METRICS_ENDPOINT_PATH', '/metrics'),
            'ip_whitelist' => array_filter(explode(',', env('METRICS_IP_WHITELIST', '127.0.0.1,::1'))),
        ],

        // Prometheus push gateway (optional)
        'push_gateway' => [
            'enabled' => env('PROMETHEUS_PUSH_GATEWAY_ENABLED', false),
            'url' => env('PROMETHEUS_PUSH_GATEWAY_URL'),
            'job' => env('PROMETHEUS_JOB_NAME', 'chom_laravel'),
            'interval' => env('PROMETHEUS_PUSH_INTERVAL', 60), // seconds
        ],

        // Histogram buckets
        'buckets' => [
            'http_duration' => [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
            'db_query_duration' => [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2],
            'queue_job_duration' => [0.1, 0.5, 1, 2, 5, 10, 30, 60, 120, 300],
            'vps_operation_duration' => [1, 5, 10, 30, 60, 120, 300, 600],
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Tracing Configuration
    |--------------------------------------------------------------------------
    */
    'tracing' => [
        'enabled' => env('TRACING_ENABLED', true),
        'driver' => env('TRACING_DRIVER', 'jaeger'), // jaeger, zipkin, null

        'jaeger' => [
            'agent_host' => env('JAEGER_AGENT_HOST', 'localhost'),
            'agent_port' => env('JAEGER_AGENT_PORT', 6831),
            'sampler_type' => env('JAEGER_SAMPLER_TYPE', 'probabilistic'),
            'sampler_param' => env('JAEGER_SAMPLER_PARAM', 0.1), // 10% sampling
        ],

        'zipkin' => [
            'endpoint' => env('ZIPKIN_ENDPOINT', 'http://localhost:9411/api/v2/spans'),
        ],

        // Trace context propagation
        'propagation' => [
            'http_headers' => true,
            'queue_jobs' => true,
            'events' => true,
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Structured Logging Configuration
    |--------------------------------------------------------------------------
    */
    'logging' => [
        'structured' => env('STRUCTURED_LOGGING_ENABLED', true),
        'format' => env('LOG_FORMAT', 'json'), // json, text

        // Context enrichment
        'enrich_context' => [
            'trace_id' => true,
            'request_id' => true,
            'user_id' => true,
            'tenant_id' => true,
            'session_id' => false,
            'ip_address' => true,
            'user_agent' => false,
        ],

        // Performance logging thresholds
        'performance' => [
            'slow_query_threshold_ms' => env('SLOW_QUERY_THRESHOLD', 100),
            'slow_request_threshold_ms' => env('SLOW_REQUEST_THRESHOLD', 500),
            'slow_job_threshold_ms' => env('SLOW_JOB_THRESHOLD', 5000),
        ],

        // Log sampling for high-volume events
        'sampling' => [
            'enabled' => env('LOG_SAMPLING_ENABLED', false),
            'rate' => env('LOG_SAMPLING_RATE', 0.1), // 10%
            'patterns' => [ // Always log these patterns
                'error',
                'critical',
                'emergency',
                'alert',
            ],
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Error Tracking Configuration
    |--------------------------------------------------------------------------
    */
    'error_tracking' => [
        'enabled' => env('ERROR_TRACKING_ENABLED', true),
        'driver' => env('ERROR_TRACKING_DRIVER', 'sentry'), // sentry, bugsnag, log, null

        'sentry' => [
            'dsn' => env('SENTRY_LARAVEL_DSN', env('SENTRY_DSN')),
            'environment' => env('APP_ENV', 'production'),
            'release' => env('APP_VERSION'),
            'traces_sample_rate' => env('SENTRY_TRACES_SAMPLE_RATE', 0.2),
        ],

        'bugsnag' => [
            'api_key' => env('BUGSNAG_API_KEY'),
        ],

        // Error grouping configuration
        'grouping' => [
            'by_exception_class' => true,
            'by_file_and_line' => true,
            'ignore_patterns' => [
                'Illuminate\Session\TokenMismatchException',
            ],
        ],

        // Context to capture
        'capture_context' => [
            'user' => true,
            'request' => true,
            'environment' => true,
            'breadcrumbs' => true,
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Performance Monitoring Configuration
    |--------------------------------------------------------------------------
    */
    'performance' => [
        'enabled' => env('PERFORMANCE_MONITORING_ENABLED', true),

        // Query monitoring
        'queries' => [
            'enabled' => true,
            'slow_threshold_ms' => 100,
            'log_bindings' => env('APP_DEBUG', false),
            'backtrace' => env('APP_DEBUG', false),
        ],

        // Memory monitoring
        'memory' => [
            'enabled' => true,
            'threshold_mb' => 256,
            'log_on_threshold' => true,
        ],

        // Transaction tracing
        'transactions' => [
            'enabled' => true,
            'sample_rate' => 0.1, // 10%
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Health Check Configuration
    |--------------------------------------------------------------------------
    */
    'health' => [
        'enabled' => env('HEALTH_CHECK_ENABLED', true),

        'checks' => [
            'database' => [
                'enabled' => true,
                'timeout' => 5,
            ],
            'redis' => [
                'enabled' => env('REDIS_CLIENT') !== null,
                'timeout' => 3,
            ],
            'queue' => [
                'enabled' => true,
                'timeout' => 5,
                'max_backlog' => 1000,
            ],
            'storage' => [
                'enabled' => true,
                'min_free_space_percent' => 10,
            ],
            'vps' => [
                'enabled' => env('VPS_PROVIDER') !== 'null',
                'timeout' => 10,
            ],
        ],

        // Endpoint configuration
        'endpoints' => [
            'liveness' => '/health',
            'readiness' => '/health/ready',
            'detailed' => '/health/detailed',
        ],

        // IP whitelist for detailed health checks
        'detailed_ip_whitelist' => array_filter(
            explode(',', env('HEALTH_CHECK_IP_WHITELIST', '127.0.0.1,::1'))
        ),
    ],

    /*
    |--------------------------------------------------------------------------
    | Business Metrics Configuration
    |--------------------------------------------------------------------------
    */
    'business_metrics' => [
        'enabled' => env('BUSINESS_METRICS_ENABLED', true),

        'track' => [
            'tenant_signups' => true,
            'site_provisioning' => true,
            'backup_operations' => true,
            'ssl_renewals' => true,
            'vps_operations' => true,
        ],
    ],
];
