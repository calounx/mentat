<?php

declare(strict_types=1);

namespace App\Livewire\Admin;

use App\Models\SystemSetting;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
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

    // Email settings (editable)
    public string $mailMailer = 'smtp';
    public string $mailHost = '127.0.0.1';
    public int $mailPort = 587;
    public string $mailUsername = '';
    public string $mailPassword = '';
    public string $mailEncryption = 'tls';
    public string $mailFromAddress = '';
    public string $mailFromName = '';

    public ?string $error = null;
    public ?string $success = null;
    public ?string $testEmailResult = null;

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

        // Email settings (from database)
        $this->mailMailer = SystemSetting::get('mail.mailer', 'smtp');
        $this->mailHost = SystemSetting::get('mail.host', '127.0.0.1');
        $this->mailPort = (int) SystemSetting::get('mail.port', 587);
        $this->mailUsername = SystemSetting::get('mail.username', '');
        $this->mailPassword = SystemSetting::get('mail.password', '');
        $this->mailEncryption = SystemSetting::get('mail.encryption', 'tls');
        $this->mailFromAddress = SystemSetting::get('mail.from_address', 'noreply@example.com');
        $this->mailFromName = SystemSetting::get('mail.from_name', 'CHOM');
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

    public function saveMailSettings(): void
    {
        $this->error = null;
        $this->success = null;
        $this->testEmailResult = null;

        // Validate
        $this->validate([
            'mailMailer' => 'required|string',
            'mailHost' => 'required|string',
            'mailPort' => 'required|integer|min:1|max:65535',
            'mailUsername' => 'nullable|string',
            'mailPassword' => 'nullable|string',
            'mailEncryption' => 'required|in:tls,ssl,null',
            'mailFromAddress' => 'required|email',
            'mailFromName' => 'required|string',
        ]);

        try {
            // Save to database
            SystemSetting::set('mail.mailer', $this->mailMailer, 'string', 'Mail driver');
            SystemSetting::set('mail.host', $this->mailHost, 'string', 'SMTP host');
            SystemSetting::set('mail.port', (string) $this->mailPort, 'integer', 'SMTP port');
            SystemSetting::set('mail.username', $this->mailUsername, 'string', 'SMTP username');
            SystemSetting::set('mail.password', $this->mailPassword, 'encrypted', 'SMTP password');
            SystemSetting::set('mail.encryption', $this->mailEncryption, 'string', 'SMTP encryption');
            SystemSetting::set('mail.from_address', $this->mailFromAddress, 'string', 'From email address');
            SystemSetting::set('mail.from_name', $this->mailFromName, 'string', 'From name');

            // Update runtime config
            Config::set('mail.default', $this->mailMailer);
            Config::set('mail.mailers.smtp.host', $this->mailHost);
            Config::set('mail.mailers.smtp.port', $this->mailPort);
            Config::set('mail.mailers.smtp.username', $this->mailUsername);
            Config::set('mail.mailers.smtp.password', $this->mailPassword);
            Config::set('mail.mailers.smtp.encryption', $this->mailEncryption === 'null' ? null : $this->mailEncryption);
            Config::set('mail.from.address', $this->mailFromAddress);
            Config::set('mail.from.name', $this->mailFromName);

            $this->success = 'Mail settings saved successfully.';
        } catch (\Exception $e) {
            Log::error('Mail settings save error', ['error' => $e->getMessage()]);
            $this->error = 'Failed to save mail settings: ' . $e->getMessage();
        }
    }

    public function testEmailConnection(): void
    {
        $this->error = null;
        $this->success = null;
        $this->testEmailResult = null;

        // Update runtime config with current form values
        Config::set('mail.default', $this->mailMailer);
        Config::set('mail.mailers.smtp.host', $this->mailHost);
        Config::set('mail.mailers.smtp.port', $this->mailPort);
        Config::set('mail.mailers.smtp.username', $this->mailUsername);
        Config::set('mail.mailers.smtp.password', $this->mailPassword);
        Config::set('mail.mailers.smtp.encryption', $this->mailEncryption === 'null' ? null : $this->mailEncryption);
        Config::set('mail.from.address', $this->mailFromAddress);
        Config::set('mail.from.name', $this->mailFromName);

        try {
            // Send test email
            Mail::raw('This is a test email from CHOM system.', function ($message) {
                $message->to($this->mailFromAddress)
                    ->subject('CHOM Test Email - ' . now()->format('Y-m-d H:i:s'));
            });

            $this->testEmailResult = '✓ Test email sent successfully to ' . $this->mailFromAddress;
        } catch (\Exception $e) {
            Log::error('Test email failed', ['error' => $e->getMessage()]);
            $this->testEmailResult = '✗ Failed: ' . $e->getMessage();
        }
    }

    public function getSystemInfo(): array
    {
        // Get Livewire version from composer
        $livewireVersion = 'Unknown';
        $composerLock = base_path('composer.lock');
        if (file_exists($composerLock)) {
            $lock = json_decode(file_get_contents($composerLock), true);
            foreach ($lock['packages'] ?? [] as $package) {
                if ($package['name'] === 'livewire/livewire') {
                    $livewireVersion = $package['version'];
                    break;
                }
            }
        }

        // Get Git commit hash
        $gitCommit = $this->getGitCommit();

        return [
            'chom_version' => config('chom.version', '2.0.0'),
            'git_commit' => $gitCommit,
            'php_version' => PHP_VERSION,
            'laravel_version' => app()->version(),
            'livewire_version' => $livewireVersion,
            'os' => php_uname('s') . ' ' . php_uname('r'),
            'server' => $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown',
            'memory_limit' => ini_get('memory_limit'),
            'max_execution_time' => ini_get('max_execution_time') . 's',
            'upload_max_filesize' => ini_get('upload_max_filesize'),
            'timezone' => config('app.timezone'),
        ];
    }

    private function getGitCommit(): string
    {
        // Try to read from a VERSION file (created during deployment)
        $versionFile = base_path('VERSION');
        if (file_exists($versionFile)) {
            return trim(file_get_contents($versionFile));
        }

        // Try to get from Git directly
        $gitHead = base_path('.git/HEAD');
        if (file_exists($gitHead)) {
            $head = trim(file_get_contents($gitHead));
            if (str_starts_with($head, 'ref: ')) {
                $refPath = base_path('.git/' . substr($head, 5));
                if (file_exists($refPath)) {
                    return substr(trim(file_get_contents($refPath)), 0, 7);
                }
            } else {
                return substr($head, 0, 7);
            }
        }

        return 'Unknown';
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

    private function formatBytes(int|float $bytes, int $precision = 2): string
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
