<?php

namespace Tests\Feature;

use App\Models\Organization;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Password;
use Tests\TestCase;

class PasswordResetTest extends TestCase
{
    use RefreshDatabase;

    protected function createUser(): User
    {
        $organization = Organization::create([
            'name' => 'Test Organization',
            'slug' => 'test-org',
            'billing_email' => 'billing@test.com',
        ]);

        return User::create([
            'name' => 'Test User',
            'email' => 'test@example.com',
            'password' => Hash::make('password123'),
            'organization_id' => $organization->id,
            'role' => 'owner',
        ]);
    }

    public function test_forgot_password_form_renders(): void
    {
        $response = $this->get('/forgot-password');

        $response->assertStatus(200);
        $response->assertSee('Forgot your password?');
        $response->assertSee('Email Password Reset Link');
    }

    public function test_reset_password_link_can_be_requested(): void
    {
        Notification::fake();

        $user = $this->createUser();

        $response = $this->post('/forgot-password', [
            'email' => $user->email,
        ]);

        $response->assertSessionHas('status');
    }

    public function test_forgot_password_rate_limiting(): void
    {
        $user = $this->createUser();

        // Manually set the rate limiter to test the blocking behavior
        $throttleKey = 'password-reset:' . $this->app['request']->ip();

        // Hit the rate limiter 3 times (the maximum)
        for ($i = 0; $i < 3; $i++) {
            \Illuminate\Support\Facades\RateLimiter::hit($throttleKey, 3600);
        }

        // The next request should be rate limited
        $response = $this->post('/forgot-password', ['email' => $user->email]);

        // After 3 attempts, the rate limiter should block
        $response->assertSessionHasErrors(['email']);
        $errors = $response->getSession()->get('errors');
        $this->assertNotNull($errors);
        $this->assertStringContainsString('Too many password reset attempts', $errors->first('email'));
    }

    public function test_reset_password_form_renders_with_token(): void
    {
        $user = $this->createUser();
        $token = Password::createToken($user);

        $response = $this->get("/reset-password/{$token}?email={$user->email}");

        $response->assertStatus(200);
        $response->assertSee('Reset your password');
        $response->assertSee('Reset Password');
    }

    public function test_password_can_be_reset_with_valid_token(): void
    {
        $user = $this->createUser();
        $token = Password::createToken($user);

        $response = $this->post('/reset-password', [
            'token' => $token,
            'email' => $user->email,
            'password' => 'NewPassword123',
            'password_confirmation' => 'NewPassword123',
        ]);

        $response->assertRedirect('/login');
        $response->assertSessionHas('status');

        // Verify the password was changed
        $this->assertTrue(Hash::check('NewPassword123', $user->fresh()->password));
    }

    public function test_password_reset_requires_valid_token(): void
    {
        $user = $this->createUser();

        $response = $this->post('/reset-password', [
            'token' => 'invalid-token',
            'email' => $user->email,
            'password' => 'NewPassword123',
            'password_confirmation' => 'NewPassword123',
        ]);

        $response->assertSessionHasErrors(['email']);
    }

    public function test_password_reset_requires_password_confirmation(): void
    {
        $user = $this->createUser();
        $token = Password::createToken($user);

        $response = $this->post('/reset-password', [
            'token' => $token,
            'email' => $user->email,
            'password' => 'NewPassword123',
            'password_confirmation' => 'DifferentPassword123',
        ]);

        $response->assertSessionHasErrors(['password']);
    }

    public function test_password_reset_enforces_password_rules(): void
    {
        $user = $this->createUser();
        $token = Password::createToken($user);

        // Test too short
        $response = $this->post('/reset-password', [
            'token' => $token,
            'email' => $user->email,
            'password' => 'short',
            'password_confirmation' => 'short',
        ]);
        $response->assertSessionHasErrors(['password']);

        // Test no uppercase
        $token = Password::createToken($user); // Recreate token
        $response = $this->post('/reset-password', [
            'token' => $token,
            'email' => $user->email,
            'password' => 'lowercase123',
            'password_confirmation' => 'lowercase123',
        ]);
        $response->assertSessionHasErrors(['password']);

        // Test no numbers
        $token = Password::createToken($user); // Recreate token
        $response = $this->post('/reset-password', [
            'token' => $token,
            'email' => $user->email,
            'password' => 'NoNumbers',
            'password_confirmation' => 'NoNumbers',
        ]);
        $response->assertSessionHasErrors(['password']);
    }

    public function test_password_reset_clears_must_reset_password_flag(): void
    {
        $user = $this->createUser();
        $user->update(['must_reset_password' => true]);

        $token = Password::createToken($user);

        $this->post('/reset-password', [
            'token' => $token,
            'email' => $user->email,
            'password' => 'NewPassword123',
            'password_confirmation' => 'NewPassword123',
        ]);

        $this->assertFalse($user->fresh()->must_reset_password);
    }

    public function test_login_page_has_forgot_password_link(): void
    {
        $response = $this->get('/login');

        $response->assertStatus(200);
        $response->assertSee('Forgot password?');
        $response->assertSee(route('password.request'));
    }
}
