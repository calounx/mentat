<?php

declare(strict_types=1);

namespace Tests\Unit\Services;

use App\Models\User;
use App\Services\SessionSecurityService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Session;
use Tests\TestCase;

class SessionSecurityServiceTest extends TestCase
{
    use RefreshDatabase;

    private SessionSecurityService $service;
    private User $user;

    protected function setUp(): void
    {
        parent::setUp();

        $this->service = new SessionSecurityService();
        $this->user = User::factory()->create([
            'password' => Hash::make('password123'),
        ]);

        Cache::flush();
        Session::flush();
    }

    protected function tearDown(): void
    {
        Cache::flush();
        parent::tearDown();
    }

    public function test_prevents_session_fixation(): void
    {
        $request = Request::create('/login', 'POST');
        Session::start();
        $oldSessionId = Session::getId();

        $this->service->regenerateSession();

        $newSessionId = Session::getId();

        $this->assertNotEquals($oldSessionId, $newSessionId);
    }

    public function test_validates_ip_address_consistency(): void
    {
        $ipAddress = '192.168.1.100';
        Session::put('ip_address', $ipAddress);

        $request = Request::create('/test', 'GET', [], [], [], [
            'REMOTE_ADDR' => $ipAddress,
        ]);

        $result = $this->service->validateIpAddress($request);

        $this->assertTrue($result);
    }

    public function test_detects_ip_address_change(): void
    {
        $originalIp = '192.168.1.100';
        $newIp = '10.0.0.50';

        Session::put('ip_address', $originalIp);

        $request = Request::create('/test', 'GET', [], [], [], [
            'REMOTE_ADDR' => $newIp,
        ]);

        $result = $this->service->validateIpAddress($request);

        $this->assertFalse($result);
    }

    public function test_detects_suspicious_login_from_new_location(): void
    {
        $userId = $this->user->id;
        $knownIp = '192.168.1.100';
        $suspiciousIp = '203.45.67.89';

        // Record successful login from known IP
        Cache::put("login_history:{$userId}", [$knownIp], 3600);

        $result = $this->service->detectSuspiciousLogin($userId, $suspiciousIp);

        $this->assertTrue($result);
    }

    public function test_allows_login_from_known_location(): void
    {
        $userId = $this->user->id;
        $knownIp = '192.168.1.100';

        // Record successful login history
        Cache::put("login_history:{$userId}", [$knownIp], 3600);

        $result = $this->service->detectSuspiciousLogin($userId, $knownIp);

        $this->assertFalse($result);
    }

    public function test_detects_multiple_failed_login_attempts(): void
    {
        $userId = $this->user->id;
        $ipAddress = '192.168.1.100';

        // Record 5 failed attempts
        for ($i = 0; $i < 5; $i++) {
            $this->service->recordFailedLogin($userId, $ipAddress);
        }

        $result = $this->service->shouldLockAccount($userId);

        $this->assertTrue($result);
    }

    public function test_locks_account_after_threshold_exceeded(): void
    {
        $userId = $this->user->id;
        $ipAddress = '192.168.1.100';

        // Record 6 failed attempts (threshold is 5)
        for ($i = 0; $i < 6; $i++) {
            $this->service->recordFailedLogin($userId, $ipAddress);
        }

        $this->service->lockAccount($userId);

        $this->assertTrue($this->service->isAccountLocked($userId));
    }

    public function test_account_lock_expires_after_timeout(): void
    {
        $userId = $this->user->id;

        // Lock account for 1 second
        $this->service->lockAccount($userId, 1);

        $this->assertTrue($this->service->isAccountLocked($userId));

        // Wait for lock to expire
        sleep(2);

        $this->assertFalse($this->service->isAccountLocked($userId));
    }

    public function test_clears_failed_attempts_after_successful_login(): void
    {
        $userId = $this->user->id;
        $ipAddress = '192.168.1.100';

        // Record failed attempts
        for ($i = 0; $i < 3; $i++) {
            $this->service->recordFailedLogin($userId, $ipAddress);
        }

        $this->assertEquals(3, $this->service->getFailedAttempts($userId));

        // Successful login
        $this->service->clearFailedAttempts($userId);

        $this->assertEquals(0, $this->service->getFailedAttempts($userId));
    }

    public function test_detects_session_hijacking_attempt(): void
    {
        Session::start();
        Session::put('user_agent', 'Mozilla/5.0 (Windows)');
        Session::put('fingerprint', hash('sha256', 'original_fingerprint'));

        $request = Request::create('/test', 'GET', [], [], [], [
            'HTTP_USER_AGENT' => 'Different User Agent',
        ]);

        $result = $this->service->validateSessionFingerprint($request);

        $this->assertFalse($result);
    }

    public function test_validates_correct_session_fingerprint(): void
    {
        $userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)';

        Session::start();
        Session::put('user_agent', $userAgent);
        Session::put('fingerprint', hash('sha256', $userAgent));

        $request = Request::create('/test', 'GET', [], [], [], [
            'HTTP_USER_AGENT' => $userAgent,
        ]);

        $result = $this->service->validateSessionFingerprint($request);

        $this->assertTrue($result);
    }

    public function test_enforces_session_timeout(): void
    {
        Session::start();
        Session::put('last_activity', now()->subMinutes(31)->timestamp);

        $result = $this->service->isSessionExpired();

        $this->assertTrue($result);
    }

    public function test_session_not_expired_within_timeout_window(): void
    {
        Session::start();
        Session::put('last_activity', now()->subMinutes(15)->timestamp);

        $result = $this->service->isSessionExpired();

        $this->assertFalse($result);
    }

    public function test_updates_last_activity_timestamp(): void
    {
        Session::start();
        $oldTimestamp = now()->subMinutes(5)->timestamp;
        Session::put('last_activity', $oldTimestamp);

        $this->service->updateLastActivity();

        $newTimestamp = Session::get('last_activity');

        $this->assertGreaterThan($oldTimestamp, $newTimestamp);
        $this->assertEqualsWithDelta(now()->timestamp, $newTimestamp, 2);
    }

    public function test_detects_concurrent_sessions_from_different_ips(): void
    {
        $userId = $this->user->id;
        $ip1 = '192.168.1.100';
        $ip2 = '10.0.0.50';

        $this->service->recordActiveSession($userId, $ip1);
        $this->service->recordActiveSession($userId, $ip2);

        $activeSessions = $this->service->getActiveSessions($userId);

        $this->assertCount(2, $activeSessions);
        $this->assertContains($ip1, $activeSessions);
        $this->assertContains($ip2, $activeSessions);
    }

    public function test_revokes_all_sessions_for_user(): void
    {
        $userId = $this->user->id;

        $this->service->recordActiveSession($userId, '192.168.1.100');
        $this->service->recordActiveSession($userId, '10.0.0.50');

        $this->service->revokeAllSessions($userId);

        $activeSessions = $this->service->getActiveSessions($userId);

        $this->assertEmpty($activeSessions);
    }

    public function test_tracks_login_timestamps(): void
    {
        $userId = $this->user->id;
        $ipAddress = '192.168.1.100';

        $this->service->recordSuccessfulLogin($userId, $ipAddress);

        $lastLogin = $this->service->getLastLoginTimestamp($userId);

        $this->assertEqualsWithDelta(now()->timestamp, $lastLogin, 2);
    }

    public function test_detects_impossible_travel(): void
    {
        $userId = $this->user->id;

        // Login from New York
        $this->service->recordSuccessfulLogin($userId, '192.168.1.100', [
            'location' => 'New York, US',
            'timestamp' => now()->timestamp,
        ]);

        // Login from Tokyo 1 minute later (impossible)
        $result = $this->service->detectImpossibleTravel($userId, '203.45.67.89', [
            'location' => 'Tokyo, JP',
            'timestamp' => now()->addMinute()->timestamp,
        ]);

        $this->assertTrue($result);
    }

    public function test_generates_secure_session_token(): void
    {
        $token = $this->service->generateSecureToken();

        $this->assertIsString($token);
        $this->assertGreaterThanOrEqual(32, strlen($token));
        $this->assertMatchesRegularExpression('/^[a-f0-9]+$/', $token);
    }

    public function test_validates_csrf_token(): void
    {
        Session::start();
        $token = $this->service->generateSecureToken();
        Session::put('csrf_token', $token);

        $result = $this->service->validateCsrfToken($token);

        $this->assertTrue($result);
    }

    public function test_rejects_invalid_csrf_token(): void
    {
        Session::start();
        Session::put('csrf_token', 'valid_token_abc123');

        $result = $this->service->validateCsrfToken('invalid_token_xyz789');

        $this->assertFalse($result);
    }

    public function test_rate_limits_login_attempts_per_ip(): void
    {
        $ipAddress = '192.168.1.100';

        // Make 10 login attempts
        for ($i = 0; $i < 10; $i++) {
            $this->service->recordLoginAttempt($ipAddress);
        }

        $result = $this->service->isIpRateLimited($ipAddress);

        $this->assertTrue($result);
    }

    public function test_stores_security_audit_trail(): void
    {
        $userId = $this->user->id;
        $event = 'password_changed';
        $metadata = ['ip' => '192.168.1.100', 'timestamp' => now()->toIso8601String()];

        $this->service->logSecurityEvent($userId, $event, $metadata);

        $events = $this->service->getSecurityEvents($userId);

        $this->assertNotEmpty($events);
        $this->assertEquals($event, $events[0]['event']);
        $this->assertEquals($metadata, $events[0]['metadata']);
    }

    public function test_performance_under_concurrent_validation_requests(): void
    {
        Session::start();
        $userAgent = 'Mozilla/5.0';
        Session::put('user_agent', $userAgent);
        Session::put('fingerprint', hash('sha256', $userAgent));

        $request = Request::create('/test', 'GET', [], [], [], [
            'HTTP_USER_AGENT' => $userAgent,
        ]);

        $startTime = microtime(true);

        for ($i = 0; $i < 100; $i++) {
            $this->service->validateSessionFingerprint($request);
        }

        $endTime = microtime(true);
        $duration = ($endTime - $startTime) * 1000;

        // 100 validations should complete in under 100ms
        $this->assertLessThan(100, $duration);
    }
}
