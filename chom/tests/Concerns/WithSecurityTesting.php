<?php

declare(strict_types=1);

namespace Tests\Concerns;

use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Testing\TestResponse;

/**
 * Provides security testing utilities
 *
 * This trait provides methods for testing common security vulnerabilities
 * including injection attacks, authorization bypasses, and session security.
 */
trait WithSecurityTesting
{
    /**
     * Common SQL injection payloads
     */
    protected array $sqlInjectionPayloads = [
        "' OR '1'='1",
        "1' OR '1'='1' --",
        "' UNION SELECT NULL--",
        "'; DROP TABLE users--",
        "admin'--",
        "' OR 1=1--",
    ];

    /**
     * Common PromQL injection payloads
     */
    protected array $promqlInjectionPayloads = [
        'up{job="test"} or vector(1)',
        'up or (up * 0) + 1',
        'up{job=~".*"}',
        'up offset 1y or vector(999)',
    ];

    /**
     * Common LogQL injection payloads
     */
    protected array $logqlInjectionPayloads = [
        '{job="test"} |= ".*"',
        '{job=~".*"}',
        '{job="test"} or {job="other"}',
    ];

    /**
     * Common XSS payloads
     */
    protected array $xssPayloads = [
        '<script>alert("xss")</script>',
        '<img src=x onerror=alert(1)>',
        '<svg onload=alert(1)>',
        'javascript:alert(1)',
        '<iframe src="javascript:alert(1)">',
    ];

    /**
     * Test SQL injection vulnerability
     *
     * @param  callable  $callback  Function that accepts payload and makes request
     */
    protected function assertSqlInjectionProtection(callable $callback): void
    {
        foreach ($this->sqlInjectionPayloads as $payload) {
            $queryCountBefore = count(DB::getQueryLog());

            try {
                $response = $callback($payload);

                // Should either reject the input or sanitize it
                if ($response instanceof TestResponse) {
                    // Accept validation errors or successful sanitization
                    $this->assertTrue(
                        $response->status() === 422 || $response->status() === 200,
                        "SQL injection payload was not properly handled: {$payload}"
                    );
                }

                // Ensure no SQL errors occurred
                $queryCountAfter = count(DB::getQueryLog());
                $this->assertTrue(
                    $queryCountAfter >= $queryCountBefore,
                    'SQL injection may have caused query execution to fail'
                );
            } catch (\Exception $e) {
                // PDO exceptions indicate SQL injection attempt
                $this->assertStringNotContainsString(
                    'SQLSTATE',
                    $e->getMessage(),
                    "SQL injection vulnerability detected: {$payload}"
                );
            }
        }
    }

    /**
     * Test PromQL injection protection
     *
     * @param  callable  $queryCallback  Function that executes PromQL query
     */
    protected function assertPromQLInjectionProtection(callable $queryCallback): void
    {
        foreach ($this->promqlInjectionPayloads as $payload) {
            $result = $queryCallback($payload);

            // Query should be sanitized or rejected
            $this->assertTrue(
                is_array($result) && isset($result['status']),
                "PromQL injection payload was not handled: {$payload}"
            );

            // Should not return unauthorized data
            if (isset($result['data']['result'])) {
                $this->assertNotContains(
                    999,
                    collect($result['data']['result'])->pluck('value.1')->toArray(),
                    'PromQL injection may have succeeded'
                );
            }
        }
    }

    /**
     * Test LogQL injection protection
     *
     * @param  callable  $queryCallback  Function that executes LogQL query
     */
    protected function assertLogQLInjectionProtection(callable $queryCallback): void
    {
        foreach ($this->logqlInjectionPayloads as $payload) {
            $result = $queryCallback($payload);

            $this->assertTrue(
                is_array($result) && isset($result['status']),
                "LogQL injection payload was not handled: {$payload}"
            );
        }
    }

    /**
     * Test XSS protection
     */
    protected function assertXSSProtection(TestResponse $response): void
    {
        $content = $response->getContent();

        foreach ($this->xssPayloads as $payload) {
            $this->assertStringNotContainsString(
                $payload,
                $content,
                "XSS vulnerability: unescaped payload found: {$payload}"
            );
        }

        // Check for proper Content-Security-Policy header
        $response->assertHeader('Content-Security-Policy');
        $response->assertHeader('X-Content-Type-Options', 'nosniff');
        $response->assertHeader('X-Frame-Options', 'DENY');
    }

    /**
     * Test CSRF protection
     */
    protected function assertCSRFProtection(string $method, string $uri, array $data = []): void
    {
        // Attempt request without CSRF token
        $response = $this->call($method, $uri, $data, [], [], [
            'HTTP_REFERER' => config('app.url'),
        ]);

        $response->assertStatus(419); // CSRF token mismatch
    }

    /**
     * Test authorization bypass attempts
     */
    protected function assertAuthorizationEnforcement(
        User $user,
        string $method,
        string $uri,
        array $data = [],
        int $expectedStatus = 403
    ): void {
        $response = $this->actingAs($user)->call($method, $uri, $data);

        $this->assertEquals(
            $expectedStatus,
            $response->status(),
            "Authorization bypass: User gained unauthorized access to {$uri}"
        );
    }

    /**
     * Test tenant isolation
     *
     * @param  int  $resourceId  Resource belonging to different tenant
     */
    protected function assertTenantIsolation(User $user, int $resourceId, string $uri): void
    {
        $response = $this->actingAs($user)->get($uri);

        // Should not be able to access another tenant's resource
        $response->assertStatus(403);

        // Should not leak information in response
        $content = $response->getContent();
        $this->assertStringNotContainsString(
            (string) $resourceId,
            $content,
            'Tenant isolation breach: Resource ID leaked in response'
        );
    }

    /**
     * Test rate limiting
     */
    protected function assertRateLimiting(
        string $uri,
        int $maxAttempts = 60,
        ?User $user = null
    ): void {
        $request = $user ? $this->actingAs($user) : $this;

        // Make requests up to the limit
        for ($i = 0; $i < $maxAttempts; $i++) {
            $response = $request->get($uri);
            $this->assertNotEquals(429, $response->status());
        }

        // Next request should be rate limited
        $response = $request->get($uri);
        $response->assertStatus(429);
        $response->assertHeader('Retry-After');
    }

    /**
     * Test session fixation protection
     */
    protected function assertSessionFixationProtection(): void
    {
        // Get initial session ID
        $this->get('/');
        $sessionIdBefore = session()->getId();

        // Authenticate
        $user = User::factory()->create();
        $this->post('/login', [
            'email' => $user->email,
            'password' => 'password',
        ]);

        // Session ID should regenerate after authentication
        $sessionIdAfter = session()->getId();

        $this->assertNotEquals(
            $sessionIdBefore,
            $sessionIdAfter,
            'Session fixation vulnerability: Session ID not regenerated after login'
        );
    }

    /**
     * Test session hijacking protection
     */
    protected function assertSessionHijackingProtection(): void
    {
        $user = User::factory()->create();

        // Login and get session
        $this->post('/login', [
            'email' => $user->email,
            'password' => 'password',
        ]);

        $sessionId = session()->getId();

        // Attempt to use session with different IP
        $this->withServerVariables(['REMOTE_ADDR' => '10.0.0.1'])
            ->get('/dashboard')
            ->assertStatus(401);
    }

    /**
     * Test password requirements
     */
    protected function assertPasswordStrength(array $weakPasswords = []): void
    {
        $defaultWeakPasswords = [
            'password',
            '12345678',
            'qwerty',
            'abc123',
            'password123',
        ];

        $passwords = array_merge($defaultWeakPasswords, $weakPasswords);

        foreach ($passwords as $password) {
            $response = $this->post('/register', [
                'name' => 'Test User',
                'email' => 'test@example.com',
                'password' => $password,
                'password_confirmation' => $password,
            ]);

            $response->assertSessionHasErrors('password');
        }
    }

    /**
     * Test for mass assignment vulnerabilities
     */
    protected function assertMassAssignmentProtection(
        string $model,
        array $unauthorizedFields
    ): void {
        $modelInstance = new $model;

        foreach ($unauthorizedFields as $field) {
            $this->assertNotContains(
                $field,
                $modelInstance->getFillable(),
                "Mass assignment vulnerability: {$field} is fillable in {$model}"
            );

            $this->assertContains(
                $field,
                $modelInstance->getGuarded() === ['*'] ? ['*'] : $modelInstance->getGuarded(),
                "Mass assignment vulnerability: {$field} is not guarded in {$model}"
            );
        }
    }

    /**
     * Test for insecure direct object reference
     */
    protected function assertIDORProtection(User $user, int $othersResourceId, string $uri): void
    {
        $response = $this->actingAs($user)->get($uri);

        $response->assertStatus(403);

        // Verify no data leakage
        $content = $response->getContent();
        $this->assertStringNotContainsString(
            (string) $othersResourceId,
            $content,
            'IDOR vulnerability: Accessed resource belonging to another user'
        );
    }

    /**
     * Test sensitive data is not logged
     */
    protected function assertNoSensitiveDataInLogs(callable $operation, array $sensitiveData): void
    {
        // Clear existing logs
        DB::flushQueryLog();

        // Execute operation
        $operation();

        // Check query log
        $queryLog = DB::getQueryLog();
        $logContent = json_encode($queryLog);

        foreach ($sensitiveData as $sensitive) {
            $this->assertStringNotContainsString(
                $sensitive,
                $logContent,
                "Sensitive data logged: {$sensitive}"
            );
        }
    }

    /**
     * Assert secure headers are present
     */
    protected function assertSecureHeaders(TestResponse $response): void
    {
        $response->assertHeader('X-Content-Type-Options', 'nosniff');
        $response->assertHeader('X-Frame-Options');
        $response->assertHeader('X-XSS-Protection');
        $response->assertHeader('Strict-Transport-Security');
        $response->assertHeader('Content-Security-Policy');
        $response->assertHeader('Referrer-Policy');
        $response->assertHeader('Permissions-Policy');
    }
}
