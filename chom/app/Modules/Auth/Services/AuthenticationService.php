<?php

declare(strict_types=1);

namespace App\Modules\Auth\Services;

use App\Models\User;
use App\Modules\Auth\Contracts\AuthenticationInterface;
use App\Modules\Auth\Events\UserAuthenticated;
use App\Modules\Auth\Events\UserLoggedOut;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;

/**
 * Authentication Service
 *
 * Handles core authentication operations including login, logout,
 * session management, and credential verification.
 */
class AuthenticationService implements AuthenticationInterface
{
    /**
     * Authenticate a user with credentials.
     *
     * @param array $credentials User credentials (email, password)
     * @param bool $remember Remember user session
     * @return User Authenticated user
     * @throws AuthenticationException
     */
    public function authenticate(array $credentials, bool $remember = false): User
    {
        try {
            if (!Auth::attempt($credentials, $remember)) {
                Log::warning('Authentication failed', [
                    'email' => $credentials['email'] ?? 'unknown',
                    'ip' => request()->ip(),
                ]);

                throw new AuthenticationException('Invalid credentials');
            }

            $user = Auth::user();

            if (!$user instanceof User) {
                Auth::logout();
                throw new AuthenticationException('Invalid user type');
            }

            // Check if user account is active
            if (!$user->is_active) {
                Auth::logout();
                throw new AuthenticationException('User account is inactive');
            }

            Log::info('User authenticated successfully', [
                'user_id' => $user->id,
                'email' => $user->email,
                'ip' => request()->ip(),
            ]);

            Event::dispatch(new UserAuthenticated($user, request()->ip()));

            return $user;
        } catch (AuthenticationException $e) {
            throw $e;
        } catch (\Exception $e) {
            Log::error('Authentication error', [
                'email' => $credentials['email'] ?? 'unknown',
                'error' => $e->getMessage(),
            ]);

            throw new AuthenticationException('Authentication failed');
        }
    }

    /**
     * Log out the current user.
     *
     * @param string $userId User ID to log out
     * @return bool Success status
     */
    public function logout(string $userId): bool
    {
        try {
            $user = User::find($userId);

            if (!$user) {
                Log::warning('Logout attempted for non-existent user', [
                    'user_id' => $userId,
                ]);
                return false;
            }

            Auth::logout();

            request()->session()->invalidate();
            request()->session()->regenerateToken();

            Log::info('User logged out', [
                'user_id' => $userId,
                'email' => $user->email,
            ]);

            Event::dispatch(new UserLoggedOut($user));

            return true;
        } catch (\Exception $e) {
            Log::error('Logout error', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Verify user credentials without logging in.
     *
     * @param array $credentials User credentials
     * @return bool Verification result
     */
    public function verifyCredentials(array $credentials): bool
    {
        try {
            $user = User::where('email', $credentials['email'])->first();

            if (!$user) {
                return false;
            }

            return Hash::check($credentials['password'], $user->password);
        } catch (\Exception $e) {
            Log::error('Credential verification error', [
                'email' => $credentials['email'] ?? 'unknown',
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Refresh user session.
     *
     * @param string $userId User ID
     * @return bool Success status
     */
    public function refreshSession(string $userId): bool
    {
        try {
            $user = User::find($userId);

            if (!$user) {
                return false;
            }

            request()->session()->regenerate();

            Log::debug('Session refreshed', [
                'user_id' => $userId,
            ]);

            return true;
        } catch (\Exception $e) {
            Log::error('Session refresh error', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Invalidate all sessions for a user.
     *
     * @param string $userId User ID
     * @return int Number of sessions invalidated
     */
    public function invalidateAllSessions(string $userId): int
    {
        try {
            $count = DB::table('sessions')
                ->where('user_id', $userId)
                ->delete();

            Log::info('All sessions invalidated', [
                'user_id' => $userId,
                'session_count' => $count,
            ]);

            return $count;
        } catch (\Exception $e) {
            Log::error('Session invalidation error', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);

            return 0;
        }
    }

    /**
     * Check if user has active sessions.
     *
     * @param string $userId User ID
     * @return bool Has active sessions
     */
    public function hasActiveSessions(string $userId): bool
    {
        try {
            return DB::table('sessions')
                ->where('user_id', $userId)
                ->where('last_activity', '>', now()->subMinutes(30)->timestamp)
                ->exists();
        } catch (\Exception $e) {
            Log::error('Active session check error', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }
}
