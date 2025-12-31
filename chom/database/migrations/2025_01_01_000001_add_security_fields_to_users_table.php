<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * SECURITY: Add 2FA, Password Confirmation, and Key Rotation Fields
 *
 * This migration adds security enhancement fields to the users table:
 * - Two-factor authentication backup codes
 * - 2FA confirmation timestamp
 * - Password confirmation timestamp (step-up auth)
 * - SSH key rotation tracking
 */
return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            // Two-Factor Authentication enhancements
            $table->text('two_factor_backup_codes')->nullable()->after('two_factor_secret');
            $table->timestamp('two_factor_confirmed_at')->nullable()->after('two_factor_backup_codes');

            // Step-up authentication (password confirmation)
            $table->timestamp('password_confirmed_at')->nullable()->after('two_factor_confirmed_at');

            // Key rotation tracking
            $table->timestamp('ssh_key_rotated_at')->nullable()->after('password_confirmed_at');

            // Add indexes for performance
            $table->index('two_factor_enabled');
            $table->index('ssh_key_rotated_at');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropIndex(['two_factor_enabled']);
            $table->dropIndex(['ssh_key_rotated_at']);

            $table->dropColumn([
                'two_factor_backup_codes',
                'two_factor_confirmed_at',
                'password_confirmed_at',
                'ssh_key_rotated_at',
            ]);
        });
    }
};
