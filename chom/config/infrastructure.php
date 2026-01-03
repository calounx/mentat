<?php

declare(strict_types=1);

return [
    /*
    |--------------------------------------------------------------------------
    | VPS Provider Configuration
    |--------------------------------------------------------------------------
    |
    | Configure the VPS provider used for server management.
    | Supported providers: 'local', 'digitalocean', 'vultr', 'ssh'
    |
    */
    'vps' => [
        'provider' => env('VPS_PROVIDER', 'local'),

        'timeout' => env('VPS_TIMEOUT', 300),

        'local' => [
            'user' => env('VPS_LOCAL_USER', 'root'),
            'port' => env('VPS_LOCAL_PORT', 22),
            'use_docker' => env('VPS_LOCAL_USE_DOCKER', true),
        ],

        'digitalocean' => [
            'token' => env('DIGITALOCEAN_TOKEN'),
            'ssh_key_id' => env('DIGITALOCEAN_SSH_KEY_ID'),
        ],

        'vultr' => [
            'api_key' => env('VULTR_API_KEY'),
        ],

        'ssh' => [
            'port' => env('SSH_PORT', 22),
            'private_key_path' => env('SSH_PRIVATE_KEY_PATH'),
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Observability Configuration
    |--------------------------------------------------------------------------
    |
    | Configure metrics, tracing, and monitoring.
    | Supported drivers: 'prometheus', 'grafana', 'null'
    |
    */
    'observability' => [
        'driver' => env('OBSERVABILITY_DRIVER', 'null'),

        'prometheus' => [
            'push_gateway_url' => env('PROMETHEUS_PUSH_GATEWAY_URL'),
            'namespace' => env('PROMETHEUS_NAMESPACE', 'chom'),
            'buffer_size' => env('PROMETHEUS_BUFFER_SIZE', 100),
        ],

        'grafana' => [
            'cloud_url' => env('GRAFANA_CLOUD_URL'),
            'api_key' => env('GRAFANA_API_KEY'),
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Notification Configuration
    |--------------------------------------------------------------------------
    |
    | Configure notification channels and settings.
    | Available channels: 'email', 'sms', 'slack', 'webhook', 'log'
    |
    */
    'notifications' => [
        'channels' => array_filter(explode(',', env('NOTIFICATION_CHANNELS', 'log'))),

        'fail_silently' => env('NOTIFICATION_FAIL_SILENTLY', true),

        'email' => [
            'from' => env('MAIL_FROM_ADDRESS', 'noreply@chom.app'),
            'from_name' => env('MAIL_FROM_NAME', 'CHOM'),
        ],

        'slack' => [
            'webhook_url' => env('SLACK_WEBHOOK_URL'),
            'default_channel' => env('SLACK_DEFAULT_CHANNEL', '#general'),
        ],

        'sms' => [
            'provider' => env('SMS_PROVIDER', 'twilio'),
            'from' => env('SMS_FROM_NUMBER'),
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Storage Configuration
    |--------------------------------------------------------------------------
    |
    | Configure file storage backend.
    | Supported drivers: 'local', 's3', 'digitalocean_spaces'
    |
    */
    'storage' => [
        'driver' => env('STORAGE_DRIVER', 'local'),

        'local' => [
            'disk' => 'local',
            'visibility' => 'private',
        ],

        's3' => [
            'disk' => 's3',
            'visibility' => env('S3_VISIBILITY', 'private'),
            'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
            'bucket' => env('AWS_BUCKET'),
        ],

        'digitalocean_spaces' => [
            'disk' => 'spaces',
            'visibility' => env('SPACES_VISIBILITY', 'private'),
            'region' => env('SPACES_REGION', 'nyc3'),
            'bucket' => env('SPACES_BUCKET'),
        ],
    ],
];
