<?php

namespace Tests\Regression;

use App\Models\Organization;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class AuthenticationRegressionTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
    }

    #[Test]
    public function user_can_register_with_new_organization(): void
    {
        $response = $this->post('/register', [
            'name' => 'Test User',
            'email' => 'test@example.com',
            'password' => 'password123',
            'password_confirmation' => 'password123',
            'organization_name' => 'Test Organization',
        ]);

        $response->assertRedirect(route('verification.notice'));
        $this->assertDatabaseHas('users', [
            'email' => 'test@example.com',
            'name' => 'Test User',
            'role' => 'owner',
        ]);
        $this->assertDatabaseHas('organizations', [
            'name' => 'Test Organization',
        ]);

        $user = User::where('email', 'test@example.com')->first();
        $this->assertNotNull($user->organization);
        $this->assertEquals('owner', $user->role);
    }

    #[Test]
    public function registration_creates_default_tenant(): void
    {
        $this->post('/register', [
            'name' => 'Test User',
            'email' => 'test@example.com',
            'password' => 'password123',
            'password_confirmation' => 'password123',
            'organization_name' => 'Test Organization',
        ]);

        $user = User::where('email', 'test@example.com')->first();
        $organization = $user->organization;

        $this->assertNotNull($organization->defaultTenant);
        $this->assertEquals('Default', $organization->defaultTenant->name);
        $this->assertEquals('starter', $organization->defaultTenant->tier);
        $this->assertEquals('active', $organization->defaultTenant->status);
    }

    #[Test]
    public function registration_requires_all_fields(): void
    {
        $response = $this->post('/register', []);

        $response->assertSessionHasErrors(['name', 'email', 'password', 'organization_name']);
        $this->assertEquals(0, User::count());
    }

    #[Test]
    public function registration_prevents_duplicate_email(): void
    {
        User::factory()->create(['email' => 'existing@example.com']);

        $response = $this->post('/register', [
            'name' => 'Test User',
            'email' => 'existing@example.com',
            'password' => 'password123',
            'password_confirmation' => 'password123',
            'organization_name' => 'Test Organization',
        ]);

        $response->assertSessionHasErrors(['email']);
        $this->assertEquals(1, User::count());
    }

    #[Test]
    public function user_can_login_with_valid_credentials(): void
    {
        $user = User::factory()->create([
            'email' => 'test@example.com',
            'password' => Hash::make('password123'),
        ]);

        $response = $this->post('/login', [
            'email' => 'test@example.com',
            'password' => 'password123',
        ]);

        $response->assertRedirect(route('dashboard'));
        $this->assertAuthenticatedAs($user);
    }

    #[Test]
    public function user_cannot_login_with_invalid_password(): void
    {
        User::factory()->create([
            'email' => 'test@example.com',
            'password' => Hash::make('password123'),
        ]);

        $response = $this->post('/login', [
            'email' => 'test@example.com',
            'password' => 'wrongpassword',
        ]);

        $response->assertSessionHasErrors(['email']);
        $this->assertGuest();
    }

    #[Test]
    public function user_cannot_login_with_nonexistent_email(): void
    {
        $response = $this->post('/login', [
            'email' => 'nonexistent@example.com',
            'password' => 'password123',
        ]);

        $response->assertSessionHasErrors(['email']);
        $this->assertGuest();
    }

    #[Test]
    public function remember_me_functionality_works(): void
    {
        $user = User::factory()->create([
            'email' => 'test@example.com',
            'password' => Hash::make('password123'),
        ]);

        $response = $this->post('/login', [
            'email' => 'test@example.com',
            'password' => 'password123',
            'remember' => true,
        ]);

        $response->assertRedirect(route('dashboard'));
        $this->assertAuthenticatedAs($user);

        // Check that remember token was set
        $user->refresh();
        $this->assertNotNull($user->remember_token);
    }

    #[Test]
    public function user_can_logout(): void
    {
        $user = User::factory()->create();

        $response = $this->actingAs($user)->post('/logout');

        $response->assertRedirect('/');
        $this->assertGuest();
    }

    #[Test]
    public function unauthenticated_user_cannot_access_dashboard(): void
    {
        $response = $this->get(route('dashboard'));

        $response->assertRedirect(route('login'));
    }

    #[Test]
    public function authenticated_user_redirects_from_login_page(): void
    {
        $user = User::factory()->create();

        $response = $this->actingAs($user)->get(route('login'));

        $response->assertRedirect(route('dashboard'));
    }

    #[Test]
    public function session_regenerates_on_login(): void
    {
        $user = User::factory()->create([
            'email' => 'test@example.com',
            'password' => Hash::make('password123'),
        ]);

        $oldSessionId = session()->getId();

        $this->post('/login', [
            'email' => 'test@example.com',
            'password' => 'password123',
        ]);

        $newSessionId = session()->getId();

        // Session ID should change after login for security
        $this->assertNotEquals($oldSessionId, $newSessionId);
    }

    #[Test]
    public function login_requires_email_and_password(): void
    {
        $response = $this->post('/login', []);

        $response->assertSessionHasErrors(['email', 'password']);
    }

    #[Test]
    public function email_must_be_valid_format(): void
    {
        $response = $this->post('/login', [
            'email' => 'invalid-email',
            'password' => 'password123',
        ]);

        $response->assertSessionHasErrors(['email']);
    }

    #[Test]
    public function new_users_require_email_verification(): void
    {
        $this->post('/register', [
            'name' => 'Test User',
            'email' => 'test@example.com',
            'password' => 'password123',
            'password_confirmation' => 'password123',
            'organization_name' => 'Test Organization',
        ]);

        $user = User::where('email', 'test@example.com')->first();

        $this->assertNull($user->email_verified_at);
    }

    #[Test]
    public function user_can_verify_email_with_valid_link(): void
    {
        $user = User::factory()->unverified()->create([
            'email' => 'test@example.com',
        ]);

        $hash = sha1($user->email);

        $response = $this->actingAs($user)->get("/email/verify/{$user->id}/{$hash}");

        $response->assertRedirect(route('dashboard'));

        $user->refresh();
        $this->assertNotNull($user->email_verified_at);
    }

    #[Test]
    public function email_verification_fails_with_invalid_hash(): void
    {
        $user = User::factory()->unverified()->create([
            'email' => 'test@example.com',
        ]);

        $invalidHash = 'invalidhash123';

        $response = $this->actingAs($user)->get("/email/verify/{$user->id}/{$invalidHash}");

        $response->assertForbidden();

        $user->refresh();
        $this->assertNull($user->email_verified_at);
    }

    #[Test]
    public function already_verified_user_redirects_to_dashboard(): void
    {
        $user = User::factory()->create([
            'email' => 'test@example.com',
            'email_verified_at' => now(),
        ]);

        $hash = sha1($user->email);

        $response = $this->actingAs($user)->get("/email/verify/{$user->id}/{$hash}");

        $response->assertRedirect(route('dashboard'));
    }
}
