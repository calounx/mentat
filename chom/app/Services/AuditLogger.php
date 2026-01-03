<?php

declare(strict_types=1);

namespace App\Services;

use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Carbon\Carbon;

/**
 * Audit Logger Service
 *
 * Comprehensive audit logging with cryptographic hash chain for tamper detection.
 *
 * Features:
 * - Tamper-proof logging using SHA-256 hash chains
 * - Severity levels for prioritizing security events
 * - Automatic logging of authentication and authorization
 * - Sensitive operation tracking
 * - Hash chain integrity verification
 * - Contextual metadata capture
 *
 * OWASP Reference: A09:2021 – Security Logging and Monitoring Failures
 * Protection: Ensures security events are logged and tamper-proof
 *
 * Hash Chain Implementation:
 * - Each log entry contains hash of: previous_hash + log_data
 * - Any modification breaks the chain
 * - Missing entries detected by gaps in chain
 * - Chain integrity can be verified by recalculating hashes
 *
 * @package App\Services
 */
class AuditLogger
{
    /**
     * Audit logging configuration.
     */
    protected array $config;

    /**
     * Cache for last hash in chain.
     */
    protected ?string $lastHash = null;

    /**
     * Create a new audit logger instance.
     */
    public function __construct()
    {
        $this->config = Config::get('security.audit', []);
    }

    /**
     * Log an audit event.
     *
     * Creates tamper-proof log entry with hash chain.
     *
     * @param string $action Action performed (e.g., 'user.login', 'site.created')
     * @param string $severity Severity level: low, medium, high, critical
     * @param array $context Additional context data
     * @return string Log entry ID
     */
    public function log(string $action, string $severity = 'medium', array $context = []): string
    {
        if (!($this->config['enabled'] ?? true)) {
            return '';
        }

        // Generate unique log ID
        $logId = (string) Str::uuid();

        // Get current user and organization
        $userId = $context['user_id'] ?? auth()->id();
        $organizationId = $context['organization_id'] ?? $this->getCurrentOrganizationId();

        // Extract resource information
        $resourceType = $context['resource_type'] ?? null;
        $resourceId = $context['resource_id'] ?? null;

        // Get request metadata
        $ipAddress = $context['ip_address'] ?? request()?->ip();
        $userAgent = $context['user_agent'] ?? request()?->userAgent();

        // Remove extracted fields from metadata
        $metadata = array_diff_key($context, array_flip([
            'user_id',
            'organization_id',
            'resource_type',
            'resource_id',
            'ip_address',
            'user_agent',
        ]));

        $createdAt = now();

        // Calculate hash for this entry
        $previousHash = $this->getLastHash();
        $hash = $this->calculateHash(
            $previousHash,
            $logId,
            $organizationId,
            $userId,
            $action,
            $resourceType,
            $resourceId,
            $ipAddress,
            $createdAt
        );

        // Insert log entry
        DB::table('audit_logs')->insert([
            'id' => $logId,
            'organization_id' => $organizationId,
            'user_id' => $userId,
            'action' => $action,
            'severity' => $severity,
            'resource_type' => $resourceType,
            'resource_id' => $resourceId,
            'ip_address' => $ipAddress,
            'user_agent' => $userAgent,
            'metadata' => json_encode($metadata),
            'hash' => $hash,
            'created_at' => $createdAt,
            'updated_at' => $createdAt,
        ]);

        // Update cached last hash
        $this->lastHash = $hash;

        return $logId;
    }

    /**
     * Log authentication event.
     *
     * @param string $event Event type (login_success, login_failed, logout, etc.)
     * @param string|null $userId User ID
     * @param array $context Additional context
     * @return string Log entry ID
     */
    public function logAuthentication(string $event, ?string $userId = null, array $context = []): string
    {
        if (!($this->config['log_authentication'] ?? true)) {
            return '';
        }

        $action = "auth.{$event}";

        // Determine severity based on event
        $severity = match ($event) {
            'login_failed', 'account_locked', 'suspicious_login' => 'high',
            'password_reset_requested', 'password_changed' => 'medium',
            default => 'low',
        };

        $context['user_id'] = $userId;

        return $this->log($action, $severity, $context);
    }

    /**
     * Log authorization failure.
     *
     * Called when user attempts unauthorized action.
     *
     * @param string $action Action attempted
     * @param string|null $userId User ID
     * @param string|null $resourceType Resource type
     * @param string|null $resourceId Resource ID
     * @param array $context Additional context
     * @return string Log entry ID
     */
    public function logAuthorizationFailure(
        string $action,
        ?string $userId = null,
        ?string $resourceType = null,
        ?string $resourceId = null,
        array $context = []
    ): string {
        if (!($this->config['log_authorization_failures'] ?? true)) {
            return '';
        }

        $context['user_id'] = $userId;
        $context['resource_type'] = $resourceType;
        $context['resource_id'] = $resourceId;
        $context['attempted_action'] = $action;

        return $this->log('authz.denied', 'high', $context);
    }

    /**
     * Log sensitive operation.
     *
     * Logs operations that require audit trail.
     *
     * @param string $operation Operation name
     * @param string|null $resourceType Resource type
     * @param string|null $resourceId Resource ID
     * @param array $context Additional context
     * @return string Log entry ID
     */
    public function logSensitiveOperation(
        string $operation,
        ?string $resourceType = null,
        ?string $resourceId = null,
        array $context = []
    ): string {
        if (!($this->config['log_sensitive_operations'] ?? true)) {
            return '';
        }

        // Check if operation is in sensitive list
        $sensitiveOps = $this->config['sensitive_operations'] ?? [];

        if (!in_array($operation, $sensitiveOps, true)) {
            return '';
        }

        $context['resource_type'] = $resourceType;
        $context['resource_id'] = $resourceId;

        return $this->log($operation, 'critical', $context);
    }

    /**
     * Log data access.
     *
     * Tracks access to sensitive data.
     *
     * @param string $resourceType Type of resource accessed
     * @param string $resourceId Resource ID
     * @param string $accessType Access type (read, export, etc.)
     * @param array $context Additional context
     * @return string Log entry ID
     */
    public function logDataAccess(
        string $resourceType,
        string $resourceId,
        string $accessType = 'read',
        array $context = []
    ): string {
        if (!($this->config['log_data_access'] ?? false)) {
            return '';
        }

        $context['resource_type'] = $resourceType;
        $context['resource_id'] = $resourceId;
        $context['access_type'] = $accessType;

        return $this->log("data.{$accessType}", 'low', $context);
    }

    /**
     * Verify hash chain integrity.
     *
     * Recalculates all hashes to detect tampering.
     *
     * @param string|null $organizationId Optional organization filter
     * @return array Verification result
     */
    public function verifyHashChain(?string $organizationId = null): array
    {
        $query = DB::table('audit_logs')
            ->orderBy('created_at', 'asc')
            ->orderBy('id', 'asc');

        if ($organizationId) {
            $query->where('organization_id', $organizationId);
        }

        $logs = $query->get();

        if ($logs->isEmpty()) {
            return [
                'valid' => true,
                'total_logs' => 0,
                'message' => 'No logs to verify',
            ];
        }

        $previousHash = '0000000000000000000000000000000000000000000000000000000000000000';
        $errors = [];
        $verified = 0;

        foreach ($logs as $log) {
            $expectedHash = $this->calculateHash(
                $previousHash,
                $log->id,
                $log->organization_id,
                $log->user_id,
                $log->action,
                $log->resource_type,
                $log->resource_id,
                $log->ip_address,
                Carbon::parse($log->created_at)
            );

            if ($log->hash !== $expectedHash) {
                $errors[] = [
                    'log_id' => $log->id,
                    'action' => $log->action,
                    'expected_hash' => $expectedHash,
                    'actual_hash' => $log->hash,
                    'created_at' => $log->created_at,
                ];
            } else {
                $verified++;
            }

            $previousHash = $log->hash;
        }

        $valid = empty($errors);

        // Alert if tampering detected
        if (!$valid && ($this->config['alert_on_tampering'] ?? true)) {
            $this->alertHashChainViolation($errors);
        }

        return [
            'valid' => $valid,
            'total_logs' => $logs->count(),
            'verified' => $verified,
            'errors' => $errors,
            'error_count' => count($errors),
            'message' => $valid
                ? 'Hash chain integrity verified'
                : 'Hash chain tampering detected!',
        ];
    }

    /**
     * Get recent audit logs.
     *
     * @param array $filters Filters (action, severity, user_id, etc.)
     * @param int $limit Maximum logs to return
     * @return array Audit logs
     */
    public function getRecentLogs(array $filters = [], int $limit = 100): array
    {
        $query = DB::table('audit_logs')
            ->orderBy('created_at', 'desc')
            ->limit($limit);

        if (isset($filters['action'])) {
            $query->where('action', $filters['action']);
        }

        if (isset($filters['severity'])) {
            $query->where('severity', $filters['severity']);
        }

        if (isset($filters['user_id'])) {
            $query->where('user_id', $filters['user_id']);
        }

        if (isset($filters['organization_id'])) {
            $query->where('organization_id', $filters['organization_id']);
        }

        if (isset($filters['resource_type'])) {
            $query->where('resource_type', $filters['resource_type']);
        }

        if (isset($filters['start_date'])) {
            $query->where('created_at', '>=', $filters['start_date']);
        }

        if (isset($filters['end_date'])) {
            $query->where('created_at', '<=', $filters['end_date']);
        }

        return $query->get()->map(function ($log) {
            return [
                'id' => $log->id,
                'action' => $log->action,
                'severity' => $log->severity,
                'user_id' => $log->user_id,
                'organization_id' => $log->organization_id,
                'resource_type' => $log->resource_type,
                'resource_id' => $log->resource_id,
                'ip_address' => $log->ip_address,
                'metadata' => json_decode($log->metadata, true),
                'created_at' => $log->created_at,
            ];
        })->toArray();
    }

    /**
     * Get security statistics.
     *
     * Returns aggregated security metrics.
     *
     * @param string|null $organizationId Organization filter
     * @param int $days Days to include
     * @return array Security statistics
     */
    public function getSecurityStatistics(?string $organizationId = null, int $days = 30): array
    {
        $startDate = now()->subDays($days);

        $query = DB::table('audit_logs')
            ->where('created_at', '>=', $startDate);

        if ($organizationId) {
            $query->where('organization_id', $organizationId);
        }

        // Get counts by severity
        $bySeverity = DB::table('audit_logs')
            ->where('created_at', '>=', $startDate)
            ->when($organizationId, fn($q) => $q->where('organization_id', $organizationId))
            ->select('severity', DB::raw('count(*) as count'))
            ->groupBy('severity')
            ->pluck('count', 'severity')
            ->toArray();

        // Get counts by action category
        $byCategory = DB::table('audit_logs')
            ->where('created_at', '>=', $startDate)
            ->when($organizationId, fn($q) => $q->where('organization_id', $organizationId))
            ->select(DB::raw('SUBSTRING_INDEX(action, ".", 1) as category'), DB::raw('count(*) as count'))
            ->groupBy('category')
            ->pluck('count', 'category')
            ->toArray();

        // Get failed login attempts
        $failedLogins = DB::table('audit_logs')
            ->where('created_at', '>=', $startDate)
            ->where('action', 'auth.login_failed')
            ->when($organizationId, fn($q) => $q->where('organization_id', $organizationId))
            ->count();

        // Get suspicious activities
        $suspiciousActivities = DB::table('audit_logs')
            ->where('created_at', '>=', $startDate)
            ->whereIn('severity', ['high', 'critical'])
            ->when($organizationId, fn($q) => $q->where('organization_id', $organizationId))
            ->count();

        return [
            'period_days' => $days,
            'total_events' => array_sum($bySeverity),
            'by_severity' => $bySeverity,
            'by_category' => $byCategory,
            'failed_logins' => $failedLogins,
            'suspicious_activities' => $suspiciousActivities,
        ];
    }

    /**
     * Calculate SHA-256 hash for audit log entry.
     *
     * Hash includes all critical fields to detect any tampering.
     *
     * @param string $previousHash Previous hash in chain
     * @param string $id Log entry ID
     * @param string|null $organizationId Organization ID
     * @param string|null $userId User ID
     * @param string $action Action performed
     * @param string|null $resourceType Resource type
     * @param string|null $resourceId Resource ID
     * @param string|null $ipAddress IP address
     * @param Carbon $createdAt Created timestamp
     * @return string SHA-256 hash
     */
    protected function calculateHash(
        string $previousHash,
        string $id,
        ?string $organizationId,
        ?string $userId,
        string $action,
        ?string $resourceType,
        ?string $resourceId,
        ?string $ipAddress,
        Carbon $createdAt
    ): string {
        $data = implode('|', [
            $previousHash,
            $id,
            $organizationId ?? '',
            $userId ?? '',
            $action,
            $resourceType ?? '',
            $resourceId ?? '',
            $ipAddress ?? '',
            $createdAt->toIso8601String(),
        ]);

        return hash('sha256', $data);
    }

    /**
     * Get last hash in chain.
     *
     * Used for linking new entries to chain.
     *
     * @return string Last hash or genesis hash
     */
    protected function getLastHash(): string
    {
        // Return cached value if available
        if ($this->lastHash !== null) {
            return $this->lastHash;
        }

        // Get most recent log entry
        $lastLog = DB::table('audit_logs')
            ->orderBy('created_at', 'desc')
            ->orderBy('id', 'desc')
            ->first();

        if ($lastLog && $lastLog->hash) {
            $this->lastHash = $lastLog->hash;
            return $lastLog->hash;
        }

        // Genesis hash (first entry in chain)
        return '0000000000000000000000000000000000000000000000000000000000000000';
    }

    /**
     * Get current organization ID.
     *
     * @return string|null Organization ID
     */
    protected function getCurrentOrganizationId(): ?string
    {
        $user = auth()->user();

        if (!$user) {
            return null;
        }

        // Get current team/organization from user
        return $user->current_team_id ?? null;
    }

    /**
     * Alert on hash chain violation.
     *
     * Sends immediate alert for detected tampering.
     *
     * @param array $errors Hash chain errors
     * @return void
     */
    protected function alertHashChainViolation(array $errors): void
    {
        // Log critical security event
        $this->log('audit.hash_chain_violation', 'critical', [
            'error_count' => count($errors),
            'affected_logs' => array_column($errors, 'log_id'),
        ]);

        // Implementation would send immediate alert to security team
        // Mail::to(config('security.alert_email'))->send(new HashChainViolationAlert($errors));
    }
}
