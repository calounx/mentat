<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Backup Configuration
    |--------------------------------------------------------------------------
    |
    | Configuration for automated database backups.
    |
    */

    'enabled' => env('BACKUP_ENABLED', true),

    /*
    |--------------------------------------------------------------------------
    | Backup Schedule
    |--------------------------------------------------------------------------
    |
    | When to run automated backups (cron syntax).
    |
    */

    'schedule' => [
        'frequency' => env('BACKUP_FREQUENCY', 'daily'),
        'time' => env('BACKUP_TIME', '02:00'),
    ],

    /*
    |--------------------------------------------------------------------------
    | Backup Retention Policy
    |--------------------------------------------------------------------------
    |
    | How many backups to keep.
    |
    */

    'retention' => [
        'daily' => env('BACKUP_RETENTION_DAILY', 7),
        'weekly' => env('BACKUP_RETENTION_WEEKLY', 4),
        'monthly' => env('BACKUP_RETENTION_MONTHLY', 12),
    ],

    /*
    |--------------------------------------------------------------------------
    | Encryption
    |--------------------------------------------------------------------------
    |
    | Enable backup encryption for security.
    |
    */

    'encryption' => [
        'enabled' => env('BACKUP_ENCRYPTION_ENABLED', true),
        'algorithm' => 'aes-256-cbc',
    ],

    /*
    |--------------------------------------------------------------------------
    | Remote Storage
    |--------------------------------------------------------------------------
    |
    | Upload backups to remote storage for disaster recovery.
    |
    */

    'remote_storage' => [
        'enabled' => env('BACKUP_REMOTE_ENABLED', false),
        'disk' => env('BACKUP_REMOTE_DISK', 's3'),
        'path' => env('BACKUP_REMOTE_PATH', 'backups'),
    ],

    /*
    |--------------------------------------------------------------------------
    | Remote Disk Configuration
    |--------------------------------------------------------------------------
    |
    | The filesystem disk to use for remote backups.
    |
    */

    'remote_disk' => env('BACKUP_REMOTE_DISK', 's3'),

    /*
    |--------------------------------------------------------------------------
    | Backup Verification
    |--------------------------------------------------------------------------
    |
    | Test backup integrity after creation.
    |
    */

    'verification' => [
        'enabled' => env('BACKUP_VERIFICATION_ENABLED', true),
        'test_restore' => env('BACKUP_TEST_RESTORE', false),
    ],

    /*
    |--------------------------------------------------------------------------
    | Notifications
    |--------------------------------------------------------------------------
    |
    | Send notifications about backup status.
    |
    */

    'notifications' => [
        'on_success' => env('BACKUP_NOTIFY_SUCCESS', false),
        'on_failure' => env('BACKUP_NOTIFY_FAILURE', true),
    ],

    /*
    |--------------------------------------------------------------------------
    | Compression
    |--------------------------------------------------------------------------
    |
    | Compress backups to save space.
    |
    */

    'compression' => [
        'enabled' => env('BACKUP_COMPRESSION_ENABLED', false),
        'method' => 'gzip', // gzip, bzip2, zip
    ],

];
