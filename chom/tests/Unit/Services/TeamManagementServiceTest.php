<?php

namespace Tests\Unit\Services;

use App\Events\MemberInvited;
use App\Events\MemberJoined;
use App\Events\MemberRemoved;
use App\Events\MemberRoleUpdated;
use App\Events\OwnershipTransferred;
use App\Mail\TeamInvitationMail;
use App\Models\TeamInvitation;
use App\Models\User;
use App\Repositories\UserRepository;
use App\Services\TeamManagementService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Mail;
use Illuminate\Validation\ValidationException;
use Mockery;
use Tests\TestCase;

class TeamManagementServiceTest extends TestCase
{
    use RefreshDatabase;

    private TeamManagementService $service;
    private $userRepo;

    protected function setUp(): void
    {
        parent::setUp();

        $this->userRepo = Mockery::mock(UserRepository::class);

        $this->service = new TeamManagementService($this->userRepo);

        Event::fake();
        Mail::fake();
    }

    protected function tearDown(): void
    {
        Mockery::close();
        parent::tearDown();
    }

    public function test_it_invites_member_successfully()
    {
        $this->userRepo->shouldReceive('findByEmailAndOrganization')
            ->once()
            ->with('newmember@example.com', 'org-123')
            ->andReturn(null);

        $this->actingAs(User::factory()->make(['id' => 'user-123']));

        $invitation = $this->service->inviteMember(
            'org-123',
            'newmember@example.com',
            'member',
            []
        );

        $this->assertInstanceOf(TeamInvitation::class, $invitation);
        $this->assertEquals('newmember@example.com', $invitation->email);
        $this->assertEquals('member', $invitation->role);
        $this->assertNotNull($invitation->token);

        Mail::assertSent(TeamInvitationMail::class);
        Event::assertDispatched(MemberInvited::class);
    }

    public function test_it_throws_exception_when_user_already_exists_in_organization()
    {
        $existingUser = User::factory()->make();

        $this->userRepo->shouldReceive('findByEmailAndOrganization')
            ->once()
            ->andReturn($existingUser);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('User already exists in this organization');

        $this->service->inviteMember('org-123', 'existing@example.com', 'member');
    }

    public function test_it_throws_exception_when_pending_invitation_exists()
    {
        $this->userRepo->shouldReceive('findByEmailAndOrganization')
            ->once()
            ->andReturn(null);

        TeamInvitation::factory()->create([
            'organization_id' => 'org-123',
            'email' => 'pending@example.com',
            'expires_at' => now()->addDays(5),
            'accepted_at' => null,
        ]);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('A pending invitation already exists');

        $this->service->inviteMember('org-123', 'pending@example.com', 'member');
    }

    public function test_it_validates_email_format()
    {
        $this->expectException(ValidationException::class);

        $this->service->inviteMember('org-123', 'invalid-email', 'member');
    }

    public function test_it_validates_role()
    {
        $this->expectException(ValidationException::class);

        $this->service->inviteMember('org-123', 'test@example.com', 'invalid_role');
    }

    public function test_it_accepts_invitation_successfully()
    {
        $invitation = TeamInvitation::factory()->create([
            'token' => 'valid-token',
            'email' => 'invitee@example.com',
            'organization_id' => 'org-123',
            'role' => 'member',
            'expires_at' => now()->addDays(5),
            'accepted_at' => null,
        ]);

        $user = User::factory()->create([
            'id' => 'user-123',
            'email' => 'invitee@example.com',
        ]);

        $this->userRepo->shouldReceive('findById')
            ->once()
            ->with('user-123')
            ->andReturn($user);

        $this->userRepo->shouldReceive('update')
            ->once()
            ->andReturn($user);

        $result = $this->service->acceptInvitation('valid-token', 'user-123');

        $this->assertTrue($result);
        $this->assertNotNull($invitation->fresh()->accepted_at);
        Event::assertDispatched(MemberJoined::class);
    }

    public function test_it_throws_exception_for_invalid_invitation_token()
    {
        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Invalid or already accepted invitation');

        $this->service->acceptInvitation('invalid-token', 'user-123');
    }

    public function test_it_throws_exception_for_expired_invitation()
    {
        TeamInvitation::factory()->create([
            'token' => 'expired-token',
            'expires_at' => now()->subDay(),
            'accepted_at' => null,
        ]);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Invitation has expired');

        $this->service->acceptInvitation('expired-token', 'user-123');
    }

    public function test_it_throws_exception_when_email_does_not_match()
    {
        TeamInvitation::factory()->create([
            'token' => 'valid-token',
            'email' => 'invitee@example.com',
            'expires_at' => now()->addDays(5),
            'accepted_at' => null,
        ]);

        $user = User::factory()->create([
            'email' => 'different@example.com',
        ]);

        $this->userRepo->shouldReceive('findById')
            ->once()
            ->andReturn($user);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Email does not match invitation');

        $this->service->acceptInvitation('valid-token', 'user-123');
    }

    public function test_it_cancels_invitation_successfully()
    {
        $invitation = TeamInvitation::factory()->create([
            'accepted_at' => null,
        ]);

        $result = $this->service->cancelInvitation($invitation->id);

        $this->assertTrue($result);
        $this->assertDatabaseMissing('team_invitations', ['id' => $invitation->id]);
    }

    public function test_it_throws_exception_when_canceling_accepted_invitation()
    {
        $invitation = TeamInvitation::factory()->create([
            'accepted_at' => now(),
        ]);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Cannot cancel an accepted invitation');

        $this->service->cancelInvitation($invitation->id);
    }

    public function test_it_updates_member_role_successfully()
    {
        $currentUser = User::factory()->make([
            'id' => 'admin-123',
            'role' => 'owner',
        ]);

        $member = User::factory()->make([
            'id' => 'member-123',
            'role' => 'member',
            'organization_id' => 'org-123',
        ]);

        $this->actingAs($currentUser);

        $this->userRepo->shouldReceive('findById')
            ->once()
            ->with('member-123')
            ->andReturn($member);

        $this->userRepo->shouldReceive('update')
            ->once()
            ->with('member-123', ['role' => 'admin'])
            ->andReturn($member);

        $result = $this->service->updateMemberRole('member-123', 'admin');

        $this->assertInstanceOf(User::class, $result);
        Event::assertDispatched(MemberRoleUpdated::class);
    }

    public function test_it_prevents_self_role_change()
    {
        $user = User::factory()->make([
            'id' => 'user-123',
            'role' => 'admin',
        ]);

        $this->actingAs($user);

        $this->userRepo->shouldReceive('findById')
            ->once()
            ->andReturn($user);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Cannot change your own role');

        $this->service->updateMemberRole('user-123', 'member');
    }

    public function test_it_prevents_promoting_to_higher_role_than_self()
    {
        $currentUser = User::factory()->make([
            'id' => 'admin-123',
            'role' => 'admin',
        ]);

        $member = User::factory()->make([
            'id' => 'member-123',
            'role' => 'member',
        ]);

        $this->actingAs($currentUser);

        $this->userRepo->shouldReceive('findById')
            ->once()
            ->andReturn($member);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Cannot assign a role equal to or higher than your own');

        $this->service->updateMemberRole('member-123', 'owner');
    }

    public function test_it_prevents_changing_last_owner_role()
    {
        $currentUser = User::factory()->make([
            'id' => 'owner-123',
            'role' => 'owner',
            'organization_id' => 'org-123',
        ]);

        $lastOwner = User::factory()->make([
            'id' => 'owner-456',
            'role' => 'owner',
            'organization_id' => 'org-123',
        ]);

        $this->actingAs($currentUser);

        $this->userRepo->shouldReceive('findById')
            ->once()
            ->andReturn($lastOwner);

        $this->userRepo->shouldReceive('countByRole')
            ->once()
            ->with('org-123', 'owner')
            ->andReturn(1);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Cannot change role of the last owner');

        $this->service->updateMemberRole('owner-456', 'admin');
    }

    public function test_it_removes_member_successfully()
    {
        $currentUser = User::factory()->make([
            'id' => 'admin-123',
            'role' => 'admin',
        ]);

        $member = User::factory()->make([
            'id' => 'member-123',
            'role' => 'member',
            'organization_id' => 'org-123',
        ]);

        $this->actingAs($currentUser);

        $this->userRepo->shouldReceive('findById')
            ->once()
            ->andReturn($member);

        $this->userRepo->shouldReceive('update')
            ->once()
            ->with('member-123', [
                'organization_id' => null,
                'role' => 'member',
            ])
            ->andReturn($member);

        $result = $this->service->removeMember('member-123', 'org-123');

        $this->assertTrue($result);
        Event::assertDispatched(MemberRemoved::class);
    }

    public function test_it_prevents_self_removal()
    {
        $user = User::factory()->make([
            'id' => 'user-123',
            'organization_id' => 'org-123',
        ]);

        $this->actingAs($user);

        $this->userRepo->shouldReceive('findById')
            ->once()
            ->andReturn($user);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Cannot remove yourself');

        $this->service->removeMember('user-123', 'org-123');
    }

    public function test_it_prevents_removing_last_owner()
    {
        $currentUser = User::factory()->make([
            'id' => 'admin-123',
            'role' => 'admin',
        ]);

        $owner = User::factory()->make([
            'id' => 'owner-123',
            'role' => 'owner',
            'organization_id' => 'org-123',
        ]);

        $owner->shouldReceive('isOwner')->andReturn(true);

        $this->actingAs($currentUser);

        $this->userRepo->shouldReceive('findById')
            ->once()
            ->andReturn($owner);

        $this->userRepo->shouldReceive('countByRole')
            ->once()
            ->with('org-123', 'owner')
            ->andReturn(1);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Cannot remove the last owner');

        $this->service->removeMember('owner-123', 'org-123');
    }

    public function test_it_transfers_ownership_successfully()
    {
        $currentOwner = User::factory()->make([
            'id' => 'owner-123',
            'role' => 'owner',
            'organization_id' => 'org-123',
        ]);

        $currentOwner->shouldReceive('isOwner')->andReturn(true);

        $newOwner = User::factory()->make([
            'id' => 'member-123',
            'role' => 'admin',
            'organization_id' => 'org-123',
        ]);

        $this->userRepo->shouldReceive('findById')
            ->with('owner-123')
            ->once()
            ->andReturn($currentOwner);

        $this->userRepo->shouldReceive('findById')
            ->with('member-123')
            ->once()
            ->andReturn($newOwner);

        $this->userRepo->shouldReceive('update')
            ->with('owner-123', ['role' => 'admin'])
            ->once()
            ->andReturn($currentOwner);

        $this->userRepo->shouldReceive('update')
            ->with('member-123', ['role' => 'owner'])
            ->once()
            ->andReturn($newOwner);

        $result = $this->service->transferOwnership('org-123', 'member-123', 'owner-123');

        $this->assertTrue($result);
        Event::assertDispatched(OwnershipTransferred::class);
    }

    public function test_it_throws_exception_when_current_owner_invalid()
    {
        $nonOwner = User::factory()->make([
            'role' => 'admin',
        ]);

        $nonOwner->shouldReceive('isOwner')->andReturn(false);

        $this->userRepo->shouldReceive('findById')
            ->once()
            ->andReturn($nonOwner);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('Current owner not found or invalid');

        $this->service->transferOwnership('org-123', 'new-owner', 'current-owner');
    }

    public function test_it_throws_exception_when_new_owner_not_in_organization()
    {
        $currentOwner = User::factory()->make([
            'id' => 'owner-123',
            'role' => 'owner',
            'organization_id' => 'org-123',
        ]);

        $currentOwner->shouldReceive('isOwner')->andReturn(true);

        $outsider = User::factory()->make([
            'id' => 'outsider-123',
            'organization_id' => 'org-456',
        ]);

        $this->userRepo->shouldReceive('findById')
            ->with('owner-123')
            ->once()
            ->andReturn($currentOwner);

        $this->userRepo->shouldReceive('findById')
            ->with('outsider-123')
            ->once()
            ->andReturn($outsider);

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('New owner does not belong to this organization');

        $this->service->transferOwnership('org-123', 'outsider-123', 'owner-123');
    }
}
