<?php

declare(strict_types=1);

namespace Tests\Security;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\WithSecurityTesting;
use Tests\TestCase;

/**
 * Test session security features
 *
 * @package Tests\Security
 */
class SessionSecurityTest extends TestCase
{
    use RefreshDatabase;
    use WithSecurityTesting;

    /**
     * Test session regeneration on login
     *
     * @return void
     */
    public function test_session_id_regenerates_on_login(): void
    {
        $this->assertSessionFixationProtection();
    }

    /**
     * Test session has secure attributes
     *
     * @return void
     */
    public function test_session_cookies_have_secure_attributes(): void
    {
        $user = User::factory()->create();

        $response = $this->post('/login', [
            'email' => $user->email,
            'password' => 'password',
        ]);

        $cookies = $response->headers->getCookies();
        $sessionCookie = collect($cookies)->first(
            fn($cookie) => str_contains($cookie->getName(), 'session')
        );

        if ($sessionCookie) {
            $this->assertTrue($sessionCookie->isHttpOnly());
            $this->assertTrue($sessionCookie->isSecure() || !config('app.env') === 'production');
            $this->assertEquals('lax', strtolower($sessionCookie->getSameSite()));
        }
    }

    /**
     * Test session timeout is enforced
     *
     * @return void
     */
    public function test_session_timeout_enforced(): void
    {
        $user = User::factory()->create();
        $this->actingAs($user);

        // Simulate session expiry
        session()->put('last_activity', now()->subHours(3)->timestamp);

        $response = $this->get('/dashboard');

        $response->assertRedirect('/login');
    }

    /**
     * Test concurrent session handling
     *
     * @return void
     */
    public function test_detects_concurrent_sessions(): void
    {
        $user = User::factory()->create();

        // First login
        $this->post('/login', [
            'email' => $user->email,
            'password' => 'password',
        ]);

        $firstSessionId = session()->getId();

        // Second login from different location
        $this->post('/login', [
            'email' => $user->email,
            'password' => 'password',
        ]);

        $secondSessionId = session()->getId();

        // Sessions should be different
        $this->assertNotEquals($firstSessionId, $secondSessionId);
    }
}
