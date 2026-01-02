<?php

namespace Tests\Browser;

use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseMigrations;
use Laravel\Dusk\Browser;
use Tests\DuskTestCase;

/**
 * E2E Test Suite: Authentication Flow
 *
 * Covers complete user authentication workflows including:
 * - Registration with organization creation
 * - Login with email/password
 * - Two-factor authentication setup and login
 * - Password reset flow
 * - Logout
 */
class AuthenticationFlowTest extends DuskTestCase
{
    use DatabaseMigrations;

    /**
     * Test 1: Complete registration with organization creation.
     *
     * @test
     */
    public function user_can_register_and_create_organization(): void
    {
        $this->browse(function (Browser $browser) {
            $browser->visit('/register')
                ->assertSee('Create Account')
                ->type('name', 'John Doe')
                ->type('email', 'john@example.com')
                ->type('password', 'SecurePassword123!')
                ->type('password_confirmation', 'SecurePassword123!')
                ->type('organization_name', 'Acme Corporation')
                ->press('Register')
                ->waitForLocation('/email/verify', 15)
                ->assertPathIs('/email/verify')
                ->assertSee('Verify Email');

            // Verify user was created in database
            $this->assertDatabaseHas('users', [
                'name' => 'John Doe',
                'email' => 'john@example.com',
                'role' => 'owner',
            ]);

            // Verify organization was created
            $this->assertDatabaseHas('organizations', [
                'name' => 'Acme Corporation',
            ]);

            // Verify user is linked to organization
            $user = User::where('email', 'john@example.com')->first();
            $this->assertNotNull($user->organization_id);
            $this->assertEquals('Acme Corporation', $user->organization->name);

            // Verify default tenant was created
            $this->assertNotNull($user->organization->default_tenant_id);
            $this->assertDatabaseHas('tenants', [
                'organization_id' => $user->organization_id,
                'name' => 'Default',
                'tier' => 'starter',
            ]);
        });
    }

    /**
     * Test 2: Login with email and password.
     *
     * @test
     */
    public function user_can_login_with_credentials(): void
    {
        $user = $this->createUser([
            'email' => 'test@example.com',
            'password' => bcrypt('password123'),
        ]);

        $this->browse(function (Browser $browser) use ($user) {
            $browser->visit('/login')
                ->assertSee('Login')
                ->type('email', 'test@example.com')
                ->type('password', 'password123')
                ->press('Log in')
                ->waitForLocation('/dashboard', 15)
                ->assertPathIs('/dashboard')
                ->assertSee('Dashboard')
                ->assertAuthenticatedAs($user);
        });
    }

    /**
     * Test 3: Enable 2FA and login with 2FA code.
     *
     * @test
     */
    public function user_can_enable_2fa_and_login_with_code(): void
    {
        $user = $this->createUser([
            'email' => '2fa@example.com',
            'password' => bcrypt('password123'),
        ]);

        $this->browse(function (Browser $browser) use ($user) {
            // Step 1: Login as user
            $this->loginAs($browser, $user, 'password123');

            // Step 2: Enable 2FA via API endpoint (simulating the process)
            $response = $user->enableTwoFactorAuthentication();
            $secret = $response['secret'];

            // Generate a valid TOTP code
            $google2fa = new \PragmaRX\Google2FA\Google2FA();
            $validCode = $google2fa->getCurrentOtp($secret);

            // Step 3: Confirm 2FA setup
            $user->update(['two_factor_secret' => $secret]);
            $user->confirmTwoFactorAuthentication();

            // Step 4: Logout
            $browser->visit('/logout')
                ->press('Logout')
                ->waitForLocation('/', 10);

            // Step 5: Login again (should require 2FA)
            $browser->visit('/login')
                ->type('email', '2fa@example.com')
                ->type('password', 'password123')
                ->press('Log in')
                ->waitFor('input[name="two_factor_code"]', 10)
                ->assertSee('Two-Factor Authentication')
                ->type('two_factor_code', $validCode)
                ->press('Verify')
                ->waitForLocation('/dashboard', 15)
                ->assertPathIs('/dashboard')
                ->assertAuthenticatedAs($user);
        });
    }

    /**
     * Test 4: Password reset flow.
     *
     * @test
     */
    public function user_can_reset_password(): void
    {
        $user = $this->createUser([
            'email' => 'reset@example.com',
        ]);

        $this->browse(function (Browser $browser) use ($user) {
            // Step 1: Request password reset
            $browser->visit('/login')
                ->clickLink('Forgot password?')
                ->waitForLocation('/forgot-password', 10)
                ->assertSee('Reset Password')
                ->type('email', 'reset@example.com')
                ->press('Send Reset Link')
                ->waitFor('.alert-success', 10)
                ->assertSee('reset link has been sent');

            // Verify password reset token was created
            $this->assertDatabaseHas('password_reset_tokens', [
                'email' => 'reset@example.com',
            ]);

            // Step 2: Simulate clicking reset link and setting new password
            $token = \Illuminate\Support\Facades\DB::table('password_reset_tokens')
                ->where('email', 'reset@example.com')
                ->value('token');

            $browser->visit("/reset-password/{$token}?email=reset@example.com")
                ->assertSee('Reset Password')
                ->type('email', 'reset@example.com')
                ->type('password', 'NewPassword123!')
                ->type('password_confirmation', 'NewPassword123!')
                ->press('Reset Password')
                ->waitForLocation('/login', 15)
                ->assertPathIs('/login')
                ->assertSee('password has been reset');

            // Step 3: Login with new password
            $browser->type('email', 'reset@example.com')
                ->type('password', 'NewPassword123!')
                ->press('Log in')
                ->waitForLocation('/dashboard', 15)
                ->assertPathIs('/dashboard')
                ->assertAuthenticatedAs($user);
        });
    }

    /**
     * Test 5: Logout.
     *
     * @test
     */
    public function user_can_logout(): void
    {
        $user = $this->createUser([
            'email' => 'logout@example.com',
        ]);

        $this->browse(function (Browser $browser) use ($user) {
            // Step 1: Login
            $this->loginAs($browser, $user);

            // Step 2: Verify logged in
            $browser->assertPathIs('/dashboard')
                ->assertAuthenticatedAs($user);

            // Step 3: Logout
            $browser->press('Logout')
                ->waitForLocation('/', 15)
                ->assertPathIs('/')
                ->assertGuest();

            // Step 4: Verify cannot access protected routes
            $browser->visit('/dashboard')
                ->waitForLocation('/login', 10)
                ->assertPathIs('/login')
                ->assertSee('Login');
        });
    }

    /**
     * Test: Failed login with invalid credentials.
     *
     * @test
     */
    public function login_fails_with_invalid_credentials(): void
    {
        $this->browse(function (Browser $browser) {
            $browser->visit('/login')
                ->type('email', 'nonexistent@example.com')
                ->type('password', 'wrongpassword')
                ->press('Log in')
                ->waitFor('.alert-error', 10)
                ->assertSee('credentials do not match')
                ->assertPathIs('/login')
                ->assertGuest();
        });
    }

    /**
     * Test: Registration validation errors.
     *
     * @test
     */
    public function registration_shows_validation_errors(): void
    {
        $this->browse(function (Browser $browser) {
            $browser->visit('/register')
                ->type('name', 'Test')
                ->type('email', 'invalid-email')
                ->type('password', 'short')
                ->type('password_confirmation', 'different')
                ->press('Register')
                ->waitFor('.error', 5)
                ->assertSee('valid email address')
                ->assertSee('at least 8 characters')
                ->assertPathIs('/register');
        });
    }
}
