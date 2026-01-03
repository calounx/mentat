<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Config;
use Symfony\Component\HttpFoundation\Response;

/**
 * Security Headers Middleware
 *
 * Adds comprehensive security headers to HTTP responses to protect against
 * common web vulnerabilities including XSS, clickjacking, and MIME sniffing.
 *
 * Headers Implemented:
 * - X-Frame-Options: Prevent clickjacking attacks
 * - X-Content-Type-Options: Prevent MIME type sniffing
 * - X-XSS-Protection: Enable browser XSS filter
 * - Strict-Transport-Security: Force HTTPS connections
 * - Referrer-Policy: Control referrer information leakage
 * - Permissions-Policy: Control browser feature access
 * - Content-Security-Policy: Prevent XSS and data injection
 *
 * OWASP Reference: A05:2021 – Security Misconfiguration
 * Protection: Defense in depth through browser security features
 *
 * @package App\Http\Middleware
 */
class SecurityHeadersMiddleware
{
    /**
     * Security headers configuration.
     */
    protected array $config;

    /**
     * Create a new middleware instance.
     */
    public function __construct()
    {
        $this->config = Config::get('security.headers', []);
    }

    /**
     * Handle an incoming request.
     *
     * Adds security headers to all responses to enable browser-level
     * protections against common web vulnerabilities.
     *
     * @param Request $request The incoming HTTP request
     * @param Closure $next The next middleware in the pipeline
     * @return Response
     */
    public function handle(Request $request, Closure $next): Response
    {
        $response = $next($request);

        // Skip if security headers are disabled
        if (!($this->config['enabled'] ?? true)) {
            return $response;
        }

        // Add all security headers
        $this->addFrameOptions($response);
        $this->addContentTypeOptions($response);
        $this->addXssProtection($response);
        $this->addStrictTransportSecurity($response);
        $this->addReferrerPolicy($response);
        $this->addPermissionsPolicy($response);
        $this->addContentSecurityPolicy($response, $request);

        return $response;
    }

    /**
     * Add X-Frame-Options header.
     *
     * Protects against clickjacking attacks by controlling whether
     * the page can be embedded in frames/iframes.
     *
     * Values:
     * - DENY: Cannot be embedded anywhere
     * - SAMEORIGIN: Can only be embedded on same domain
     * - ALLOW-FROM uri: Can be embedded on specific domain
     *
     * OWASP: Prevents UI redress attacks (clickjacking)
     *
     * @param Response $response The HTTP response
     * @return void
     */
    protected function addFrameOptions(Response $response): void
    {
        $value = $this->config['x_frame_options'] ?? 'DENY';

        if ($value) {
            $response->headers->set('X-Frame-Options', $value);
        }
    }

    /**
     * Add X-Content-Type-Options header.
     *
     * Prevents browsers from MIME-sniffing a response away from the
     * declared content-type. This reduces exposure to drive-by download
     * attacks and sites serving user uploaded content.
     *
     * Value: nosniff (only valid value)
     *
     * OWASP: Prevents MIME confusion attacks
     *
     * @param Response $response The HTTP response
     * @return void
     */
    protected function addContentTypeOptions(Response $response): void
    {
        $value = $this->config['x_content_type_options'] ?? 'nosniff';

        if ($value) {
            $response->headers->set('X-Content-Type-Options', $value);
        }
    }

    /**
     * Add X-XSS-Protection header.
     *
     * Enables browser's built-in XSS filter. While modern browsers
     * rely more on CSP, this provides defense in depth.
     *
     * Values:
     * - 0: Disable XSS filter
     * - 1: Enable XSS filter
     * - 1; mode=block: Enable and block rendering if attack detected
     *
     * OWASP: Additional layer against reflected XSS attacks
     *
     * @param Response $response The HTTP response
     * @return void
     */
    protected function addXssProtection(Response $response): void
    {
        $value = $this->config['x_xss_protection'] ?? '1; mode=block';

        if ($value) {
            $response->headers->set('X-XSS-Protection', $value);
        }
    }

    /**
     * Add Strict-Transport-Security (HSTS) header.
     *
     * Forces browsers to only connect via HTTPS, preventing
     * protocol downgrade attacks and cookie hijacking.
     *
     * Directives:
     * - max-age: How long to enforce HTTPS (in seconds)
     * - includeSubDomains: Apply to all subdomains
     * - preload: Submit to browser HSTS preload list
     *
     * SECURITY: Only enabled for HTTPS connections
     * OWASP: Prevents SSL stripping and protocol downgrade attacks
     *
     * @param Response $response The HTTP response
     * @return void
     */
    protected function addStrictTransportSecurity(Response $response): void
    {
        $hstsConfig = $this->config['strict_transport_security'] ?? [];

        // Only enable HSTS on HTTPS connections
        if (!($hstsConfig['enabled'] ?? true) || !$this->isHttps()) {
            return;
        }

        $maxAge = $hstsConfig['max_age'] ?? 31536000; // 1 year
        $value = "max-age={$maxAge}";

        if ($hstsConfig['include_subdomains'] ?? true) {
            $value .= '; includeSubDomains';
        }

        if ($hstsConfig['preload'] ?? false) {
            $value .= '; preload';
        }

        $response->headers->set('Strict-Transport-Security', $value);
    }

    /**
     * Add Referrer-Policy header.
     *
     * Controls how much referrer information is sent with requests.
     * Prevents leakage of sensitive information in URLs.
     *
     * Values:
     * - no-referrer: Never send referrer
     * - no-referrer-when-downgrade: Send referrer except HTTPS->HTTP
     * - origin: Send only origin (no path/query)
     * - origin-when-cross-origin: Full URL for same-origin, origin for cross-origin
     * - same-origin: Send referrer only for same-origin requests
     * - strict-origin: Send origin, except HTTPS->HTTP
     * - strict-origin-when-cross-origin: Full for same-origin, origin for cross-origin (recommended)
     *
     * OWASP: Prevents information leakage via referrer header
     *
     * @param Response $response The HTTP response
     * @return void
     */
    protected function addReferrerPolicy(Response $response): void
    {
        $value = $this->config['referrer_policy'] ?? 'strict-origin-when-cross-origin';

        if ($value) {
            $response->headers->set('Referrer-Policy', $value);
        }
    }

    /**
     * Add Permissions-Policy header.
     *
     * Controls which browser features and APIs can be used.
     * Successor to Feature-Policy header.
     *
     * Features to control:
     * - geolocation: GPS access
     * - microphone: Microphone access
     * - camera: Camera access
     * - payment: Payment Request API
     * - usb: WebUSB API
     * - And many more...
     *
     * OWASP: Reduces attack surface by disabling unnecessary features
     *
     * @param Response $response The HTTP response
     * @return void
     */
    protected function addPermissionsPolicy(Response $response): void
    {
        $value = $this->config['permissions_policy'] ?? 'geolocation=(), microphone=(), camera=()';

        if ($value) {
            $response->headers->set('Permissions-Policy', $value);
        }
    }

    /**
     * Add Content-Security-Policy header.
     *
     * The most powerful security header. Prevents XSS, clickjacking,
     * and other code injection attacks by restricting resource sources.
     *
     * Directives:
     * - default-src: Fallback for other directives
     * - script-src: JavaScript sources
     * - style-src: CSS sources
     * - img-src: Image sources
     * - font-src: Font sources
     * - connect-src: XMLHttpRequest, WebSocket, EventSource
     * - frame-ancestors: Valid parents for frames (replaces X-Frame-Options)
     * - base-uri: Restrict <base> tag URLs
     * - form-action: Valid form submission targets
     *
     * Special values:
     * - 'self': Same origin only
     * - 'none': Block all
     * - 'unsafe-inline': Allow inline scripts/styles (avoid if possible)
     * - 'unsafe-eval': Allow eval() (avoid if possible)
     * - 'nonce-{random}': Allow scripts with matching nonce attribute
     * - https:: Only HTTPS sources
     *
     * OWASP: Primary defense against XSS and injection attacks
     * SECURITY: Uses nonces for inline scripts to avoid 'unsafe-inline'
     *
     * @param Response $response The HTTP response
     * @param Request $request The HTTP request (for nonce)
     * @return void
     */
    protected function addContentSecurityPolicy(Response $response, Request $request): void
    {
        $cspConfig = $this->config['content_security_policy'] ?? [];

        if (!($cspConfig['enabled'] ?? true)) {
            return;
        }

        $directives = $cspConfig['directives'] ?? [];

        if (empty($directives)) {
            return;
        }

        // Get nonce for inline scripts (if available from GenerateCspNonce middleware)
        $nonce = $request->attributes->get('csp_nonce', '');

        // Build CSP header value
        $cspParts = [];

        foreach ($directives as $directive => $value) {
            if ($value === null || $value === '') {
                continue;
            }

            // Replace {nonce} placeholder with actual nonce
            if ($nonce) {
                $value = str_replace('{nonce}', $nonce, $value);
            } else {
                // Remove nonce placeholder if no nonce available
                $value = str_replace("'nonce-{nonce}'", '', $value);
                $value = trim($value);
            }

            $cspParts[] = "{$directive} {$value}";
        }

        if (empty($cspParts)) {
            return;
        }

        $cspValue = implode('; ', $cspParts);

        // Add report-uri if configured
        if (!empty($cspConfig['report_uri'])) {
            $cspValue .= "; report-uri {$cspConfig['report_uri']}";
        }

        // Use report-only mode if configured (for testing CSP without breaking site)
        $headerName = ($cspConfig['report_only'] ?? false)
            ? 'Content-Security-Policy-Report-Only'
            : 'Content-Security-Policy';

        $response->headers->set($headerName, $cspValue);
    }

    /**
     * Check if current connection is HTTPS.
     *
     * Checks multiple sources to determine if connection is secure:
     * 1. SERVER_PORT (443 = HTTPS)
     * 2. HTTPS server variable
     * 3. X-Forwarded-Proto header (if behind proxy)
     *
     * @return bool True if connection is HTTPS
     */
    protected function isHttps(): bool
    {
        // Check server port
        if (isset($_SERVER['SERVER_PORT']) && $_SERVER['SERVER_PORT'] == '443') {
            return true;
        }

        // Check HTTPS server variable
        if (isset($_SERVER['HTTPS']) && strtolower($_SERVER['HTTPS']) !== 'off') {
            return true;
        }

        // Check X-Forwarded-Proto header (proxy/load balancer)
        if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && strtolower($_SERVER['HTTP_X_FORWARDED_PROTO']) === 'https') {
            return true;
        }

        return false;
    }
}
