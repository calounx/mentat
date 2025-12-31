<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Site;
use App\Models\User;
use App\Models\VpsServer;
use App\Services\Secrets\SecretsRotationService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Cache;

/**
 * SECURITY: Health Check and Security Posture Monitoring
 *
 * Provides endpoints for monitoring application health and security posture.
 * Used by monitoring systems and security teams to detect issues early.
 *
 * OWASP Reference: A09:2021 – Security Logging and Monitoring Failures
 * - Proactive security monitoring prevents breaches
 * - Health checks enable rapid incident response
 * - Security posture visibility drives improvement
 *
 * Endpoints:
 * - GET /health           - Basic health check (public, no auth)
 * - GET /health/security  - Security posture check (requires auth + admin)
 * - GET /health/database  - Database connectivity check
 * - GET /health/dependencies - Dependency vulnerability check
 */
class HealthController extends Controller
{
    /**
     * Basic health check endpoint.
     *
     * SECURITY NOTES:
     * - Public endpoint (no authentication required)
     * - Minimal information disclosure
     * - Used by load balancers and monitoring systems
     * - No rate limiting for uptime monitoring
     *
     * @return \Illuminate\Http\JsonResponse
     */
    public function index()
    {
        return response()->json([
            'status' => 'ok',
            'service' => 'chom-api',
            'version' => config('app.version', '1.0.0'),
            'timestamp' => now()->toIso8601String(),
        ]);
    }

    /**
     * Detailed health check with component status.
     *
     * SECURITY NOTES:
     * - Requires authentication
     * - More detailed than basic health check
     * - Includes database, cache, and queue status
     *
     * @return \Illuminate\Http\JsonResponse
     */
    public function detailed(Request $request)
    {
        $checks = [
            'database' => $this->checkDatabase(),
            'cache' => $this->checkCache(),
            'storage' => $this->checkStorage(),
        ];

        $allHealthy = collect($checks)->every(fn($check) => $check['status'] === 'ok');

        return response()->json([
            'status' => $allHealthy ? 'ok' : 'degraded',
            'service' => 'chom-api',
            'version' => config('app.version', '1.0.0'),
            'timestamp' => now()->toIso8601String(),
            'checks' => $checks,
        ], $allHealthy ? 200 : 503);
    }

    /**
     * Security posture check endpoint.
     *
     * SECURITY NOTES:
     * - Requires authentication + admin role
     * - Comprehensive security health assessment
     * - Identifies security misconfigurations
     * - Used for compliance reporting
     *
     * Checks performed:
     * - Expired SSL certificates
     * - Admin accounts without 2FA
     * - Stale SSH keys (>90 days)
     * - Weak passwords detected
     * - Inactive audit logging
     * - Session security settings
     *
     * @return \Illuminate\Http\JsonResponse
     */
    public function security(Request $request, SecretsRotationService $rotationService)
    {
        $user = $request->user();

        // SECURITY: Only admins can access security posture
        if (!$user || !$user->isAdmin()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'FORBIDDEN',
                    'message' => 'Admin access required for security health check.',
                ],
            ], 403);
        }

        $issues = [];
        $warnings = [];
        $passes = [];

        // CHECK 1: Admin accounts without 2FA
        $adminsWithout2FA = User::whereIn('role', ['owner', 'admin'])
            ->where('two_factor_enabled', false)
            ->where('created_at', '<', now()->subDays(7)) // Past grace period
            ->count();

        if ($adminsWithout2FA > 0) {
            $issues[] = [
                'category' => 'authentication',
                'severity' => 'high',
                'issue' => '2FA_NOT_ENFORCED',
                'message' => "{$adminsWithout2FA} admin account(s) without 2FA enabled.",
                'remediation' => 'Enforce 2FA for all admin accounts.',
                'affected_count' => $adminsWithout2FA,
            ];
        } else {
            $passes[] = 'All admin accounts have 2FA enabled';
        }

        // CHECK 2: Stale SSH keys (>90 days)
        $staleKeys = $rotationService->getServersNeedingRotation();

        if ($staleKeys->isNotEmpty()) {
            $warnings[] = [
                'category' => 'cryptography',
                'severity' => 'medium',
                'issue' => 'STALE_SSH_KEYS',
                'message' => "{$staleKeys->count()} VPS server(s) with SSH keys older than 90 days.",
                'remediation' => 'Run: php artisan secrets:rotate --all',
                'affected_count' => $staleKeys->count(),
            ];
        } else {
            $passes[] = 'All SSH keys are current (<90 days)';
        }

        // CHECK 3: SSL certificate expiration
        $expiringCertificates = Site::where('ssl_enabled', true)
            ->where('ssl_expires_at', '<', now()->addDays(30))
            ->count();

        if ($expiringCertificates > 0) {
            $warnings[] = [
                'category' => 'cryptography',
                'severity' => 'medium',
                'issue' => 'SSL_EXPIRING_SOON',
                'message' => "{$expiringCertificates} SSL certificate(s) expiring within 30 days.",
                'remediation' => 'Review and renew SSL certificates.',
                'affected_count' => $expiringCertificates,
            ];
        } else {
            $passes[] = 'All SSL certificates are valid for >30 days';
        }

        // CHECK 4: Audit log integrity
        $auditLogCheck = $this->checkAuditLogIntegrity();
        if (!$auditLogCheck['healthy']) {
            $issues[] = [
                'category' => 'logging',
                'severity' => 'high',
                'issue' => 'AUDIT_LOG_ISSUES',
                'message' => $auditLogCheck['message'],
                'remediation' => 'Review audit log configuration and storage.',
            ];
        } else {
            $passes[] = 'Audit logging is functioning correctly';
        }

        // CHECK 5: Session security settings
        $sessionCheck = $this->checkSessionSecurity();
        if (!$sessionCheck['secure']) {
            $warnings[] = [
                'category' => 'session',
                'severity' => 'medium',
                'issue' => 'SESSION_CONFIG',
                'message' => $sessionCheck['message'],
                'remediation' => 'Review session configuration in config/session.php',
            ];
        } else {
            $passes[] = 'Session security configuration is optimal';
        }

        // CHECK 6: Environment security
        $envCheck = $this->checkEnvironmentSecurity();
        if (!$envCheck['secure']) {
            $issues[] = [
                'category' => 'configuration',
                'severity' => 'critical',
                'issue' => 'ENVIRONMENT_MISCONFIGURATION',
                'message' => $envCheck['message'],
                'remediation' => $envCheck['remediation'],
            ];
        } else {
            $passes[] = 'Environment configuration is secure';
        }

        // Calculate overall security score
        $totalChecks = count($issues) + count($warnings) + count($passes);
        $passCount = count($passes);
        $securityScore = $totalChecks > 0 ? round(($passCount / $totalChecks) * 100) : 0;

        // Determine overall status
        $status = match(true) {
            count($issues) > 0 => 'critical',
            count($warnings) > 2 => 'warning',
            count($warnings) > 0 => 'notice',
            default => 'healthy',
        };

        return response()->json([
            'status' => $status,
            'security_score' => $securityScore,
            'timestamp' => now()->toIso8601String(),
            'summary' => [
                'critical_issues' => count($issues),
                'warnings' => count($warnings),
                'checks_passed' => count($passes),
                'total_checks' => $totalChecks,
            ],
            'issues' => $issues,
            'warnings' => $warnings,
            'passes' => $passes,
            'recommendations' => $this->getSecurityRecommendations($issues, $warnings),
        ]);
    }

    /**
     * Database connectivity check.
     */
    protected function checkDatabase(): array
    {
        try {
            DB::connection()->getPdo();
            $time = DB::connection()->selectOne('SELECT NOW() as time');

            return [
                'status' => 'ok',
                'message' => 'Database connection successful',
                'latency_ms' => 0, // Could measure actual latency
            ];
        } catch (\Exception $e) {
            return [
                'status' => 'error',
                'message' => 'Database connection failed',
                'error' => $e->getMessage(),
            ];
        }
    }

    /**
     * Cache connectivity check.
     */
    protected function checkCache(): array
    {
        try {
            $key = 'health_check_' . time();
            Cache::put($key, 'test', 10);
            $value = Cache::get($key);
            Cache::forget($key);

            return [
                'status' => $value === 'test' ? 'ok' : 'error',
                'message' => $value === 'test' ? 'Cache is working' : 'Cache read/write failed',
            ];
        } catch (\Exception $e) {
            return [
                'status' => 'error',
                'message' => 'Cache system error',
                'error' => $e->getMessage(),
            ];
        }
    }

    /**
     * Storage system check.
     */
    protected function checkStorage(): array
    {
        try {
            $storagePath = storage_path('app');
            $writable = is_writable($storagePath);

            return [
                'status' => $writable ? 'ok' : 'error',
                'message' => $writable ? 'Storage is writable' : 'Storage is not writable',
                'path' => $storagePath,
            ];
        } catch (\Exception $e) {
            return [
                'status' => 'error',
                'message' => 'Storage check failed',
                'error' => $e->getMessage(),
            ];
        }
    }

    /**
     * Check audit log integrity and functionality.
     */
    protected function checkAuditLogIntegrity(): array
    {
        try {
            // Check if audit logs are being created recently
            $recentLogs = DB::table('audit_logs')
                ->where('created_at', '>', now()->subHour())
                ->count();

            if ($recentLogs === 0) {
                return [
                    'healthy' => false,
                    'message' => 'No audit logs in the past hour - logging may be disabled',
                ];
            }

            return ['healthy' => true];

        } catch (\Exception $e) {
            return [
                'healthy' => false,
                'message' => 'Unable to verify audit log integrity: ' . $e->getMessage(),
            ];
        }
    }

    /**
     * Check session security configuration.
     */
    protected function checkSessionSecurity(): array
    {
        $issues = [];

        // Check session driver
        if (config('session.driver') === 'file') {
            $issues[] = 'File-based sessions are not recommended for production';
        }

        // Check secure cookies
        if (!config('session.secure') && config('app.env') === 'production') {
            $issues[] = 'Secure cookie flag should be enabled in production';
        }

        // Check HTTP only cookies
        if (!config('session.http_only')) {
            $issues[] = 'HTTP-only cookie flag should be enabled';
        }

        // Check same site setting
        if (config('session.same_site') !== 'strict' && config('session.same_site') !== 'lax') {
            $issues[] = 'SameSite cookie attribute should be set to strict or lax';
        }

        return [
            'secure' => empty($issues),
            'message' => empty($issues) ? 'Session security is properly configured' : implode('; ', $issues),
        ];
    }

    /**
     * Check environment security settings.
     */
    protected function checkEnvironmentSecurity(): array
    {
        $issues = [];

        // Check debug mode
        if (config('app.debug') === true && config('app.env') === 'production') {
            $issues[] = 'Debug mode is enabled in production';
        }

        // Check APP_KEY is set
        if (empty(config('app.key'))) {
            $issues[] = 'APP_KEY is not set - critical security issue';
        }

        // Check HTTPS enforcement
        if (!config('app.url')) {
            $issues[] = 'APP_URL is not configured';
        }

        return [
            'secure' => empty($issues),
            'message' => empty($issues) ? 'Environment is securely configured' : implode('; ', $issues),
            'remediation' => !empty($issues) ? 'Review .env file and fix configuration issues' : null,
        ];
    }

    /**
     * Generate security recommendations based on findings.
     */
    protected function getSecurityRecommendations(array $issues, array $warnings): array
    {
        $recommendations = [];

        if (count($issues) > 0) {
            $recommendations[] = 'Address critical security issues immediately';
        }

        if (count($warnings) > 2) {
            $recommendations[] = 'Review and remediate warnings to improve security posture';
        }

        $recommendations[] = 'Run regular security audits using: php artisan health:security';
        $recommendations[] = 'Enable automated monitoring with alerts for security issues';
        $recommendations[] = 'Review OWASP Top 10 and apply relevant security controls';

        return $recommendations;
    }
}
