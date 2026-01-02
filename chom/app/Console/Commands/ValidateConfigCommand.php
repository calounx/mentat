<?php

namespace App\Console\Commands;

use Exception;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;

class ValidateConfigCommand extends Command
{
    protected $signature = 'config:validate
                          {--strict : Fail on warnings}
                          {--fix : Attempt to fix issues automatically}';

    protected $description = 'Validate application configuration and dependencies';

    protected int $errors = 0;

    protected int $warnings = 0;

    protected array $fixes = [];

    public function handle(): int
    {
        $this->info('===========================================');
        $this->info('  APPLICATION CONFIGURATION VALIDATION');
        $this->info('===========================================');
        $this->newLine();

        // Run all checks
        $this->checkPhpVersion();
        $this->checkPhpExtensions();
        $this->checkEnvironmentVariables();
        $this->checkDatabaseConnection();
        $this->checkRedisConnection();
        $this->checkFilePermissions();
        $this->checkStorageDirectories();
        $this->checkCacheConfiguration();
        $this->checkQueueConfiguration();
        $this->checkSecurityConfiguration();
        $this->checkSslConfiguration();
        $this->checkExternalServices();

        // Summary
        $this->newLine();
        $this->info('===========================================');
        $this->info('  VALIDATION SUMMARY');
        $this->info('===========================================');

        if ($this->errors === 0 && $this->warnings === 0) {
            $this->info('✓ All checks passed!');

            return Command::SUCCESS;
        }

        if ($this->errors === 0) {
            $this->warn("✓ Passed with {$this->warnings} warning(s)");

            return $this->option('strict') ? Command::FAILURE : Command::SUCCESS;
        }

        $this->error("✗ Failed with {$this->errors} error(s) and {$this->warnings} warning(s)");

        if (! empty($this->fixes)) {
            $this->newLine();
            $this->info('Suggested fixes:');
            foreach ($this->fixes as $fix) {
                $this->line("  - {$fix}");
            }
        }

        return Command::FAILURE;
    }

    protected function checkPhpVersion(): void
    {
        $this->info('Checking PHP version...');

        $requiredVersion = '8.2.0';
        $currentVersion = PHP_VERSION;

        if (version_compare($currentVersion, $requiredVersion, '>=')) {
            $this->success("PHP version: {$currentVersion}");
        } else {
            $this->reportError("PHP version {$currentVersion} is too old (requires >= {$requiredVersion})");
            $this->fixes[] = "Upgrade PHP to version {$requiredVersion} or higher";
        }
    }

    protected function checkPhpExtensions(): void
    {
        $this->info('Checking PHP extensions...');

        $required = ['mbstring', 'xml', 'bcmath', 'curl', 'gd', 'zip', 'pdo', 'tokenizer', 'ctype', 'json', 'openssl'];
        $optional = ['redis', 'imagick', 'intl'];

        foreach ($required as $ext) {
            if (extension_loaded($ext)) {
                $this->success("Required extension: {$ext}");
            } else {
                $this->reportError("Missing required extension: {$ext}");
                $this->fixes[] = "Install PHP extension: {$ext}";
            }
        }

        foreach ($optional as $ext) {
            if (extension_loaded($ext)) {
                $this->success("Optional extension: {$ext}");
            } else {
                $this->reportWarning("Missing optional extension: {$ext}");
            }
        }
    }

    protected function checkEnvironmentVariables(): void
    {
        $this->info('Checking environment variables...');

        $required = [
            'APP_NAME',
            'APP_KEY',
            'APP_ENV',
            'APP_URL',
            'DB_CONNECTION',
            'DB_DATABASE',
            'REDIS_HOST',
        ];

        foreach ($required as $var) {
            $value = config(strtolower(str_replace('_', '.', $var)));

            if (! empty($value)) {
                // Don't display sensitive values
                $displayValue = in_array($var, ['APP_KEY', 'DB_PASSWORD']) ? '****' : $value;
                $this->success("{$var}: {$displayValue}");
            } else {
                $this->reportError("Missing or empty: {$var}");
                $this->fixes[] = "Set {$var} in .env file";
            }
        }

        // Check APP_KEY format
        $appKey = config('app.key');
        if ($appKey && ! str_starts_with($appKey, 'base64:')) {
            $this->reportWarning('APP_KEY should be base64 encoded');
            $this->fixes[] = 'Run: php artisan key:generate';
        }
    }

    protected function checkDatabaseConnection(): void
    {
        $this->info('Checking database connection...');

        try {
            DB::connection()->getPdo();
            $dbName = DB::connection()->getDatabaseName();
            $this->success("Connected to database: {$dbName}");

            // Check tables exist
            $tables = DB::connection()->getDoctrineSchemaManager()->listTableNames();
            if (count($tables) > 0) {
                $this->success('Found '.count($tables).' table(s)');
            } else {
                $this->reportWarning('No tables found - database may not be migrated');
                $this->fixes[] = 'Run: php artisan migrate';
            }
        } catch (Exception $e) {
            $this->reportError('Cannot connect to database: '.$e->getMessage());
            $this->fixes[] = 'Check database credentials in .env file';
        }
    }

    protected function checkRedisConnection(): void
    {
        $this->info('Checking Redis connection...');

        try {
            Redis::ping();
            $this->success('Redis connection successful');

            // Check Redis info
            $info = Redis::info();
            if (isset($info['used_memory_human'])) {
                $this->success('Redis memory usage: '.$info['used_memory_human']);
            }
        } catch (Exception $e) {
            $this->reportError('Cannot connect to Redis: '.$e->getMessage());
            $this->fixes[] = 'Check Redis configuration in .env file';
            $this->fixes[] = 'Ensure Redis server is running';
        }
    }

    protected function checkFilePermissions(): void
    {
        $this->info('Checking file permissions...');

        $paths = [
            storage_path(),
            storage_path('app'),
            storage_path('framework'),
            storage_path('logs'),
            base_path('bootstrap/cache'),
        ];

        foreach ($paths as $path) {
            if (is_writable($path)) {
                $this->success("Writable: {$path}");
            } else {
                $this->reportError("Not writable: {$path}");
                $this->fixes[] = "chmod -R 775 {$path}";
                $this->fixes[] = "chown -R www-data:www-data {$path}";
            }
        }
    }

    protected function checkStorageDirectories(): void
    {
        $this->info('Checking storage directories...');

        $directories = [
            'app/backups',
            'app/public',
            'framework/cache',
            'framework/sessions',
            'framework/views',
            'logs',
        ];

        foreach ($directories as $dir) {
            $path = storage_path($dir);

            if (is_dir($path)) {
                $this->success("Directory exists: storage/{$dir}");
            } else {
                if ($this->option('fix')) {
                    mkdir($path, 0755, true);
                    $this->success("Created directory: storage/{$dir}");
                } else {
                    $this->reportWarning("Directory missing: storage/{$dir}");
                    $this->fixes[] = "mkdir -p {$path}";
                }
            }
        }
    }

    protected function checkCacheConfiguration(): void
    {
        $this->info('Checking cache configuration...');

        $driver = config('cache.default');
        $this->success("Cache driver: {$driver}");

        try {
            cache()->put('config_validation_test', 'test', 60);
            $value = cache()->get('config_validation_test');
            cache()->forget('config_validation_test');

            if ($value === 'test') {
                $this->success('Cache read/write working');
            } else {
                $this->reportError('Cache read/write failed');
            }
        } catch (Exception $e) {
            $this->reportError('Cache error: '.$e->getMessage());
        }
    }

    protected function checkQueueConfiguration(): void
    {
        $this->info('Checking queue configuration...');

        $driver = config('queue.default');
        $this->success("Queue driver: {$driver}");

        if ($driver !== 'sync') {
            // Check if queue workers are running
            exec('ps aux | grep "queue:work" | grep -v grep', $output);

            if (count($output) > 0) {
                $this->success('Queue workers running: '.count($output));
            } else {
                $this->reportWarning('No queue workers found');
                $this->fixes[] = 'Start queue workers: php artisan queue:work';
            }
        }
    }

    protected function checkSecurityConfiguration(): void
    {
        $this->info('Checking security configuration...');

        // Check debug mode
        if (config('app.debug') && config('app.env') === 'production') {
            $this->reportError('Debug mode is enabled in production');
            $this->fixes[] = 'Set APP_DEBUG=false in .env';
        } else {
            $this->success('Debug mode properly configured');
        }

        // Check HTTPS
        if (config('app.env') === 'production' && ! str_starts_with(config('app.url'), 'https://')) {
            $this->reportWarning('APP_URL should use HTTPS in production');
            $this->fixes[] = 'Set APP_URL to https:// in .env';
        }

        // Check session security
        if (config('session.secure') === false && config('app.env') === 'production') {
            $this->reportWarning('Session cookies should be secure in production');
            $this->fixes[] = 'Set SESSION_SECURE_COOKIE=true in .env';
        } else {
            $this->success('Session security configured');
        }
    }

    protected function checkSslConfiguration(): void
    {
        $this->info('Checking SSL configuration...');

        if (config('app.env') !== 'production') {
            $this->success('SSL check skipped (not production)');

            return;
        }

        $url = config('app.url');
        if (! str_starts_with($url, 'https://')) {
            $this->reportWarning('SSL not configured');

            return;
        }

        // Try to check SSL certificate
        try {
            $parsedUrl = parse_url($url);
            $host = $parsedUrl['host'] ?? null;

            if ($host) {
                $streamContext = stream_context_create([
                    'ssl' => [
                        'capture_peer_cert' => true,
                        'verify_peer' => false,
                        'verify_peer_name' => false,
                    ],
                ]);

                $client = @stream_socket_client(
                    "ssl://{$host}:443",
                    $errno,
                    $errstr,
                    10,
                    STREAM_CLIENT_CONNECT,
                    $streamContext
                );

                if ($client) {
                    $params = stream_context_get_params($client);
                    $cert = openssl_x509_parse($params['options']['ssl']['peer_certificate']);

                    $expiryDate = $cert['validTo_time_t'];
                    $daysUntilExpiry = ($expiryDate - time()) / 86400;

                    if ($daysUntilExpiry > 30) {
                        $this->success('SSL certificate valid for '.round($daysUntilExpiry).' days');
                    } elseif ($daysUntilExpiry > 0) {
                        $this->reportWarning('SSL certificate expires in '.round($daysUntilExpiry).' days');
                        $this->fixes[] = 'Renew SSL certificate soon';
                    } else {
                        $this->reportError('SSL certificate has expired');
                        $this->fixes[] = 'Renew SSL certificate immediately';
                    }
                } else {
                    $this->warn("Could not connect to {$host}:443");
                }
            }
        } catch (Exception $e) {
            $this->warn('Could not check SSL certificate: '.$e->getMessage());
        }
    }

    protected function checkExternalServices(): void
    {
        $this->info('Checking external services...');

        // Check if Stripe is configured (if using payments)
        if (config('services.stripe.key')) {
            $this->success('Stripe configured');
        } else {
            $this->warn('Stripe not configured (skip if not using payments)');
        }
    }

    protected function success(string $message): void
    {
        $this->line("  <fg=green>✓</> {$message}");
    }

    protected function reportError(string $message): void
    {
        $this->errors++;
        $this->line("  <fg=red>✗</> {$message}");
    }

    protected function reportWarning(string $message): void
    {
        $this->warnings++;
        $this->line("  <fg=yellow>⚠</> {$message}");
    }
}
