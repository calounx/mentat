<?php

declare(strict_types=1);

namespace App\Modules\Auth\Contracts;

use App\Models\User;

/**
 * Two-Factor Authentication Service Contract
 *
 * Defines the contract for 2FA operations within the Identity & Access module.
 */
interface TwoFactorInterface
{
    /**
     * Enable two-factor authentication for a user.
     *
     * @param string $userId User ID
     * @return array QR code data and recovery codes
     * @throws \RuntimeException
     */
    public function enable(string $userId): array;

    /**
     * Disable two-factor authentication for a user.
     *
     * @param string $userId User ID
     * @param string $password User password for verification
     * @return bool Success status
     * @throws \RuntimeException
     */
    public function disable(string $userId, string $password): bool;

    /**
     * Verify a two-factor authentication code.
     *
     * @param string $userId User ID
     * @param string $code 2FA code
     * @return bool Verification result
     */
    public function verify(string $userId, string $code): bool;

    /**
     * Generate new recovery codes.
     *
     * @param string $userId User ID
     * @return array Recovery codes
     * @throws \RuntimeException
     */
    public function generateRecoveryCodes(string $userId): array;

    /**
     * Verify a recovery code.
     *
     * @param string $userId User ID
     * @param string $code Recovery code
     * @return bool Verification result
     */
    public function verifyRecoveryCode(string $userId, string $code): bool;

    /**
     * Check if user has 2FA enabled.
     *
     * @param string $userId User ID
     * @return bool 2FA status
     */
    public function isEnabled(string $userId): bool;
}
