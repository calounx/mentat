<?php

declare(strict_types=1);

namespace Tests\Integration;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use PragmaRX\Google2FA\Google2FA;
use Tests\Concerns\WithSecurityTesting;
use Tests\TestCase;

/**
 * Integration test for complete authentication flow
 *
 * Tests user registration, login, two-factor authentication, password reset,
 * session management, and security features.
 */
class AuthenticationFlowTest extends TestCase
{
    use RefreshDatabase;
    use WithSecurityTesting;

    /**
     * Test complete user registration and email verification flow
     */
    public function test_complete_registration_flow_with_email_verification(): void
    {
        // Act - Register
        $response = $this->post('/register', [
            'name' => 'John Doe',
            'email' => 'john@example.com',
            'password' => 'SecurePassword123!',
            'password_confirmation' => 'SecurePassword123!',
            'organization_name' => 'Test Organization',
        ]);

        // Assert - User created but not verified
        $response->assertRedirect('/email/verify');
        $this->assertDatabaseHas('users', [
            'email' => 'john@example.com',
            'email_verified_at' => null,
        ]);

        // Act - Verify email
        $user = User::where('email', 'john@example.com')->first();
        $verificationUrl = \URL::temporarySignedRoute(
            'verification.verify',
            now()->addMinutes(60),
            ['id' => $user->id, 'hash' => sha1($user->email)]
        );

        $verifyResponse = $this->actingAs($user)->get($verificationUrl);

        // Assert - Email verified
        $verifyResponse->assertRedirect('/dashboard');
        $user->refresh();
        $this->assertNotNull($user->email_verified_at);
    }

    /**
     * Test login with valid credentials
     */
    public function test_login_with_valid_credentials(): void
    {
        // Arrange
        $user = User::factory()->create([
            'password' => Hash::make('password123'),
        ]);

        // Act
        $response = $this->post('/login', [
            'email' => $user->email,
            'password' => 'password123',
        ]);

        // Assert
        $response->assertRedirect('/dashboard');
        $this->assertAuthenticatedAs($user);
    }

    /**
     * Test two-factor authentication setup and verification
     */
    public function test_two_factor_authentication_setup_and_verification(): void
    {
        $this->markTestSkipped('Google2FA package not installed');

        // Arrange
        $user = User::factory()->create();
        $google2fa = new Google2FA;

        // Act - Enable 2FA
        $setupResponse = $this->actingAs($user)
            ->post('/user/two-factor-authentication');

        // Assert - 2FA enabled
        $setupResponse->assertStatus(200);
        $user->refresh();
        $this->assertNotNull($user->two_factor_secret);

        // Act - Login requires 2FA
        $this->post('/logout');
        $loginResponse = $this->post('/login', [
            'email' => $user->email,
            'password' => 'password',
        ]);

        // Should redirect to 2FA challenge
        $loginResponse->assertRedirect('/two-factor-challenge');

        // Act - Verify 2FA code
        $secret = decrypt($user->two_factor_secret);
        $validCode = $google2fa->getCurrentOtp($secret);

        $twoFactorResponse = $this->post('/two-factor-challenge', [
            'code' => $validCode,
        ]);

        // Assert - Successfully authenticated
        $twoFactorResponse->assertRedirect('/dashboard');
        $this->assertAuthenticatedAs($user);
    }

    /**
     * Test account lockout after multiple failed login attempts
     */
    public function test_account_lockout_after_failed_attempts(): void
    {
        // Arrange
        $user = User::factory()->create();

        // Act - Multiple failed attempts
        for ($i = 0; $i < 5; $i++) {
            $this->post('/login', [
                'email' => $user->email,
                'password' => 'wrong-password',
            ]);
        }

        // Assert - Account locked
        $response = $this->post('/login', [
            'email' => $user->email,
            'password' => 'password',
        ]);

        $response->assertSessionHasErrors();
        $this->assertGuest();
    }

    /**
     * Test password reset flow
     */
    public function test_password_reset_flow(): void
    {
        // Arrange
        $user = User::factory()->create();

        // Act - Request password reset
        $requestResponse = $this->post('/forgot-password', [
            'email' => $user->email,
        ]);

        $requestResponse->assertSessionHas('status');

        // Act - Reset password
        $token = \Password::createToken($user);
        $resetResponse = $this->post('/reset-password', [
            'token' => $token,
            'email' => $user->email,
            'password' => 'NewSecurePassword123!',
            'password_confirmation' => 'NewSecurePassword123!',
        ]);

        // Assert
        $resetResponse->assertRedirect('/login');
        $user->refresh();
        $this->assertTrue(Hash::check('NewSecurePassword123!', $user->password));
    }

    /**
     * Test session regeneration prevents fixation
     */
    public function test_session_regeneration_on_login(): void
    {
        $this->assertSessionFixationProtection();
    }

    /**
     * Test API token generation and usage
     */
    public function test_api_token_generation_and_usage(): void
    {
        // Arrange
        $user = User::factory()->create();

        // Act - Generate token
        $response = $this->actingAs($user)
            ->post('/user/api-tokens', [
                'name' => 'Test Token',
                'abilities' => ['sites:read', 'sites:write'],
            ]);

        $token = $response->json('plainTextToken');

        // Assert - Can use token for API requests
        $apiResponse = $this->withHeader('Authorization', "Bearer {$token}")
            ->get('/api/v1/sites');

        $apiResponse->assertStatus(200);
    }

    /**
     * Test concurrent session handling
     */
    public function test_concurrent_session_management(): void
    {
        // Arrange
        $user = User::factory()->create();

        // Act - Login from two different sessions
        $session1 = $this->post('/login', [
            'email' => $user->email,
            'password' => 'password',
        ]);

        $session2 = $this->post('/login', [
            'email' => $user->email,
            'password' => 'password',
        ]);

        // Both sessions should be valid unless "single session" is enforced
        $this->assertAuthenticatedAs($user);
    }
}
