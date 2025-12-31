<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Monitoring Enabled
    |--------------------------------------------------------------------------
    |
    | Enable or disable monitoring globally. When disabled, metrics collection
    | and reporting will be skipped to reduce overhead.
    |
    */

    'enabled' => env('MONITORING_ENABLED', true),

    /*
    |--------------------------------------------------------------------------
    | Prometheus Configuration
    |--------------------------------------------------------------------------
    |
    | Configuration for Prometheus metrics export.
    |
    */

    'prometheus' => [
        'enabled' => env('PROMETHEUS_ENABLED', false),
        'namespace' => env('PROMETHEUS_NAMESPACE', 'laravel_app'),
        'pushgateway_url' => env('PROMETHEUS_PUSHGATEWAY_URL'),
        'push_interval' => env('PROMETHEUS_PUSH_INTERVAL', 60), // seconds
    ],

    /*
    |--------------------------------------------------------------------------
    | Sentry Configuration
    |--------------------------------------------------------------------------
    |
    | Configuration for Sentry error tracking.
    |
    */

    'sentry' => [
        'enabled' => env('SENTRY_ENABLED', false),
        'dsn' => env('SENTRY_LARAVEL_DSN'),
        'environment' => env('SENTRY_ENVIRONMENT', env('APP_ENV', 'production')),
        'traces_sample_rate' => env('SENTRY_TRACES_SAMPLE_RATE', 0.1),
        'profiles_sample_rate' => env('SENTRY_PROFILES_SAMPLE_RATE', 0.1),
    ],

    /*
    |--------------------------------------------------------------------------
    | Performance Monitoring
    |--------------------------------------------------------------------------
    |
    | Configuration for performance monitoring and slow query logging.
    |
    */

    'performance' => [
        'slow_request_threshold' => env('SLOW_REQUEST_THRESHOLD', 1000), // milliseconds
        'slow_query_threshold' => env('SLOW_QUERY_THRESHOLD', 1000), // milliseconds
        'log_slow_requests' => env('LOG_SLOW_REQUESTS', true),
        'log_slow_queries' => env('LOG_SLOW_QUERIES', true),
    ],

    /*
    |--------------------------------------------------------------------------
    | Metrics Collection
    |--------------------------------------------------------------------------
    |
    | Define which metrics should be collected and their collection intervals.
    |
    */

    'metrics' => [
        'request_metrics' => [
            'enabled' => true,
            'track_response_time' => true,
            'track_memory_usage' => true,
            'track_query_count' => true,
        ],

        'system_metrics' => [
            'enabled' => true,
            'collect_interval' => 60, // seconds
            'track_memory' => true,
            'track_cpu' => true,
            'track_disk' => true,
        ],

        'application_metrics' => [
            'enabled' => true,
            'track_queue_depth' => true,
            'track_cache_hits' => true,
            'track_active_users' => true,
            'track_error_rate' => true,
        ],

        'business_metrics' => [
            'enabled' => true,
            'track_sites_created' => true,
            'track_backups_run' => true,
            'track_deployments' => true,
            'track_api_calls' => true,
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Data Retention
    |--------------------------------------------------------------------------
    |
    | How long to keep different types of metrics data.
    |
    */

    'retention' => [
        'high_resolution' => 24, // hours - 1 minute granularity
        'medium_resolution' => 7, // days - 5 minute granularity
        'low_resolution' => 90, // days - 1 hour granularity
    ],

    /*
    |--------------------------------------------------------------------------
    | External Services Health Checks
    |--------------------------------------------------------------------------
    |
    | URLs to check for external service dependencies.
    |
    */

    'external_health_checks' => [
        // Add your external services here
        // 'service_name' => 'https://api.example.com/health',
    ],

    /*
    |--------------------------------------------------------------------------
    | VPS Health Check
    |--------------------------------------------------------------------------
    |
    | Enable checking connectivity to VPS servers.
    |
    */

    'vps_health_check' => env('VPS_HEALTH_CHECK_ENABLED', false),

    /*
    |--------------------------------------------------------------------------
    | Metrics Storage
    |--------------------------------------------------------------------------
    |
    | Where to store collected metrics. Options: 'database', 'redis', 'file'
    |
    */

    'storage' => [
        'driver' => env('METRICS_STORAGE_DRIVER', 'redis'),
        'prefix' => env('METRICS_STORAGE_PREFIX', 'metrics:'),
    ],

    /*
    |--------------------------------------------------------------------------
    | Custom Metrics
    |--------------------------------------------------------------------------
    |
    | Define custom application-specific metrics to track.
    |
    */

    'custom_metrics' => [
        // Example:
        // 'user_signups' => [
        //     'type' => 'counter',
        //     'description' => 'Total number of user signups',
        //     'labels' => ['plan', 'source'],
        // ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Third-Party Integrations
    |--------------------------------------------------------------------------
    |
    | Configuration for third-party monitoring services.
    |
    */

    'integrations' => [
        'new_relic' => [
            'enabled' => env('NEW_RELIC_ENABLED', false),
            'app_name' => env('NEW_RELIC_APP_NAME', config('app.name')),
            'license_key' => env('NEW_RELIC_LICENSE_KEY'),
        ],

        'datadog' => [
            'enabled' => env('DATADOG_ENABLED', false),
            'api_key' => env('DATADOG_API_KEY'),
            'app_key' => env('DATADOG_APP_KEY'),
            'host' => env('DATADOG_HOST', 'localhost'),
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Debug Mode
    |--------------------------------------------------------------------------
    |
    | Enable debug mode to log additional information about metrics collection.
    |
    */

    'debug' => env('MONITORING_DEBUG', false),

];
