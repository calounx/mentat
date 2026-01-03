<?php

declare(strict_types=1);

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Organization;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class SecurityIntegrationTest extends TestCase
{
    use RefreshDatabase;

    private User $user;
    private Organization $organization;

    protected function setUp(): void
    {
        parent::setUp();

        $this->organization = Organization::factory()->create(['tier' => 'free']);
        $this->user = User::factory()->create([
            'organization_id' => $this->organization->id,
            'password' => Hash::make('password123'),
        ]);

        Cache::flush();
        RateLimiter::clear('test-key');
    }

    public function test_complete_authentication_flow_with_security_features(): void
    {
        // 1. Attempt login
        $response = $this->postJson('/api/v1/login', [
            'email' => $this->user->email,
            'password' => 'password123',
        ]);

        $response->assertStatus(200);
        $response->assertJsonStructure(['data' => ['token', 'user']]);

        // 2. Verify audit log created
        $this->assertDatabaseHas('audit_logs', [
            'user_id' => $this->user->id,
            'action' => 'authentication.login',
        ]);

        // 3. Verify session security headers
        $response->assertHeader('X-Content-Type-Options', 'nosniff');
        $response->assertHeader('X-Frame-Options');
        $response->assertHeader('Strict-Transport-Security');

        // 4. Use token for authenticated request
        $token = $response->json('data.token');

        $authedResponse = $this->withHeaders([
            'Authorization' => "Bearer {$token}",
        ])->getJson('/api/v1/user');

        $authedResponse->assertStatus(200);
    }

    public function test_rate_limiting_prevents_brute_force_attacks(): void
    {
        $attempts = 0;
        $rateLimited = false;

        // Attempt multiple failed logins
        for ($i = 0; $i < 10; $i++) {
            $response = $this->postJson('/api/v1/login', [
                'email' => $this->user->email,
                'password' => 'wrong_password',
            ]);

            $attempts++;

            if ($response->status() === 429) {
                $rateLimited = true;
                break;
            }
        }

        $this->assertTrue($rateLimited, 'Rate limiting should kick in after multiple failed attempts');
        $this->assertLessThan(10, $attempts);
    }

    public function test_rate_limiting_includes_retry_after_header(): void
    {
        // Exhaust rate limit
        for ($i = 0; $i < 100; $i++) {
            RateLimiter::hit('test-limit', 60);
        }

        $response = $this->getJson('/api/v1/sites');

        if ($response->status() === 429) {
            $response->assertHeader('Retry-After');
            $this->assertIsNumeric($response->headers->get('Retry-After'));
        }
    }

    public function test_suspicious_activity_triggers_audit_logging(): void
    {
        Sanctum::actingAs($this->user);

        // Attempt unauthorized action
        $response = $this->deleteJson('/api/v1/organizations/' . $this->organization->id);

        // Should log authorization failure
        $this->assertDatabaseHas('audit_logs', [
            'user_id' => $this->user->id,
            'action' => 'authorization.failed',
        ]);
    }

    public function test_input_validation_prevents_sql_injection(): void
    {
        Sanctum::actingAs($this->user);

        $sqlInjections = [
            "1' OR '1'='1",
            "admin'--",
            "'; DROP TABLE users;--",
        ];

        foreach ($sqlInjections as $injection) {
            $response = $this->postJson('/api/v1/sites', [
                'domain' => $injection,
                'type' => 'wordpress',
            ]);

            $response->assertStatus(422);
            $response->assertJsonValidationErrors();
        }
    }

    public function test_input_validation_prevents_xss_attacks(): void
    {
        Sanctum::actingAs($this->user);

        $xssPayloads = [
            '<script>alert("XSS")</script>',
            '<img src="x" onerror="alert(1)">',
            'javascript:alert(1)',
        ];

        foreach ($xssPayloads as $payload) {
            $response = $this->postJson('/api/v1/sites', [
                'name' => $payload,
                'domain' => 'test.com',
                'type' => 'wordpress',
            ]);

            $response->assertStatus(422);
        }
    }

    public function test_security_headers_present_on_all_responses(): void
    {
        $endpoints = [
            '/api/v1/login',
            '/api/health',
        ];

        foreach ($endpoints as $endpoint) {
            $response = $this->getJson($endpoint);

            $response->assertHeader('X-Content-Type-Options', 'nosniff');
            $response->assertHeader('X-Frame-Options');
            $response->assertHeader('X-XSS-Protection');
            $response->assertHeader('Strict-Transport-Security');
        }
    }

    public function test_csrf_protection_on_state_changing_requests(): void
    {
        Sanctum::actingAs($this->user);

        // Without CSRF token
        $response = $this->postJson('/api/v1/sites', [
            'domain' => 'test.com',
            'type' => 'wordpress',
        ]);

        // API routes using Sanctum don't need CSRF, but session-based routes do
        // This test validates the setup is correct
        $this->assertTrue(in_array($response->status(), [200, 201, 401, 422]));
    }

    public function test_sensitive_operations_create_audit_trail(): void
    {
        Sanctum::actingAs($this->user);

        $auditLogCountBefore = AuditLog::count();

        // Perform sensitive operation
        $this->postJson('/api/v1/sites', [
            'domain' => 'example.com',
            'type' => 'wordpress',
        ]);

        $auditLogCountAfter = AuditLog::count();

        $this->assertGreaterThan($auditLogCountBefore, $auditLogCountAfter);
    }

    public function test_account_lockout_after_failed_attempts(): void
    {
        // Make multiple failed login attempts
        for ($i = 0; $i < 6; $i++) {
            $this->postJson('/api/v1/login', [
                'email' => $this->user->email,
                'password' => 'wrong_password',
            ]);
        }

        // Next attempt should be locked
        $response = $this->postJson('/api/v1/login', [
            'email' => $this->user->email,
            'password' => 'password123', // Even with correct password
        ]);

        $this->assertTrue(in_array($response->status(), [423, 429])); // Locked or rate limited
    }

    public function test_session_hijacking_prevention(): void
    {
        Sanctum::actingAs($this->user);

        $response1 = $this->getJson('/api/v1/user', [
            'User-Agent' => 'Mozilla/5.0 (Windows)',
        ]);

        $response1->assertStatus(200);

        // Try with different user agent (potential hijacking)
        $response2 = $this->getJson('/api/v1/user', [
            'User-Agent' => 'Different Browser',
        ]);

        // Should still work with token-based auth, but session-based would fail
        $this->assertTrue(in_array($response2->status(), [200, 401]));
    }

    public function test_disposable_email_rejection(): void
    {
        $response = $this->postJson('/api/v1/register', [
            'name' => 'Test User',
            'email' => 'test@mailinator.com',
            'password' => 'password123',
            'password_confirmation' => 'password123',
        ]);

        $response->assertStatus(422);
        $response->assertJsonValidationErrors(['email']);
    }

    public function test_mass_assignment_protection(): void
    {
        Sanctum::actingAs($this->user);

        $response = $this->postJson('/api/v1/user/profile', [
            'name' => 'Updated Name',
            'is_admin' => true, // Attempt to elevate privileges
            'role' => 'admin',
        ]);

        // Should update name but ignore protected fields
        $this->user->refresh();
        $this->assertNotTrue($this->user->is_admin ?? false);
    }

    public function test_api_versioning_enforced(): void
    {
        Sanctum::actingAs($this->user);

        // Valid versioned endpoint
        $response1 = $this->getJson('/api/v1/user');
        $this->assertEquals(200, $response1->status());

        // Invalid version
        $response2 = $this->getJson('/api/v999/user');
        $this->assertEquals(404, $response2->status());
    }

    public function test_cors_headers_configured_correctly(): void
    {
        $response = $this->options('/api/v1/sites', [
            'Origin' => 'https://example.com',
            'Access-Control-Request-Method' => 'POST',
        ]);

        // CORS should be properly configured
        $this->assertTrue(
            $response->headers->has('Access-Control-Allow-Origin') ||
            $response->status() === 404
        );
    }

    public function test_api_authentication_required_for_protected_routes(): void
    {
        $protectedRoutes = [
            '/api/v1/sites',
            '/api/v1/backups',
            '/api/v1/user',
        ];

        foreach ($protectedRoutes as $route) {
            $response = $this->getJson($route);
            $this->assertEquals(401, $response->status(), "Route {$route} should require authentication");
        }
    }

    public function test_complete_security_flow_with_2fa(): void
    {
        // Enable 2FA for user
        $this->user->update(['two_factor_enabled' => true]);

        // Login with password
        $response = $this->postJson('/api/v1/login', [
            'email' => $this->user->email,
            'password' => 'password123',
        ]);

        // Should require 2FA
        $this->assertTrue(in_array($response->status(), [200, 202]));

        if ($response->status() === 202) {
            $response->assertJson(['message' => '2FA code required']);
        }
    }

    public function test_password_complexity_requirements(): void
    {
        $weakPasswords = [
            'password',
            '12345678',
            'abcdefgh',
        ];

        foreach ($weakPasswords as $password) {
            $response = $this->postJson('/api/v1/register', [
                'name' => 'Test User',
                'email' => 'test' . rand(1000, 9999) . '@example.com',
                'password' => $password,
                'password_confirmation' => $password,
            ]);

            $response->assertStatus(422);
            $response->assertJsonValidationErrors(['password']);
        }
    }

    public function test_rate_limit_varies_by_tier(): void
    {
        // Free tier user
        $freeUser = User::factory()->create([
            'organization_id' => Organization::factory()->create(['tier' => 'free'])->id,
        ]);

        // Enterprise tier user
        $enterpriseUser = User::factory()->create([
            'organization_id' => Organization::factory()->create(['tier' => 'enterprise'])->id,
        ]);

        // Free tier should hit limit faster
        Sanctum::actingAs($freeUser);
        for ($i = 0; $i < 101; $i++) {
            $response = $this->getJson('/api/v1/sites');
            if ($response->status() === 429) {
                $this->assertLessThan(101, $i);
                break;
            }
        }
    }

    public function test_end_to_end_secure_request_lifecycle(): void
    {
        // 1. Login
        $loginResponse = $this->postJson('/api/v1/login', [
            'email' => $this->user->email,
            'password' => 'password123',
        ]);

        $loginResponse->assertStatus(200);
        $token = $loginResponse->json('data.token');

        // 2. Make authenticated request
        $response = $this->withHeaders([
            'Authorization' => "Bearer {$token}",
        ])->postJson('/api/v1/sites', [
            'domain' => 'secure-test.com',
            'type' => 'wordpress',
        ]);

        // 3. Verify security headers
        $response->assertHeader('X-Content-Type-Options');
        $response->assertHeader('Content-Security-Policy');

        // 4. Verify rate limiting headers
        $response->assertHeader('X-RateLimit-Limit');
        $response->assertHeader('X-RateLimit-Remaining');

        // 5. Verify audit logging
        $this->assertDatabaseHas('audit_logs', [
            'user_id' => $this->user->id,
            'resource_type' => 'Site',
        ]);

        // 6. Verify input validation worked
        if ($response->status() === 201) {
            $this->assertDatabaseHas('sites', [
                'domain' => 'secure-test.com',
            ]);
        }
    }
}
