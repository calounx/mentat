<?php

declare(strict_types=1);

namespace App\Livewire\Admin;

use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Log;
use Livewire\Component;

class SystemSettings extends Component
{
    // General settings
    public string $appName = '';
    public string $appEnv = '';
    public bool $appDebug = false;

    // Default site settings
    public string $defaultPhpVersion = '8.2';
    public int $defaultBackupRetentionDays = 30;
    public int $defaultMetricsRetentionDays = 15;

    // Email settings (display only for security)
    public string $mailDriver = '';
    public string $mailFromAddress = '';
    public string $mailFromName = '';

    public ?string $error = null;
    public ?string $success = null;

    public function mount(): void
    {
        $this->loadSettings();
    }

    private function loadSettings(): void
    {
        // Load current config values
        $this->appName = config('app.name', 'CHOM');
        $this->appEnv = config('app.env', 'production');
        $this->appDebug = config('app.debug', false);

        // Default site settings from config or DB
        $this->defaultPhpVersion = config('chom.default_php_version', '8.2');
        $this->defaultBackupRetentionDays = (int) config('chom.backup_retention_days', 30);
        $this->defaultMetricsRetentionDays = (int) config('chom.metrics_retention_days', 15);

        // Email settings (display only)
        $this->mailDriver = config('mail.default', 'smtp');
        $this->mailFromAddress = config('mail.from.address', '');
        $this->mailFromName = config('mail.from.name', '');
    }

    public function clearCache(): void
    {
        try {
            Artisan::call('cache:clear');
            Artisan::call('config:clear');
            Artisan::call('view:clear');
            Artisan::call('route:clear');

            $this->success = 'All caches cleared successfully.';
        } catch (\Exception $e) {
            Log::error('Cache clear error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to clear caches: ' . $e->getMessage();
        }
    }

    public function optimizeApplication(): void
    {
        try {
            Artisan::call('config:cache');
            Artisan::call('route:cache');
            Artisan::call('view:cache');

            $this->success = 'Application optimized successfully.';
        } catch (\Exception $e) {
            Log::error('Optimize error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to optimize application: ' . $e->getMessage();
        }
    }

    public function runMigrations(): void
    {
        try {
            Artisan::call('migrate', ['--force' => true]);
            $output = Artisan::output();

            $this->success = 'Migrations completed. ' . $output;
        } catch (\Exception $e) {
            Log::error('Migration error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to run migrations: ' . $e->getMessage();
        }
    }

    public function getSystemInfo(): array
    {
        return [
            'php_version' => PHP_VERSION,
            'laravel_version' => app()->version(),
            'livewire_version' => \Livewire\Livewire::VERSION ?? 'Unknown',
            'os' => php_uname('s') . ' ' . php_uname('r'),
            'server' => $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown',
            'memory_limit' => ini_get('memory_limit'),
            'max_execution_time' => ini_get('max_execution_time') . 's',
            'upload_max_filesize' => ini_get('upload_max_filesize'),
            'timezone' => config('app.timezone'),
        ];
    }

    public function getStorageStats(): array
    {
        $storagePath = storage_path();
        $totalSpace = disk_total_space($storagePath);
        $freeSpace = disk_free_space($storagePath);
        $usedSpace = $totalSpace - $freeSpace;

        return [
            'total' => $this->formatBytes($totalSpace),
            'used' => $this->formatBytes($usedSpace),
            'free' => $this->formatBytes($freeSpace),
            'percent_used' => round(($usedSpace / $totalSpace) * 100, 1),
        ];
    }

    public function getDatabaseStats(): array
    {
        try {
            $connection = config('database.default');
            $driver = config("database.connections.{$connection}.driver");

            $stats = [
                'connection' => $connection,
                'driver' => $driver,
            ];

            if ($driver === 'sqlite') {
                $dbPath = config("database.connections.{$connection}.database");
                if (file_exists($dbPath)) {
                    $stats['size'] = $this->formatBytes(filesize($dbPath));
                }
            }

            return $stats;
        } catch (\Exception $e) {
            return ['error' => 'Failed to get database stats'];
        }
    }

    private function formatBytes(int $bytes, int $precision = 2): string
    {
        $units = ['B', 'KB', 'MB', 'GB', 'TB'];
        $bytes = max($bytes, 0);
        $pow = floor(($bytes ? log($bytes) : 0) / log(1024));
        $pow = min($pow, count($units) - 1);
        $bytes /= pow(1024, $pow);

        return round($bytes, $precision) . ' ' . $units[$pow];
    }

    public function render()
    {
        return view('livewire.admin.system-settings', [
            'systemInfo' => $this->getSystemInfo(),
            'storageStats' => $this->getStorageStats(),
            'databaseStats' => $this->getDatabaseStats(),
        ])->layout('layouts.admin', ['title' => 'System Settings']);
    }
}
