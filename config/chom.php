<?php

return [
    /*
    |--------------------------------------------------------------------------
    | CHOM Platform Settings
    |--------------------------------------------------------------------------
    */

    'name' => env('CHOM_NAME', 'CHOM'),
    'version' => '2.0.0',

    /*
    |--------------------------------------------------------------------------
    | SSH Configuration
    |--------------------------------------------------------------------------
    */

    // Use absolute path to shared storage (persists across deployments)
    'ssh_key_path' => env('CHOM_SSH_KEY_PATH', '/var/www/chom/shared/storage/app/ssh/chom_deploy_key'),

    // SSH user for VPSManager operations (stilgar for all servers)
    'ssh_user' => env('CHOM_SSH_USER', 'stilgar'),

    /*
    |--------------------------------------------------------------------------
    | Observability Stack
    |--------------------------------------------------------------------------
    */

    'observability' => [
        'prometheus_url' => env('CHOM_PROMETHEUS_URL', 'http://localhost:9090'),
        'loki_url' => env('CHOM_LOKI_URL', 'http://localhost:3100'),
        'grafana_url' => env('CHOM_GRAFANA_URL', 'http://localhost:3000'),
        'grafana_api_key' => env('CHOM_GRAFANA_API_KEY'),
    ],

    /*
    |--------------------------------------------------------------------------
    | Billing Tiers
    |--------------------------------------------------------------------------
    */

    'tiers' => [
        'starter' => [
            'name' => 'Starter',
            'stripe_price_id' => env('STRIPE_STARTER_PRICE_ID'),
            'price_monthly' => 29.00,
            'limits' => [
                'sites' => 5,
                'storage_gb' => 10,
                'bandwidth_gb' => 100,
                'backups_retention_days' => 7,
            ],
            'features' => [
                'ssl_certificates' => true,
                'daily_backups' => true,
                'staging_environments' => false,
                'white_label' => false,
                'priority_support' => false,
            ],
        ],
        'pro' => [
            'name' => 'Pro',
            'stripe_price_id' => env('STRIPE_PRO_PRICE_ID'),
            'price_monthly' => 79.00,
            'limits' => [
                'sites' => 25,
                'storage_gb' => 100,
                'bandwidth_gb' => 500,
                'backups_retention_days' => 30,
            ],
            'features' => [
                'ssl_certificates' => true,
                'daily_backups' => true,
                'staging_environments' => true,
                'white_label' => false,
                'priority_support' => true,
            ],
        ],
        'enterprise' => [
            'name' => 'Enterprise',
            'stripe_price_id' => env('STRIPE_ENTERPRISE_PRICE_ID'),
            'price_monthly' => 249.00,
            'limits' => [
                'sites' => -1, // unlimited
                'storage_gb' => -1,
                'bandwidth_gb' => -1,
                'backups_retention_days' => 90,
            ],
            'features' => [
                'ssl_certificates' => true,
                'daily_backups' => true,
                'staging_environments' => true,
                'white_label' => true,
                'priority_support' => true,
                'dedicated_ip' => true,
                'sla_guarantee' => true,
            ],
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Usage Metering
    |--------------------------------------------------------------------------
    */

    'usage_metering' => [
        'extra_site' => [
            'stripe_price_id' => env('STRIPE_EXTRA_SITE_PRICE_ID'),
            'unit_amount' => 5.00, // per site per month
        ],
        'extra_storage' => [
            'stripe_price_id' => env('STRIPE_EXTRA_STORAGE_PRICE_ID'),
            'unit_amount' => 0.10, // per GB per month
        ],
        'extra_bandwidth' => [
            'stripe_price_id' => env('STRIPE_EXTRA_BANDWIDTH_PRICE_ID'),
            'unit_amount' => 0.05, // per GB
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | VPS Fleet Settings
    |--------------------------------------------------------------------------
    */

    'vps' => [
        'default_memory_per_site_mb' => 256,
        'max_sites_per_shared_vps' => 50,
        'health_check_interval_seconds' => 300,
        'auto_scale_threshold_percent' => 70,
    ],

    /*
    |--------------------------------------------------------------------------
    | Default Site Settings
    |--------------------------------------------------------------------------
    */

    'sites' => [
        'default_php_version' => '8.2',
        'supported_php_versions' => ['8.2', '8.4'],
        'auto_ssl' => true,
        'auto_backup' => true,
        'backup_retention_days' => 7,
    ],
];
