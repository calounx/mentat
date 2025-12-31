<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Stateful Domains
    |--------------------------------------------------------------------------
    |
    | Requests from the following domains / hosts will receive stateful API
    | authentication cookies. Typically, these should include your local
    | and production domains which access your API via a frontend SPA.
    |
    */

    'stateful' => explode(',', env('SANCTUM_STATEFUL_DOMAINS', sprintf(
        '%s%s',
        'localhost,localhost:3000,127.0.0.1,127.0.0.1:8000,::1',
        env('APP_URL') ? ','.parse_url(env('APP_URL'), PHP_URL_HOST) : ''
    ))),

    /*
    |--------------------------------------------------------------------------
    | Sanctum Guards
    |--------------------------------------------------------------------------
    |
    | This array contains the authentication guards that will be checked when
    | Sanctum is trying to authenticate a request. If none of these guards
    | are able to authenticate the request, Sanctum will use the bearer
    | token that's present on an incoming request for authentication.
    |
    */

    'guard' => ['web'],

    /*
    |--------------------------------------------------------------------------
    | Token Expiration
    |--------------------------------------------------------------------------
    |
    | This value controls the number of minutes until an issued token will be
    | considered expired. This will override any values set in the token's
    | "expires_at" attribute, but first-party sessions are not affected.
    |
    | SECURITY: Tokens expire after 60 minutes to minimize risk window.
    | Use token rotation to maintain active sessions securely.
    |
    */

    'expiration' => env('SANCTUM_TOKEN_EXPIRATION', 60),

    /*
    |--------------------------------------------------------------------------
    | Token Rotation
    |--------------------------------------------------------------------------
    |
    | When enabled, tokens approaching expiration will be automatically rotated
    | to new tokens. This provides seamless user experience while maintaining
    | short token lifetimes for security.
    |
    | SECURITY: Rotation threshold set to 15 minutes before expiration.
    | Frontend must handle X-New-Token header to update stored token.
    |
    */

    'token_rotation' => [
        'enabled' => env('SANCTUM_TOKEN_ROTATION_ENABLED', true),

        // Rotate token when it has less than this many minutes remaining
        'rotation_threshold_minutes' => env('SANCTUM_TOKEN_ROTATION_THRESHOLD', 15),

        // Grace period where old token remains valid after rotation (in minutes)
        // This prevents race conditions in distributed systems
        'grace_period_minutes' => env('SANCTUM_TOKEN_GRACE_PERIOD', 5),
    ],

    /*
    |--------------------------------------------------------------------------
    | Sanctum Middleware
    |--------------------------------------------------------------------------
    |
    | When authenticating your first-party SPA with Sanctum you may need to
    | customize some of the middleware Sanctum uses while processing the
    | request. You may change the middleware listed below as required.
    |
    */

    'middleware' => [
        'authenticate_session' => Laravel\Sanctum\Http\Middleware\AuthenticateSession::class,
        'encrypt_cookies' => Illuminate\Cookie\Middleware\EncryptCookies::class,
        'validate_csrf_token' => Illuminate\Foundation\Http\Middleware\ValidateCsrfToken::class,
    ],

];
