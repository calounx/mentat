<?php

namespace Tests\Regression;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class ApiAuthenticationRegressionTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function user_can_register_via_api(): void
    {
        $response = $this->postJson('/api/v1/auth/register', [
            'name' => 'API Test User',
            'email' => 'apitest@example.com',
            'password' => 'password123',
            'password_confirmation' => 'password123',
            'organization_name' => 'API Test Organization',
        ]);

        $response->assertStatus(201);
        $response->assertJsonStructure([
            'user' => ['id', 'name', 'email', 'role'],
            'token',
        ]);

        $this->assertDatabaseHas('users', [
            'email' => 'apitest@example.com',
            'role' => 'owner',
        ]);
    }

    #[Test]
    public function user_can_login_via_api(): void
    {
        $user = User::factory()->create([
            'email' => 'test@example.com',
            'password' => bcrypt('password123'),
        ]);

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => 'test@example.com',
            'password' => 'password123',
        ]);

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'user' => ['id', 'name', 'email'],
            'token',
        ]);
    }

    #[Test]
    public function api_login_fails_with_invalid_credentials(): void
    {
        User::factory()->create([
            'email' => 'test@example.com',
            'password' => bcrypt('password123'),
        ]);

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => 'test@example.com',
            'password' => 'wrongpassword',
        ]);

        $response->assertStatus(401);
        $response->assertJson([
            'message' => 'Invalid credentials',
        ]);
    }

    #[Test]
    public function authenticated_user_can_access_protected_endpoints(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $response = $this->getJson('/api/v1/auth/me');

        $response->assertStatus(200);
        $response->assertJson([
            'id' => $user->id,
            'email' => $user->email,
        ]);
    }

    #[Test]
    public function unauthenticated_user_cannot_access_protected_endpoints(): void
    {
        $response = $this->getJson('/api/v1/auth/me');

        $response->assertStatus(401);
    }

    #[Test]
    public function user_can_logout_via_api(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $response = $this->postJson('/api/v1/auth/logout');

        $response->assertStatus(200);
        $response->assertJson([
            'message' => 'Logged out successfully',
        ]);
    }

    #[Test]
    public function api_token_can_be_created(): void
    {
        $user = User::factory()->create();

        $token = $user->createToken('Test Token');

        $this->assertNotNull($token->plainTextToken);
        $this->assertDatabaseHas('personal_access_tokens', [
            'tokenable_id' => $user->id,
            'name' => 'Test Token',
        ]);
    }

    #[Test]
    public function api_token_can_be_revoked(): void
    {
        $user = User::factory()->create();
        $token = $user->createToken('Test Token');

        Sanctum::actingAs($user);

        // Revoke the token
        $user->tokens()->where('name', 'Test Token')->delete();

        $this->assertDatabaseMissing('personal_access_tokens', [
            'tokenable_id' => $user->id,
            'name' => 'Test Token',
        ]);
    }

    #[Test]
    public function multiple_api_tokens_can_exist_per_user(): void
    {
        $user = User::factory()->create();

        $token1 = $user->createToken('Token 1');
        $token2 = $user->createToken('Token 2');
        $token3 = $user->createToken('Token 3');

        $this->assertEquals(3, $user->tokens()->count());
    }

    #[Test]
    public function api_registration_validates_required_fields(): void
    {
        $response = $this->postJson('/api/v1/auth/register', []);

        $response->assertStatus(422);
        $response->assertJsonValidationErrors([
            'name',
            'email',
            'password',
            'organization_name',
        ]);
    }

    #[Test]
    public function api_registration_prevents_duplicate_email(): void
    {
        User::factory()->create(['email' => 'existing@example.com']);

        $response = $this->postJson('/api/v1/auth/register', [
            'name' => 'New User',
            'email' => 'existing@example.com',
            'password' => 'password123',
            'password_confirmation' => 'password123',
            'organization_name' => 'New Organization',
        ]);

        $response->assertStatus(422);
        $response->assertJsonValidationErrors(['email']);
    }

    #[Test]
    public function api_login_validates_required_fields(): void
    {
        $response = $this->postJson('/api/v1/auth/login', []);

        $response->assertStatus(422);
        $response->assertJsonValidationErrors(['email', 'password']);
    }

    #[Test]
    public function api_token_provides_user_abilities(): void
    {
        $user = User::factory()->create();

        $token = $user->createToken('Test Token', ['sites:read', 'sites:write']);

        Sanctum::actingAs($user, ['sites:read', 'sites:write']);

        $this->assertTrue($user->tokenCan('sites:read'));
        $this->assertTrue($user->tokenCan('sites:write'));
        $this->assertFalse($user->tokenCan('admin:access'));
    }
}
