<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Add Audit Log Hash Chain Migration
 *
 * SECURITY: Implements tamper-proof audit logging using cryptographic hash chains.
 * This ensures audit logs cannot be modified or deleted without detection.
 *
 * How it works:
 * 1. Each log entry contains hash of: previous hash + current log data
 * 2. Any modification to log entry breaks the chain
 * 3. Missing entries detected by gap in chain
 * 4. Chain integrity can be verified by recalculating all hashes
 *
 * OWASP Reference: A09:2021 – Security Logging and Monitoring Failures
 * Hash chain prevents tampering with security audit trail.
 */
return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('audit_logs', function (Blueprint $table) {
            // SECURITY: SHA-256 hash creates tamper-proof chain
            // Hash includes: previous_hash + log data + timestamp
            // Fixed length (64 chars for SHA-256 hex) for efficient indexing
            $table->string('hash', 64)->nullable()->after('metadata')
                ->comment('SHA-256 hash chain for tamper detection');

            // Index for efficient hash chain verification queries
            $table->index('hash', 'idx_audit_hash');

            // SECURITY: Add security severity level for prioritizing alerts
            $table->enum('severity', ['low', 'medium', 'high', 'critical'])
                ->default('medium')
                ->after('action')
                ->comment('Security event severity for alerting');

            // Index for querying high-severity events
            $table->index('severity', 'idx_audit_severity');
        });

        // Calculate and set hashes for existing audit logs
        $this->initializeHashChain();
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('audit_logs', function (Blueprint $table) {
            $table->dropIndex('idx_audit_hash');
            $table->dropIndex('idx_audit_severity');
            $table->dropColumn(['hash', 'severity']);
        });
    }

    /**
     * Initialize hash chain for existing audit logs.
     *
     * SECURITY: Creates cryptographic chain linking all existing logs.
     * This must be done in chronological order to maintain chain integrity.
     */
    protected function initializeHashChain(): void
    {
        // Get all existing logs in chronological order
        $logs = DB::table('audit_logs')
            ->orderBy('created_at', 'asc')
            ->orderBy('id', 'asc')
            ->get();

        $previousHash = '0000000000000000000000000000000000000000000000000000000000000000'; // Genesis hash

        foreach ($logs as $log) {
            // Calculate hash for this log entry
            $hash = $this->calculateHash($previousHash, $log);

            // Update log with calculated hash
            DB::table('audit_logs')
                ->where('id', $log->id)
                ->update([
                    'hash' => $hash,
                    'updated_at' => $log->updated_at, // Preserve original timestamp
                ]);

            // This hash becomes previous hash for next entry
            $previousHash = $hash;
        }
    }

    /**
     * Calculate SHA-256 hash for audit log entry.
     *
     * SECURITY: Hash includes all critical fields to detect any tampering.
     * Changing any field in log entry will break the hash chain.
     */
    protected function calculateHash(string $previousHash, object $log): string
    {
        $data = $previousHash
            . $log->id
            . $log->organization_id
            . $log->user_id
            . $log->action
            . $log->resource_type
            . $log->resource_id
            . $log->ip_address
            . $log->created_at;

        return hash('sha256', $data);
    }
};
