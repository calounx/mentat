<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\File;
use App\Services\Security\SecurityMonitor;

class SecurityScan extends Command
{
    protected $signature = 'security:scan
                          {--fix : Attempt to fix issues automatically}';

    protected $description = 'Run security scan on the application';

    protected SecurityMonitor $securityMonitor;
    protected int $issues = 0;
    protected int $warnings = 0;

    public function __construct(SecurityMonitor $securityMonitor)
    {
        parent::__construct();
        $this->securityMonitor = $securityMonitor;
    }

    public function handle(): int
    {
        $this->info('===========================================');
        $this->info('  SECURITY SCAN');
        $this->info('===========================================');
        $this->newLine();

        $this->checkDebugMode();
        $this->checkEnvironmentFile();
        $this->checkStoragePermissions();
        $this->checkSshKeys();
        $this->checkSslConfiguration();
        $this->checkDependencies();
        $this->checkSensitiveFiles();
        $this->checkSecurityHeaders();

        $this->newLine();
        $this->info('===========================================');
        $this->info('  SCAN SUMMARY');
        $this->info('===========================================');

        if ($this->issues === 0 && $this->warnings === 0) {
            $this->info('✓ No security issues found!');
            return Command::SUCCESS;
        }

        if ($this->issues === 0) {
            $this->warn("✓ Scan completed with {$this->warnings} warning(s)");
            return Command::SUCCESS;
        }

        $this->error("✗ Found {$this->issues} security issue(s) and {$this->warnings} warning(s)");
        return Command::FAILURE;
    }

    protected function checkDebugMode(): void
    {
        $this->info('Checking debug mode...');

        if (config('app.debug') && config('app.env') === 'production') {
            $this->error('Debug mode is enabled in production');
            $this->issues++;
        } else {
            $this->success('Debug mode properly configured');
        }
    }

    protected function checkEnvironmentFile(): void
    {
        $this->info('Checking .env file security...');

        $envPath = base_path('.env');

        if (file_exists($envPath)) {
            $permissions = substr(sprintf('%o', fileperms($envPath)), -4);

            if ($permissions !== '0600' && $permissions !== '0640') {
                $this->warn(".env file has loose permissions: {$permissions}");
                $this->warnings++;

                if ($this->option('fix')) {
                    chmod($envPath, 0600);
                    $this->info('Fixed: Set .env permissions to 0600');
                }
            } else {
                $this->success('.env file permissions are secure');
            }

            // Check if .env contains sensitive data
            $content = file_get_contents($envPath);
            if (strpos($content, 'password=root') !== false || strpos($content, 'password=password') !== false) {
                $this->warn('.env contains default passwords');
                $this->warnings++;
            }
        } else {
            $this->error('.env file not found');
            $this->issues++;
        }
    }

    protected function checkStoragePermissions(): void
    {
        $this->info('Checking storage permissions...');

        $paths = [
            storage_path(),
            storage_path('app'),
            storage_path('logs'),
        ];

        foreach ($paths as $path) {
            $permissions = substr(sprintf('%o', fileperms($path)), -4);

            if ($permissions === '0777') {
                $this->warn("{$path} has insecure permissions (777)");
                $this->warnings++;

                if ($this->option('fix')) {
                    chmod($path, 0775);
                    $this->info("Fixed: Set {$path} permissions to 0775");
                }
            } elseif (!is_writable($path)) {
                $this->error("{$path} is not writable");
                $this->issues++;
            } else {
                $this->success("{$path} permissions are acceptable");
            }
        }
    }

    protected function checkSshKeys(): void
    {
        $this->info('Checking SSH keys...');

        $sshPath = storage_path('app/ssh');

        if (!is_dir($sshPath)) {
            $this->success('No SSH keys directory found');
            return;
        }

        $keys = File::glob($sshPath . '/*.pem');

        foreach ($keys as $key) {
            $age = $this->securityMonitor->checkSshKeyAge($key);

            if ($age && $age > 365) {
                $this->warn(basename($key) . " is {$age} days old");
                $this->warnings++;
            }

            $permissions = substr(sprintf('%o', fileperms($key)), -4);

            if ($permissions !== '0600') {
                $this->error(basename($key) . " has insecure permissions: {$permissions}");
                $this->issues++;

                if ($this->option('fix')) {
                    chmod($key, 0600);
                    $this->info('Fixed: Set ' . basename($key) . ' permissions to 0600');
                }
            }
        }
    }

    protected function checkSslConfiguration(): void
    {
        $this->info('Checking SSL configuration...');

        if (config('app.env') !== 'production') {
            $this->success('SSL check skipped (not production)');
            return;
        }

        if (!str_starts_with(config('app.url'), 'https://')) {
            $this->warn('APP_URL does not use HTTPS');
            $this->warnings++;
        }

        if (!config('session.secure')) {
            $this->warn('Session cookies are not secure');
            $this->warnings++;
        }
    }

    protected function checkDependencies(): void
    {
        $this->info('Checking for known vulnerabilities...');

        // Run composer audit
        exec('composer audit --format=json 2>&1', $output, $returnCode);

        if ($returnCode === 0) {
            $this->success('No known vulnerabilities in dependencies');
        } else {
            $this->warn('Potential vulnerabilities detected - run "composer audit" for details');
            $this->warnings++;
        }
    }

    protected function checkSensitiveFiles(): void
    {
        $this->info('Checking for exposed sensitive files...');

        $sensitiveFiles = [
            '.env',
            '.env.backup',
            '.git/config',
            'composer.json',
            'composer.lock',
            'phpunit.xml',
        ];

        foreach ($sensitiveFiles as $file) {
            $publicPath = public_path($file);

            if (file_exists($publicPath)) {
                $this->error("Sensitive file exposed in public directory: {$file}");
                $this->issues++;
            }
        }

        $this->success('No sensitive files exposed in public directory');
    }

    protected function checkSecurityHeaders(): void
    {
        $this->info('Checking security headers configuration...');

        $url = config('app.url');

        if (!str_starts_with($url, 'http')) {
            $this->warn('Cannot check headers - invalid APP_URL');
            return;
        }

        try {
            $headers = get_headers($url, 1);

            $requiredHeaders = [
                'X-Frame-Options',
                'X-Content-Type-Options',
                'X-XSS-Protection',
            ];

            foreach ($requiredHeaders as $header) {
                if (!isset($headers[$header])) {
                    $this->warn("Missing security header: {$header}");
                    $this->warnings++;
                }
            }
        } catch (\Exception $e) {
            $this->warn('Could not check security headers: ' . $e->getMessage());
        }
    }

    protected function success(string $message): void
    {
        $this->line("  <fg=green>✓</> {$message}");
    }

    protected function error(string $message): void
    {
        $this->issues++;
        $this->line("  <fg=red>✗</> {$message}");
    }

    protected function warn(string $message): void
    {
        $this->warnings++;
        $this->line("  <fg=yellow>⚠</> {$message}");
    }
}
