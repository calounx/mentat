<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * SECURITY: Request Signature Verification (HMAC-SHA256)
 *
 * Implements request signing for high-security operations to ensure:
 * 1. Request authenticity - Request comes from legitimate client
 * 2. Request integrity - Request was not tampered with in transit
 * 3. Replay protection - Request cannot be replayed by attacker
 *
 * OWASP Reference: A02:2021 – Cryptographic Failures
 * - HMAC provides cryptographic proof of message authenticity
 * - Prevents man-in-the-middle tampering
 * - Protects against replay attacks
 *
 * Use Cases:
 * - Webhook callbacks from external services
 * - High-value financial transactions
 * - Administrative API operations
 * - Cross-service communication
 *
 * Signature Algorithm: HMAC-SHA256
 * - Industry standard (used by AWS, GitHub, Stripe)
 * - 256-bit security strength
 * - Resistant to collision attacks
 *
 * Signature Format:
 *   X-Signature: sha256=<hex_encoded_hmac>
 *   X-Signature-Timestamp: <unix_timestamp>
 *
 * Signed Payload:
 *   timestamp + method + uri + body
 *
 * Security Features:
 * - 5-minute timestamp tolerance (prevents replay)
 * - Constant-time signature comparison (prevents timing attacks)
 * - Comprehensive audit logging
 * - Configurable per route
 */
class VerifyRequestSignature
{
    /**
     * Maximum age of request in seconds (5 minutes).
     * Prevents replay attacks by rejecting old requests.
     */
    protected const MAX_REQUEST_AGE = 300;

    /**
     * Handle an incoming request.
     *
     * SECURITY FLOW:
     * 1. Extract signature and timestamp from headers
     * 2. Verify timestamp is recent (within 5 minutes)
     * 3. Reconstruct canonical request string
     * 4. Compute expected HMAC signature
     * 5. Compare signatures in constant time (prevent timing attacks)
     * 6. Audit log verification attempt
     *
     * @param  \Closure(\Illuminate\Http\Request): (\Symfony\Component\HttpFoundation\Response)  $next
     */
    public function handle(Request $request, Closure $next, ?string $secretKey = null): Response
    {
        // Extract signature headers
        $providedSignature = $request->header('X-Signature');
        $timestamp = $request->header('X-Signature-Timestamp');

        if (! $providedSignature || ! $timestamp) {
            return $this->unauthorizedResponse(
                'SIGNATURE_MISSING',
                'Request signature headers are required for this endpoint.'
            );
        }

        // SECURITY CHECK 1: Verify timestamp is recent (replay protection)
        if (! $this->isTimestampValid($timestamp)) {
            return $this->unauthorizedResponse(
                'SIGNATURE_EXPIRED',
                'Request signature has expired. Please generate a new request.'
            );
        }

        // Get signing secret (from parameter or default)
        $secret = $secretKey ?? config('app.signing_secret');

        if (! $secret) {
            // SECURITY: Fail closed - reject if no secret configured
            \Log::critical('Request signing secret not configured but signature verification enabled');

            return $this->unauthorizedResponse(
                'CONFIGURATION_ERROR',
                'Request signature verification is not properly configured.'
            );
        }

        // SECURITY CHECK 2: Compute expected signature
        $expectedSignature = $this->computeSignature($request, $timestamp, $secret);

        // SECURITY CHECK 3: Compare signatures in constant time (prevent timing attacks)
        if (! hash_equals($expectedSignature, $providedSignature)) {
            // Audit log failed verification
            \Log::warning('Request signature verification failed', [
                'method' => $request->method(),
                'uri' => $request->getRequestUri(),
                'ip' => $request->ip(),
                'timestamp' => $timestamp,
            ]);

            return $this->unauthorizedResponse(
                'SIGNATURE_INVALID',
                'Request signature is invalid. Please check your signing implementation.'
            );
        }

        // Signature verified successfully - audit log and proceed
        \Log::info('Request signature verified successfully', [
            'method' => $request->method(),
            'uri' => $request->getRequestUri(),
            'timestamp' => $timestamp,
        ]);

        return $next($request);
    }

    /**
     * Compute HMAC-SHA256 signature for request.
     *
     * Canonical Request Format:
     *   {timestamp}\n{method}\n{uri}\n{body}
     *
     * Example:
     *   1640000000
     *   POST
     *   /api/v1/webhooks/payment
     *   {"amount":1000,"currency":"USD"}
     *
     * @return string HMAC signature in format: sha256=<hex>
     */
    protected function computeSignature(Request $request, string $timestamp, string $secret): string
    {
        // Build canonical request string
        $canonicalRequest = implode("\n", [
            $timestamp,
            $request->method(),
            $request->getRequestUri(),
            $request->getContent(),
        ]);

        // Compute HMAC-SHA256
        $hmac = hash_hmac('sha256', $canonicalRequest, $secret);

        return "sha256={$hmac}";
    }

    /**
     * Verify timestamp is recent (within MAX_REQUEST_AGE seconds).
     *
     * SECURITY RATIONALE:
     * - Prevents replay attacks by rejecting old requests
     * - 5-minute window balances security and clock skew tolerance
     * - Assumes reasonable NTP synchronization between systems
     *
     * @param  string  $timestamp  Unix timestamp
     * @return bool True if timestamp is valid
     */
    protected function isTimestampValid(string $timestamp): bool
    {
        if (! is_numeric($timestamp)) {
            return false;
        }

        $requestTime = (int) $timestamp;
        $currentTime = time();

        // Check timestamp is not in the future (allow 1 minute clock skew)
        if ($requestTime > $currentTime + 60) {
            return false;
        }

        // Check timestamp is not too old
        if ($currentTime - $requestTime > self::MAX_REQUEST_AGE) {
            return false;
        }

        return true;
    }

    /**
     * Generate unauthorized response with error details.
     */
    protected function unauthorizedResponse(string $code, string $message): Response
    {
        return response()->json([
            'success' => false,
            'error' => [
                'code' => $code,
                'message' => $message,
                'documentation' => 'See documentation for request signing requirements.',
            ],
        ], 401);
    }
}
