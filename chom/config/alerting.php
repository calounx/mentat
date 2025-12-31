<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Alerting Enabled
    |--------------------------------------------------------------------------
    |
    | Enable or disable alerting globally.
    |
    */

    'enabled' => env('ALERTING_ENABLED', true),

    /*
    |--------------------------------------------------------------------------
    | Alert Channels
    |--------------------------------------------------------------------------
    |
    | Configure which channels to use for different alert severities.
    |
    */

    'channels' => [
        'critical' => ['slack', 'pagerduty', 'email'],
        'warning' => ['slack', 'email'],
        'info' => ['slack'],
    ],

    /*
    |--------------------------------------------------------------------------
    | Slack Configuration
    |--------------------------------------------------------------------------
    |
    | Configuration for Slack notifications.
    |
    */

    'slack' => [
        'enabled' => env('SLACK_ALERTS_ENABLED', false),
        'webhook_url' => env('SLACK_WEBHOOK_URL'),
        'channel' => env('SLACK_ALERT_CHANNEL', '#alerts'),
        'username' => env('SLACK_ALERT_USERNAME', 'Alert Bot'),
        'icon_emoji' => env('SLACK_ALERT_ICON', ':rotating_light:'),
    ],

    /*
    |--------------------------------------------------------------------------
    | Email Configuration
    |--------------------------------------------------------------------------
    |
    | Configuration for email notifications.
    |
    */

    'email' => [
        'enabled' => env('EMAIL_ALERTS_ENABLED', true),
        'recipients' => explode(',', env('ALERT_EMAIL_RECIPIENTS', '')),
        'from' => [
            'address' => env('ALERT_EMAIL_FROM', env('MAIL_FROM_ADDRESS', 'alerts@example.com')),
            'name' => env('ALERT_EMAIL_FROM_NAME', 'System Alerts'),
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | PagerDuty Configuration
    |--------------------------------------------------------------------------
    |
    | Configuration for PagerDuty incident management.
    |
    */

    'pagerduty' => [
        'enabled' => env('PAGERDUTY_ENABLED', false),
        'integration_key' => env('PAGERDUTY_INTEGRATION_KEY'),
        'api_url' => 'https://events.pagerduty.com/v2/enqueue',
    ],

    /*
    |--------------------------------------------------------------------------
    | Alert Rules
    |--------------------------------------------------------------------------
    |
    | Define alert rules with thresholds and severities.
    |
    */

    'rules' => [
        // Performance alerts
        'high_error_rate' => [
            'enabled' => true,
            'threshold' => 5, // percentage
            'window' => 300, // seconds (5 minutes)
            'severity' => 'critical',
            'description' => 'Error rate exceeds 5%',
        ],

        'slow_response_time' => [
            'enabled' => true,
            'threshold' => 1000, // milliseconds
            'window' => 300,
            'severity' => 'warning',
            'description' => 'Average response time exceeds 1 second',
        ],

        // Infrastructure alerts
        'database_connection_failure' => [
            'enabled' => true,
            'threshold' => 1,
            'window' => 60,
            'severity' => 'critical',
            'description' => 'Cannot connect to database',
        ],

        'redis_connection_failure' => [
            'enabled' => true,
            'threshold' => 1,
            'window' => 60,
            'severity' => 'critical',
            'description' => 'Cannot connect to Redis',
        ],

        'high_database_connections' => [
            'enabled' => true,
            'threshold' => 80, // percentage
            'severity' => 'warning',
            'description' => 'Database connection pool above 80%',
        ],

        // Resource alerts
        'high_memory_usage' => [
            'enabled' => true,
            'threshold' => 90, // percentage
            'severity' => 'warning',
            'description' => 'Memory usage above 90%',
        ],

        'low_disk_space' => [
            'enabled' => true,
            'threshold' => 20, // percentage free
            'severity' => 'critical',
            'description' => 'Disk space below 20%',
        ],

        // Queue alerts
        'high_queue_depth' => [
            'enabled' => true,
            'threshold' => 1000,
            'severity' => 'warning',
            'description' => 'Queue depth exceeds 1000 jobs',
        ],

        'high_failed_jobs' => [
            'enabled' => true,
            'threshold' => 10, // per minute
            'window' => 60,
            'severity' => 'critical',
            'description' => 'More than 10 failed jobs per minute',
        ],

        // Security alerts
        'high_failed_login_attempts' => [
            'enabled' => true,
            'threshold' => 10, // per minute
            'window' => 60,
            'severity' => 'critical',
            'description' => 'More than 10 failed login attempts per minute',
        ],

        'security_event' => [
            'enabled' => true,
            'threshold' => 1,
            'severity' => 'critical',
            'description' => 'Security event detected',
        ],

        'unauthorized_access_attempt' => [
            'enabled' => true,
            'threshold' => 5,
            'window' => 300,
            'severity' => 'warning',
            'description' => 'Multiple unauthorized access attempts',
        ],

        // SSL/TLS alerts
        'ssl_certificate_expiring' => [
            'enabled' => true,
            'threshold' => 30, // days
            'severity' => 'warning',
            'description' => 'SSL certificate expires in less than 30 days',
        ],

        'ssl_certificate_expired' => [
            'enabled' => true,
            'threshold' => 0,
            'severity' => 'critical',
            'description' => 'SSL certificate has expired',
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Alert Throttling
    |--------------------------------------------------------------------------
    |
    | Prevent alert spam by throttling repeated alerts.
    |
    */

    'throttling' => [
        'enabled' => true,
        'window' => 3600, // seconds (1 hour)
        'max_alerts_per_rule' => 3, // maximum alerts per rule per window
    ],

    /*
    |--------------------------------------------------------------------------
    | Alert Grouping
    |--------------------------------------------------------------------------
    |
    | Group similar alerts together to reduce noise.
    |
    */

    'grouping' => [
        'enabled' => true,
        'window' => 300, // seconds (5 minutes)
    ],

    /*
    |--------------------------------------------------------------------------
    | Escalation Policy
    |--------------------------------------------------------------------------
    |
    | Define how alerts should escalate if not acknowledged.
    |
    */

    'escalation' => [
        'enabled' => env('ALERT_ESCALATION_ENABLED', false),
        'intervals' => [
            15, // minutes - first escalation
            30, // minutes - second escalation
            60, // minutes - final escalation
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Quiet Hours
    |--------------------------------------------------------------------------
    |
    | Define hours when non-critical alerts should be suppressed.
    |
    */

    'quiet_hours' => [
        'enabled' => env('QUIET_HOURS_ENABLED', false),
        'start' => env('QUIET_HOURS_START', '22:00'),
        'end' => env('QUIET_HOURS_END', '08:00'),
        'timezone' => env('QUIET_HOURS_TIMEZONE', 'UTC'),
        'suppress_severities' => ['info', 'warning'], // Still allow critical alerts
    ],

    /*
    |--------------------------------------------------------------------------
    | Alert Storage
    |--------------------------------------------------------------------------
    |
    | Configuration for storing alert history.
    |
    */

    'storage' => [
        'enabled' => true,
        'driver' => env('ALERT_STORAGE_DRIVER', 'database'),
        'retention_days' => env('ALERT_RETENTION_DAYS', 90),
    ],

    /*
    |--------------------------------------------------------------------------
    | Alert Context
    |--------------------------------------------------------------------------
    |
    | Additional context to include with every alert.
    |
    */

    'context' => [
        'include_environment' => true,
        'include_server_info' => true,
        'include_recent_logs' => true,
        'log_lines' => 20,
    ],

];
