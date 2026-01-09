<?php

return [
    /*
    |--------------------------------------------------------------------------
    | Graceful Degradation Configuration
    |--------------------------------------------------------------------------
    |
    | Configure which features should gracefully degrade when dependencies
    | are unavailable. This allows the application to continue functioning
    | with reduced capabilities rather than failing completely.
    |
    */

    'features' => [
        /*
         * Real-time metrics display
         * Falls back to cached metrics when Prometheus is unavailable
         */
        'metrics_dashboard' => [
            'enabled' => env('DEGRADATION_METRICS_ENABLED', true),
            'dependencies' => ['prometheus'],
            'fallback_strategy' => 'cached_data',
            'cache_ttl' => 3600, // 1 hour
        ],

        /*
         * Log streaming
         * Falls back to cached logs when Loki is unavailable
         */
        'log_viewer' => [
            'enabled' => env('DEGRADATION_LOGS_ENABLED', true),
            'dependencies' => ['loki'],
            'fallback_strategy' => 'cached_data',
            'cache_ttl' => 1800, // 30 minutes
        ],

        /*
         * Alerting
         * Queues alerts locally when Alertmanager is unavailable
         */
        'alerting' => [
            'enabled' => env('DEGRADATION_ALERTING_ENABLED', true),
            'dependencies' => ['alertmanager'],
            'fallback_strategy' => 'queue',
            'cache_ttl' => 300, // 5 minutes
        ],

        /*
         * Grafana dashboards
         * Shows static dashboard placeholders when Grafana is unavailable
         */
        'grafana_dashboards' => [
            'enabled' => env('DEGRADATION_GRAFANA_ENABLED', true),
            'dependencies' => ['grafana'],
            'fallback_strategy' => 'static_content',
            'cache_ttl' => 3600, // 1 hour
        ],

        /*
         * VPS provisioning
         * Queues provisioning requests when VPSManager is unavailable
         */
        'vps_provisioning' => [
            'enabled' => env('DEGRADATION_VPS_ENABLED', true),
            'dependencies' => ['vpsmanager'],
            'fallback_strategy' => 'queue',
            'cache_ttl' => 600, // 10 minutes
        ],

        /*
         * Email notifications
         * Queues emails when SMTP is unavailable
         */
        'email_notifications' => [
            'enabled' => env('DEGRADATION_EMAIL_ENABLED', true),
            'dependencies' => ['smtp'],
            'fallback_strategy' => 'queue',
            'cache_ttl' => 1800, // 30 minutes
        ],

        /*
         * Database-backed features
         * Uses read replicas or cached data when primary DB is slow
         */
        'database_heavy_queries' => [
            'enabled' => env('DEGRADATION_DB_ENABLED', true),
            'dependencies' => ['database'],
            'fallback_strategy' => 'cached_data',
            'cache_ttl' => 300, // 5 minutes
        ],

        /*
         * Session/cache features
         * Falls back to database sessions when Redis is unavailable
         */
        'redis_features' => [
            'enabled' => env('DEGRADATION_REDIS_ENABLED', true),
            'dependencies' => ['redis'],
            'fallback_strategy' => 'database',
            'cache_ttl' => 300, // 5 minutes
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Dependency Health Tracking
    |--------------------------------------------------------------------------
    |
    | Configuration for tracking and responding to dependency health issues.
    |
    */

    'health_check_interval' => env('DEGRADATION_HEALTH_CHECK_INTERVAL', 60), // seconds
    'unhealthy_threshold' => env('DEGRADATION_UNHEALTHY_THRESHOLD', 3), // consecutive failures
    'recovery_check_interval' => env('DEGRADATION_RECOVERY_INTERVAL', 120), // seconds

    /*
    |--------------------------------------------------------------------------
    | User Notifications
    |--------------------------------------------------------------------------
    |
    | Configure how users are notified about degraded features.
    |
    */

    'show_degradation_banner' => env('DEGRADATION_SHOW_BANNER', true),
    'log_degradation_events' => env('DEGRADATION_LOG_EVENTS', true),
];
