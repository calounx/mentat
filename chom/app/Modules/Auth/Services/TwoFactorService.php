<?php

declare(strict_types=1);

namespace App\Modules\Auth\Services;

use App\Models\User;
use App\Modules\Auth\Contracts\TwoFactorInterface;
use App\Modules\Auth\Events\TwoFactorDisabled;
use App\Modules\Auth\Events\TwoFactorEnabled;
use App\Modules\Auth\ValueObjects\TwoFactorSecret;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use PragmaRX\Google2FA\Google2FA;

/**
 * Two-Factor Authentication Service
 *
 * Handles 2FA operations including enabling/disabling, code verification,
 * and recovery code management.
 */
class TwoFactorService implements TwoFactorInterface
{
    private Google2FA $google2fa;

    public function __construct()
    {
        $this->google2fa = new Google2FA();
    }

    /**
     * Enable two-factor authentication for a user.
     *
     * @param string $userId User ID
     * @return array QR code data and recovery codes
     * @throws \RuntimeException
     */
    public function enable(string $userId): array
    {
        try {
            $user = User::find($userId);

            if (!$user) {
                throw new \RuntimeException('User not found');
            }

            if ($this->isEnabled($userId)) {
                throw new \RuntimeException('Two-factor authentication is already enabled');
            }

            // Generate secret
            $secret = $this->google2fa->generateSecretKey();
            $recoveryCodes = $this->generateRecoveryCodesArray();

            // Store encrypted secret and recovery codes
            $user->update([
                'two_factor_secret' => Crypt::encryptString($secret),
                'two_factor_recovery_codes' => Crypt::encryptString(json_encode($recoveryCodes)),
                'two_factor_enabled_at' => now(),
            ]);

            // Generate QR code URL
            $qrCodeUrl = $this->google2fa->getQRCodeUrl(
                config('app.name'),
                $user->email,
                $secret
            );

            Log::info('Two-factor authentication enabled', [
                'user_id' => $userId,
                'email' => $user->email,
            ]);

            Event::dispatch(new TwoFactorEnabled($user));

            return [
                'secret' => $secret,
                'qr_code_url' => $qrCodeUrl,
                'recovery_codes' => $recoveryCodes,
            ];
        } catch (\Exception $e) {
            Log::error('Failed to enable two-factor authentication', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to enable two-factor authentication: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Disable two-factor authentication for a user.
     *
     * @param string $userId User ID
     * @param string $password User password for verification
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function disable(string $userId, string $password): bool
    {
        try {
            $user = User::find($userId);

            if (!$user) {
                throw new \RuntimeException('User not found');
            }

            if (!Hash::check($password, $user->password)) {
                throw new \RuntimeException('Invalid password');
            }

            if (!$this->isEnabled($userId)) {
                throw new \RuntimeException('Two-factor authentication is not enabled');
            }

            $user->update([
                'two_factor_secret' => null,
                'two_factor_recovery_codes' => null,
                'two_factor_enabled_at' => null,
            ]);

            Log::info('Two-factor authentication disabled', [
                'user_id' => $userId,
                'email' => $user->email,
            ]);

            Event::dispatch(new TwoFactorDisabled($user));

            return true;
        } catch (\Exception $e) {
            Log::error('Failed to disable two-factor authentication', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to disable two-factor authentication: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Verify a two-factor authentication code.
     *
     * @param string $userId User ID
     * @param string $code 2FA code
     * @return bool Verification result
     */
    public function verify(string $userId, string $code): bool
    {
        try {
            $user = User::find($userId);

            if (!$user || !$this->isEnabled($userId)) {
                return false;
            }

            $secret = Crypt::decryptString($user->two_factor_secret);

            $valid = $this->google2fa->verifyKey($secret, $code);

            if ($valid) {
                Log::debug('Two-factor code verified', [
                    'user_id' => $userId,
                ]);
            } else {
                Log::warning('Two-factor code verification failed', [
                    'user_id' => $userId,
                ]);
            }

            return $valid;
        } catch (\Exception $e) {
            Log::error('Two-factor verification error', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Generate new recovery codes.
     *
     * @param string $userId User ID
     * @return array Recovery codes
     * @throws \RuntimeException
     */
    public function generateRecoveryCodes(string $userId): array
    {
        try {
            $user = User::find($userId);

            if (!$user) {
                throw new \RuntimeException('User not found');
            }

            if (!$this->isEnabled($userId)) {
                throw new \RuntimeException('Two-factor authentication is not enabled');
            }

            $recoveryCodes = $this->generateRecoveryCodesArray();

            $user->update([
                'two_factor_recovery_codes' => Crypt::encryptString(json_encode($recoveryCodes)),
            ]);

            Log::info('Recovery codes regenerated', [
                'user_id' => $userId,
            ]);

            return $recoveryCodes;
        } catch (\Exception $e) {
            Log::error('Failed to generate recovery codes', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);

            throw new \RuntimeException('Failed to generate recovery codes: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
     * Verify a recovery code.
     *
     * @param string $userId User ID
     * @param string $code Recovery code
     * @return bool Verification result
     */
    public function verifyRecoveryCode(string $userId, string $code): bool
    {
        try {
            $user = User::find($userId);

            if (!$user || !$this->isEnabled($userId)) {
                return false;
            }

            $recoveryCodes = json_decode(
                Crypt::decryptString($user->two_factor_recovery_codes),
                true
            );

            if (!is_array($recoveryCodes)) {
                return false;
            }

            $codeIndex = array_search($code, $recoveryCodes, true);

            if ($codeIndex === false) {
                Log::warning('Invalid recovery code used', [
                    'user_id' => $userId,
                ]);
                return false;
            }

            // Remove used recovery code
            unset($recoveryCodes[$codeIndex]);
            $recoveryCodes = array_values($recoveryCodes);

            $user->update([
                'two_factor_recovery_codes' => Crypt::encryptString(json_encode($recoveryCodes)),
            ]);

            Log::info('Recovery code used', [
                'user_id' => $userId,
                'remaining_codes' => count($recoveryCodes),
            ]);

            return true;
        } catch (\Exception $e) {
            Log::error('Recovery code verification error', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Check if user has 2FA enabled.
     *
     * @param string $userId User ID
     * @return bool 2FA status
     */
    public function isEnabled(string $userId): bool
    {
        try {
            $user = User::find($userId);

            return $user && !is_null($user->two_factor_secret) && !is_null($user->two_factor_enabled_at);
        } catch (\Exception $e) {
            Log::error('2FA status check error', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Generate array of recovery codes.
     *
     * @return array Recovery codes
     */
    private function generateRecoveryCodesArray(): array
    {
        $codes = [];

        for ($i = 0; $i < 8; $i++) {
            $codes[] = Str::random(10);
        }

        return $codes;
    }
}
