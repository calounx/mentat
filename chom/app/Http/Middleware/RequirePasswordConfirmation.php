<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * SECURITY: Step-Up Authentication for Sensitive Operations
 *
 * Implements "step-up authentication" pattern where users must re-confirm
 * their password before accessing highly sensitive operations, even if already
 * authenticated. This prevents session hijacking from accessing critical functions.
 *
 * OWASP Reference: A07:2021 – Identification and Authentication Failures
 * - Step-up authentication adds defense-in-depth for sensitive operations
 * - Prevents privilege escalation through session hijacking or XSS
 * - Similar to sudo requiring password re-entry on Unix systems
 *
 * Use Cases (Apply this middleware to):
 * - Viewing SSH private keys
 * - Deleting sites or databases
 * - Transferring ownership
 * - Changing security settings
 * - Accessing backup encryption keys
 * - Modifying payment methods
 *
 * Security Policy:
 * - Password confirmation valid for 10 minutes
 * - Must re-confirm after expiration
 * - Cannot be bypassed via API tokens alone
 */
class RequirePasswordConfirmation
{
    /**
     * Handle an incoming request.
     *
     * SECURITY FLOW:
     * 1. Check if user is authenticated
     * 2. Check if password was recently confirmed
     * 3. If not, require password re-confirmation
     * 4. Audit log the sensitive operation attempt
     *
     * @param  \Closure(\Illuminate\Http\Request): (\Symfony\Component\HttpFoundation\Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        // Require authentication first
        if (!$user) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => 'AUTHENTICATION_REQUIRED',
                    'message' => 'You must be authenticated to access this resource.',
                ],
            ], 401);
        }

        // Check if password was recently confirmed
        if ($user->hasRecentPasswordConfirmation()) {
            // Password confirmed recently - allow access
            return $next($request);
        }

        // Password confirmation required
        return response()->json([
            'success' => false,
            'error' => [
                'code' => 'PASSWORD_CONFIRMATION_REQUIRED',
                'message' => 'This operation requires password re-confirmation for security.',
                'confirm_url' => route('auth.password.confirm'),
                'expires_after' => '10 minutes',
                'reason' => 'Sensitive operation requires additional verification',
            ],
        ], 403);
    }
}
