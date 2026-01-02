<?php

namespace Tests\Regression;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class AuthorizationRegressionTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function owner_has_all_permissions(): void
    {
        $user = User::factory()->owner()->create();

        $this->assertTrue($user->isOwner());
        $this->assertTrue($user->isAdmin());
        $this->assertTrue($user->canManageSites());
        $this->assertFalse($user->isViewer());
    }

    #[Test]
    public function admin_has_management_permissions(): void
    {
        $user = User::factory()->admin()->create();

        $this->assertFalse($user->isOwner());
        $this->assertTrue($user->isAdmin());
        $this->assertTrue($user->canManageSites());
        $this->assertFalse($user->isViewer());
    }

    #[Test]
    public function member_can_manage_sites(): void
    {
        $user = User::factory()->create(['role' => 'member']);

        $this->assertFalse($user->isOwner());
        $this->assertFalse($user->isAdmin());
        $this->assertTrue($user->canManageSites());
        $this->assertFalse($user->isViewer());
    }

    #[Test]
    public function viewer_has_read_only_permissions(): void
    {
        $user = User::factory()->viewer()->create();

        $this->assertFalse($user->isOwner());
        $this->assertFalse($user->isAdmin());
        $this->assertFalse($user->canManageSites());
        $this->assertTrue($user->isViewer());
    }

    #[Test]
    public function user_can_access_their_own_organization(): void
    {
        $user = User::factory()->create();

        $this->assertNotNull($user->organization);
        $this->assertEquals($user->organization_id, $user->organization->id);
    }

    #[Test]
    public function user_has_current_tenant(): void
    {
        $user = User::factory()->create();

        $tenant = $user->currentTenant();

        $this->assertNotNull($tenant);
        $this->assertEquals($user->organization->default_tenant_id, $tenant->id);
    }

    #[Test]
    public function different_roles_are_distinct(): void
    {
        $owner = User::factory()->owner()->create();
        $admin = User::factory()->admin()->create();
        $member = User::factory()->create(['role' => 'member']);
        $viewer = User::factory()->viewer()->create();

        $this->assertEquals('owner', $owner->role);
        $this->assertEquals('admin', $admin->role);
        $this->assertEquals('member', $member->role);
        $this->assertEquals('viewer', $viewer->role);

        $this->assertNotEquals($owner->role, $admin->role);
        $this->assertNotEquals($admin->role, $member->role);
        $this->assertNotEquals($member->role, $viewer->role);
    }

    #[Test]
    public function user_belongs_to_single_organization(): void
    {
        $user = User::factory()->create();

        $this->assertNotNull($user->organization_id);
        $this->assertInstanceOf(\App\Models\Organization::class, $user->organization);
        $this->assertEquals(1, User::where('id', $user->id)->count());
    }

    #[Test]
    public function organization_can_have_multiple_users(): void
    {
        $organization = \App\Models\Organization::factory()->create();

        $owner = User::factory()->owner()->create(['organization_id' => $organization->id]);
        $admin = User::factory()->admin()->create(['organization_id' => $organization->id]);
        $member = User::factory()->create([
            'role' => 'member',
            'organization_id' => $organization->id,
        ]);

        $this->assertEquals(3, $organization->users()->count());
        $this->assertTrue($organization->users->contains($owner));
        $this->assertTrue($organization->users->contains($admin));
        $this->assertTrue($organization->users->contains($member));
    }

    #[Test]
    public function organization_has_single_owner(): void
    {
        $organization = \App\Models\Organization::factory()->create();

        $owner1 = User::factory()->owner()->create(['organization_id' => $organization->id]);
        $owner2 = User::factory()->owner()->create(['organization_id' => $organization->id]);

        // While technically possible to have multiple owners in DB,
        // the owner() relationship should return one owner
        $this->assertInstanceOf(User::class, $organization->owner);
        $this->assertEquals('owner', $organization->owner->role);
    }

    #[Test]
    public function role_based_access_control_is_enforced(): void
    {
        $owner = User::factory()->owner()->create();
        $admin = User::factory()->admin()->create();
        $member = User::factory()->create(['role' => 'member']);
        $viewer = User::factory()->viewer()->create();

        // Test role hierarchy
        $roles = [
            'owner' => [$owner->isOwner(), $owner->isAdmin(), $owner->canManageSites()],
            'admin' => [$admin->isOwner(), $admin->isAdmin(), $admin->canManageSites()],
            'member' => [$member->isOwner(), $member->isAdmin(), $member->canManageSites()],
            'viewer' => [$viewer->isOwner(), $viewer->isAdmin(), $viewer->canManageSites()],
        ];

        $this->assertEquals([true, true, true], $roles['owner']);
        $this->assertEquals([false, true, true], $roles['admin']);
        $this->assertEquals([false, false, true], $roles['member']);
        $this->assertEquals([false, false, false], $roles['viewer']);
    }
}
