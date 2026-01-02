<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\V1\TwoFactor\ConfirmTwoFactorRequest;
use App\Http\Requests\V1\TwoFactor\DisableTwoFactorRequest;
use App\Models\AuditLog;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

/**
 * Two-Factor Authentication Controller
 *
 * Manages the complete 2FA lifecycle for user accounts including:
 * - Enabling 2FA (QR code generation)
 * - Confirming 2FA setup with TOTP verification
 * - Disabling 2FA with password confirmation
 * - Managing recovery codes
 * - Verifying 2FA codes during authentication
 *
 * SECURITY FEATURES:
 * - TOTP (Time-based One-Time Password) using Google Authenticator protocol
 * - Encrypted secret storage (AES-256-CBC)
 * - Hashed recovery codes
 * - Password confirmation for sensitive operations
 * - Rate limiting on verification attempts
 * - Comprehensive audit logging
 *
 * OWASP Reference: A07:2021 – Identification and Authentication Failures
 */
class TwoFactorAuthenticationController extends Controller
{
    /**
     * Enable two-factor authentication.
     *
     * Generates a new 2FA secret and QR code for the user.
     * The secret is stored but 2FA is not enabled until confirmed.
     *
     * SECURITY NOTES:
     * - Secret is encrypted at rest via User model cast
     * - QR code is returned as SVG data
     * - Recovery codes generated immediately
     * - User must verify code before 2FA is fully enabled
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function enable(Request $request): JsonResponse
    {
        $user = $request->user();

        // SECURITY: Prevent re-enabling if already confirmed without password
        if ($user->two_factor_enabled && !$user->hasRecentPasswordConfirmation()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'PASSWORD_CONFIRMATION_REQUIRED',
                    'message' => 'Password confirmation required to reset 2FA settings.',
                ],
            ], 403);
        }

        try {
            // Generate secret, QR code, and recovery codes
            $data = $user->enableTwoFactorAuthentication();

            // AUDIT: Log 2FA setup initiation
            AuditLog::log(
                'user.2fa_enable_initiated',
                userId: $user->id,
                resourceType: 'User',
                resourceId: $user->id,
                metadata: [
                    'requires_2fa' => $user->requires2FA(),
                    'in_grace_period' => $user->isIn2FAGracePeriod(),
                ],
                severity: 'low'
            );

            return response()->json([
                'success' => true,
                'message' => 'Two-factor authentication has been initialized. Please scan the QR code and verify with a code.',
                'data' => [
                    'qr_code' => $data['qr_code'],
                    'secret' => $data['secret'],
                    'recovery_codes' => $data['recovery_codes'],
                    'manual_entry_key' => chunk_split($data['secret'], 4, ' '),
                    'next_step' => 'Scan QR code with authenticator app and call /confirm endpoint',
                ],
            ], 200);

        } catch (\Exception $e) {
            // AUDIT: Log failure
            AuditLog::log(
                'user.2fa_enable_failed',
                userId: $user->id,
                resourceType: 'User',
                resourceId: $user->id,
                metadata: ['error' => $e->getMessage()],
                severity: 'medium'
            );

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'ENABLE_2FA_FAILED',
                    'message' => 'Failed to enable two-factor authentication.',
                ],
            ], 500);
        }
    }

    /**
     * Confirm two-factor authentication setup.
     *
     * Verifies the TOTP code from user's authenticator app.
     * Marks 2FA as confirmed and enabled only after successful verification.
     *
     * SECURITY NOTES:
     * - Code must be exactly 6 digits
     * - Verified against temporary secret
     * - 2FA not enabled until this step succeeds
     * - Rate limited to prevent brute force
     *
     * @param ConfirmTwoFactorRequest $request
     * @return JsonResponse
     */
    public function confirm(ConfirmTwoFactorRequest $request): JsonResponse
    {
        $user = $request->user();
        $code = $request->validated()['code'];

        // Check if 2FA secret exists but not yet confirmed
        if (!$user->two_factor_secret) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => '2FA_NOT_INITIALIZED',
                    'message' => 'Please call /enable endpoint first to initialize 2FA.',
                ],
            ], 400);
        }

        if ($user->two_factor_enabled) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => '2FA_ALREADY_ENABLED',
                    'message' => 'Two-factor authentication is already enabled.',
                ],
            ], 400);
        }

        // Verify the code
        if (!$user->verifyTwoFactorCode($code)) {
            // AUDIT: Log failed verification
            AuditLog::log(
                'user.2fa_confirm_failed',
                userId: $user->id,
                resourceType: 'User',
                resourceId: $user->id,
                metadata: ['reason' => 'Invalid TOTP code'],
                severity: 'medium'
            );

            throw ValidationException::withMessages([
                'code' => ['The verification code is invalid or has expired.'],
            ]);
        }

        // Confirm and enable 2FA
        $user->confirmTwoFactorAuthentication();

        // Mark 2FA as verified in session
        $request->session()->put('2fa_verified', true);
        $request->session()->put('2fa_verified_at', now());

        // AUDIT: Log successful 2FA activation
        AuditLog::log(
            'user.2fa_enabled',
            userId: $user->id,
            resourceType: 'User',
            resourceId: $user->id,
            metadata: [
                'recovery_codes_count' => count($user->two_factor_backup_codes ?? []),
            ],
            severity: 'high'
        );

        return response()->json([
            'success' => true,
            'message' => 'Two-factor authentication has been enabled successfully.',
            'data' => [
                'enabled' => true,
                'confirmed_at' => $user->two_factor_confirmed_at->toIso8601String(),
                'recovery_codes_remaining' => count($user->two_factor_backup_codes ?? []),
            ],
        ], 200);
    }

    /**
     * Disable two-factor authentication.
     *
     * Disables 2FA and clears all related secrets and codes.
     * Requires password confirmation for security.
     *
     * SECURITY NOTES:
     * - Password verification handled by DisableTwoFactorRequest
     * - Cannot disable if 2FA is required for user's role
     * - Clears all 2FA data including secrets and recovery codes
     * - Comprehensive audit logging
     *
     * @param DisableTwoFactorRequest $request
     * @return JsonResponse
     */
    public function disable(DisableTwoFactorRequest $request): JsonResponse
    {
        $user = $request->user();

        if (!$user->two_factor_enabled) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => '2FA_NOT_ENABLED',
                    'message' => 'Two-factor authentication is not enabled.',
                ],
            ], 400);
        }

        // Disable 2FA (clears all data)
        $user->disableTwoFactorAuthentication();

        // Clear 2FA session
        $request->session()->forget(['2fa_verified', '2fa_verified_at']);

        // AUDIT: Log 2FA disablement
        AuditLog::log(
            'user.2fa_disabled',
            userId: $user->id,
            resourceType: 'User',
            resourceId: $user->id,
            severity: 'high'
        );

        return response()->json([
            'success' => true,
            'message' => 'Two-factor authentication has been disabled successfully.',
            'data' => [
                'enabled' => false,
            ],
        ], 200);
    }

    /**
     * Get current recovery codes.
     *
     * Returns the count of remaining recovery codes.
     * Requires password confirmation to view actual codes.
     *
     * SECURITY NOTES:
     * - Codes are hashed in database
     * - Cannot return actual codes (one-way hash)
     * - Only shows count and status
     * - Password confirmation required
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function recoveryCodes(Request $request): JsonResponse
    {
        $user = $request->user();

        if (!$user->two_factor_enabled) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => '2FA_NOT_ENABLED',
                    'message' => 'Two-factor authentication is not enabled.',
                ],
            ], 400);
        }

        // SECURITY: Require password confirmation
        if (!$user->hasRecentPasswordConfirmation()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'PASSWORD_CONFIRMATION_REQUIRED',
                    'message' => 'Password confirmation required to view recovery codes.',
                ],
            ], 403);
        }

        $codesRemaining = count($user->two_factor_backup_codes ?? []);

        return response()->json([
            'success' => true,
            'data' => [
                'recovery_codes_remaining' => $codesRemaining,
                'warning' => $codesRemaining <= 2
                    ? 'You have only ' . $codesRemaining . ' recovery codes remaining. Consider regenerating them.'
                    : null,
                'note' => 'Recovery codes are hashed and cannot be retrieved. Use /regenerate endpoint to create new codes.',
            ],
        ], 200);
    }

    /**
     * Regenerate recovery codes.
     *
     * Generates new recovery codes and invalidates all existing ones.
     * Requires password confirmation.
     *
     * SECURITY NOTES:
     * - All old recovery codes are invalidated
     * - New codes returned in plain text (shown only once)
     * - Codes are hashed before storage
     * - Password confirmation required
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function regenerateRecoveryCodes(Request $request): JsonResponse
    {
        $user = $request->user();

        if (!$user->two_factor_enabled) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => '2FA_NOT_ENABLED',
                    'message' => 'Two-factor authentication must be enabled to regenerate recovery codes.',
                ],
            ], 400);
        }

        // SECURITY: Require password confirmation
        if (!$user->hasRecentPasswordConfirmation()) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'PASSWORD_CONFIRMATION_REQUIRED',
                    'message' => 'Password confirmation required to regenerate recovery codes.',
                ],
            ], 403);
        }

        // Generate new recovery codes
        $recoveryCodes = $user->generateRecoveryCodes();

        // AUDIT: Log recovery code regeneration
        AuditLog::log(
            'user.2fa_recovery_codes_regenerated',
            userId: $user->id,
            resourceType: 'User',
            resourceId: $user->id,
            metadata: ['codes_generated' => count($recoveryCodes)],
            severity: 'high'
        );

        return response()->json([
            'success' => true,
            'message' => 'Recovery codes have been regenerated successfully.',
            'data' => [
                'recovery_codes' => $recoveryCodes,
                'warning' => 'Previous recovery codes are now invalid. Store these codes securely - they will not be shown again.',
            ],
        ], 200);
    }

    /**
     * Verify two-factor authentication code.
     *
     * Verifies a TOTP code or recovery code during login or session validation.
     * Supports both 6-digit TOTP codes and 10-character recovery codes.
     *
     * SECURITY NOTES:
     * - Rate limited to prevent brute force
     * - Recovery codes are single-use
     * - Warns when recovery codes are running low
     * - Comprehensive audit logging
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function verify(Request $request): JsonResponse
    {
        $request->validate([
            'code' => 'required|string|min:6|max:10',
        ]);

        $user = $request->user();
        $code = $request->input('code');

        if (!$user->two_factor_enabled) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => '2FA_NOT_ENABLED',
                    'message' => 'Two-factor authentication is not enabled for your account.',
                ],
            ], 400);
        }

        // Determine code type
        $isRecoveryCode = strlen($code) === 10;
        $isTotpCode = strlen($code) === 6 && ctype_digit($code);

        if (!$isRecoveryCode && !$isTotpCode) {
            throw ValidationException::withMessages([
                'code' => ['The code must be either a 6-digit TOTP code or a 10-character recovery code.'],
            ]);
        }

        // Verify the code
        $codesRemainingBefore = count($user->two_factor_backup_codes ?? []);
        $valid = $user->verifyTwoFactorCode($code);

        if (!$valid) {
            // AUDIT: Log failed verification
            AuditLog::log(
                'user.2fa_verification_failed',
                userId: $user->id,
                resourceType: 'User',
                resourceId: $user->id,
                metadata: [
                    'code_type' => $isRecoveryCode ? 'recovery' : 'totp',
                    'ip_address' => $request->ip(),
                ],
                severity: 'high'
            );

            throw ValidationException::withMessages([
                'code' => ['The verification code is invalid or has already been used.'],
            ]);
        }

        // Mark as verified in session
        $request->session()->put('2fa_verified', true);
        $request->session()->put('2fa_verified_at', now());

        // Check if recovery code was used
        $codesRemainingAfter = count($user->two_factor_backup_codes ?? []);
        $usedRecoveryCode = $codesRemainingAfter < $codesRemainingBefore;
        $method = $usedRecoveryCode ? 'recovery' : 'totp';

        // Warn if running low on recovery codes
        if ($usedRecoveryCode && $codesRemainingAfter <= 2) {
            AuditLog::log(
                'user.2fa_recovery_codes_low',
                userId: $user->id,
                resourceType: 'User',
                resourceId: $user->id,
                metadata: ['remaining_codes' => $codesRemainingAfter],
                severity: 'medium'
            );
        }

        // AUDIT: Log successful verification
        AuditLog::log(
            'user.2fa_verified',
            userId: $user->id,
            resourceType: 'User',
            resourceId: $user->id,
            metadata: [
                'method' => $method,
                'ip_address' => $request->ip(),
                'user_agent' => $request->userAgent(),
            ],
            severity: 'low'
        );

        $response = [
            'success' => true,
            'message' => 'Two-factor authentication verified successfully.',
            'data' => [
                'verified_at' => now()->toIso8601String(),
                'method' => $method,
            ],
        ];

        if ($usedRecoveryCode) {
            $response['data']['recovery_codes_remaining'] = $codesRemainingAfter;
            if ($codesRemainingAfter <= 2) {
                $response['data']['warning'] = 'You have only ' . $codesRemainingAfter . ' recovery codes remaining. Consider regenerating them.';
            }
        }

        return response()->json($response, 200);
    }
}
