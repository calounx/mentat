<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Security Headers Middleware
 *
 * SECURITY: Implements comprehensive security headers to protect against common
 * web vulnerabilities as recommended by OWASP Secure Headers Project.
 *
 * Headers implemented:
 * - X-Content-Type-Options: Prevents MIME sniffing attacks
 * - X-Frame-Options: Prevents clickjacking attacks
 * - X-XSS-Protection: Legacy XSS protection (defense in depth)
 * - Referrer-Policy: Controls referrer information leakage
 * - Permissions-Policy: Restricts browser features
 * - Content-Security-Policy: Prevents XSS and data injection attacks
 * - Strict-Transport-Security: Enforces HTTPS connections
 *
 * OWASP References:
 * - A03:2021 – Injection (CSP helps prevent XSS)
 * - A05:2021 – Security Misconfiguration
 * - OWASP Secure Headers Project
 */
class SecurityHeaders
{
    /**
     * Handle an incoming request.
     *
     * @param  \Closure(\Illuminate\Http\Request): (\Symfony\Component\HttpFoundation\Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $response = $next($request);

        // SECURITY: X-Content-Type-Options
        // Prevents browsers from MIME-sniffing responses away from declared content-type
        // This prevents attacks where attacker uploads malicious file disguised as image
        $response->headers->set('X-Content-Type-Options', 'nosniff');

        // SECURITY: X-Frame-Options
        // Prevents page from being embedded in iframe, protecting against clickjacking
        // DENY is strictest - page cannot be displayed in frame regardless of origin
        $response->headers->set('X-Frame-Options', 'DENY');

        // SECURITY: X-XSS-Protection
        // Legacy header for older browsers. Modern browsers use CSP instead.
        // Mode=block tells browser to block page if XSS attack detected
        $response->headers->set('X-XSS-Protection', '1; mode=block');

        // SECURITY: Referrer-Policy
        // Controls how much referrer information is included with requests
        // strict-origin-when-cross-origin sends full URL for same-origin, origin only for cross-origin
        $response->headers->set('Referrer-Policy', 'strict-origin-when-cross-origin');

        // SECURITY: Permissions-Policy (replaces Feature-Policy)
        // Restricts which browser features and APIs can be used
        // Principle of least privilege - only allow what's necessary
        $response->headers->set('Permissions-Policy', implode(', ', [
            'accelerometer=()',           // Disable accelerometer
            'camera=()',                  // Disable camera access
            'geolocation=()',            // Disable geolocation
            'gyroscope=()',              // Disable gyroscope
            'magnetometer=()',           // Disable magnetometer
            'microphone=()',             // Disable microphone
            'payment=()',                // Disable payment API
            'usb=()',                    // Disable USB access
        ]));

        // SECURITY: Content-Security-Policy (CSP)
        // Most powerful security header - prevents XSS, injection, and data theft
        // This is a strict policy that should be adjusted based on app requirements
        if (! $request->is('stripe/webhook')) {  // Exempt webhooks that may need different CSP
            $cspDirectives = [
                "default-src 'self'",                    // Only allow resources from same origin by default
                "script-src 'self' 'unsafe-inline'",     // Allow scripts from same origin and inline (adjust as needed)
                "style-src 'self' 'unsafe-inline'",      // Allow styles from same origin and inline
                "img-src 'self' data: https:",           // Allow images from same origin, data URIs, and HTTPS
                "font-src 'self' data:",                 // Allow fonts from same origin and data URIs
                "connect-src 'self'",                    // API calls only to same origin
                "frame-ancestors 'none'",                // Equivalent to X-Frame-Options DENY (CSP2 standard)
                "base-uri 'self'",                       // Restrict base tag to prevent base tag injection
                "form-action 'self'",                    // Forms can only submit to same origin
                "object-src 'none'",                     // Disable plugins (Flash, Java, etc.)
                "upgrade-insecure-requests",             // Automatically upgrade HTTP to HTTPS
            ];

            // Add report-uri in production for CSP violation monitoring
            if (app()->environment('production') && config('app.csp_report_uri')) {
                $cspDirectives[] = 'report-uri ' . config('app.csp_report_uri');
            }

            $response->headers->set('Content-Security-Policy', implode('; ', $cspDirectives));
        }

        // SECURITY: Strict-Transport-Security (HSTS)
        // Forces browser to only connect via HTTPS for specified time period
        // Only set in production with HTTPS enabled
        if (app()->environment('production') && $request->secure()) {
            $response->headers->set('Strict-Transport-Security', implode('; ', [
                'max-age=31536000',      // 1 year in seconds
                'includeSubDomains',     // Apply to all subdomains
                'preload',               // Allow inclusion in browser HSTS preload lists
            ]));
        }

        // SECURITY: Remove server information disclosure headers
        // Prevents information leakage about server technology
        $response->headers->remove('X-Powered-By');
        $response->headers->remove('Server');

        return $response;
    }
}
