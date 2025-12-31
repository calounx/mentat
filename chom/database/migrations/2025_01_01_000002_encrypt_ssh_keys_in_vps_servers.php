<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Encrypt SSH Keys in Database Migration
 *
 * SECURITY: This migration moves SSH keys from filesystem to encrypted database storage.
 * This addresses OWASP A02:2021 – Cryptographic Failures by ensuring SSH keys are
 * encrypted at rest using Laravel's built-in encryption (AES-256-CBC with HMAC).
 *
 * Changes:
 * 1. Add encrypted ssh_private_key and ssh_public_key columns
 * 2. Add key_rotated_at timestamp for key rotation tracking
 * 3. Migrate existing filesystem keys to database (if any)
 * 4. Add index for efficient key rotation queries
 *
 * IMPORTANT: Ensure APP_KEY is set and backed up before running this migration.
 * Loss of APP_KEY means permanent loss of access to encrypted SSH keys.
 */
return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('vps_servers', function (Blueprint $table) {
            // SECURITY: TEXT columns for encrypted keys (will be larger due to encryption overhead)
            // Laravel's encrypted cast uses AES-256-CBC with HMAC-SHA-256 for authentication
            $table->text('ssh_private_key')->nullable()->after('ssh_key_id')
                ->comment('Encrypted SSH private key for VPS access');

            $table->text('ssh_public_key')->nullable()->after('ssh_private_key')
                ->comment('Encrypted SSH public key for VPS access');

            // SECURITY: Track when keys were last rotated for compliance and key lifecycle management
            $table->timestamp('key_rotated_at')->nullable()->after('ssh_public_key')
                ->comment('Timestamp of last SSH key rotation');

            // Index for querying servers with old keys that need rotation
            $table->index('key_rotated_at', 'idx_key_rotation');
        });

        // Migrate existing filesystem-based keys to database
        $this->migrateExistingKeys();
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('vps_servers', function (Blueprint $table) {
            $table->dropIndex('idx_key_rotation');
            $table->dropColumn(['ssh_private_key', 'ssh_public_key', 'key_rotated_at']);
        });
    }

    /**
     * Migrate existing SSH keys from filesystem to encrypted database storage.
     *
     * SECURITY: This method safely migrates keys with proper error handling.
     * Original filesystem keys should be securely deleted after migration verification.
     */
    protected function migrateExistingKeys(): void
    {
        $sshKeyPath = storage_path('app/ssh-keys');

        // Check if SSH keys directory exists
        if (! is_dir($sshKeyPath)) {
            // No existing keys to migrate
            return;
        }

        $vpsServers = DB::table('vps_servers')->get();

        foreach ($vpsServers as $server) {
            // Construct expected key file paths
            $privateKeyPath = $sshKeyPath . '/' . $server->id . '_id_rsa';
            $publicKeyPath = $sshKeyPath . '/' . $server->id . '_id_rsa.pub';

            // Check if keys exist on filesystem
            if (file_exists($privateKeyPath) && file_exists($publicKeyPath)) {
                try {
                    // Read keys from filesystem
                    $privateKey = file_get_contents($privateKeyPath);
                    $publicKey = file_get_contents($publicKeyPath);

                    // SECURITY: Encrypt keys using Laravel's encryption
                    // This uses APP_KEY with AES-256-CBC + HMAC-SHA-256
                    $encryptedPrivateKey = encrypt($privateKey);
                    $encryptedPublicKey = encrypt($publicKey);

                    // Store encrypted keys in database
                    DB::table('vps_servers')
                        ->where('id', $server->id)
                        ->update([
                            'ssh_private_key' => $encryptedPrivateKey,
                            'ssh_public_key' => $encryptedPublicKey,
                            'key_rotated_at' => now(),
                            'updated_at' => now(),
                        ]);

                    // Log successful migration (but never log key contents)
                    \Log::info('Migrated SSH keys to database', [
                        'vps_id' => $server->id,
                        'hostname' => $server->hostname,
                    ]);

                    // SECURITY NOTE: Original filesystem keys should be manually deleted
                    // after verifying database encryption is working correctly
                    // DO NOT auto-delete to allow rollback if issues occur

                } catch (\Exception $e) {
                    // Log error but continue with other servers
                    \Log::error('Failed to migrate SSH keys', [
                        'vps_id' => $server->id,
                        'hostname' => $server->hostname,
                        'error' => $e->getMessage(),
                    ]);
                }
            }
        }
    }
};
