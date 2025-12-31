<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Cross-Origin Resource Sharing (CORS) Configuration
    |--------------------------------------------------------------------------
    |
    | SECURITY: Properly configured CORS is critical for API security.
    | This configuration controls which origins can access your API and
    | what operations they can perform.
    |
    | OWASP Reference: A05:2021 – Security Misconfiguration
    | A misconfigured CORS policy can allow unauthorized cross-origin access.
    |
    */

    /*
    |--------------------------------------------------------------------------
    | CORS Paths
    |--------------------------------------------------------------------------
    |
    | Define which paths should have CORS headers applied.
    | API routes and Sanctum CSRF cookie endpoint need CORS support.
    |
    */

    'paths' => [
        'api/*',                    // All API routes
        'sanctum/csrf-cookie',      // Sanctum CSRF token endpoint
    ],

    /*
    |--------------------------------------------------------------------------
    | Allowed Methods
    |--------------------------------------------------------------------------
    |
    | SECURITY: Only allow HTTP methods your API actually uses.
    | Principle of least privilege - don't allow unnecessary methods.
    |
    */

    'allowed_methods' => ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],

    /*
    |--------------------------------------------------------------------------
    | Allowed Origins
    |--------------------------------------------------------------------------
    |
    | SECURITY CRITICAL: Define exact origins that can access your API.
    | NEVER use '*' in production as it allows any website to access your API.
    |
    | Set CORS_ALLOWED_ORIGINS environment variable with comma-separated origins:
    | CORS_ALLOWED_ORIGINS="https://app.example.com,https://admin.example.com"
    |
    | For local development, you might include:
    | CORS_ALLOWED_ORIGINS="http://localhost:3000,http://localhost:5173"
    |
    */

    'allowed_origins' => array_filter(
        explode(',', env('CORS_ALLOWED_ORIGINS', ''))
    ),

    /*
    |--------------------------------------------------------------------------
    | Allowed Origins Patterns
    |--------------------------------------------------------------------------
    |
    | Use patterns for dynamic subdomains (e.g., tenant-specific subdomains).
    | Be as specific as possible to avoid overly permissive patterns.
    |
    | Example: '/^https:\/\/.*\.example\.com$/'
    |
    */

    'allowed_origins_patterns' => array_filter(
        explode(',', env('CORS_ALLOWED_ORIGIN_PATTERNS', ''))
    ),

    /*
    |--------------------------------------------------------------------------
    | Allowed Headers
    |--------------------------------------------------------------------------
    |
    | SECURITY: Only allow headers that your API needs to accept.
    | Content-Type: Required for JSON API requests
    | Authorization: Required for Bearer token authentication
    | X-Requested-With: Common for AJAX requests
    | X-CSRF-TOKEN: Required for Sanctum CSRF protection
    |
    */

    'allowed_headers' => [
        'Content-Type',
        'Authorization',
        'X-Requested-With',
        'X-CSRF-TOKEN',
        'Accept',
    ],

    /*
    |--------------------------------------------------------------------------
    | Exposed Headers
    |--------------------------------------------------------------------------
    |
    | SECURITY: Headers that should be accessible to frontend JavaScript.
    | X-New-Token: Required for token rotation - frontend must detect and update token
    |
    */

    'exposed_headers' => [
        'X-New-Token',              // For token rotation
    ],

    /*
    |--------------------------------------------------------------------------
    | Max Age
    |--------------------------------------------------------------------------
    |
    | How long (in seconds) the preflight response can be cached.
    | 3600 seconds = 1 hour reduces preflight requests while maintaining security.
    |
    */

    'max_age' => 3600,

    /*
    |--------------------------------------------------------------------------
    | Supports Credentials
    |--------------------------------------------------------------------------
    |
    | SECURITY: Must be true for cookie-based authentication (Sanctum stateful).
    | When true, allowed_origins CANNOT be '*' - must specify exact origins.
    |
    | This allows cookies to be sent with cross-origin requests, which is
    | necessary for Sanctum's stateful authentication.
    |
    */

    'supports_credentials' => true,

];
