<?php

return [
    /*
    |--------------------------------------------------------------------------
    | Cost & Capacity Metrics Configuration
    |--------------------------------------------------------------------------
    |
    | This configuration file defines pricing models and thresholds for
    | cost analysis and capacity planning dashboards.
    |
    */

    /*
    |--------------------------------------------------------------------------
    | Pricing Configuration
    |--------------------------------------------------------------------------
    */

    'pricing' => [
        // Compute pricing (monthly)
        'vps' => [
            'base_cost' => env('PRICING_VPS_BASE', 10.00),          // Per VPS per month
            'cpu_per_core' => env('PRICING_CPU_CORE', 5.00),        // Per vCPU per month
            'memory_per_gb' => env('PRICING_MEMORY_GB', 4.00),      // Per GB RAM per month
        ],

        // Storage pricing (monthly)
        'storage' => [
            'ssd_per_gb' => env('PRICING_SSD_GB', 0.15),            // Per GB SSD per month
            'hdd_per_gb' => env('PRICING_HDD_GB', 0.05),            // Per GB HDD per month
            'object_per_gb' => env('PRICING_OBJECT_GB', 0.023),     // Per GB object storage per month
            'archive_per_gb' => env('PRICING_ARCHIVE_GB', 0.004),   // Per GB archive per month
        ],

        // Network pricing (per GB transferred)
        'network' => [
            'bandwidth_per_gb' => env('PRICING_BANDWIDTH_GB', 0.08), // Per GB egress
            'bandwidth_free_tier' => env('PRICING_BANDWIDTH_FREE', 100), // Free GB per month
        ],

        // Email service pricing
        'email' => [
            'brevo' => [
                'free_tier' => 300,                                 // Emails per day
                'starter' => ['emails' => 10000, 'cost' => 25],     // Per month
                'business' => ['emails' => 100000, 'cost' => 65],   // Per month
            ],
            'ses' => [
                'per_1000' => 0.10,                                 // Per 1000 emails
            ],
            'sendgrid' => [
                'free_tier' => 100,                                 // Emails per day
                'essentials' => ['emails' => 50000, 'cost' => 19.95], // Per month
            ],
        ],

        // Database pricing
        'database' => [
            'per_gb_month' => env('PRICING_DB_GB', 0.20),           // Per GB storage per month
            'backup_per_gb' => env('PRICING_DB_BACKUP_GB', 0.10),   // Per GB backup per month
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Budget Configuration
    |--------------------------------------------------------------------------
    */

    'budgets' => [
        // Monthly budget allocations
        'monthly' => [
            'total' => env('BUDGET_MONTHLY_TOTAL', 5000),
            'compute' => env('BUDGET_MONTHLY_COMPUTE', 2000),
            'storage' => env('BUDGET_MONTHLY_STORAGE', 1500),
            'network' => env('BUDGET_MONTHLY_NETWORK', 800),
            'email' => env('BUDGET_MONTHLY_EMAIL', 200),
            'database' => env('BUDGET_MONTHLY_DATABASE', 500),
        ],

        // Budget alert thresholds (percentage)
        'alert_thresholds' => [
            'warning' => 80,     // Yellow alert at 80%
            'critical' => 100,   // Red alert at 100%
            'emergency' => 120,  // Emergency at 120%
        ],

        // Cost increase alert (percentage)
        'anomaly_threshold' => 30, // Alert if cost increases >30% vs 7-day average
    ],

    /*
    |--------------------------------------------------------------------------
    | Capacity Thresholds
    |--------------------------------------------------------------------------
    */

    'capacity' => [
        // Resource utilization thresholds (percentage)
        'thresholds' => [
            'cpu' => [
                'warning' => 60,
                'high' => 75,
                'critical' => 85,
            ],
            'memory' => [
                'warning' => 60,
                'high' => 75,
                'critical' => 85,
            ],
            'disk' => [
                'warning' => 60,
                'high' => 75,
                'critical' => 85,
            ],
            'database_connections' => [
                'warning' => 60,
                'high' => 75,
                'critical' => 85,
            ],
        ],

        // Minimum headroom (days) before scaling required
        'minimum_headroom_days' => [
            'critical' => 15,   // Scale immediately
            'high' => 30,       // Scale within 1 week
            'medium' => 60,     // Scale within 1 month
            'low' => 90,        // Plan for next quarter
        ],

        // Auto-scaling configuration
        'autoscaling' => [
            'enabled' => env('AUTOSCALING_ENABLED', true),
            'scale_up_threshold' => 80,     // Scale up when >80% utilized
            'scale_down_threshold' => 40,   // Scale down when <40% utilized
            'cooldown_period' => 300,       // 5 minutes between scaling actions
            'min_instances' => 2,
            'max_instances' => 10,
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Tenant Quotas
    |--------------------------------------------------------------------------
    */

    'quotas' => [
        'free' => [
            'storage_gb' => 10,
            'vps_count' => 2,
            'sites_count' => 5,
            'bandwidth_gb_monthly' => 100,
            'database_size_gb' => 1,
            'email_monthly' => 1000,
        ],
        'starter' => [
            'storage_gb' => 50,
            'vps_count' => 5,
            'sites_count' => 20,
            'bandwidth_gb_monthly' => 500,
            'database_size_gb' => 5,
            'email_monthly' => 10000,
        ],
        'professional' => [
            'storage_gb' => 200,
            'vps_count' => 20,
            'sites_count' => 100,
            'bandwidth_gb_monthly' => 2000,
            'database_size_gb' => 20,
            'email_monthly' => 50000,
        ],
        'enterprise' => [
            'storage_gb' => 1000,
            'vps_count' => 100,
            'sites_count' => 500,
            'bandwidth_gb_monthly' => 10000,
            'database_size_gb' => 100,
            'email_monthly' => 250000,
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Cost Optimization Opportunities
    |--------------------------------------------------------------------------
    */

    'optimization' => [
        // Minimum utilization for "right-sizing" recommendation
        'underutilized_threshold' => 40,  // <40% average utilization

        // Minimum savings to generate recommendation
        'minimum_savings_threshold' => 50.00,  // $50/month

        // Recommendation priorities
        'priority' => [
            'critical' => [
                'min_savings' => 500,
                'or_conditions' => ['capacity_days' => 15],
            ],
            'high' => [
                'min_savings' => 200,
                'or_conditions' => ['capacity_days' => 30],
            ],
            'medium' => [
                'min_savings' => 100,
                'or_conditions' => ['capacity_days' => 60],
            ],
            'low' => [
                'min_savings' => 50,
            ],
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Metrics Export Configuration
    |--------------------------------------------------------------------------
    */

    'metrics' => [
        // Enable/disable metrics export
        'enabled' => env('METRICS_ENABLED', true),

        // Metrics endpoint path
        'path' => env('METRICS_PATH', '/metrics'),

        // Cache TTL (seconds)
        'cache_ttl' => env('METRICS_CACHE_TTL', 60),

        // Metrics to export
        'export' => [
            'cost' => true,
            'capacity' => true,
            'tenant' => true,
            'optimization' => true,
        ],

        // Metrics labels
        'labels' => [
            'service' => env('APP_NAME', 'chom'),
            'environment' => env('APP_ENV', 'production'),
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Reporting Configuration
    |--------------------------------------------------------------------------
    */

    'reporting' => [
        // Enable automated reporting
        'enabled' => env('REPORTING_ENABLED', true),

        // Report recipients
        'recipients' => [
            'daily' => explode(',', env('REPORT_DAILY_RECIPIENTS', 'ops@example.com')),
            'weekly' => explode(',', env('REPORT_WEEKLY_RECIPIENTS', 'management@example.com')),
            'monthly' => explode(',', env('REPORT_MONTHLY_RECIPIENTS', 'cfo@example.com,cto@example.com')),
        ],

        // Report schedule
        'schedule' => [
            'daily' => '08:00',      // 8 AM daily
            'weekly' => 'monday 09:00',  // Monday 9 AM
            'monthly' => 'first day of month 10:00', // First of month 10 AM
        ],

        // Report retention (days)
        'retention' => [
            'daily' => 30,
            'weekly' => 90,
            'monthly' => 365,
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Alert Configuration
    |--------------------------------------------------------------------------
    */

    'alerts' => [
        // Enable alerts
        'enabled' => env('ALERTS_ENABLED', true),

        // Alert channels
        'channels' => [
            'email' => env('ALERT_EMAIL_ENABLED', true),
            'slack' => env('ALERT_SLACK_ENABLED', true),
            'pagerduty' => env('ALERT_PAGERDUTY_ENABLED', false),
        ],

        // Slack configuration
        'slack' => [
            'webhook_url' => env('SLACK_WEBHOOK_URL'),
            'channel' => env('SLACK_ALERT_CHANNEL', '#infrastructure-costs'),
            'username' => env('SLACK_ALERT_USERNAME', 'CHOM Cost Monitor'),
        ],

        // PagerDuty configuration
        'pagerduty' => [
            'integration_key' => env('PAGERDUTY_INTEGRATION_KEY'),
            'severity_mapping' => [
                'critical' => 'critical',
                'high' => 'error',
                'medium' => 'warning',
                'low' => 'info',
            ],
        ],

        // Alert throttling (minutes)
        'throttle' => [
            'critical' => 5,      // Max 1 alert per 5 minutes
            'high' => 15,         // Max 1 alert per 15 minutes
            'medium' => 60,       // Max 1 alert per hour
            'low' => 240,         // Max 1 alert per 4 hours
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Forecast Configuration
    |--------------------------------------------------------------------------
    */

    'forecast' => [
        // Forecast periods (days)
        'periods' => [7, 14, 30, 60, 90],

        // Default forecast period
        'default_period' => 30,

        // Minimum data points required for forecast
        'minimum_data_points' => 7,

        // Forecast algorithm
        'algorithm' => 'linear',  // linear, exponential, holt-winters

        // Confidence interval
        'confidence_interval' => 0.95,

        // Adjust for seasonal patterns
        'seasonal_adjustment' => true,

        // Exclude anomalies from forecast
        'exclude_anomalies' => true,
    ],

    /*
    |--------------------------------------------------------------------------
    | Data Retention
    |--------------------------------------------------------------------------
    */

    'retention' => [
        // Metrics retention (days)
        'metrics' => [
            'raw' => 7,           // Keep raw metrics for 7 days
            'hourly' => 30,       // Keep hourly aggregates for 30 days
            'daily' => 90,        // Keep daily aggregates for 90 days
            'monthly' => 365,     // Keep monthly aggregates for 1 year
        ],

        // Cost data retention (days)
        'cost_data' => 1095,      // 3 years for compliance

        // Capacity data retention (days)
        'capacity_data' => 365,   // 1 year

        // Recommendation history (days)
        'recommendations' => 180, // 6 months
    ],

    /*
    |--------------------------------------------------------------------------
    | External Integrations
    |--------------------------------------------------------------------------
    */

    'integrations' => [
        // JIRA integration for scaling recommendations
        'jira' => [
            'enabled' => env('JIRA_ENABLED', false),
            'url' => env('JIRA_URL'),
            'username' => env('JIRA_USERNAME'),
            'api_token' => env('JIRA_API_TOKEN'),
            'project' => env('JIRA_PROJECT', 'INFRA'),
            'auto_create_tickets' => env('JIRA_AUTO_CREATE', false),
        ],

        // Cloud provider cost APIs
        'cloud_providers' => [
            'aws' => [
                'enabled' => env('AWS_COST_API_ENABLED', false),
                'access_key' => env('AWS_ACCESS_KEY_ID'),
                'secret_key' => env('AWS_SECRET_ACCESS_KEY'),
            ],
            'gcp' => [
                'enabled' => env('GCP_COST_API_ENABLED', false),
                'credentials_path' => env('GCP_CREDENTIALS_PATH'),
            ],
        ],
    ],
];
