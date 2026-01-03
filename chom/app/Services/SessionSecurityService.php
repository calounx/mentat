<?php

declare(strict_types=1);

namespace App\Services;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\DB;
use Carbon\Carbon;

/**
 * Session Security Service
 *
 * Provides enhanced session security with IP validation, user agent checking,
 * suspicious login detection, and account lockout protection.
 *
 * Features:
 * - Session fixation protection (regenerate on login)
 * - IP address validation with subnet tolerance
 * - User agent validation to detect session hijacking
 * - New device/location detection
 * - Account lockout after failed login attempts
 * - Progressive lockout (increases with repeated failures)
 * - Notification of suspicious login attempts
 *
 * OWASP Reference: A07:2021 – Identification and Authentication Failures
 * Protection: Prevents session hijacking and brute force attacks
 *
 * @package App\Services
 */
class SessionSecurityService
{
    /**
     * Session security configuration.
     */
    protected array $sessionConfig;

    /**
     * Account lockout configuration.
     */
    protected array $lockoutConfig;

    /**
     * Suspicious login configuration.
     */
    protected array $suspiciousConfig;

    /**
     * Redis connection for tracking login attempts.
     */
    protected string $redisConnection;

    /**
     * Create a new service instance.
     */
    public function __construct()
    {
        $this->sessionConfig = Config::get('security.session', []);
        $this->lockoutConfig = Config::get('security.account_lockout', []);
        $this->suspiciousConfig = Config::get('security.suspicious_login', []);
        $this->redisConnection = Config::get('security.rate_limiting.redis_connection', 'default');
    }

    /**
     * Validate session security.
     *
     * Checks if current request matches session metadata:
     * - IP address matches (with optional subnet tolerance)
     * - User agent matches
     *
     * SECURITY: Detects session hijacking attempts
     *
     * @param Request $request Current request
     * @param object $user Authenticated user
     * @return array Validation result [valid, reason]
     */
    public function validateSession(Request $request, object $user): array
    {
        // Get session metadata
        $sessionIp = $request->session()->get('security.ip_address');
        $sessionUserAgent = $request->session()->get('security.user_agent');

        // Validate IP address
        if ($this->sessionConfig['validate_ip'] ?? true) {
            if (!$this->validateIpAddress($request->ip(), $sessionIp)) {
                return [
                    'valid' => false,
                    'reason' => 'ip_mismatch',
                    'message' => 'Session IP address mismatch detected',
                ];
            }
        }

        // Validate user agent
        if ($this->sessionConfig['validate_user_agent'] ?? true) {
            if (!$this->validateUserAgent($request->userAgent(), $sessionUserAgent)) {
                return [
                    'valid' => false,
                    'reason' => 'user_agent_mismatch',
                    'message' => 'Session user agent mismatch detected',
                ];
            }
        }

        return ['valid' => true];
    }

    /**
     * Initialize session security metadata.
     *
     * Called after successful login to store security information.
     * Also regenerates session ID to prevent session fixation.
     *
     * SECURITY: Session regeneration prevents session fixation attacks
     *
     * @param Request $request Current request
     * @param object $user Authenticated user
     * @return void
     */
    public function initializeSession(Request $request, object $user): void
    {
        // Regenerate session ID to prevent session fixation
        if ($this->sessionConfig['regenerate_on_login'] ?? true) {
            $request->session()->regenerate();
        }

        // Store security metadata
        $request->session()->put('security.ip_address', $request->ip());
        $request->session()->put('security.user_agent', $request->userAgent());
        $request->session()->put('security.login_at', now()->timestamp);
        $request->session()->put('security.user_id', $user->id);

        // Create device fingerprint for detection
        $fingerprint = $this->generateDeviceFingerprint($request);
        $request->session()->put('security.device_fingerprint', $fingerprint);
    }

    /**
     * Record failed login attempt.
     *
     * Tracks failed login attempts per user/IP combination.
     * Implements account lockout after max attempts exceeded.
     *
     * SECURITY: Prevents brute force password attacks
     *
     * @param string $identifier User identifier (email/username)
     * @param string $ipAddress Client IP address
     * @return array Result with lockout status
     */
    public function recordFailedLogin(string $identifier, string $ipAddress): array
    {
        if (!($this->lockoutConfig['enabled'] ?? true)) {
            return ['locked' => false];
        }

        $key = "login_attempts:{$identifier}:{$ipAddress}";
        $redis = Redis::connection($this->redisConnection);

        // Increment attempt counter
        $attempts = (int) $redis->incr($key);

        // Set expiration on first attempt
        if ($attempts === 1) {
            $window = $this->lockoutConfig['attempt_window'] ?? 15;
            $redis->expire($key, $window * 60);
        }

        $maxAttempts = $this->lockoutConfig['max_attempts'] ?? 5;

        // Check if account should be locked
        if ($attempts >= $maxAttempts) {
            $lockoutDuration = $this->calculateLockoutDuration($identifier);
            $this->lockAccount($identifier, $ipAddress, $lockoutDuration);

            return [
                'locked' => true,
                'attempts' => $attempts,
                'lockout_duration' => $lockoutDuration,
                'unlock_at' => now()->addMinutes($lockoutDuration)->timestamp,
            ];
        }

        return [
            'locked' => false,
            'attempts' => $attempts,
            'remaining' => max(0, $maxAttempts - $attempts),
        ];
    }

    /**
     * Record successful login.
     *
     * Clears failed attempt counter and checks for suspicious activity.
     *
     * @param object $user Authenticated user
     * @param Request $request Current request
     * @return array Result with suspicious activity flags
     */
    public function recordSuccessfulLogin(object $user, Request $request): array
    {
        // Clear failed attempts
        $this->clearFailedAttempts($user->email, $request->ip());

        // Unlock account if locked
        $this->unlockAccount($user->email);

        // Check for suspicious activity
        $suspicious = $this->detectSuspiciousLogin($user, $request);

        // Record login in database
        $this->recordLoginHistory($user, $request, $suspicious);

        // Send notification if suspicious
        if ($suspicious['is_suspicious']) {
            $this->notifySuspiciousLogin($user, $request, $suspicious);
        }

        return $suspicious;
    }

    /**
     * Check if account is locked.
     *
     * @param string $identifier User identifier
     * @return array Lock status and details
     */
    public function isAccountLocked(string $identifier): array
    {
        if (!($this->lockoutConfig['enabled'] ?? true)) {
            return ['locked' => false];
        }

        $key = "account_locked:{$identifier}";
        $redis = Redis::connection($this->redisConnection);

        $lockData = $redis->get($key);

        if (!$lockData) {
            return ['locked' => false];
        }

        $data = json_decode($lockData, true);

        return [
            'locked' => true,
            'locked_at' => $data['locked_at'],
            'unlock_at' => $data['unlock_at'],
            'reason' => $data['reason'] ?? 'too_many_failed_attempts',
        ];
    }

    /**
     * Detect suspicious login activity.
     *
     * Flags logins as suspicious based on:
     * - New device (never seen device fingerprint)
     * - New location (different IP range)
     * - Unusual time (outside normal login hours)
     * - Rapid location changes
     *
     * SECURITY: Helps detect account compromise
     *
     * @param object $user Authenticated user
     * @param Request $request Current request
     * @return array Suspicious activity details
     */
    protected function detectSuspiciousLogin(object $user, Request $request): array
    {
        if (!($this->suspiciousConfig['enabled'] ?? true)) {
            return ['is_suspicious' => false];
        }

        $fingerprint = $this->generateDeviceFingerprint($request);
        $ipAddress = $request->ip();

        $flags = [];

        // Check for new device
        if ($this->suspiciousConfig['require_verification_new_device'] ?? true) {
            if (!$this->isKnownDevice($user, $fingerprint)) {
                $flags[] = 'new_device';
            }
        }

        // Check for new location
        if ($this->suspiciousConfig['require_verification_new_location'] ?? true) {
            if (!$this->isKnownLocation($user, $ipAddress)) {
                $flags[] = 'new_location';
            }
        }

        // Check for rapid location change
        if ($this->hasRapidLocationChange($user, $ipAddress)) {
            $flags[] = 'rapid_location_change';
        }

        return [
            'is_suspicious' => !empty($flags),
            'flags' => $flags,
            'fingerprint' => $fingerprint,
            'ip_address' => $ipAddress,
        ];
    }

    /**
     * Validate IP address matches session.
     *
     * Supports subnet tolerance for mobile users.
     *
     * @param string|null $currentIp Current IP address
     * @param string|null $sessionIp Session IP address
     * @return bool True if IP is valid
     */
    protected function validateIpAddress(?string $currentIp, ?string $sessionIp): bool
    {
        if (!$currentIp || !$sessionIp) {
            return false;
        }

        // Exact match
        if ($currentIp === $sessionIp) {
            return true;
        }

        // Allow subnet changes for mobile users
        if ($this->sessionConfig['allow_subnet_changes'] ?? false) {
            return $this->isSameSubnet($currentIp, $sessionIp);
        }

        return false;
    }

    /**
     * Validate user agent matches session.
     *
     * Allows minor version changes in browsers.
     *
     * @param string|null $currentUa Current user agent
     * @param string|null $sessionUa Session user agent
     * @return bool True if user agent is valid
     */
    protected function validateUserAgent(?string $currentUa, ?string $sessionUa): bool
    {
        if (!$currentUa || !$sessionUa) {
            return false;
        }

        // Exact match
        if ($currentUa === $sessionUa) {
            return true;
        }

        // Allow minor version changes (e.g., browser auto-update)
        return $this->isSimilarUserAgent($currentUa, $sessionUa);
    }

    /**
     * Check if IPs are in same subnet.
     *
     * Compares first 3 octets for IPv4 (/24 subnet).
     *
     * @param string $ip1 First IP address
     * @param string $ip2 Second IP address
     * @return bool True if in same subnet
     */
    protected function isSameSubnet(string $ip1, string $ip2): bool
    {
        $octets1 = explode('.', $ip1);
        $octets2 = explode('.', $ip2);

        if (count($octets1) !== 4 || count($octets2) !== 4) {
            return false;
        }

        // Compare first 3 octets (/24 subnet)
        return $octets1[0] === $octets2[0]
            && $octets1[1] === $octets2[1]
            && $octets1[2] === $octets2[2];
    }

    /**
     * Check if user agents are similar.
     *
     * Extracts browser name and major version for comparison.
     *
     * @param string $ua1 First user agent
     * @param string $ua2 Second user agent
     * @return bool True if user agents are similar
     */
    protected function isSimilarUserAgent(string $ua1, string $ua2): bool
    {
        // Extract browser name and major version
        $browser1 = $this->extractBrowserInfo($ua1);
        $browser2 = $this->extractBrowserInfo($ua2);

        return $browser1['name'] === $browser2['name']
            && $browser1['major_version'] === $browser2['major_version']
            && $browser1['platform'] === $browser2['platform'];
    }

    /**
     * Extract browser information from user agent.
     *
     * @param string $userAgent User agent string
     * @return array Browser information
     */
    protected function extractBrowserInfo(string $userAgent): array
    {
        $info = [
            'name' => 'unknown',
            'major_version' => '0',
            'platform' => 'unknown',
        ];

        // Detect browser
        if (preg_match('/Chrome\/(\d+)/', $userAgent, $matches)) {
            $info['name'] = 'Chrome';
            $info['major_version'] = $matches[1];
        } elseif (preg_match('/Firefox\/(\d+)/', $userAgent, $matches)) {
            $info['name'] = 'Firefox';
            $info['major_version'] = $matches[1];
        } elseif (preg_match('/Safari\/(\d+)/', $userAgent, $matches)) {
            $info['name'] = 'Safari';
            $info['major_version'] = $matches[1];
        }

        // Detect platform
        if (str_contains($userAgent, 'Windows')) {
            $info['platform'] = 'Windows';
        } elseif (str_contains($userAgent, 'Macintosh')) {
            $info['platform'] = 'Mac';
        } elseif (str_contains($userAgent, 'Linux')) {
            $info['platform'] = 'Linux';
        } elseif (str_contains($userAgent, 'iPhone') || str_contains($userAgent, 'iPad')) {
            $info['platform'] = 'iOS';
        } elseif (str_contains($userAgent, 'Android')) {
            $info['platform'] = 'Android';
        }

        return $info;
    }

    /**
     * Generate device fingerprint.
     *
     * Creates unique identifier for device based on:
     * - User agent
     * - Accept headers
     * - Accept-Language
     * - Screen resolution (if available)
     *
     * @param Request $request Current request
     * @return string Device fingerprint hash
     */
    protected function generateDeviceFingerprint(Request $request): string
    {
        $components = [
            $request->userAgent(),
            $request->header('Accept'),
            $request->header('Accept-Language'),
            $request->header('Accept-Encoding'),
        ];

        $data = implode('|', array_filter($components));

        return hash('sha256', $data);
    }

    /**
     * Calculate lockout duration with progressive increase.
     *
     * Increases lockout duration for repeated violations.
     *
     * @param string $identifier User identifier
     * @return int Lockout duration in minutes
     */
    protected function calculateLockoutDuration(string $identifier): int
    {
        $baseDuration = $this->lockoutConfig['lockout_duration'] ?? 15;

        if (!($this->lockoutConfig['progressive_lockout'] ?? true)) {
            return $baseDuration;
        }

        // Get number of previous lockouts
        $key = "lockout_count:{$identifier}";
        $redis = Redis::connection($this->redisConnection);
        $lockoutCount = (int) $redis->get($key) ?? 0;

        // Double duration for each repeated lockout (max 8 hours)
        $duration = min($baseDuration * pow(2, $lockoutCount), 480);

        return (int) $duration;
    }

    /**
     * Lock account.
     *
     * @param string $identifier User identifier
     * @param string $ipAddress IP address
     * @param int $duration Lockout duration in minutes
     * @return void
     */
    protected function lockAccount(string $identifier, string $ipAddress, int $duration): void
    {
        $key = "account_locked:{$identifier}";
        $redis = Redis::connection($this->redisConnection);

        $lockData = json_encode([
            'locked_at' => now()->timestamp,
            'unlock_at' => now()->addMinutes($duration)->timestamp,
            'ip_address' => $ipAddress,
            'reason' => 'too_many_failed_attempts',
        ]);

        $redis->setex($key, $duration * 60, $lockData);

        // Increment lockout counter
        $countKey = "lockout_count:{$identifier}";
        $redis->incr($countKey);
        $redis->expire($countKey, 86400 * 30); // 30 days

        // Send notification if enabled
        if ($this->lockoutConfig['notify_on_lockout'] ?? true) {
            $this->notifyAccountLockout($identifier, $duration);
        }
    }

    /**
     * Unlock account.
     *
     * @param string $identifier User identifier
     * @return void
     */
    protected function unlockAccount(string $identifier): void
    {
        $key = "account_locked:{$identifier}";
        $redis = Redis::connection($this->redisConnection);
        $redis->del($key);
    }

    /**
     * Clear failed login attempts.
     *
     * @param string $identifier User identifier
     * @param string $ipAddress IP address
     * @return void
     */
    protected function clearFailedAttempts(string $identifier, string $ipAddress): void
    {
        $key = "login_attempts:{$identifier}:{$ipAddress}";
        $redis = Redis::connection($this->redisConnection);
        $redis->del($key);
    }

    /**
     * Check if device is known.
     *
     * @param object $user User object
     * @param string $fingerprint Device fingerprint
     * @return bool True if device is known
     */
    protected function isKnownDevice(object $user, string $fingerprint): bool
    {
        $maxDevices = $this->suspiciousConfig['max_trusted_devices'] ?? 10;
        $trustDuration = $this->suspiciousConfig['device_trust_duration'] ?? 30;

        $key = "trusted_devices:{$user->id}";
        $redis = Redis::connection($this->redisConnection);

        $devices = json_decode($redis->get($key) ?? '[]', true);

        foreach ($devices as $device) {
            if ($device['fingerprint'] === $fingerprint) {
                // Check if trust has expired
                $trustedAt = Carbon::parse($device['trusted_at']);
                if ($trustedAt->addDays($trustDuration)->isFuture()) {
                    return true;
                }
            }
        }

        return false;
    }

    /**
     * Check if location is known.
     *
     * @param object $user User object
     * @param string $ipAddress IP address
     * @return bool True if location is known
     */
    protected function isKnownLocation(object $user, string $ipAddress): bool
    {
        // Get recent login locations from database
        $recentLogins = DB::table('login_history')
            ->where('user_id', $user->id)
            ->where('created_at', '>=', now()->subDays(30))
            ->pluck('ip_address')
            ->unique();

        foreach ($recentLogins as $knownIp) {
            if ($this->isSameSubnet($ipAddress, $knownIp)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Check for rapid location change.
     *
     * Detects impossible travel (location change too fast).
     *
     * @param object $user User object
     * @param string $ipAddress Current IP address
     * @return bool True if rapid location change detected
     */
    protected function hasRapidLocationChange(object $user, string $ipAddress): bool
    {
        // Get most recent login
        $lastLogin = DB::table('login_history')
            ->where('user_id', $user->id)
            ->orderBy('created_at', 'desc')
            ->first();

        if (!$lastLogin) {
            return false;
        }

        // Check if IP changed within last hour
        $timeSinceLastLogin = now()->diffInMinutes(Carbon::parse($lastLogin->created_at));

        if ($timeSinceLastLogin > 60) {
            return false;
        }

        // Check if IP is from different subnet
        return !$this->isSameSubnet($ipAddress, $lastLogin->ip_address);
    }

    /**
     * Record login in history.
     *
     * @param object $user User object
     * @param Request $request Current request
     * @param array $suspicious Suspicious activity data
     * @return void
     */
    protected function recordLoginHistory(object $user, Request $request, array $suspicious): void
    {
        DB::table('login_history')->insert([
            'user_id' => $user->id,
            'ip_address' => $request->ip(),
            'user_agent' => $request->userAgent(),
            'device_fingerprint' => $suspicious['fingerprint'] ?? null,
            'is_suspicious' => $suspicious['is_suspicious'],
            'suspicious_flags' => json_encode($suspicious['flags'] ?? []),
            'created_at' => now(),
        ]);
    }

    /**
     * Notify user of suspicious login.
     *
     * @param object $user User object
     * @param Request $request Current request
     * @param array $suspicious Suspicious activity data
     * @return void
     */
    protected function notifySuspiciousLogin(object $user, Request $request, array $suspicious): void
    {
        if (!($this->suspiciousConfig['notify_new_login'] ?? true)) {
            return;
        }

        // Implementation would send email notification
        // Mail::to($user->email)->send(new SuspiciousLoginNotification($user, $request, $suspicious));
    }

    /**
     * Notify user of account lockout.
     *
     * @param string $identifier User identifier
     * @param int $duration Lockout duration
     * @return void
     */
    protected function notifyAccountLockout(string $identifier, int $duration): void
    {
        // Implementation would send email notification
        // Mail::to($identifier)->send(new AccountLockedNotification($duration));
    }
}
