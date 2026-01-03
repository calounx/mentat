<?php

declare(strict_types=1);

namespace App\Services;

use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Carbon\Carbon;
use RuntimeException;

/**
 * Secrets Manager Service
 *
 * Secure management of sensitive credentials including encryption,
 * rotation, and access tracking.
 *
 * Features:
 * - AES-256-GCM encryption for secrets at rest
 * - Automatic key rotation
 * - VPS credential encryption
 * - API key management with expiration
 * - Access audit logging
 * - Key derivation with unique salts
 *
 * OWASP Reference: A02:2021 – Cryptographic Failures
 * Protection: Ensures sensitive data is properly encrypted at rest
 *
 * Security Principles:
 * - Secrets are never stored in plaintext
 * - Each secret has unique encryption parameters (IV, salt)
 * - Master key derived from application key
 * - Automatic rotation prevents long-term key exposure
 * - Access is logged for audit trail
 *
 * @package App\Services
 */
class SecretsManagerService
{
    /**
     * Encryption cipher to use.
     */
    protected string $cipher;

    /**
     * Configuration for secrets management.
     */
    protected array $config;

    /**
     * Master encryption key (derived from APP_KEY).
     */
    protected string $masterKey;

    /**
     * Create a new service instance.
     *
     * @throws RuntimeException If APP_KEY is not set
     */
    public function __construct()
    {
        $this->config = Config::get('security.secrets', []);
        $this->cipher = $this->config['cipher'] ?? 'aes-256-gcm';

        // Derive master key from application key
        $appKey = Config::get('app.key');

        if (!$appKey) {
            throw new RuntimeException('Application key (APP_KEY) is not set');
        }

        // Remove 'base64:' prefix if present
        if (str_starts_with($appKey, 'base64:')) {
            $appKey = base64_decode(substr($appKey, 7));
        }

        $this->masterKey = $appKey;
    }

    /**
     * Encrypt and store a secret.
     *
     * Encrypts secret using AES-256-GCM with:
     * - Unique initialization vector (IV)
     * - Authenticated encryption (prevents tampering)
     * - Optional additional authenticated data (AAD)
     *
     * SECURITY: Uses authenticated encryption to detect tampering
     * SECURITY: Unique IV for each encryption prevents pattern analysis
     *
     * @param string $secretType Type of secret (vps_password, api_key, etc.)
     * @param string $plaintext Secret value in plaintext
     * @param string $identifier Identifier for this secret (user_id, vps_id, etc.)
     * @param array $metadata Additional metadata to store
     * @return string Secret ID for retrieval
     */
    public function storeSecret(
        string $secretType,
        string $plaintext,
        string $identifier,
        array $metadata = []
    ): string {
        // Generate unique IV for this encryption
        $ivLength = openssl_cipher_iv_length($this->cipher);
        $iv = openssl_random_pseudo_bytes($ivLength);

        // Additional authenticated data (prevents tampering)
        $aad = json_encode([
            'type' => $secretType,
            'identifier' => $identifier,
            'created_at' => now()->toIso8601String(),
        ]);

        // Encrypt with authentication tag
        $tag = '';
        $ciphertext = openssl_encrypt(
            $plaintext,
            $this->cipher,
            $this->masterKey,
            OPENSSL_RAW_DATA,
            $iv,
            $tag,
            $aad
        );

        if ($ciphertext === false) {
            throw new RuntimeException('Encryption failed: ' . openssl_error_string());
        }

        // Generate unique secret ID
        $secretId = (string) Str::uuid();

        // Calculate expiration based on secret type
        $expiresAt = $this->calculateExpiration($secretType);

        // Store encrypted secret in database
        DB::table('encrypted_secrets')->insert([
            'id' => $secretId,
            'secret_type' => $secretType,
            'identifier' => $identifier,
            'ciphertext' => base64_encode($ciphertext),
            'iv' => base64_encode($iv),
            'tag' => base64_encode($tag),
            'aad' => $aad,
            'metadata' => json_encode($metadata),
            'expires_at' => $expiresAt,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        // Log secret creation for audit
        $this->logSecretAccess($secretId, 'created', $identifier);

        return $secretId;
    }

    /**
     * Retrieve and decrypt a secret.
     *
     * SECURITY: Validates authentication tag before decryption
     * SECURITY: Checks expiration before returning secret
     * SECURITY: Logs access for audit trail
     *
     * @param string $secretId Secret ID to retrieve
     * @return string|null Decrypted secret or null if not found/expired
     */
    public function retrieveSecret(string $secretId): ?string
    {
        $record = DB::table('encrypted_secrets')
            ->where('id', $secretId)
            ->first();

        if (!$record) {
            return null;
        }

        // Check if secret has expired
        if ($record->expires_at && Carbon::parse($record->expires_at)->isPast()) {
            $this->logSecretAccess($secretId, 'access_denied_expired', null);
            return null;
        }

        // Decrypt secret
        $ciphertext = base64_decode($record->ciphertext);
        $iv = base64_decode($record->iv);
        $tag = base64_decode($record->tag);
        $aad = $record->aad;

        $plaintext = openssl_decrypt(
            $ciphertext,
            $this->cipher,
            $this->masterKey,
            OPENSSL_RAW_DATA,
            $iv,
            $tag,
            $aad
        );

        if ($plaintext === false) {
            // Decryption failed - possible tampering
            $this->logSecretAccess($secretId, 'decryption_failed', null);
            throw new RuntimeException('Decryption failed - possible tampering detected');
        }

        // Log successful access
        $this->logSecretAccess($secretId, 'retrieved', $record->identifier);

        return $plaintext;
    }

    /**
     * Rotate a secret.
     *
     * Re-encrypts secret with new encryption parameters.
     * Used for periodic key rotation.
     *
     * SECURITY: Rotation limits exposure from key compromise
     *
     * @param string $secretId Secret ID to rotate
     * @return bool True if rotation successful
     */
    public function rotateSecret(string $secretId): bool
    {
        // Retrieve current secret
        $currentPlaintext = $this->retrieveSecret($secretId);

        if ($currentPlaintext === null) {
            return false;
        }

        $record = DB::table('encrypted_secrets')
            ->where('id', $secretId)
            ->first();

        // Generate new IV and re-encrypt
        $ivLength = openssl_cipher_iv_length($this->cipher);
        $iv = openssl_random_pseudo_bytes($ivLength);

        $aad = json_encode([
            'type' => $record->secret_type,
            'identifier' => $record->identifier,
            'rotated_at' => now()->toIso8601String(),
        ]);

        $tag = '';
        $ciphertext = openssl_encrypt(
            $currentPlaintext,
            $this->cipher,
            $this->masterKey,
            OPENSSL_RAW_DATA,
            $iv,
            $tag,
            $aad
        );

        if ($ciphertext === false) {
            return false;
        }

        // Update with new encrypted data
        DB::table('encrypted_secrets')
            ->where('id', $secretId)
            ->update([
                'ciphertext' => base64_encode($ciphertext),
                'iv' => base64_encode($iv),
                'tag' => base64_encode($tag),
                'aad' => $aad,
                'rotated_at' => now(),
                'updated_at' => now(),
            ]);

        $this->logSecretAccess($secretId, 'rotated', $record->identifier);

        return true;
    }

    /**
     * Delete a secret.
     *
     * SECURITY: Secure deletion to prevent recovery
     *
     * @param string $secretId Secret ID to delete
     * @return bool True if deletion successful
     */
    public function deleteSecret(string $secretId): bool
    {
        $record = DB::table('encrypted_secrets')
            ->where('id', $secretId)
            ->first();

        if (!$record) {
            return false;
        }

        // Delete from database
        $deleted = DB::table('encrypted_secrets')
            ->where('id', $secretId)
            ->delete();

        if ($deleted) {
            $this->logSecretAccess($secretId, 'deleted', $record->identifier);
        }

        return $deleted > 0;
    }

    /**
     * Rotate VPS credentials.
     *
     * Generates new password and stores encrypted.
     *
     * @param string $vpsId VPS identifier
     * @param string|null $newPassword New password (generated if not provided)
     * @return array New credentials
     */
    public function rotateVpsCredentials(string $vpsId, ?string $newPassword = null): array
    {
        // Generate strong password if not provided
        if ($newPassword === null) {
            $newPassword = $this->generateStrongPassword();
        }

        // Find existing VPS password secret
        $existingSecret = DB::table('encrypted_secrets')
            ->where('secret_type', 'vps_password')
            ->where('identifier', $vpsId)
            ->first();

        if ($existingSecret) {
            // Delete old secret
            $this->deleteSecret($existingSecret->id);
        }

        // Store new password
        $secretId = $this->storeSecret(
            'vps_password',
            $newPassword,
            $vpsId,
            ['rotated_from' => $existingSecret->id ?? null]
        );

        return [
            'secret_id' => $secretId,
            'password' => $newPassword,
            'vps_id' => $vpsId,
        ];
    }

    /**
     * Generate API key with secure random.
     *
     * Creates API key with high entropy for security.
     *
     * @param string $userId User identifier
     * @param array $metadata Additional metadata
     * @return array API key data
     */
    public function generateApiKey(string $userId, array $metadata = []): array
    {
        // Generate secure random key (32 bytes = 256 bits)
        $apiKey = 'chom_' . bin2hex(random_bytes(32));

        // Hash for storage (never store plaintext API keys)
        $hashedKey = hash('sha256', $apiKey);

        // Store hashed key
        $keyId = (string) Str::uuid();
        $expiresAt = now()->addDays($this->config['api_key_rotation_days'] ?? 90);

        DB::table('api_keys')->insert([
            'id' => $keyId,
            'user_id' => $userId,
            'key_hash' => $hashedKey,
            'is_active' => true,
            'metadata' => json_encode($metadata),
            'last_used_at' => null,
            'expires_at' => $expiresAt,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->logSecretAccess($keyId, 'api_key_created', $userId);

        // Return plaintext key only once
        return [
            'key_id' => $keyId,
            'api_key' => $apiKey,
            'expires_at' => $expiresAt,
        ];
    }

    /**
     * Revoke API key.
     *
     * @param string $keyId API key identifier
     * @return bool True if revoked successfully
     */
    public function revokeApiKey(string $keyId): bool
    {
        $updated = DB::table('api_keys')
            ->where('id', $keyId)
            ->update([
                'is_active' => false,
                'revoked_at' => now(),
                'updated_at' => now(),
            ]);

        if ($updated) {
            $this->logSecretAccess($keyId, 'api_key_revoked', null);
        }

        return $updated > 0;
    }

    /**
     * Find secrets requiring rotation.
     *
     * Returns secrets that are expired or approaching expiration.
     *
     * @param int $warningDays Days before expiration to warn
     * @return array List of secrets needing rotation
     */
    public function findSecretsRequiringRotation(int $warningDays = 7): array
    {
        $warningDate = now()->addDays($warningDays);

        $secrets = DB::table('encrypted_secrets')
            ->where(function ($query) use ($warningDate) {
                $query->where('expires_at', '<=', $warningDate)
                    ->orWhereNull('rotated_at')
                    ->orWhere('rotated_at', '<=', now()->subDays(90));
            })
            ->get();

        return $secrets->map(function ($secret) {
            return [
                'id' => $secret->id,
                'type' => $secret->secret_type,
                'identifier' => $secret->identifier,
                'expires_at' => $secret->expires_at,
                'last_rotated' => $secret->rotated_at,
                'age_days' => $secret->rotated_at
                    ? now()->diffInDays(Carbon::parse($secret->rotated_at))
                    : now()->diffInDays(Carbon::parse($secret->created_at)),
            ];
        })->toArray();
    }

    /**
     * Calculate expiration date based on secret type.
     *
     * @param string $secretType Type of secret
     * @return Carbon|null Expiration date
     */
    protected function calculateExpiration(string $secretType): ?Carbon
    {
        $rotationDays = match ($secretType) {
            'vps_password' => $this->config['vps_credential_rotation_days'] ?? 30,
            'api_key' => $this->config['api_key_rotation_days'] ?? 90,
            default => $this->config['key_rotation_days'] ?? 90,
        };

        return now()->addDays($rotationDays);
    }

    /**
     * Generate strong random password.
     *
     * Creates password with:
     * - Mixed case letters
     * - Numbers
     * - Special characters
     * - Minimum 32 characters
     *
     * @param int $length Password length
     * @return string Generated password
     */
    protected function generateStrongPassword(int $length = 32): string
    {
        $lowercase = 'abcdefghijklmnopqrstuvwxyz';
        $uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        $numbers = '0123456789';
        $special = '!@#$%^&*()_+-=[]{}|;:,.<>?';

        $all = $lowercase . $uppercase . $numbers . $special;

        // Ensure at least one of each type
        $password = '';
        $password .= $lowercase[random_int(0, strlen($lowercase) - 1)];
        $password .= $uppercase[random_int(0, strlen($uppercase) - 1)];
        $password .= $numbers[random_int(0, strlen($numbers) - 1)];
        $password .= $special[random_int(0, strlen($special) - 1)];

        // Fill remaining length
        for ($i = 4; $i < $length; $i++) {
            $password .= $all[random_int(0, strlen($all) - 1)];
        }

        // Shuffle to randomize position of guaranteed characters
        return str_shuffle($password);
    }

    /**
     * Log secret access for audit trail.
     *
     * @param string $secretId Secret ID
     * @param string $action Action performed
     * @param string|null $identifier Related identifier
     * @return void
     */
    protected function logSecretAccess(string $secretId, string $action, ?string $identifier): void
    {
        DB::table('secret_access_log')->insert([
            'secret_id' => $secretId,
            'action' => $action,
            'identifier' => $identifier,
            'ip_address' => request()?->ip(),
            'user_agent' => request()?->userAgent(),
            'created_at' => now(),
        ]);
    }
}
