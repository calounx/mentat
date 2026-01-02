<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Generate CSP Nonce Middleware
 *
 * SECURITY: Generates cryptographically secure nonce for Content Security Policy
 * to prevent XSS attacks without allowing 'unsafe-inline' scripts/styles.
 *
 * How it works:
 * 1. Generates a unique random nonce for each request
 * 2. Stores nonce in request attributes for use in SecurityHeaders middleware
 * 3. Makes nonce available to views via view()->share()
 * 4. Views can use {{ $cspNonce }} in script/style tags
 *
 * OWASP References:
 * - A03:2021 – Injection (XSS Prevention)
 * - CSP Level 3: Nonce-based script execution
 *
 * Example usage in Blade template:
 * <script nonce="{{ $cspNonce }}">
 *     console.log('This script is allowed by CSP');
 * </script>
 *
 * @see https://www.w3.org/TR/CSP3/#framework-nonce
 * @see https://cheatsheetseries.owasp.org/cheatsheets/Content_Security_Policy_Cheat_Sheet.html
 */
class GenerateCspNonce
{
    /**
     * Handle an incoming request.
     *
     * Generates a cryptographically secure random nonce using random_bytes()
     * which is suitable for security-sensitive operations.
     *
     * @param  \Illuminate\Http\Request  $request
     * @param  \Closure  $next
     * @return \Symfony\Component\HttpFoundation\Response
     */
    public function handle(Request $request, Closure $next): Response
    {
        // SECURITY: Generate cryptographically secure random nonce
        // - Uses random_bytes() for CSPRNG (cryptographically secure pseudo-random number generator)
        // - 16 bytes (128 bits) provides sufficient entropy
        // - Base64 encoding makes it safe for HTML attributes
        $nonce = base64_encode(random_bytes(16));

        // Store nonce in request attributes for use in SecurityHeaders middleware
        $request->attributes->set('csp_nonce', $nonce);

        // Make nonce available globally in all Blade views
        // Views can access it as {{ $cspNonce }}
        view()->share('cspNonce', $nonce);

        return $next($request);
    }
}
