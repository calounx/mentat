<?php

namespace App\Services\Secrets;

use App\Jobs\RotateVpsCredentialsJob;
use App\Models\AuditLog;
use App\Models\VpsServer;
use Illuminate\Support\Facades\Process;
use Illuminate\Support\Str;

/**
 * SECURITY: Automated Secrets and Credentials Rotation
 *
 * Implements automated rotation of cryptographic keys and credentials to limit
 * the window of exposure if credentials are compromised. Regular rotation is a
 * key defense-in-depth security control.
 *
 * OWASP Reference: A02:2021 – Cryptographic Failures
 * - Regular key rotation limits exposure window if keys are compromised
 * - Implements "cryptographic agility" - ability to change keys smoothly
 * - Prevents accumulation of stale credentials across infrastructure
 *
 * NIST SP 800-57: Key rotation every 90 days for SSH keys
 * PCI DSS: Key rotation for payment processing systems
 *
 * Rotation Strategy:
 * - SSH Keys: Every 90 days
 * - API Keys: On-demand or annually
 * - Database Credentials: Annually or on breach
 * - Graceful rollover: Both old and new keys valid during transition (24h)
 *
 * Security Features:
 * - Zero-downtime key rotation with overlap period
 * - Automatic deployment to all VPS servers
 * - Comprehensive audit logging
 * - Rollback capability if deployment fails
 * - Secure deletion of old keys
 */
class SecretsRotationService
{
    /**
     * Rotate VPS server SSH credentials.
     *
     * SECURITY FLOW:
     * 1. Generate new SSH key pair (ED25519, 256-bit)
     * 2. Deploy new public key to VPS server (keep old key)
     * 3. Test new key works correctly
     * 4. Update database with new private key (encrypted)
     * 5. Schedule old key removal after 24 hour overlap
     * 6. Audit log the rotation
     *
     * @param  VpsServer  $vps  The VPS server to rotate credentials for
     * @return array Rotation result with new key information
     *
     * @throws \RuntimeException If rotation fails
     */
    public function rotateVpsCredentials(VpsServer $vps): array
    {
        AuditLog::log(
            'vps.credentials_rotation_started',
            resourceType: 'VpsServer',
            resourceId: $vps->id,
            metadata: [
                'last_rotation' => $vps->key_rotated_at?->toIso8601String(),
                'days_since_rotation' => $vps->key_rotated_at?->diffInDays(now()),
            ],
            severity: 'high'
        );

        try {
            // STEP 1: Generate new ED25519 SSH key pair (most secure)
            $newKeyPair = $this->generateSshKeyPair($vps->name);

            // STEP 2: Deploy new public key to VPS (both keys will work)
            $this->deployPublicKey($vps, $newKeyPair['public']);

            // STEP 3: Test new key authentication
            $this->testNewKey($vps, $newKeyPair['private']);

            // STEP 4: Store old private key for 24h rollback window
            $oldPrivateKey = $vps->ssh_private_key;
            $oldPublicKey = $vps->ssh_public_key;

            // STEP 5: Update database with new credentials (encrypted at rest)
            $vps->update([
                'ssh_private_key' => $newKeyPair['private'],
                'ssh_public_key' => $newKeyPair['public'],
                'key_rotated_at' => now(),
                // Store old keys for 24h emergency rollback
                'previous_ssh_private_key' => $oldPrivateKey,
                'previous_ssh_public_key' => $oldPublicKey,
            ]);

            // STEP 6: Schedule old key removal after 24 hour overlap
            RotateVpsCredentialsJob::dispatch($vps, 'cleanup_old_key')
                ->delay(now()->addDay());

            // AUDIT: Log successful rotation
            AuditLog::log(
                'vps.credentials_rotated',
                resourceType: 'VpsServer',
                resourceId: $vps->id,
                metadata: [
                    'rotation_date' => now()->toIso8601String(),
                    'key_algorithm' => 'ed25519',
                    'key_size' => 256,
                    'overlap_period_hours' => 24,
                ],
                severity: 'high'
            );

            return [
                'success' => true,
                'vps_id' => $vps->id,
                'rotated_at' => now()->toIso8601String(),
                'next_rotation_due' => now()->addDays(90)->toIso8601String(),
                'overlap_period_ends' => now()->addDay()->toIso8601String(),
            ];

        } catch (\Exception $e) {
            // AUDIT: Log rotation failure
            AuditLog::log(
                'vps.credentials_rotation_failed',
                resourceType: 'VpsServer',
                resourceId: $vps->id,
                metadata: [
                    'error' => $e->getMessage(),
                    'trace' => $e->getTraceAsString(),
                ],
                severity: 'critical'
            );

            throw new \RuntimeException(
                "Failed to rotate credentials for VPS {$vps->name}: {$e->getMessage()}",
                previous: $e
            );
        }
    }

    /**
     * Remove old SSH key from VPS server after overlap period.
     *
     * SECURITY NOTES:
     * - Called 24 hours after new key deployment
     * - Removes old public key from authorized_keys
     * - Securely wipes old private key from database
     */
    public function cleanupOldKey(VpsServer $vps): void
    {
        if (! $vps->previous_ssh_public_key) {
            return; // Nothing to clean up
        }

        try {
            // Extract key fingerprint from old public key for removal
            $oldKeyFingerprint = $this->extractKeyFingerprint($vps->previous_ssh_public_key);

            // Remove old key from VPS authorized_keys
            $command = "sed -i '/{$oldKeyFingerprint}/d' ~/.ssh/authorized_keys";
            $this->executeRemoteCommand($vps, $command);

            // Secure wipe of old keys from database
            $vps->update([
                'previous_ssh_private_key' => null,
                'previous_ssh_public_key' => null,
            ]);

            AuditLog::log(
                'vps.old_credentials_removed',
                resourceType: 'VpsServer',
                resourceId: $vps->id,
                metadata: ['removed_at' => now()->toIso8601String()],
                severity: 'medium'
            );

        } catch (\Exception $e) {
            AuditLog::log(
                'vps.old_credentials_cleanup_failed',
                resourceType: 'VpsServer',
                resourceId: $vps->id,
                metadata: ['error' => $e->getMessage()],
                severity: 'high'
            );

            throw $e;
        }
    }

    /**
     * Rotate API token for a user or organization.
     *
     * SECURITY NOTES:
     * - Generates cryptographically secure random token
     * - Invalidates old token immediately (no overlap period for API tokens)
     * - Tokens are hashed before storage (SHA-256)
     *
     * @param  \Illuminate\Database\Eloquent\Model  $model  User or Organization
     * @return array New token information
     */
    public function rotateApiToken($model): array
    {
        // Generate cryptographically secure token (256-bit entropy)
        $token = bin2hex(random_bytes(32));

        // Hash token before storage (only hash stored, not plain token)
        $hashedToken = hash('sha256', $token);

        $model->update([
            'api_token' => $hashedToken,
            'api_token_rotated_at' => now(),
        ]);

        AuditLog::log(
            'api_token_rotated',
            resourceType: get_class($model),
            resourceId: $model->id,
            metadata: [
                'rotated_at' => now()->toIso8601String(),
                'token_preview' => substr($token, 0, 8).'...',
            ],
            severity: 'high'
        );

        return [
            'success' => true,
            'token' => $token, // Return plain token ONCE
            'token_preview' => substr($token, 0, 8).'...',
            'rotated_at' => now()->toIso8601String(),
            'warning' => 'Save this token securely. It will not be shown again.',
        ];
    }

    /**
     * Check all VPS servers and identify those needing key rotation.
     *
     * @return \Illuminate\Support\Collection<VpsServer>
     */
    public function getServersNeedingRotation()
    {
        return VpsServer::where(function ($query) {
            $query->whereNull('key_rotated_at')
                ->orWhere('key_rotated_at', '<', now()->subDays(90));
        })->get();
    }

    /**
     * Rotate all VPS credentials that are due for rotation.
     *
     * @return array Summary of rotation operations
     */
    public function rotateAllDueCredentials(): array
    {
        $servers = $this->getServersNeedingRotation();
        $results = [
            'total' => $servers->count(),
            'successful' => 0,
            'failed' => 0,
            'errors' => [],
        ];

        foreach ($servers as $vps) {
            try {
                $this->rotateVpsCredentials($vps);
                $results['successful']++;
            } catch (\Exception $e) {
                $results['failed']++;
                $results['errors'][] = [
                    'vps_id' => $vps->id,
                    'vps_name' => $vps->name,
                    'error' => $e->getMessage(),
                ];
            }
        }

        return $results;
    }

    /**
     * Generate new SSH key pair using ED25519 algorithm.
     *
     * SECURITY NOTES:
     * - ED25519: Most secure SSH algorithm (2023)
     * - 256-bit security (equivalent to RSA 3072-bit)
     * - Fast and resistant to timing attacks
     * - No passphrase (stored encrypted in database instead)
     *
     * @param  string  $comment  Key comment/identifier
     * @return array ['private' => string, 'public' => string]
     */
    protected function generateSshKeyPair(string $comment): array
    {
        $tempDir = sys_get_temp_dir();
        $keyName = 'chom_rotation_'.Str::random(16);
        $keyPath = "{$tempDir}/{$keyName}";

        try {
            // Generate ED25519 key pair (no passphrase, encrypted at rest in DB)
            $result = Process::run([
                'ssh-keygen',
                '-t', 'ed25519',
                '-C', "chom-vps-{$comment}",
                '-f', $keyPath,
                '-N', '', // No passphrase (encrypted by Laravel)
            ]);

            if (! $result->successful()) {
                throw new \RuntimeException("SSH key generation failed: {$result->errorOutput()}");
            }

            // Read generated keys
            $privateKey = file_get_contents($keyPath);
            $publicKey = file_get_contents("{$keyPath}.pub");

            // Secure deletion of temporary files
            unlink($keyPath);
            unlink("{$keyPath}.pub");

            return [
                'private' => $privateKey,
                'public' => $publicKey,
            ];

        } catch (\Exception $e) {
            // Cleanup on failure
            @unlink($keyPath);
            @unlink("{$keyPath}.pub");
            throw $e;
        }
    }

    /**
     * Deploy new public key to VPS server.
     */
    protected function deployPublicKey(VpsServer $vps, string $publicKey): void
    {
        // Add new key to authorized_keys (keeps old key too)
        $command = "echo '{$publicKey}' >> ~/.ssh/authorized_keys";
        $this->executeRemoteCommand($vps, $command);
    }

    /**
     * Test new SSH key authentication.
     *
     * @throws \RuntimeException If test fails
     */
    protected function testNewKey(VpsServer $vps, string $privateKey): void
    {
        // Write private key to temporary file
        $tempKeyPath = sys_get_temp_dir().'/test_key_'.Str::random(16);
        file_put_contents($tempKeyPath, $privateKey);
        chmod($tempKeyPath, 0600);

        try {
            $result = Process::run([
                'ssh',
                '-i', $tempKeyPath,
                '-o', 'StrictHostKeyChecking=no',
                '-o', 'BatchMode=yes',
                '-o', 'ConnectTimeout=10',
                '-p', $vps->ssh_port,
                "{$vps->ssh_user}@{$vps->ip}",
                'echo "test"',
            ]);

            unlink($tempKeyPath);

            if (! $result->successful()) {
                throw new \RuntimeException('New key authentication test failed');
            }
        } catch (\Exception $e) {
            @unlink($tempKeyPath);
            throw $e;
        }
    }

    /**
     * Execute command on remote VPS using current credentials.
     */
    protected function executeRemoteCommand(VpsServer $vps, string $command): void
    {
        $tempKeyPath = sys_get_temp_dir().'/vps_key_'.Str::random(16);
        file_put_contents($tempKeyPath, $vps->ssh_private_key);
        chmod($tempKeyPath, 0600);

        try {
            $result = Process::run([
                'ssh',
                '-i', $tempKeyPath,
                '-o', 'StrictHostKeyChecking=no',
                '-p', $vps->ssh_port,
                "{$vps->ssh_user}@{$vps->ip}",
                $command,
            ]);

            unlink($tempKeyPath);

            if (! $result->successful()) {
                throw new \RuntimeException("Remote command failed: {$result->errorOutput()}");
            }
        } catch (\Exception $e) {
            @unlink($tempKeyPath);
            throw $e;
        }
    }

    /**
     * Extract key fingerprint from public key for identification.
     */
    protected function extractKeyFingerprint(string $publicKey): string
    {
        // Extract key data (second field of public key)
        $parts = explode(' ', trim($publicKey));

        return $parts[1] ?? '';
    }
}
