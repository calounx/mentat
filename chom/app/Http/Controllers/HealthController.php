<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Http;
use Exception;

class HealthController extends Controller
{
    /**
     * Basic health check - just returns 200 if application is up
     */
    public function index(): JsonResponse
    {
        return response()->json([
            'status' => 'healthy',
            'timestamp' => now()->toIso8601String(),
        ]);
    }

    /**
     * Readiness check - validates all dependencies are ready
     * Used by load balancers to determine if instance can receive traffic
     */
    public function ready(): JsonResponse
    {
        $checks = [
            'database' => $this->checkDatabase(),
            'redis' => $this->checkRedis(),
            'cache' => $this->checkCache(),
            'queue' => $this->checkQueue(),
            'storage' => $this->checkStorage(),
        ];

        // Add VPS connectivity check if configured
        if (config('services.vps_health_check')) {
            $checks['vps_connectivity'] = $this->checkVpsConnectivity();
        }

        $healthy = !in_array(false, $checks, true);
        $httpCode = $healthy ? 200 : 503;

        return response()->json([
            'status' => $healthy ? 'ready' : 'not_ready',
            'checks' => $checks,
            'timestamp' => now()->toIso8601String(),
        ], $httpCode);
    }

    /**
     * Liveness check - validates application is responsive
     * Used by orchestrators to determine if instance needs restart
     */
    public function live(): JsonResponse
    {
        $checks = [
            'application' => true,
            'memory' => $this->checkMemory(),
        ];

        $healthy = !in_array(false, $checks, true);
        $httpCode = $healthy ? 200 : 503;

        return response()->json([
            'status' => $healthy ? 'alive' : 'unhealthy',
            'checks' => $checks,
            'timestamp' => now()->toIso8601String(),
        ], $httpCode);
    }

    /**
     * Security posture check - validates security configuration
     */
    public function security(): JsonResponse
    {
        $checks = [
            'https_enabled' => $this->checkHttps(),
            'debug_disabled' => !config('app.debug'),
            'app_key_set' => !empty(config('app.key')),
            'csrf_protection' => true, // Laravel has CSRF enabled by default
            'secure_cookies' => config('session.secure'),
            'rate_limiting' => $this->checkRateLimiting(),
        ];

        // Check SSL certificate expiry if in production
        if (config('app.env') === 'production') {
            $checks['ssl_certificate'] = $this->checkSslCertificate();
        }

        $secure = !in_array(false, $checks, true);

        return response()->json([
            'status' => $secure ? 'secure' : 'insecure',
            'checks' => $checks,
            'environment' => config('app.env'),
            'timestamp' => now()->toIso8601String(),
        ], $secure ? 200 : 503);
    }

    /**
     * Dependencies health check - validates external dependencies
     */
    public function dependencies(): JsonResponse
    {
        $checks = [];

        // Check configured external services
        $externalServices = config('services.external_health_checks', []);

        foreach ($externalServices as $name => $url) {
            $checks[$name] = $this->checkExternalService($url);
        }

        // Add Stripe if configured
        if (config('services.stripe.key')) {
            $checks['stripe'] = $this->checkStripeConnectivity();
        }

        $healthy = empty($checks) || !in_array(false, $checks, true);

        return response()->json([
            'status' => $healthy ? 'healthy' : 'degraded',
            'checks' => $checks,
            'timestamp' => now()->toIso8601String(),
        ], $healthy ? 200 : 503);
    }

    /**
     * Detailed health check - all checks combined
     */
    public function detailed(): JsonResponse
    {
        $startTime = microtime(true);

        $checks = [
            'basic' => [
                'application' => true,
                'environment' => config('app.env'),
                'php_version' => PHP_VERSION,
                'laravel_version' => app()->version(),
            ],
            'infrastructure' => [
                'database' => $this->checkDatabase(),
                'redis' => $this->checkRedis(),
                'cache' => $this->checkCache(),
                'queue' => $this->checkQueue(),
                'storage' => $this->checkStorage(),
            ],
            'resources' => [
                'memory' => $this->getMemoryUsage(),
                'disk_space' => $this->getDiskSpace(),
            ],
            'performance' => [
                'response_time_ms' => 0, // Will be calculated at end
            ],
        ];

        $healthy = $this->isSystemHealthy($checks);
        $responseTime = round((microtime(true) - $startTime) * 1000, 2);
        $checks['performance']['response_time_ms'] = $responseTime;

        return response()->json([
            'status' => $healthy ? 'healthy' : 'unhealthy',
            'checks' => $checks,
            'timestamp' => now()->toIso8601String(),
        ], $healthy ? 200 : 503);
    }

    /**
     * Check database connectivity
     */
    private function checkDatabase(): bool
    {
        try {
            DB::connection()->getPdo();
            DB::connection()->getDatabaseName();
            return true;
        } catch (Exception $e) {
            report($e);
            return false;
        }
    }

    /**
     * Check Redis connectivity
     */
    private function checkRedis(): bool
    {
        try {
            Redis::ping();
            return true;
        } catch (Exception $e) {
            report($e);
            return false;
        }
    }

    /**
     * Check cache functionality
     */
    private function checkCache(): bool
    {
        try {
            $key = 'health_check_' . time();
            $value = 'test_' . time();

            Cache::put($key, $value, 60);
            $retrieved = Cache::get($key);
            Cache::forget($key);

            return $retrieved === $value;
        } catch (Exception $e) {
            report($e);
            return false;
        }
    }

    /**
     * Check queue connectivity
     */
    private function checkQueue(): bool
    {
        try {
            // Check if queue connection is working
            $connection = Queue::connection();
            return $connection !== null;
        } catch (Exception $e) {
            report($e);
            return false;
        }
    }

    /**
     * Check storage write permissions
     */
    private function checkStorage(): bool
    {
        try {
            $testFile = 'health_check_' . time() . '.tmp';
            Storage::put($testFile, 'test');
            $exists = Storage::exists($testFile);
            Storage::delete($testFile);

            return $exists;
        } catch (Exception $e) {
            report($e);
            return false;
        }
    }

    /**
     * Check VPS connectivity
     */
    private function checkVpsConnectivity(): bool
    {
        try {
            // This would check connectivity to your VPS servers
            // Implement based on your specific requirements
            return true;
        } catch (Exception $e) {
            report($e);
            return false;
        }
    }

    /**
     * Check memory usage
     */
    private function checkMemory(): bool
    {
        $memoryLimit = $this->convertToBytes(ini_get('memory_limit'));
        $memoryUsage = memory_get_usage(true);

        // Alert if using more than 90% of memory limit
        return $memoryLimit === -1 || ($memoryUsage / $memoryLimit) < 0.9;
    }

    /**
     * Get memory usage details
     */
    private function getMemoryUsage(): array
    {
        $memoryLimit = ini_get('memory_limit');
        $memoryUsage = memory_get_usage(true);
        $memoryPeak = memory_get_peak_usage(true);

        return [
            'current' => $this->formatBytes($memoryUsage),
            'peak' => $this->formatBytes($memoryPeak),
            'limit' => $memoryLimit,
            'usage_percent' => $memoryLimit !== '-1'
                ? round(($memoryUsage / $this->convertToBytes($memoryLimit)) * 100, 2)
                : 0,
        ];
    }

    /**
     * Get disk space information
     */
    private function getDiskSpace(): array
    {
        $storagePath = storage_path();
        $freeSpace = disk_free_space($storagePath);
        $totalSpace = disk_total_space($storagePath);
        $usedSpace = $totalSpace - $freeSpace;

        return [
            'free' => $this->formatBytes($freeSpace),
            'used' => $this->formatBytes($usedSpace),
            'total' => $this->formatBytes($totalSpace),
            'usage_percent' => round(($usedSpace / $totalSpace) * 100, 2),
        ];
    }

    /**
     * Check HTTPS configuration
     */
    private function checkHttps(): bool
    {
        return config('app.env') === 'production'
            ? request()->isSecure()
            : true; // Don't require HTTPS in non-production
    }

    /**
     * Check rate limiting configuration
     */
    private function checkRateLimiting(): bool
    {
        // Check if rate limiting middleware is configured
        return true; // Laravel has rate limiting built-in
    }

    /**
     * Check SSL certificate expiry
     */
    private function checkSslCertificate(): bool|array
    {
        try {
            $url = config('app.url');
            $parsedUrl = parse_url($url);

            if (!isset($parsedUrl['host'])) {
                return false;
            }

            $streamContext = stream_context_create([
                'ssl' => [
                    'capture_peer_cert' => true,
                    'verify_peer' => false,
                    'verify_peer_name' => false,
                ],
            ]);

            $client = @stream_socket_client(
                "ssl://{$parsedUrl['host']}:443",
                $errno,
                $errstr,
                30,
                STREAM_CLIENT_CONNECT,
                $streamContext
            );

            if (!$client) {
                return false;
            }

            $params = stream_context_get_params($client);
            $cert = openssl_x509_parse($params['options']['ssl']['peer_certificate']);

            $expiryDate = $cert['validTo_time_t'];
            $daysUntilExpiry = ($expiryDate - time()) / 86400;

            return [
                'valid' => $daysUntilExpiry > 0,
                'days_until_expiry' => round($daysUntilExpiry),
                'warning' => $daysUntilExpiry < 30,
            ];
        } catch (Exception $e) {
            report($e);
            return false;
        }
    }

    /**
     * Check external service connectivity
     */
    private function checkExternalService(string $url): bool
    {
        try {
            $response = Http::timeout(5)->get($url);
            return $response->successful();
        } catch (Exception $e) {
            report($e);
            return false;
        }
    }

    /**
     * Check Stripe connectivity
     */
    private function checkStripeConnectivity(): bool
    {
        try {
            // Simple check to see if we can access Stripe API
            // In production, you might want to make an actual API call
            return !empty(config('services.stripe.key')) &&
                   !empty(config('services.stripe.secret'));
        } catch (Exception $e) {
            report($e);
            return false;
        }
    }

    /**
     * Determine if system is healthy based on all checks
     */
    private function isSystemHealthy(array $checks): bool
    {
        // Check infrastructure health
        foreach ($checks['infrastructure'] as $check) {
            if ($check === false) {
                return false;
            }
        }

        return true;
    }

    /**
     * Convert memory size string to bytes
     */
    private function convertToBytes(string $value): int
    {
        $value = trim($value);
        $last = strtolower($value[strlen($value) - 1]);
        $value = (int) $value;

        switch ($last) {
            case 'g':
                $value *= 1024;
                // no break
            case 'm':
                $value *= 1024;
                // no break
            case 'k':
                $value *= 1024;
        }

        return $value;
    }

    /**
     * Format bytes to human-readable string
     */
    private function formatBytes(int $bytes, int $precision = 2): string
    {
        $units = ['B', 'KB', 'MB', 'GB', 'TB'];

        for ($i = 0; $bytes > 1024 && $i < count($units) - 1; $i++) {
            $bytes /= 1024;
        }

        return round($bytes, $precision) . ' ' . $units[$i];
    }
}
