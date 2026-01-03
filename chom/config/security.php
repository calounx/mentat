<?php

declare(strict_types=1);

return [
    /*
    |--------------------------------------------------------------------------
    | Rate Limiting Configuration
    |--------------------------------------------------------------------------
    |
    | Configure rate limits for API endpoints and general application usage.
    | Uses Redis for distributed rate limiting across multiple servers.
    | OWASP Reference: API4:2023 – Unrestricted Resource Consumption
    |
    */
    'rate_limiting' => [
        // Enable/disable rate limiting globally
        'enabled' => env('RATE_LIMITING_ENABLED', true),

        // Redis connection to use for rate limiting
        'redis_connection' => env('RATE_LIMIT_REDIS_CONNECTION', 'default'),

        // Authenticated user rate limits (per minute)
        'authenticated' => [
            'requests' => env('RATE_LIMIT_AUTH_REQUESTS', 100),
            'decay_minutes' => env('RATE_LIMIT_AUTH_DECAY', 1),
        ],

        // Anonymous/guest rate limits (per minute)
        'anonymous' => [
            'requests' => env('RATE_LIMIT_ANON_REQUESTS', 20),
            'decay_minutes' => env('RATE_LIMIT_ANON_DECAY', 1),
        ],

        // Per-tenant rate limits based on subscription tier
        'tenant_limits' => [
            'free' => [
                'requests_per_hour' => env('RATE_LIMIT_FREE_TIER', 1000),
                'burst' => env('RATE_LIMIT_FREE_BURST', 50),
            ],
            'basic' => [
                'requests_per_hour' => env('RATE_LIMIT_BASIC_TIER', 5000),
                'burst' => env('RATE_LIMIT_BASIC_BURST', 100),
            ],
            'professional' => [
                'requests_per_hour' => env('RATE_LIMIT_PRO_TIER', 20000),
                'burst' => env('RATE_LIMIT_PRO_BURST', 200),
            ],
            'enterprise' => [
                'requests_per_hour' => env('RATE_LIMIT_ENTERPRISE_TIER', 100000),
                'burst' => env('RATE_LIMIT_ENTERPRISE_BURST', 500),
            ],
        ],

        // Critical operations with stricter limits
        'critical_operations' => [
            'login' => [
                'requests' => env('RATE_LIMIT_LOGIN', 5),
                'decay_minutes' => env('RATE_LIMIT_LOGIN_DECAY', 15),
            ],
            'password_reset' => [
                'requests' => env('RATE_LIMIT_PASSWORD_RESET', 3),
                'decay_minutes' => env('RATE_LIMIT_PASSWORD_RESET_DECAY', 60),
            ],
            'api_key_generation' => [
                'requests' => env('RATE_LIMIT_API_KEY', 5),
                'decay_minutes' => env('RATE_LIMIT_API_KEY_DECAY', 60),
            ],
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Session Security Configuration
    |--------------------------------------------------------------------------
    |
    | Enhanced session security including IP validation, user agent checking,
    | and suspicious login detection.
    | OWASP Reference: A07:2021 – Identification and Authentication Failures
    |
    */
    'session' => [
        // Enable session fixation protection
        'regenerate_on_login' => env('SESSION_REGENERATE_ON_LOGIN', true),

        // Validate IP address matches session
        'validate_ip' => env('SESSION_VALIDATE_IP', true),

        // Validate user agent matches session
        'validate_user_agent' => env('SESSION_VALIDATE_USER_AGENT', true),

        // Allow IP changes within same subnet (useful for mobile users)
        'allow_subnet_changes' => env('SESSION_ALLOW_SUBNET', false),

        // Session timeout in minutes
        'lifetime' => env('SESSION_LIFETIME', 120),

        // Idle timeout in minutes
        'idle_timeout' => env('SESSION_IDLE_TIMEOUT', 30),
    ],

    /*
    |--------------------------------------------------------------------------
    | Account Lockout Configuration
    |--------------------------------------------------------------------------
    |
    | Protection against brute force attacks by locking accounts after
    | repeated failed login attempts.
    | OWASP Reference: A07:2021 – Identification and Authentication Failures
    |
    */
    'account_lockout' => [
        // Enable account lockout
        'enabled' => env('ACCOUNT_LOCKOUT_ENABLED', true),

        // Number of failed attempts before lockout
        'max_attempts' => env('ACCOUNT_LOCKOUT_MAX_ATTEMPTS', 5),

        // Lockout duration in minutes
        'lockout_duration' => env('ACCOUNT_LOCKOUT_DURATION', 15),

        // Time window for counting attempts (minutes)
        'attempt_window' => env('ACCOUNT_LOCKOUT_WINDOW', 15),

        // Notify user via email on lockout
        'notify_on_lockout' => env('ACCOUNT_LOCKOUT_NOTIFY', true),

        // Progressive lockout (increase duration with repeated lockouts)
        'progressive_lockout' => env('ACCOUNT_LOCKOUT_PROGRESSIVE', true),
    ],

    /*
    |--------------------------------------------------------------------------
    | Suspicious Login Detection
    |--------------------------------------------------------------------------
    |
    | Detect and respond to suspicious login attempts based on location,
    | device, and behavioral patterns.
    | OWASP Reference: A07:2021 – Identification and Authentication Failures
    |
    */
    'suspicious_login' => [
        // Enable suspicious login detection
        'enabled' => env('SUSPICIOUS_LOGIN_ENABLED', true),

        // Require 2FA/email verification for new locations
        'require_verification_new_location' => env('SUSPICIOUS_LOGIN_NEW_LOCATION', true),

        // Require 2FA/email verification for new devices
        'require_verification_new_device' => env('SUSPICIOUS_LOGIN_NEW_DEVICE', true),

        // Notify user of new login via email
        'notify_new_login' => env('SUSPICIOUS_LOGIN_NOTIFY', true),

        // Maximum trusted devices per user
        'max_trusted_devices' => env('SUSPICIOUS_LOGIN_MAX_DEVICES', 10),

        // Trust device for this many days
        'device_trust_duration' => env('SUSPICIOUS_LOGIN_TRUST_DAYS', 30),
    ],

    /*
    |--------------------------------------------------------------------------
    | Security Headers Configuration
    |--------------------------------------------------------------------------
    |
    | HTTP security headers to protect against common web vulnerabilities.
    | OWASP Reference: A05:2021 – Security Misconfiguration
    |
    */
    'headers' => [
        // Enable security headers middleware
        'enabled' => env('SECURITY_HEADERS_ENABLED', true),

        // X-Frame-Options: Prevent clickjacking attacks
        'x_frame_options' => env('SECURITY_HEADER_FRAME_OPTIONS', 'DENY'),

        // X-Content-Type-Options: Prevent MIME type sniffing
        'x_content_type_options' => env('SECURITY_HEADER_CONTENT_TYPE', 'nosniff'),

        // X-XSS-Protection: Enable browser XSS filter
        'x_xss_protection' => env('SECURITY_HEADER_XSS', '1; mode=block'),

        // Strict-Transport-Security: Force HTTPS
        'strict_transport_security' => [
            'enabled' => env('SECURITY_HEADER_HSTS_ENABLED', true),
            'max_age' => env('SECURITY_HEADER_HSTS_MAX_AGE', 31536000), // 1 year
            'include_subdomains' => env('SECURITY_HEADER_HSTS_SUBDOMAINS', true),
            'preload' => env('SECURITY_HEADER_HSTS_PRELOAD', false),
        ],

        // Referrer-Policy: Control referrer information
        'referrer_policy' => env('SECURITY_HEADER_REFERRER', 'strict-origin-when-cross-origin'),

        // Permissions-Policy: Control browser features
        'permissions_policy' => env('SECURITY_HEADER_PERMISSIONS', 'geolocation=(), microphone=(), camera=()'),

        // Content-Security-Policy: Prevent XSS and data injection
        'content_security_policy' => [
            'enabled' => env('CSP_ENABLED', true),
            'report_only' => env('CSP_REPORT_ONLY', false),
            'report_uri' => env('CSP_REPORT_URI', '/api/csp-report'),
            'directives' => [
                'default-src' => env('CSP_DEFAULT_SRC', "'self'"),
                'script-src' => env('CSP_SCRIPT_SRC', "'self' 'nonce-{nonce}'"),
                'style-src' => env('CSP_STYLE_SRC', "'self' 'nonce-{nonce}' 'unsafe-inline'"),
                'img-src' => env('CSP_IMG_SRC', "'self' data: https:"),
                'font-src' => env('CSP_FONT_SRC', "'self' data:"),
                'connect-src' => env('CSP_CONNECT_SRC', "'self'"),
                'frame-ancestors' => env('CSP_FRAME_ANCESTORS', "'none'"),
                'base-uri' => env('CSP_BASE_URI', "'self'"),
                'form-action' => env('CSP_FORM_ACTION', "'self'"),
            ],
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Secrets Management Configuration
    |--------------------------------------------------------------------------
    |
    | Configuration for encrypting and managing sensitive credentials.
    | OWASP Reference: A02:2021 – Cryptographic Failures
    |
    */
    'secrets' => [
        // Encryption cipher for secrets
        'cipher' => env('SECRETS_CIPHER', 'aes-256-gcm'),

        // Rotate encryption keys every N days
        'key_rotation_days' => env('SECRETS_KEY_ROTATION_DAYS', 90),

        // Rotate VPS credentials every N days
        'vps_credential_rotation_days' => env('VPS_CREDENTIAL_ROTATION_DAYS', 30),

        // Rotate API keys every N days
        'api_key_rotation_days' => env('API_KEY_ROTATION_DAYS', 90),

        // Enable automatic rotation
        'auto_rotation_enabled' => env('SECRETS_AUTO_ROTATION', true),

        // Notify admins before key expiration (days)
        'expiration_warning_days' => env('SECRETS_EXPIRATION_WARNING', 7),
    ],

    /*
    |--------------------------------------------------------------------------
    | API Security Configuration
    |--------------------------------------------------------------------------
    |
    | Security settings for API endpoints including authentication,
    | CORS, and request signing.
    | OWASP Reference: API1:2023 – Broken Object Level Authorization
    |
    */
    'api' => [
        // Enable API security middleware
        'enabled' => env('API_SECURITY_ENABLED', true),

        // JWT configuration
        'jwt' => [
            'enabled' => env('JWT_ENABLED', true),
            'secret' => env('JWT_SECRET'),
            'algorithm' => env('JWT_ALGORITHM', 'HS256'),
            'ttl' => env('JWT_TTL', 3600), // 1 hour
            'refresh_ttl' => env('JWT_REFRESH_TTL', 604800), // 7 days
            'leeway' => env('JWT_LEEWAY', 60), // 1 minute clock skew
        ],

        // API Key authentication
        'api_key' => [
            'enabled' => env('API_KEY_ENABLED', true),
            'header_name' => env('API_KEY_HEADER', 'X-API-Key'),
            'hash_algorithm' => env('API_KEY_HASH_ALGO', 'sha256'),
        ],

        // CORS configuration
        'cors' => [
            'enabled' => env('CORS_ENABLED', true),
            'allowed_origins' => array_filter(explode(',', env('CORS_ALLOWED_ORIGINS', ''))),
            'allowed_methods' => array_filter(explode(',', env('CORS_ALLOWED_METHODS', 'GET,POST,PUT,DELETE,OPTIONS'))),
            'allowed_headers' => array_filter(explode(',', env('CORS_ALLOWED_HEADERS', 'Content-Type,Authorization,X-Requested-With'))),
            'exposed_headers' => array_filter(explode(',', env('CORS_EXPOSED_HEADERS', ''))),
            'max_age' => env('CORS_MAX_AGE', 3600),
            'supports_credentials' => env('CORS_SUPPORTS_CREDENTIALS', true),
        ],

        // Request signing for critical operations
        'request_signing' => [
            'enabled' => env('REQUEST_SIGNING_ENABLED', false),
            'algorithm' => env('REQUEST_SIGNING_ALGO', 'sha256'),
            'header_name' => env('REQUEST_SIGNING_HEADER', 'X-Signature'),
            'timestamp_header' => env('REQUEST_SIGNING_TIMESTAMP', 'X-Timestamp'),
            'max_timestamp_drift' => env('REQUEST_SIGNING_DRIFT', 300), // 5 minutes
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Audit Logging Configuration
    |--------------------------------------------------------------------------
    |
    | Configuration for security audit logging with tamper protection.
    | OWASP Reference: A09:2021 – Security Logging and Monitoring Failures
    |
    */
    'audit' => [
        // Enable audit logging
        'enabled' => env('AUDIT_LOGGING_ENABLED', true),

        // Log authentication events
        'log_authentication' => env('AUDIT_LOG_AUTH', true),

        // Log authorization failures
        'log_authorization_failures' => env('AUDIT_LOG_AUTHZ_FAILURES', true),

        // Log data access
        'log_data_access' => env('AUDIT_LOG_DATA_ACCESS', false),

        // Log configuration changes
        'log_config_changes' => env('AUDIT_LOG_CONFIG', true),

        // Log sensitive operations
        'log_sensitive_operations' => env('AUDIT_LOG_SENSITIVE', true),

        // Verify hash chain integrity on startup
        'verify_chain_on_startup' => env('AUDIT_VERIFY_CHAIN', true),

        // Alert on hash chain violations
        'alert_on_tampering' => env('AUDIT_ALERT_TAMPER', true),

        // Sensitive operations requiring audit logs
        'sensitive_operations' => [
            'user.role.changed',
            'user.deleted',
            'site.deleted',
            'vps.credentials.rotated',
            'api_key.created',
            'api_key.revoked',
            'subscription.changed',
            'payment_method.added',
            'team.member.removed',
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Input Validation Configuration
    |--------------------------------------------------------------------------
    |
    | Configuration for input validation and sanitization.
    | OWASP Reference: A03:2021 – Injection
    |
    */
    'validation' => [
        // Enable strict validation mode
        'strict_mode' => env('VALIDATION_STRICT_MODE', true),

        // Block SQL injection patterns
        'block_sql_injection' => env('VALIDATION_BLOCK_SQL_INJECTION', true),

        // Block XSS patterns
        'block_xss' => env('VALIDATION_BLOCK_XSS', true),

        // Detect disposable email addresses
        'block_disposable_emails' => env('VALIDATION_BLOCK_DISPOSABLE_EMAIL', true),

        // Detect IDN homograph attacks in domains
        'detect_homograph_attacks' => env('VALIDATION_DETECT_HOMOGRAPH', true),

        // Maximum input length
        'max_input_length' => env('VALIDATION_MAX_LENGTH', 10000),

        // SQL injection patterns to detect
        'sql_injection_patterns' => [
            '/(\bunion\b.*\bselect\b)/i',
            '/(\bselect\b.*\bfrom\b)/i',
            '/(\binsert\b.*\binto\b)/i',
            '/(\bdelete\b.*\bfrom\b)/i',
            '/(\bdrop\b.*\b(table|database)\b)/i',
            '/(\bexec\b.*\()/i',
            '/(\bscript\b.*>)/i',
            '/(;|\-\-|\/\*|\*\/)/i',
        ],

        // XSS patterns to detect
        'xss_patterns' => [
            '/<script[^>]*>.*?<\/script>/i',
            '/javascript:/i',
            '/on\w+\s*=/i', // onclick, onload, etc.
            '/<iframe[^>]*>/i',
            '/<object[^>]*>/i',
            '/<embed[^>]*>/i',
            '/eval\s*\(/i',
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | CSRF Protection Configuration
    |--------------------------------------------------------------------------
    |
    | Enhanced CSRF protection configuration.
    | OWASP Reference: A01:2021 – Broken Access Control
    |
    */
    'csrf' => [
        // Enable double-submit cookie pattern for API
        'double_submit_cookie' => env('CSRF_DOUBLE_SUBMIT', false),

        // SameSite cookie attribute
        'same_site' => env('SESSION_SAME_SITE', 'lax'),

        // Token lifetime in minutes
        'token_lifetime' => env('CSRF_TOKEN_LIFETIME', 120),

        // Regenerate token on sensitive operations
        'regenerate_on_sensitive_ops' => env('CSRF_REGENERATE_SENSITIVE', true),
    ],

    /*
    |--------------------------------------------------------------------------
    | Environment Validation
    |--------------------------------------------------------------------------
    |
    | Required environment variables for security features.
    | Application will fail to start if these are missing in production.
    |
    */
    'required_env_vars' => [
        'APP_KEY',
        'DB_PASSWORD',
        'REDIS_PASSWORD',
        'SESSION_DRIVER',
        'CACHE_DRIVER',
    ],

    // Additional required vars for production
    'required_env_vars_production' => [
        'APP_KEY',
        'DB_PASSWORD',
        'REDIS_PASSWORD',
        'MAIL_PASSWORD',
        'JWT_SECRET',
    ],
];
