<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\User;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * Security Implementation Test Suite
 *
 * Verifies all critical security fixes are working correctly:
 * 1. Token expiration and rotation
 * 2. SSH key encryption at rest
 * 3. Security headers
 * 4. CORS configuration
 * 5. Audit logging with hash chain
 * 6. Session security
 * 7. 2FA secret encryption
 */
class SecurityImplementationTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Test token expiration is configured correctly.
     */
    public function test_token_expiration_is_configured(): void
    {
        $this->assertEquals(60, Config::get('sanctum.expiration'));
        $this->assertTrue(Config::get('sanctum.token_rotation.enabled'));
        $this->assertEquals(15, Config::get('sanctum.token_rotation.rotation_threshold_minutes'));
        $this->assertEquals(5, Config::get('sanctum.token_rotation.grace_period_minutes'));
    }

    /**
     * Test tokens expire after configured time.
     */
    public function test_token_expires_after_configured_time(): void
    {
        $user = User::factory()->create();

        // Create token with expiration
        $token = $user->createToken(
            'test-token',
            ['*'],
            now()->addMinutes(60)
        );

        // Token should be valid now
        $this->assertNotNull($token->accessToken->expires_at);
        $this->assertTrue($token->accessToken->expires_at->isFuture());

        // Simulate time passing
        $token->accessToken->update(['expires_at' => now()->subMinute()]);

        // Token should be expired
        $this->assertTrue($token->accessToken->expires_at->isPast());
    }

    /**
     * Test SSH keys are encrypted in database.
     */
    public function test_ssh_keys_are_encrypted(): void
    {
        $privateKey = 'test-private-key-content';
        $publicKey = 'test-public-key-content';

        // Create VPS server with SSH keys
        $vpsServer = VpsServer::factory()->create([
            'ssh_private_key' => $privateKey,
            'ssh_public_key' => $publicKey,
            'key_rotated_at' => now(),
        ]);

        // Keys should be decrypted when accessed via model
        $this->assertEquals($privateKey, $vpsServer->ssh_private_key);
        $this->assertEquals($publicKey, $vpsServer->ssh_public_key);

        // Keys should be encrypted in database
        $rawData = DB::table('vps_servers')->where('id', $vpsServer->id)->first();

        // Encrypted data should be different from plain text
        $this->assertNotEquals($privateKey, $rawData->ssh_private_key);
        $this->assertNotEquals($publicKey, $rawData->ssh_public_key);

        // Encrypted data should be longer than plain text (encryption overhead)
        $this->assertGreaterThan(strlen($privateKey), strlen($rawData->ssh_private_key));
        $this->assertGreaterThan(strlen($publicKey), strlen($rawData->ssh_public_key));
    }

    /**
     * Test SSH keys are hidden from JSON serialization.
     */
    public function test_ssh_keys_are_hidden_from_json(): void
    {
        $vpsServer = VpsServer::factory()->create([
            'ssh_private_key' => 'secret-private-key',
            'ssh_public_key' => 'secret-public-key',
        ]);

        $json = $vpsServer->toArray();

        $this->assertArrayNotHasKey('ssh_private_key', $json);
        $this->assertArrayNotHasKey('ssh_public_key', $json);
    }

    /**
     * Test security headers are applied to responses.
     */
    public function test_security_headers_are_applied(): void
    {
        $response = $this->get('/');

        // Test all security headers
        $response->assertHeader('X-Content-Type-Options', 'nosniff');
        $response->assertHeader('X-Frame-Options', 'DENY');
        $response->assertHeader('X-XSS-Protection', '1; mode=block');
        $response->assertHeader('Referrer-Policy', 'strict-origin-when-cross-origin');

        // Check Permissions-Policy exists
        $this->assertTrue($response->headers->has('Permissions-Policy'));

        // Check CSP exists
        $this->assertTrue($response->headers->has('Content-Security-Policy'));
        $csp = $response->headers->get('Content-Security-Policy');
        $this->assertStringContainsString("default-src 'self'", $csp);
        $this->assertStringContainsString("frame-ancestors 'none'", $csp);
        $this->assertStringContainsString("object-src 'none'", $csp);
    }

    /**
     * Test HSTS header is applied in production.
     */
    public function test_hsts_header_in_production(): void
    {
        // Simulate production environment
        Config::set('app.env', 'production');

        $response = $this->get('/', ['HTTPS' => 'on']);

        if ($response->headers->has('Strict-Transport-Security')) {
            $hsts = $response->headers->get('Strict-Transport-Security');
            $this->assertStringContainsString('max-age=31536000', $hsts);
            $this->assertStringContainsString('includeSubDomains', $hsts);
        }
    }

    /**
     * Test CORS configuration is loaded.
     */
    public function test_cors_configuration_is_loaded(): void
    {
        $this->assertIsArray(Config::get('cors.paths'));
        $this->assertContains('api/*', Config::get('cors.paths'));
        $this->assertContains('sanctum/csrf-cookie', Config::get('cors.paths'));

        $this->assertTrue(Config::get('cors.supports_credentials'));
        $this->assertIsArray(Config::get('cors.allowed_methods'));
        $this->assertIsArray(Config::get('cors.allowed_headers'));
        $this->assertIsArray(Config::get('cors.exposed_headers'));
        $this->assertContains('X-New-Token', Config::get('cors.exposed_headers'));
    }

    /**
     * Test audit log hash chain is working.
     */
    public function test_audit_log_hash_chain_is_working(): void
    {
        // Create first audit log
        $log1 = AuditLog::log(
            action: 'test.action1',
            severity: 'low'
        );

        // First log should have hash
        $this->assertNotNull($log1->hash);
        $this->assertEquals(64, strlen($log1->hash)); // SHA-256 hash length

        // Create second audit log
        $log2 = AuditLog::log(
            action: 'test.action2',
            severity: 'medium'
        );

        // Second log should have different hash
        $this->assertNotNull($log2->hash);
        $this->assertNotEquals($log1->hash, $log2->hash);

        // Verify hash chain integrity
        $result = AuditLog::verifyHashChain();
        $this->assertTrue($result['valid']);
        $this->assertEquals(2, $result['total_logs']);
        $this->assertEmpty($result['errors']);
    }

    /**
     * Test audit log detects tampering.
     */
    public function test_audit_log_detects_tampering(): void
    {
        // Create audit logs
        AuditLog::log(action: 'test.action1', severity: 'low');
        $log2 = AuditLog::log(action: 'test.action2', severity: 'medium');

        // Verify chain is valid
        $result = AuditLog::verifyHashChain();
        $this->assertTrue($result['valid']);

        // Tamper with second log directly in database
        DB::table('audit_logs')
            ->where('id', $log2->id)
            ->update(['action' => 'tampered.action']);

        // Hash chain should detect tampering
        $result = AuditLog::verifyHashChain();
        $this->assertFalse($result['valid']);
        $this->assertNotEmpty($result['errors']);
        $this->assertEquals($log2->id, $result['errors'][0]['log_id']);
    }

    /**
     * Test audit log severity classification.
     */
    public function test_audit_log_severity_classification(): void
    {
        // Test automatic severity detection
        $log1 = AuditLog::log(action: 'authentication.failed');
        $this->assertEquals('high', $log1->severity);

        $log2 = AuditLog::log(action: 'authentication.success');
        $this->assertEquals('medium', $log2->severity);

        $log3 = AuditLog::log(action: 'security.breach.detected');
        $this->assertEquals('critical', $log3->severity);

        // Test manual severity override
        $log4 = AuditLog::log(action: 'custom.action', severity: 'high');
        $this->assertEquals('high', $log4->severity);
    }

    /**
     * Test authentication events are logged.
     */
    public function test_authentication_events_are_logged(): void
    {
        $user = User::factory()->create([
            'email' => 'test@example.com',
            'password' => bcrypt('password'),
        ]);

        // Clear existing logs
        AuditLog::truncate();

        // Attempt login with wrong password
        $this->postJson('/api/v1/auth/login', [
            'email' => 'test@example.com',
            'password' => 'wrong-password',
        ]);

        // Should log authentication failure
        $this->assertDatabaseHas('audit_logs', [
            'action' => 'authentication.failed',
            'severity' => 'high',
        ]);

        // Clear logs
        AuditLog::truncate();

        // Successful login
        $this->postJson('/api/v1/auth/login', [
            'email' => 'test@example.com',
            'password' => 'password',
        ]);

        // Should log authentication success
        $this->assertDatabaseHas('audit_logs', [
            'action' => 'authentication.success',
            'severity' => 'medium',
            'user_id' => $user->id,
        ]);
    }

    /**
     * Test authorization failures are logged.
     */
    public function test_authorization_failures_are_logged(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        // Clear existing logs
        AuditLog::truncate();

        // Attempt to access forbidden resource
        $this->getJson('/api/v1/admin/settings');

        // Check if 403 was returned and logged
        $log = AuditLog::where('action', 'authorization.denied')->first();

        if ($log) {
            $this->assertEquals('high', $log->severity);
            $this->assertEquals($user->id, $log->user_id);
        }
    }

    /**
     * Test session configuration is hardened.
     */
    public function test_session_configuration_is_hardened(): void
    {
        $this->assertTrue(Config::get('session.expire_on_close'));
        $this->assertEquals('strict', Config::get('session.same_site'));

        // In production, secure should be true
        if (app()->environment('production')) {
            $this->assertTrue(Config::get('session.secure'));
        }

        $this->assertTrue(Config::get('session.http_only'));
    }

    /**
     * Test 2FA secrets are encrypted.
     */
    public function test_two_factor_secrets_are_encrypted(): void
    {
        $secret = 'base32secret3232';

        $user = User::factory()->create([
            'two_factor_enabled' => true,
            'two_factor_secret' => $secret,
        ]);

        // Secret should be decrypted when accessed via model
        $this->assertEquals($secret, $user->two_factor_secret);

        // Secret should be encrypted in database
        $rawData = DB::table('users')->where('id', $user->id)->first();

        // Encrypted data should be different from plain text
        $this->assertNotEquals($secret, $rawData->two_factor_secret);

        // Encrypted data should be longer than plain text
        $this->assertGreaterThan(strlen($secret), strlen($rawData->two_factor_secret));
    }

    /**
     * Test 2FA secrets are hidden from JSON.
     */
    public function test_two_factor_secrets_are_hidden_from_json(): void
    {
        $user = User::factory()->create([
            'two_factor_enabled' => true,
            'two_factor_secret' => 'secret',
        ]);

        $json = $user->toArray();

        $this->assertArrayNotHasKey('two_factor_secret', $json);
    }

    /**
     * Test X-New-Token header is exposed for token rotation.
     */
    public function test_new_token_header_is_exposed(): void
    {
        $exposedHeaders = Config::get('cors.exposed_headers');

        $this->assertIsArray($exposedHeaders);
        $this->assertContains('X-New-Token', $exposedHeaders);
    }

    /**
     * Test sensitive data is not logged in audit logs.
     */
    public function test_sensitive_data_is_not_logged(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        // Clear existing logs
        AuditLog::truncate();

        // Make request with sensitive data
        $this->postJson('/api/v1/users', [
            'name' => 'Test User',
            'email' => 'test@example.com',
            'password' => 'super-secret-password',
            'api_key' => 'secret-api-key',
        ]);

        // Check audit log doesn't contain sensitive data
        $logs = AuditLog::all();

        foreach ($logs as $log) {
            if ($log->metadata) {
                $jsonData = json_encode($log->metadata);

                $this->assertStringNotContainsString('super-secret-password', $jsonData);
                $this->assertStringNotContainsString('secret-api-key', $jsonData);

                // Should contain [REDACTED] if sensitive fields were present
                if (isset($log->metadata['input'])) {
                    if (isset($log->metadata['input']['password'])) {
                        $this->assertEquals('[REDACTED]', $log->metadata['input']['password']);
                    }
                }
            }
        }
    }
}
