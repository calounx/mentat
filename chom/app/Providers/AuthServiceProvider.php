<?php

namespace App\Providers;

use Illuminate\Foundation\Support\Providers\AuthServiceProvider as ServiceProvider;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rules\Password;

/**
 * Auth Service Provider
 *
 * SECURITY: Configures authentication and authorization for the application
 * Implements enterprise-grade password policy and gate definitions
 */
class AuthServiceProvider extends ServiceProvider
{
    /**
     * The model to policy mappings for the application.
     *
     * @var array<class-string, class-string>
     */
    protected $policies = [
        // Auto-discovered via model conventions
    ];

    /**
     * Register any authentication / authorization services.
     *
     * SECURITY: Implements OWASP ASVS Level 2 password requirements
     * - Minimum 12 characters (14 in production)
     * - Mixed case letters required
     * - Numbers required
     * - Special symbols required
     * - Checks against Have I Been Pwned breach database
     *
     * OWASP References:
     * - A07:2021 – Identification and Authentication Failures
     * - ASVS V2.1: Password Security Requirements
     * - NIST SP 800-63B: Digital Identity Guidelines
     *
     * @return void
     */
    public function boot(): void
    {
        $this->registerPolicies();
        $this->configurePasswordPolicy();
    }

    /**
     * Configure enterprise-grade password policy
     *
     * SECURITY: Password must meet all criteria:
     * 1. Length: 12+ characters (14+ in production)
     * 2. Complexity: Letters, mixed case, numbers, symbols
     * 3. Breach Check: Not found in data breaches
     *
     * This prevents:
     * - Brute force attacks (long passwords)
     * - Dictionary attacks (complexity requirements)
     * - Credential stuffing (breach database check)
     *
     * @return void
     */
    protected function configurePasswordPolicy(): void
    {
        Password::defaults(function () {
            // Base password requirements (development and production)
            $password = Password::min(12)           // Minimum 12 characters
                ->letters()                         // Must contain letters (a-z, A-Z)
                ->mixedCase()                       // Must have both uppercase and lowercase
                ->numbers()                         // Must contain numbers (0-9)
                ->symbols()                         // Must contain special characters (!@#$%^&*)
                ->uncompromised();                  // Check against Have I Been Pwned API

            // Stricter requirements for production environment
            if (app()->environment('production')) {
                $password->min(14)                  // 14 characters minimum for production
                    ->uncompromised(3);             // Maximum 3 breach occurrences allowed
            }

            return $password;
        });
    }
}
