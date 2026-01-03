<?php

declare(strict_types=1);

namespace Tests\Unit\Services;

use App\Services\SessionSecurityService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Session Security Service Test
 *
 * Tests session security functionality including:
 * - IP validation
 * - User agent validation
 * - Account lockout
 * - Suspicious login detection
 *
 * @package Tests\Unit\Services
 */
class SessionSecurityServiceTest extends TestCase
{
    protected SessionSecurityService $service;

    protected function setUp(): void
    {
        parent::setUp();

        $this->service = new SessionSecurityService();

        // Configure security settings
        Config::set('security.session', [
            'validate_ip' => true,
            'validate_user_agent' => true,
            'allow_subnet_changes' => false,
        ]);

        Config::set('security.account_lockout', [
            'enabled' => true,
            'max_attempts' => 5,
            'lockout_duration' => 15,
            'attempt_window' => 15,
        ]);

        // Clear Redis
        Redis::flushall();
    }

    /**
     * Test session validation with matching IP.
     */
    public function test_session_validation_with_matching_ip(): void
    {
        $request = Request::create('/test', 'GET');
        $request->server->set('REMOTE_ADDR', '192.168.1.100');
        $request->headers->set('User-Agent', 'Mozilla/5.0');

        // Set session metadata
        $request->session()->put('security.ip_address', '192.168.1.100');
        $request->session()->put('security.user_agent', 'Mozilla/5.0');

        $user = (object) ['id' => 1];

        $result = $this->service->validateSession($request, $user);

        $this->assertTrue($result['valid']);
    }

    /**
     * Test session validation with mismatched IP.
     */
    public function test_session_validation_with_mismatched_ip(): void
    {
        $request = Request::create('/test', 'GET');
        $request->server->set('REMOTE_ADDR', '192.168.1.200');
        $request->headers->set('User-Agent', 'Mozilla/5.0');

        // Set session metadata with different IP
        $request->session()->put('security.ip_address', '192.168.1.100');
        $request->session()->put('security.user_agent', 'Mozilla/5.0');

        $user = (object) ['id' => 1];

        $result = $this->service->validateSession($request, $user);

        $this->assertFalse($result['valid']);
        $this->assertEquals('ip_mismatch', $result['reason']);
    }

    /**
     * Test session validation with mismatched user agent.
     */
    public function test_session_validation_with_mismatched_user_agent(): void
    {
        $request = Request::create('/test', 'GET');
        $request->server->set('REMOTE_ADDR', '192.168.1.100');
        $request->headers->set('User-Agent', 'Different Browser');

        // Set session metadata with different user agent
        $request->session()->put('security.ip_address', '192.168.1.100');
        $request->session()->put('security.user_agent', 'Mozilla/5.0');

        $user = (object) ['id' => 1];

        $result = $this->service->validateSession($request, $user);

        $this->assertFalse($result['valid']);
        $this->assertEquals('user_agent_mismatch', $result['reason']);
    }

    /**
     * Test failed login attempt tracking.
     */
    public function test_failed_login_attempt_tracking(): void
    {
        $identifier = 'test@example.com';
        $ipAddress = '192.168.1.100';

        // Record first failed attempt
        $result = $this->service->recordFailedLogin($identifier, $ipAddress);

        $this->assertFalse($result['locked']);
        $this->assertEquals(1, $result['attempts']);
        $this->assertEquals(4, $result['remaining']);
    }

    /**
     * Test account lockout after max attempts.
     */
    public function test_account_lockout_after_max_attempts(): void
    {
        $identifier = 'test@example.com';
        $ipAddress = '192.168.1.100';

        // Record 5 failed attempts
        for ($i = 0; $i < 5; $i++) {
            $result = $this->service->recordFailedLogin($identifier, $ipAddress);
        }

        // Should be locked now
        $this->assertTrue($result['locked']);
        $this->assertArrayHasKey('lockout_duration', $result);
        $this->assertArrayHasKey('unlock_at', $result);
    }

    /**
     * Test account locked check.
     */
    public function test_account_locked_check(): void
    {
        $identifier = 'test@example.com';
        $ipAddress = '192.168.1.100';

        // Lock account
        for ($i = 0; $i < 5; $i++) {
            $this->service->recordFailedLogin($identifier, $ipAddress);
        }

        // Check if locked
        $lockStatus = $this->service->isAccountLocked($identifier);

        $this->assertTrue($lockStatus['locked']);
        $this->assertArrayHasKey('unlock_at', $lockStatus);
    }

    /**
     * Test successful login clears failed attempts.
     */
    public function test_successful_login_clears_failed_attempts(): void
    {
        $identifier = 'test@example.com';
        $ipAddress = '192.168.1.100';

        // Record failed attempts
        for ($i = 0; $i < 3; $i++) {
            $this->service->recordFailedLogin($identifier, $ipAddress);
        }

        // Successful login
        $user = (object) [
            'id' => 1,
            'email' => $identifier,
            'current_team_id' => null,
        ];

        $request = Request::create('/login', 'POST');
        $request->server->set('REMOTE_ADDR', $ipAddress);

        $this->service->recordSuccessfulLogin($user, $request);

        // Check failed attempts cleared
        $result = $this->service->recordFailedLogin($identifier, $ipAddress);
        $this->assertEquals(1, $result['attempts']);
    }

    /**
     * Test subnet IP validation.
     */
    public function test_subnet_ip_validation(): void
    {
        Config::set('security.session.allow_subnet_changes', true);

        $request = Request::create('/test', 'GET');
        $request->server->set('REMOTE_ADDR', '192.168.1.105'); // Different last octet
        $request->headers->set('User-Agent', 'Mozilla/5.0');

        // Set session metadata with similar IP
        $request->session()->put('security.ip_address', '192.168.1.100');
        $request->session()->put('security.user_agent', 'Mozilla/5.0');

        $user = (object) ['id' => 1];

        $result = $this->service->validateSession($request, $user);

        // Should be valid with subnet tolerance
        $this->assertTrue($result['valid']);
    }

    protected function tearDown(): void
    {
        Redis::flushall();
        parent::tearDown();
    }
}
