<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AuditLog extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'organization_id',
        'user_id',
        'action',
        'severity',
        'resource_type',
        'resource_id',
        'ip_address',
        'user_agent',
        'metadata',
        'hash',
    ];

    protected function casts(): array
    {
        return [
            'metadata' => 'array',
        ];
    }

    /**
     * SECURITY: Boot method to automatically calculate hash chain on creation.
     *
     * This ensures every audit log entry is cryptographically linked to the
     * previous entry, creating a tamper-proof chain. Any modification to any
     * log entry will break the chain and be detectable.
     *
     * OWASP Reference: A09:2021 – Security Logging and Monitoring Failures
     */
    protected static function boot()
    {
        parent::boot();

        // Calculate hash before creating new audit log
        static::creating(function ($auditLog) {
            // Get hash of previous log entry (or genesis hash if first entry)
            $previousHash = static::query()
                ->whereNotNull('hash')
                ->latest('created_at')
                ->latest('id')
                ->value('hash') ?? '0000000000000000000000000000000000000000000000000000000000000000';

            // Calculate hash for this entry
            $auditLog->hash = static::calculateLogHash($previousHash, $auditLog);
        });
    }

    /**
     * Calculate SHA-256 hash for audit log entry.
     *
     * SECURITY: Hash includes all critical fields plus previous hash to create chain.
     * This makes it cryptographically impossible to modify logs without detection.
     *
     * @param  string  $previousHash  The hash of the previous log entry
     * @param  AuditLog  $log  The current log entry
     * @return string SHA-256 hash
     */
    protected static function calculateLogHash(string $previousHash, self $log): string
    {
        $data = $previousHash
            .($log->id ?? '')
            .($log->organization_id ?? '')
            .($log->user_id ?? '')
            .$log->action
            .($log->resource_type ?? '')
            .($log->resource_id ?? '')
            .$log->ip_address
            .now()->toDateTimeString();  // Use current timestamp for consistency

        return hash('sha256', $data);
    }

    /**
     * Verify integrity of audit log hash chain.
     *
     * SECURITY: Validates that no logs have been tampered with by recalculating
     * all hashes and comparing with stored values.
     *
     * @return array Array with 'valid' boolean and 'errors' array
     */
    public static function verifyHashChain(): array
    {
        $logs = static::query()
            ->whereNotNull('hash')
            ->orderBy('created_at', 'asc')
            ->orderBy('id', 'asc')
            ->get();

        $previousHash = '0000000000000000000000000000000000000000000000000000000000000000';
        $errors = [];

        foreach ($logs as $log) {
            $expectedHash = hash('sha256',
                $previousHash
                .$log->id
                .$log->organization_id
                .$log->user_id
                .$log->action
                .$log->resource_type
                .$log->resource_id
                .$log->ip_address
                .$log->created_at
            );

            if ($expectedHash !== $log->hash) {
                $errors[] = [
                    'log_id' => $log->id,
                    'action' => $log->action,
                    'expected_hash' => $expectedHash,
                    'actual_hash' => $log->hash,
                    'message' => 'Hash mismatch - possible tampering detected',
                ];
            }

            $previousHash = $log->hash;
        }

        return [
            'valid' => empty($errors),
            'total_logs' => $logs->count(),
            'errors' => $errors,
        ];
    }

    /**
     * Get the organization this audit log belongs to.
     */
    public function organization(): BelongsTo
    {
        return $this->belongsTo(Organization::class);
    }

    /**
     * Get the user who performed the action.
     */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /**
     * Create an audit log entry with automatic severity classification.
     *
     * SECURITY: Logs security-relevant events with severity levels for alerting.
     * High and critical severity events should trigger immediate notifications.
     *
     * @param  string  $action  The action being logged
     * @param  Organization|null  $organization  The organization context
     * @param  User|null  $user  The user performing the action
     * @param  string|null  $resourceType  Type of resource affected
     * @param  string|null  $resourceId  ID of resource affected
     * @param  array|null  $metadata  Additional context data
     * @param  string  $severity  Severity level (low, medium, high, critical)
     */
    public static function log(
        string $action,
        ?Organization $organization = null,
        ?User $user = null,
        ?string $resourceType = null,
        ?string $resourceId = null,
        ?array $metadata = null,
        string $severity = 'medium'
    ): self {
        // SECURITY: Auto-detect severity for common security events
        $severity = static::determineSeverity($action, $severity);

        return static::create([
            'organization_id' => $organization?->id,
            'user_id' => $user?->id,
            'action' => $action,
            'severity' => $severity,
            'resource_type' => $resourceType,
            'resource_id' => $resourceId,
            'ip_address' => request()->ip(),
            'user_agent' => request()->userAgent(),
            'metadata' => $metadata,
        ]);
    }

    /**
     * Determine severity level based on action type.
     *
     * SECURITY: Critical and high severity events require immediate attention.
     * This classification helps prioritize security monitoring and alerting.
     */
    protected static function determineSeverity(string $action, string $defaultSeverity): string
    {
        // Critical severity - immediate security threat
        $criticalActions = [
            'security.breach.detected',
            'authentication.brute_force',
            'authorization.escalation_attempt',
            'data.mass_deletion',
            'admin.privilege_granted',
        ];

        // High severity - significant security event
        $highActions = [
            'authentication.failed',
            'authorization.denied',
            'user.password_reset',
            'user.two_factor_disabled',
            'api.rate_limit_exceeded',
            'cross_tenant.access_attempt',
        ];

        // Medium severity - normal security-relevant event
        $mediumActions = [
            'authentication.success',
            'authentication.logout',
            'user.created',
            'user.updated',
            'permission.changed',
        ];

        if (in_array($action, $criticalActions)) {
            return 'critical';
        }

        if (in_array($action, $highActions)) {
            return 'high';
        }

        if (in_array($action, $mediumActions)) {
            return 'medium';
        }

        return $defaultSeverity;
    }

    /**
     * Scope to filter by action.
     */
    public function scopeForAction($query, string $action)
    {
        return $query->where('action', $action);
    }

    /**
     * Scope to filter by resource type.
     */
    public function scopeForResourceType($query, string $resourceType)
    {
        return $query->where('resource_type', $resourceType);
    }

    /**
     * Scope to filter by user.
     */
    public function scopeByUser($query, User $user)
    {
        return $query->where('user_id', $user->id);
    }
}
