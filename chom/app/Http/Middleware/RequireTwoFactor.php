<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * SECURITY: Enforce Two-Factor Authentication for Privileged Accounts
 *
 * This middleware implements mandatory 2FA for owner and admin roles as part of
 * defense-in-depth strategy. Even if primary credentials are compromised, 2FA
 * provides an additional security layer.
 *
 * OWASP Reference: A07:2021 – Identification and Authentication Failures
 * - Multi-factor authentication prevents 99.9% of account compromise attacks
 * - Privileged accounts MUST have stronger authentication requirements
 *
 * Security Policy:
 * - Owner and Admin roles: 2FA REQUIRED after 7-day grace period
 * - Member and Viewer roles: 2FA OPTIONAL
 * - Grace period: 7 days from account creation to configure 2FA
 * - Bypass routes: Authentication and 2FA setup endpoints only
 */
class RequireTwoFactor
{
    /**
     * Routes that should bypass 2FA enforcement.
     *
     * SECURITY RATIONALE:
     * - auth.login: Need to authenticate before checking 2FA
     * - auth.register: New users need to create account first
     * - auth.2fa.*: Users must access 2FA endpoints to set up 2FA
     * - auth.logout: Allow users to log out even without 2FA
     * - health: Monitoring endpoints should not require 2FA
     *
     * WARNING: Adding routes here weakens security posture.
     * Only add routes that are absolutely necessary for 2FA setup.
     */
    protected array $except = [
        'auth.login',
        'auth.register',
        'auth.2fa.setup',
        'auth.2fa.verify',
        'auth.2fa.confirm',
        'auth.2fa.recovery',
        'auth.logout',
        'health',
        'health.basic',
    ];

    /**
     * Handle an incoming request.
     *
     * @param  \Closure(\Illuminate\Http\Request): (\Symfony\Component\HttpFoundation\Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        // Skip if no authenticated user
        if (!$user) {
            return $next($request);
        }

        // Skip if route is in exception list
        if ($this->shouldBypass($request)) {
            return $next($request);
        }

        // Check if 2FA is required for this user's role
        if (!$user->requires2FA()) {
            return $next($request);
        }

        // SECURITY CHECK 1: Is 2FA enabled?
        if (!$user->two_factor_enabled) {
            // Check if user is within grace period
            if ($user->isIn2FAGracePeriod()) {
                // Within grace period - allow access but warn user
                $gracePeriodDays = config('auth.two_factor_authentication.grace_period_days', 7);
                return $next($request)->header(
                    'X-2FA-Required-Soon',
                    'Two-factor authentication will be required after ' .
                    $user->created_at->addDays($gracePeriodDays)->toIso8601String()
                );
            }

            // Grace period expired - 2FA setup is mandatory
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => '2FA_SETUP_REQUIRED',
                    'message' => 'Two-factor authentication is required for your account. Please set up 2FA to continue.',
                    'setup_url' => route('auth.2fa.setup'),
                    'grace_period_expired' => true,
                ],
            ], 403);
        }

        // SECURITY CHECK 2: Is 2FA verified in this session?
        if (!$request->session()->get('2fa_verified', false)) {
            return response()->json([
                'success' => false,
                'error' => [
                    'code' => '2FA_VERIFICATION_REQUIRED',
                    'message' => 'Please verify your two-factor authentication code.',
                    'verify_url' => route('auth.2fa.verify'),
                ],
            ], 403);
        }

        // SECURITY CHECK 3: Has 2FA session expired?
        $verified_at = $request->session()->get('2fa_verified_at');
        $sessionTimeoutHours = config('auth.two_factor_authentication.session_timeout_hours', 24);

        if ($verified_at && now()->diffInHours($verified_at) >= $sessionTimeoutHours) {
            // 2FA verification expires after configured hours for security
            $request->session()->forget(['2fa_verified', '2fa_verified_at']);

            return response()->json([
                'success' => false,
                'error' => [
                    'code' => '2FA_SESSION_EXPIRED',
                    'message' => 'Your two-factor authentication session has expired. Please verify again.',
                    'verify_url' => route('auth.2fa.verify'),
                ],
            ], 403);
        }

        // All 2FA checks passed
        return $next($request);
    }

    /**
     * Determine if the request should bypass 2FA enforcement.
     */
    protected function shouldBypass(Request $request): bool
    {
        $routeName = $request->route()?->getName();

        if (!$routeName) {
            return false;
        }

        // Check exact route name match
        if (in_array($routeName, $this->except)) {
            return true;
        }

        // Check wildcard patterns (e.g., 'auth.2fa.*')
        foreach ($this->except as $pattern) {
            if (str_contains($pattern, '*')) {
                $pattern = str_replace('*', '.*', $pattern);
                if (preg_match('/^' . $pattern . '$/', $routeName)) {
                    return true;
                }
            }
        }

        return false;
    }
}
