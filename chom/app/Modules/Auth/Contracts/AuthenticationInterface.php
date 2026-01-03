<?php

declare(strict_types=1);

namespace App\Modules\Auth\Contracts;

use App\Models\User;

/**
 * Authentication Service Contract
 *
 * Defines the contract for authentication operations within the Identity & Access module.
 */
interface AuthenticationInterface
{
    /**
     * Authenticate a user with credentials.
     *
     * @param array $credentials User credentials (email, password)
     * @param bool $remember Remember user session
     * @return User Authenticated user
     * @throws \Illuminate\Auth\AuthenticationException
     */
    public function authenticate(array $credentials, bool $remember = false): User;

    /**
     * Log out the current user.
     *
     * @param string $userId User ID to log out
     * @return bool Success status
     */
    public function logout(string $userId): bool;

    /**
     * Verify user credentials without logging in.
     *
     * @param array $credentials User credentials
     * @return bool Verification result
     */
    public function verifyCredentials(array $credentials): bool;

    /**
     * Refresh user session.
     *
     * @param string $userId User ID
     * @return bool Success status
     */
    public function refreshSession(string $userId): bool;

    /**
     * Invalidate all sessions for a user.
     *
     * @param string $userId User ID
     * @return int Number of sessions invalidated
     */
    public function invalidateAllSessions(string $userId): int;

    /**
     * Check if user has active sessions.
     *
     * @param string $userId User ID
     * @return bool Has active sessions
     */
    public function hasActiveSessions(string $userId): bool;
}
