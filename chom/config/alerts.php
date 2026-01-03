<?php

declare(strict_types=1);

return [
    /*
    |--------------------------------------------------------------------------
    | Alerting Configuration
    |--------------------------------------------------------------------------
    |
    | Define alerting rules and thresholds for production monitoring.
    |
    */

    'enabled' => env('ALERTING_ENABLED', true),

    'channels' => [
        'slack' => env('ALERT_SLACK_ENABLED', false),
        'email' => env('ALERT_EMAIL_ENABLED', true),
        'pagerduty' => env('ALERT_PAGERDUTY_ENABLED', false),
    ],

    'recipients' => [
        'email' => array_filter(explode(',', env('ALERT_EMAIL_RECIPIENTS', ''))),
        'slack_webhook' => env('ALERT_SLACK_WEBHOOK'),
        'pagerduty_key' => env('PAGERDUTY_INTEGRATION_KEY'),
    ],

    /*
    |--------------------------------------------------------------------------
    | Alert Rules
    |--------------------------------------------------------------------------
    |
    | Define alerting rules with severity levels and thresholds.
    | Severity: critical, warning, info
    |
    */

    'rules' => [
        // Application Health Alerts
        'high_error_rate' => [
            'enabled' => true,
            'severity' => 'critical',
            'threshold' => 0.01, // 1% error rate
            'window' => '5m',
            'description' => 'HTTP error rate exceeds 1% of requests',
            'runbook' => 'https://docs.chom.app/runbooks/high-error-rate',
        ],

        'critical_error_rate' => [
            'enabled' => true,
            'severity' => 'critical',
            'threshold' => 0.05, // 5% error rate
            'window' => '1m',
            'description' => 'HTTP error rate exceeds 5% - immediate action required',
            'runbook' => 'https://docs.chom.app/runbooks/critical-error-rate',
        ],

        // Performance Alerts
        'slow_response_time' => [
            'enabled' => true,
            'severity' => 'warning',
            'threshold' => 0.5, // 500ms
            'percentile' => 95, // p95
            'window' => '5m',
            'description' => 'API response time p95 exceeds 500ms',
            'runbook' => 'https://docs.chom.app/runbooks/slow-response',
        ],

        'very_slow_response_time' => [
            'enabled' => true,
            'severity' => 'critical',
            'threshold' => 2.0, // 2000ms
            'percentile' => 95,
            'window' => '5m',
            'description' => 'API response time p95 exceeds 2 seconds',
            'runbook' => 'https://docs.chom.app/runbooks/very-slow-response',
        ],

        // Database Alerts
        'slow_database_queries' => [
            'enabled' => true,
            'severity' => 'warning',
            'threshold' => 0.1, // 100ms
            'percentile' => 95,
            'window' => '5m',
            'description' => 'Database query time p95 exceeds 100ms',
            'runbook' => 'https://docs.chom.app/runbooks/slow-queries',
        ],

        'database_connection_pool_exhausted' => [
            'enabled' => true,
            'severity' => 'critical',
            'threshold' => 0.9, // 90% utilization
            'window' => '1m',
            'description' => 'Database connection pool utilization exceeds 90%',
            'runbook' => 'https://docs.chom.app/runbooks/db-connection-pool',
        ],

        'database_unavailable' => [
            'enabled' => true,
            'severity' => 'critical',
            'window' => '1m',
            'description' => 'Database health check failed',
            'runbook' => 'https://docs.chom.app/runbooks/database-down',
        ],

        // Queue Alerts
        'queue_backlog' => [
            'enabled' => true,
            'severity' => 'warning',
            'threshold' => 1000, // jobs
            'window' => '5m',
            'description' => 'Queue backlog exceeds 1000 jobs',
            'runbook' => 'https://docs.chom.app/runbooks/queue-backlog',
        ],

        'queue_critical_backlog' => [
            'enabled' => true,
            'severity' => 'critical',
            'threshold' => 5000, // jobs
            'window' => '5m',
            'description' => 'Queue backlog exceeds 5000 jobs - scaling required',
            'runbook' => 'https://docs.chom.app/runbooks/queue-critical-backlog',
        ],

        'high_job_failure_rate' => [
            'enabled' => true,
            'severity' => 'warning',
            'threshold' => 0.05, // 5%
            'window' => '10m',
            'description' => 'Queue job failure rate exceeds 5%',
            'runbook' => 'https://docs.chom.app/runbooks/job-failures',
        ],

        // Cache Alerts
        'low_cache_hit_rate' => [
            'enabled' => true,
            'severity' => 'warning',
            'threshold' => 0.5, // 50%
            'window' => '15m',
            'description' => 'Cache hit rate below 50%',
            'runbook' => 'https://docs.chom.app/runbooks/cache-hit-rate',
        ],

        'redis_unavailable' => [
            'enabled' => true,
            'severity' => 'critical',
            'window' => '1m',
            'description' => 'Redis health check failed',
            'runbook' => 'https://docs.chom.app/runbooks/redis-down',
        ],

        // Infrastructure Alerts
        'disk_space_low' => [
            'enabled' => true,
            'severity' => 'warning',
            'threshold' => 0.1, // 10% free space
            'window' => '5m',
            'description' => 'Disk space below 10%',
            'runbook' => 'https://docs.chom.app/runbooks/disk-space',
        ],

        'disk_space_critical' => [
            'enabled' => true,
            'severity' => 'critical',
            'threshold' => 0.05, // 5% free space
            'window' => '1m',
            'description' => 'Disk space below 5% - immediate action required',
            'runbook' => 'https://docs.chom.app/runbooks/disk-space-critical',
        ],

        'high_memory_usage' => [
            'enabled' => true,
            'severity' => 'warning',
            'threshold' => 0.85, // 85%
            'window' => '5m',
            'description' => 'Memory usage exceeds 85%',
            'runbook' => 'https://docs.chom.app/runbooks/high-memory',
        ],

        'high_cpu_usage' => [
            'enabled' => true,
            'severity' => 'warning',
            'threshold' => 0.8, // 80%
            'window' => '5m',
            'description' => 'CPU usage exceeds 80%',
            'runbook' => 'https://docs.chom.app/runbooks/high-cpu',
        ],

        // VPS Operations Alerts
        'vps_operation_failures' => [
            'enabled' => true,
            'severity' => 'critical',
            'threshold' => 0.05, // 5%
            'window' => '10m',
            'description' => 'VPS operation failure rate exceeds 5%',
            'runbook' => 'https://docs.chom.app/runbooks/vps-failures',
        ],

        'site_provisioning_failures' => [
            'enabled' => true,
            'severity' => 'critical',
            'threshold' => 0.1, // 10%
            'window' => '15m',
            'description' => 'Site provisioning failure rate exceeds 10%',
            'runbook' => 'https://docs.chom.app/runbooks/provisioning-failures',
        ],

        // Security Alerts
        'authentication_failures' => [
            'enabled' => true,
            'severity' => 'warning',
            'threshold' => 10, // attempts
            'window' => '5m',
            'description' => 'High number of authentication failures from single IP',
            'runbook' => 'https://docs.chom.app/runbooks/auth-failures',
        ],

        'rate_limit_exceeded' => [
            'enabled' => true,
            'severity' => 'info',
            'threshold' => 100, // requests
            'window' => '1m',
            'description' => 'Rate limit exceeded for user/IP',
            'runbook' => 'https://docs.chom.app/runbooks/rate-limiting',
        ],

        // SSL Certificate Alerts
        'ssl_expiring_soon' => [
            'enabled' => true,
            'severity' => 'warning',
            'threshold' => 7, // days
            'description' => 'SSL certificate expiring within 7 days',
            'runbook' => 'https://docs.chom.app/runbooks/ssl-renewal',
        ],

        'ssl_renewal_failures' => [
            'enabled' => true,
            'severity' => 'critical',
            'threshold' => 3, // consecutive failures
            'description' => 'SSL certificate renewal failed multiple times',
            'runbook' => 'https://docs.chom.app/runbooks/ssl-renewal-failure',
        ],

        // Backup Alerts
        'backup_failures' => [
            'enabled' => true,
            'severity' => 'critical',
            'threshold' => 0.1, // 10%
            'window' => '1h',
            'description' => 'Backup failure rate exceeds 10%',
            'runbook' => 'https://docs.chom.app/runbooks/backup-failures',
        ],

        'no_recent_backup' => [
            'enabled' => true,
            'severity' => 'critical',
            'threshold' => 48, // hours
            'description' => 'No successful backup in 48 hours',
            'runbook' => 'https://docs.chom.app/runbooks/no-recent-backup',
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Alert Routing
    |--------------------------------------------------------------------------
    |
    | Route alerts to different channels based on severity.
    |
    */

    'routing' => [
        'critical' => ['slack', 'email', 'pagerduty'],
        'warning' => ['slack', 'email'],
        'info' => ['slack'],
    ],

    /*
    |--------------------------------------------------------------------------
    | Alert Aggregation
    |--------------------------------------------------------------------------
    |
    | Prevent alert fatigue by aggregating similar alerts.
    |
    */

    'aggregation' => [
        'enabled' => true,
        'window' => 300, // 5 minutes
        'max_alerts_per_rule' => 1, // Only send one alert per rule per window
    ],

    /*
    |--------------------------------------------------------------------------
    | Quiet Hours
    |--------------------------------------------------------------------------
    |
    | Define quiet hours for non-critical alerts (UTC timezone).
    |
    */

    'quiet_hours' => [
        'enabled' => env('ALERT_QUIET_HOURS_ENABLED', false),
        'start' => '22:00',
        'end' => '08:00',
        'severity_threshold' => 'critical', // Only critical alerts during quiet hours
    ],
];
