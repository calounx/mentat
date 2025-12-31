<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Config;
use Laravel\Sanctum\PersonalAccessToken;
use Symfony\Component\HttpFoundation\Response;

/**
 * Token Rotation Middleware
 *
 * SECURITY: Automatically rotates API tokens approaching expiration to maintain
 * secure sessions with short-lived tokens. This implements a critical security
 * control that reduces the attack window while maintaining user experience.
 *
 * How it works:
 * 1. Checks if current token is within rotation threshold
 * 2. If yes, creates new token and returns in X-New-Token header
 * 3. Old token remains valid for grace period to prevent race conditions
 * 4. Frontend must listen for X-New-Token header and update stored token
 *
 * OWASP Reference: A07:2021 – Identification and Authentication Failures
 */
class RotateTokenMiddleware
{
    /**
     * Handle an incoming request.
     *
     * @param  \Closure(\Illuminate\Http\Request): (\Symfony\Component\HttpFoundation\Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        // Only process if user is authenticated via Sanctum token
        if (! $request->user() || ! $request->bearerToken()) {
            return $next($request);
        }

        // Check if token rotation is enabled
        if (! Config::get('sanctum.token_rotation.enabled', false)) {
            return $next($request);
        }

        // Get current token
        $currentToken = $request->user()->currentAccessToken();

        if (! $currentToken instanceof PersonalAccessToken) {
            return $next($request);
        }

        // Check if token should be rotated
        if ($this->shouldRotateToken($currentToken)) {
            $newToken = $this->rotateToken($currentToken, $request->user());

            // Add new token to response header for frontend to capture
            // SECURITY: Frontend MUST implement logic to detect and store new token
            $response = $next($request);
            $response->headers->set('X-New-Token', $newToken->plainTextToken);

            // Log rotation for audit trail
            \Log::info('Token rotated', [
                'user_id' => $request->user()->id,
                'old_token_id' => $currentToken->id,
                'new_token_id' => $newToken->accessToken->id,
                'ip_address' => $request->ip(),
            ]);

            return $response;
        }

        return $next($request);
    }

    /**
     * Determine if token should be rotated based on remaining lifetime.
     *
     * SECURITY: Tokens are rotated when they have less than the configured
     * threshold minutes remaining to ensure continuous short-lived tokens.
     */
    protected function shouldRotateToken(PersonalAccessToken $token): bool
    {
        // If token has no expiration, don't rotate
        if (! $token->expires_at) {
            return false;
        }

        $rotationThreshold = Config::get('sanctum.token_rotation.rotation_threshold_minutes', 15);
        $expiresAt = Carbon::parse($token->expires_at);
        $minutesRemaining = now()->diffInMinutes($expiresAt, false);

        // Rotate if token expires within threshold and hasn't expired yet
        return $minutesRemaining > 0 && $minutesRemaining <= $rotationThreshold;
    }

    /**
     * Create new token and handle old token lifecycle.
     *
     * SECURITY: Old token remains valid for grace period to handle race conditions
     * in distributed systems where multiple requests might be in flight.
     *
     * @return \Laravel\Sanctum\NewAccessToken
     */
    protected function rotateToken(PersonalAccessToken $oldToken, $user)
    {
        $expirationMinutes = Config::get('sanctum.expiration', 60);
        $gracePeriodMinutes = Config::get('sanctum.token_rotation.grace_period_minutes', 5);

        // Create new token with same abilities as old token
        $newToken = $user->createToken(
            name: 'rotated-token',
            abilities: $oldToken->abilities ?? ['*'],
            expiresAt: now()->addMinutes($expirationMinutes)
        );

        // Update old token expiration to grace period
        // SECURITY: This prevents immediate invalidation which could cause UX issues
        // but limits the window where old token remains valid
        $oldToken->update([
            'expires_at' => now()->addMinutes($gracePeriodMinutes),
        ]);

        return $newToken;
    }
}
