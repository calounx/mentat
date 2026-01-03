<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Create Security Tables Migration
 *
 * Creates database tables for security features:
 * - login_history: Track all login attempts
 * - encrypted_secrets: Store encrypted credentials
 * - secret_access_log: Audit secret access
 * - api_keys: API key management
 *
 * OWASP References:
 * - A07:2021 – Identification and Authentication Failures
 * - A02:2021 – Cryptographic Failures
 * - A09:2021 – Security Logging and Monitoring Failures
 */
return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        // Login history table for tracking authentication attempts
        Schema::create('login_history', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->nullable()->constrained()->onDelete('cascade');
            $table->string('email')->nullable()->index();
            $table->string('ip_address', 45)->index();
            $table->text('user_agent')->nullable();
            $table->string('device_fingerprint', 64)->nullable()->index();
            $table->boolean('is_successful')->default(false)->index();
            $table->boolean('is_suspicious')->default(false)->index();
            $table->json('suspicious_flags')->nullable();
            $table->string('failure_reason')->nullable();
            $table->timestamp('created_at');

            // Indexes for querying
            $table->index(['user_id', 'created_at']);
            $table->index(['ip_address', 'created_at']);
            $table->index(['is_successful', 'created_at']);
        });

        // Encrypted secrets table for secure credential storage
        Schema::create('encrypted_secrets', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('secret_type', 50)->index(); // vps_password, api_key, etc.
            $table->string('identifier')->index(); // user_id, vps_id, etc.
            $table->text('ciphertext'); // Encrypted data
            $table->string('iv', 255); // Initialization vector
            $table->string('tag', 255); // Authentication tag for GCM
            $table->text('aad'); // Additional authenticated data
            $table->json('metadata')->nullable();
            $table->timestamp('expires_at')->nullable()->index();
            $table->timestamp('rotated_at')->nullable()->index();
            $table->timestamps();

            // Compound index for lookups
            $table->index(['secret_type', 'identifier']);
            $table->index(['expires_at', 'rotated_at']);
        });

        // Secret access log for audit trail
        Schema::create('secret_access_log', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('secret_id')->index();
            $table->string('action', 50)->index(); // created, retrieved, rotated, deleted
            $table->string('identifier')->nullable();
            $table->string('ip_address', 45)->nullable();
            $table->text('user_agent')->nullable();
            $table->timestamp('created_at');

            // Foreign key with cascade delete
            $table->foreign('secret_id')
                ->references('id')
                ->on('encrypted_secrets')
                ->onDelete('cascade');

            // Index for querying
            $table->index(['secret_id', 'created_at']);
            $table->index(['action', 'created_at']);
        });

        // API keys table for API authentication
        Schema::create('api_keys', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained()->onDelete('cascade');
            $table->string('name')->nullable(); // User-friendly name
            $table->string('key_hash', 64)->unique(); // SHA-256 hash of key
            $table->boolean('is_active')->default(true)->index();
            $table->json('permissions')->nullable(); // Scoped permissions
            $table->json('metadata')->nullable();
            $table->timestamp('last_used_at')->nullable();
            $table->timestamp('expires_at')->nullable()->index();
            $table->timestamp('revoked_at')->nullable();
            $table->timestamps();

            // Indexes for queries
            $table->index(['user_id', 'is_active']);
            $table->index(['expires_at', 'is_active']);
        });

        // Account lockout tracking (Redis is primary, this is for persistence)
        Schema::create('account_lockouts', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('identifier')->index(); // Email or user ID
            $table->string('ip_address', 45)->index();
            $table->integer('failed_attempts')->default(0);
            $table->timestamp('locked_at')->nullable()->index();
            $table->timestamp('unlock_at')->nullable()->index();
            $table->string('reason')->nullable();
            $table->json('metadata')->nullable();
            $table->timestamps();

            // Compound index
            $table->unique(['identifier', 'ip_address']);
        });

        // Trusted devices for suspicious login detection
        Schema::create('trusted_devices', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained()->onDelete('cascade');
            $table->string('device_fingerprint', 64)->index();
            $table->string('device_name')->nullable(); // User-assigned name
            $table->string('ip_address', 45)->nullable();
            $table->text('user_agent')->nullable();
            $table->timestamp('first_seen_at');
            $table->timestamp('last_seen_at')->nullable();
            $table->timestamp('trusted_at');
            $table->boolean('is_trusted')->default(true)->index();
            $table->timestamps();

            // Indexes
            $table->index(['user_id', 'is_trusted']);
            $table->index(['user_id', 'device_fingerprint']);
        });

        // Security events for monitoring and alerting
        Schema::create('security_events', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->nullable()->constrained()->onDelete('set null');
            $table->string('event_type', 100)->index(); // brute_force, account_takeover, etc.
            $table->enum('severity', ['low', 'medium', 'high', 'critical'])->index();
            $table->string('ip_address', 45)->nullable()->index();
            $table->text('user_agent')->nullable();
            $table->json('event_data')->nullable();
            $table->boolean('is_resolved')->default(false)->index();
            $table->timestamp('resolved_at')->nullable();
            $table->text('resolution_notes')->nullable();
            $table->timestamps();

            // Indexes for queries
            $table->index(['event_type', 'created_at']);
            $table->index(['severity', 'is_resolved']);
            $table->index(['user_id', 'created_at']);
        });

        // CSRF tokens (database-backed for stateless API)
        Schema::create('csrf_tokens', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->nullable()->constrained()->onDelete('cascade');
            $table->string('token', 64)->unique();
            $table->string('session_id')->nullable()->index();
            $table->timestamp('expires_at')->index();
            $table->timestamp('used_at')->nullable();
            $table->boolean('is_used')->default(false)->index();
            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('csrf_tokens');
        Schema::dropIfExists('security_events');
        Schema::dropIfExists('trusted_devices');
        Schema::dropIfExists('account_lockouts');
        Schema::dropIfExists('api_keys');
        Schema::dropIfExists('secret_access_log');
        Schema::dropIfExists('encrypted_secrets');
        Schema::dropIfExists('login_history');
    }
};
