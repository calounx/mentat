<?php

namespace App\Services\Security;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use App\Services\Alerting\AlertManager;
use Illuminate\Http\Request;

class SecurityMonitor
{
    protected AlertManager $alertManager;

    public function __construct(AlertManager $alertManager)
    {
        $this->alertManager = $alertManager;
    }

    /**
     * Monitor failed login attempts
     */
    public function trackFailedLogin(string $email, Request $request): void
    {
        $key = "failed_login:{$email}";
        $attempts = Cache::get($key, 0) + 1;

        Cache::put($key, $attempts, 900); // 15 minutes

        // Log the attempt
        Log::channel('security')->warning('Failed login attempt', [
            'email' => $email,
            'ip' => $request->ip(),
            'user_agent' => $request->userAgent(),
            'attempts' => $attempts,
            'timestamp' => now()->toIso8601String(),
        ]);

        // Alert on threshold
        if ($attempts >= 5) {
            $this->alertManager->warning(
                'high_failed_login_attempts',
                "Multiple failed login attempts for {$email}",
                [
                    'email' => $email,
                    'ip' => $request->ip(),
                    'attempts' => $attempts,
                ]
            );
        }

        // Critical alert on higher threshold
        if ($attempts >= 10) {
            $this->alertManager->critical(
                'security_event',
                "Possible brute force attack on {$email}",
                [
                    'email' => $email,
                    'ip' => $request->ip(),
                    'attempts' => $attempts,
                ]
            );
        }
    }

    /**
     * Track successful login
     */
    public function trackSuccessfulLogin(string $userId, Request $request): void
    {
        Log::channel('security')->info('Successful login', [
            'user_id' => $userId,
            'ip' => $request->ip(),
            'user_agent' => $request->userAgent(),
            'timestamp' => now()->toIso8601String(),
        ]);

        // Check for unusual login location
        $this->checkUnusualLoginLocation($userId, $request->ip());
    }

    /**
     * Monitor authorization failures
     */
    public function trackAuthorizationFailure(string $userId, string $resource, string $action, Request $request): void
    {
        $key = "auth_failures:{$userId}";
        $failures = Cache::get($key, 0) + 1;

        Cache::put($key, $failures, 300); // 5 minutes

        Log::channel('security')->warning('Authorization failure', [
            'user_id' => $userId,
            'resource' => $resource,
            'action' => $action,
            'ip' => $request->ip(),
            'failures' => $failures,
            'timestamp' => now()->toIso8601String(),
        ]);

        if ($failures >= 5) {
            $this->alertManager->warning(
                'unauthorized_access_attempt',
                "Multiple authorization failures for user {$userId}",
                [
                    'user_id' => $userId,
                    'resource' => $resource,
                    'ip' => $request->ip(),
                    'failures' => $failures,
                ]
            );
        }
    }

    /**
     * Monitor SQL injection attempts
     */
    public function checkSqlInjection(Request $request): void
    {
        $suspiciousPatterns = [
            '/(\%27)|(\')|(\-\-)|(\%23)|(#)/i',
            '/((\%3D)|(=))[^\n]*((\%27)|(\')|(\-\-)|(\%3B)|(;))/i',
            '/\w*((\%27)|(\'))((\%6F)|o|(\%4F))((\%72)|r|(\%52))/i',
            '/((\%27)|(\'))union/i',
            '/exec(\s|\+)+(s|x)p\w+/i',
        ];

        $queryString = $request->getQueryString();
        $postData = json_encode($request->all());

        foreach ($suspiciousPatterns as $pattern) {
            if (preg_match($pattern, $queryString) || preg_match($pattern, $postData)) {
                Log::channel('security')->critical('Possible SQL injection attempt', [
                    'ip' => $request->ip(),
                    'url' => $request->fullUrl(),
                    'user_agent' => $request->userAgent(),
                    'pattern' => $pattern,
                    'timestamp' => now()->toIso8601String(),
                ]);

                $this->alertManager->critical(
                    'security_event',
                    'Possible SQL injection attempt detected',
                    [
                        'ip' => $request->ip(),
                        'url' => $request->fullUrl(),
                    ]
                );

                break;
            }
        }
    }

    /**
     * Monitor XSS attempts
     */
    public function checkXss(Request $request): void
    {
        $suspiciousPatterns = [
            '/<script[^>]*>.*?<\/script>/is',
            '/<iframe[^>]*>.*?<\/iframe>/is',
            '/javascript:/i',
            '/on\w+\s*=/i',
        ];

        $postData = json_encode($request->all());

        foreach ($suspiciousPatterns as $pattern) {
            if (preg_match($pattern, $postData)) {
                Log::channel('security')->critical('Possible XSS attempt', [
                    'ip' => $request->ip(),
                    'url' => $request->fullUrl(),
                    'user_agent' => $request->userAgent(),
                    'pattern' => $pattern,
                    'timestamp' => now()->toIso8601String(),
                ]);

                $this->alertManager->critical(
                    'security_event',
                    'Possible XSS attempt detected',
                    [
                        'ip' => $request->ip(),
                        'url' => $request->fullUrl(),
                    ]
                );

                break;
            }
        }
    }

    /**
     * Monitor rate limit violations
     */
    public function trackRateLimitViolation(string $key, Request $request): void
    {
        Log::channel('security')->warning('Rate limit exceeded', [
            'key' => $key,
            'ip' => $request->ip(),
            'url' => $request->fullUrl(),
            'user_agent' => $request->userAgent(),
            'timestamp' => now()->toIso8601String(),
        ]);

        // Track repeated violations
        $violationKey = "rate_limit_violations:{$request->ip()}";
        $violations = Cache::get($violationKey, 0) + 1;

        Cache::put($violationKey, $violations, 3600); // 1 hour

        if ($violations >= 10) {
            $this->alertManager->warning(
                'security_event',
                'Repeated rate limit violations from ' . $request->ip(),
                [
                    'ip' => $request->ip(),
                    'violations' => $violations,
                ]
            );
        }
    }

    /**
     * Monitor suspicious file uploads
     */
    public function checkFileUpload(string $filename, string $mimeType, int $size): bool
    {
        $suspicious = false;

        // Check for double extensions
        if (preg_match('/\.\w+\.\w+$/', $filename)) {
            Log::channel('security')->warning('Suspicious file upload: double extension', [
                'filename' => $filename,
                'mime_type' => $mimeType,
                'size' => $size,
            ]);
            $suspicious = true;
        }

        // Check for executable extensions
        $dangerousExtensions = ['php', 'exe', 'sh', 'bat', 'cmd', 'com', 'pif', 'scr', 'vbs'];
        $extension = strtolower(pathinfo($filename, PATHINFO_EXTENSION));

        if (in_array($extension, $dangerousExtensions)) {
            Log::channel('security')->critical('Dangerous file upload attempt', [
                'filename' => $filename,
                'extension' => $extension,
                'mime_type' => $mimeType,
            ]);

            $this->alertManager->critical(
                'security_event',
                'Attempt to upload dangerous file type',
                [
                    'filename' => $filename,
                    'extension' => $extension,
                ]
            );

            $suspicious = true;
        }

        return $suspicious;
    }

    /**
     * Check for unusual login location
     */
    protected function checkUnusualLoginLocation(string $userId, string $ip): void
    {
        $lastIpKey = "last_login_ip:{$userId}";
        $lastIp = Cache::get($lastIpKey);

        if ($lastIp && $lastIp !== $ip) {
            // IP changed - could be suspicious
            $countryKey = "login_countries:{$userId}";
            $countries = Cache::get($countryKey, []);

            // In a real implementation, you'd use a GeoIP service
            // For now, just track unique IPs
            if (!in_array($ip, $countries)) {
                $countries[] = $ip;
                Cache::put($countryKey, $countries, 86400 * 30); // 30 days

                Log::channel('security')->info('Login from new location', [
                    'user_id' => $userId,
                    'new_ip' => $ip,
                    'previous_ip' => $lastIp,
                ]);

                // Could send email notification to user here
            }
        }

        Cache::put($lastIpKey, $ip, 86400 * 30); // 30 days
    }

    /**
     * Monitor cross-tenant access attempts
     */
    public function trackCrossTenantAccess(string $userId, int $requestedTenantId, int $userTenantId): void
    {
        Log::channel('security')->critical('Cross-tenant access attempt', [
            'user_id' => $userId,
            'user_tenant_id' => $userTenantId,
            'requested_tenant_id' => $requestedTenantId,
            'timestamp' => now()->toIso8601String(),
        ]);

        $this->alertManager->critical(
            'security_event',
            'Cross-tenant access attempt detected',
            [
                'user_id' => $userId,
                'user_tenant' => $userTenantId,
                'requested_tenant' => $requestedTenantId,
            ]
        );
    }

    /**
     * Monitor API abuse
     */
    public function trackApiAbuse(string $userId, string $endpoint, int $requestCount): void
    {
        if ($requestCount > 100) { // Threshold
            Log::channel('security')->warning('Possible API abuse', [
                'user_id' => $userId,
                'endpoint' => $endpoint,
                'request_count' => $requestCount,
                'timestamp' => now()->toIso8601String(),
            ]);

            $this->alertManager->warning(
                'security_event',
                "High API usage detected for user {$userId}",
                [
                    'user_id' => $userId,
                    'endpoint' => $endpoint,
                    'requests' => $requestCount,
                ]
            );
        }
    }

    /**
     * Check password strength
     */
    public function checkPasswordStrength(string $password): array
    {
        $checks = [
            'length' => strlen($password) >= 12,
            'uppercase' => preg_match('/[A-Z]/', $password),
            'lowercase' => preg_match('/[a-z]/', $password),
            'numbers' => preg_match('/[0-9]/', $password),
            'special' => preg_match('/[^A-Za-z0-9]/', $password),
        ];

        $score = array_sum($checks);
        $strength = match (true) {
            $score >= 5 => 'strong',
            $score >= 4 => 'good',
            $score >= 3 => 'fair',
            default => 'weak',
        };

        if ($strength === 'weak') {
            Log::channel('security')->info('Weak password detected during registration');
        }

        return [
            'strength' => $strength,
            'score' => $score,
            'checks' => $checks,
        ];
    }

    /**
     * Monitor SSH key age
     */
    public function checkSshKeyAge(string $keyPath): ?int
    {
        if (!file_exists($keyPath)) {
            return null;
        }

        $ageInDays = (time() - filemtime($keyPath)) / 86400;

        if ($ageInDays > 365) {
            Log::channel('security')->warning('Old SSH key detected', [
                'key_path' => $keyPath,
                'age_days' => round($ageInDays),
            ]);

            $this->alertManager->warning(
                'security_event',
                'SSH key is older than 1 year',
                [
                    'key_path' => basename($keyPath),
                    'age_days' => round($ageInDays),
                ]
            );
        }

        return (int) $ageInDays;
    }
}
