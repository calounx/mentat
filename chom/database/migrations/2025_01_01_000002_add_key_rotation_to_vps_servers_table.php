<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * SECURITY: Add Key Rotation Fields to VPS Servers
 *
 * Enables tracking of SSH key rotation for VPS servers with 24-hour
 * overlap period for graceful key rollover.
 */
return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('vps_servers', function (Blueprint $table) {
            // Current SSH credentials
            $table->timestamp('key_rotated_at')->nullable()->after('ssh_public_key');

            // Previous SSH credentials (for 24h overlap period)
            $table->text('previous_ssh_private_key')->nullable()->after('key_rotated_at');
            $table->text('previous_ssh_public_key')->nullable()->after('previous_ssh_private_key');

            // Add index for finding servers needing rotation
            $table->index('key_rotated_at');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('vps_servers', function (Blueprint $table) {
            $table->dropIndex(['key_rotated_at']);

            $table->dropColumn([
                'key_rotated_at',
                'previous_ssh_private_key',
                'previous_ssh_public_key',
            ]);
        });
    }
};
