<?php

declare(strict_types=1);

namespace Tests\Security;

use App\Models\Backup;
use App\Models\Site;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\WithSecurityTesting;
use Tests\TestCase;

/**
 * Test authorization security and policy enforcement
 *
 * Tests policy bypass attempts, privilege escalation, and authorization
 * enforcement across all protected resources.
 *
 * @package Tests\Security
 */
class AuthorizationSecurityTest extends TestCase
{
    use RefreshDatabase;
    use WithSecurityTesting;

    protected User $user;
    protected User $admin;
    protected User $otherUser;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create(['role' => 'user']);
        $this->admin = User::factory()->create(['role' => 'admin']);
        $this->otherUser = User::factory()->create(['role' => 'user']);
    }

    /**
     * Test users cannot access other users' sites
     *
     * @return void
     */
    public function test_users_cannot_access_other_users_sites(): void
    {
        $otherSite = Site::factory()->create(['user_id' => $this->otherUser->id]);

        $endpoints = [
            ['GET', "/api/v1/sites/{$otherSite->id}"],
            ['PUT', "/api/v1/sites/{$otherSite->id}", ['domain' => 'hacked.com']],
            ['DELETE', "/api/v1/sites/{$otherSite->id}"],
        ];

        foreach ($endpoints as [$method, $uri, $data = []]) {
            $response = $this->actingAs($this->user)->call($method, $uri, $data);

            $this->assertEquals(403, $response->status(), "Failed authorization check for {$method} {$uri}");
        }
    }

    /**
     * Test privilege escalation attempts
     *
     * @return void
     */
    public function test_cannot_escalate_privileges_via_mass_assignment(): void
    {
        // Attempt to set admin role via mass assignment
        $response = $this->actingAs($this->user)
            ->put("/api/v1/users/{$this->user->id}", [
                'role' => 'admin',
                'is_super_admin' => true,
            ]);

        // Role should not change
        $this->user->refresh();
        $this->assertEquals('user', $this->user->role);
        $this->assertFalse($this->user->is_super_admin ?? false);
    }

    /**
     * Test IDOR (Insecure Direct Object Reference) protection
     *
     * @return void
     */
    public function test_idor_protection_on_all_resources(): void
    {
        $otherSite = Site::factory()->create(['user_id' => $this->otherUser->id]);
        $otherBackup = Backup::factory()->create(['site_id' => $otherSite->id]);

        $this->assertIDORProtection($this->user, $otherSite->id, "/api/v1/sites/{$otherSite->id}");
        $this->assertIDORProtection($this->user, $otherBackup->id, "/api/v1/backups/{$otherBackup->id}");
    }

    /**
     * Test parameter tampering protection
     *
     * @return void
     */
    public function test_parameter_tampering_protection(): void
    {
        $site = Site::factory()->create(['user_id' => $this->user->id]);

        // Attempt to change ownership via parameter tampering
        $response = $this->actingAs($this->user)
            ->put("/api/v1/sites/{$site->id}", [
                'user_id' => $this->otherUser->id,
                'domain' => 'tampered.com',
            ]);

        // Ownership should not change
        $site->refresh();
        $this->assertEquals($this->user->id, $site->user_id);
    }

    /**
     * Test horizontal privilege escalation prevention
     *
     * @return void
     */
    public function test_horizontal_privilege_escalation_prevention(): void
    {
        $user1Site = Site::factory()->create(['user_id' => $this->user->id]);
        $user2Site = Site::factory()->create(['user_id' => $this->otherUser->id]);

        // User 1 tries to modify User 2's site
        $response = $this->actingAs($this->user)
            ->put("/api/v1/sites/{$user2Site->id}", [
                'domain' => 'hacked.com',
            ]);

        $response->assertStatus(403);

        // Site should remain unchanged
        $user2Site->refresh();
        $this->assertNotEquals('hacked.com', $user2Site->domain);
    }

    /**
     * Test vertical privilege escalation prevention
     *
     * @return void
     */
    public function test_vertical_privilege_escalation_prevention(): void
    {
        // Regular user tries to access admin-only endpoints
        $adminEndpoints = [
            ['GET', '/api/v1/admin/users'],
            ['POST', '/api/v1/admin/users/suspend'],
            ['GET', '/api/v1/admin/system/settings'],
        ];

        foreach ($adminEndpoints as [$method, $uri]) {
            $response = $this->actingAs($this->user)->call($method, $uri);

            $this->assertEquals(403, $response->status(), "Regular user accessed admin endpoint: {$uri}");
        }
    }

    /**
     * Test admin can access authorized resources
     *
     * @return void
     */
    public function test_admin_has_appropriate_access(): void
    {
        $anySite = Site::factory()->create(['user_id' => $this->user->id]);

        $response = $this->actingAs($this->admin)
            ->get("/api/v1/admin/sites/{$anySite->id}");

        $response->assertStatus(200);
    }

    /**
     * Test authorization checks cannot be bypassed via headers
     *
     * @return void
     */
    public function test_authorization_not_bypassable_via_headers(): void
    {
        $otherSite = Site::factory()->create(['user_id' => $this->otherUser->id]);

        $headers = [
            ['X-User-ID', $this->otherUser->id],
            ['X-Original-User', $this->admin->id],
            ['X-Forwarded-User', $this->admin->id],
            ['X-Auth-User-ID', $this->admin->id],
        ];

        foreach ($headers as [$header, $value]) {
            $response = $this->actingAs($this->user)
                ->withHeader($header, $value)
                ->get("/api/v1/sites/{$otherSite->id}");

            $this->assertEquals(403, $response->status(), "Authorization bypassed via {$header} header");
        }
    }

    /**
     * Test forced browsing protection
     *
     * @return void
     */
    public function test_forced_browsing_protection(): void
    {
        // Test sequential ID guessing
        $site1 = Site::factory()->create(['user_id' => $this->otherUser->id]);

        for ($id = $site1->id - 5; $id <= $site1->id + 5; $id++) {
            $response = $this->actingAs($this->user)
                ->get("/api/v1/sites/{$id}");

            // Should only succeed if it's user's own site
            if ($id !== $site1->id) {
                $this->assertTrue(
                    in_array($response->status(), [403, 404]),
                    "Forced browsing allowed access to site ID: {$id}"
                );
            }
        }
    }

    /**
     * Test missing function level access control
     *
     * @return void
     */
    public function test_function_level_access_control(): void
    {
        $site = Site::factory()->create(['user_id' => $this->user->id]);

        // These operations should require specific permissions
        $sensitiveOperations = [
            ['POST', "/api/v1/sites/{$site->id}/restart"],
            ['POST', "/api/v1/sites/{$site->id}/shell"],
            ['DELETE', "/api/v1/sites/{$site->id}/force-delete"],
        ];

        foreach ($sensitiveOperations as [$method, $uri]) {
            $response = $this->actingAs($this->user)->call($method, $uri);

            // Should require elevated permissions even for own site
            $this->assertTrue(
                in_array($response->status(), [403, 404]),
                "Sensitive operation allowed without proper authorization: {$uri}"
            );
        }
    }
}
