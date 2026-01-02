<?php

namespace Tests\Browser;

use App\Models\TeamInvitation;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseMigrations;
use Illuminate\Support\Str;
use Laravel\Dusk\Browser;
use Tests\DuskTestCase;

/**
 * E2E Test Suite: Team Collaboration
 *
 * Covers complete team collaboration workflows including:
 * - Inviting team members
 * - Accepting invitations (multi-browser)
 * - Updating member roles
 * - Removing team members
 * - Transferring organization ownership
 */
class TeamCollaborationTest extends DuskTestCase
{
    use DatabaseMigrations;

    /**
     * Test 1: Invite team member.
     *
     * @test
     */
    public function owner_can_invite_team_member(): void
    {
        $owner = $this->createUser([
            'email' => 'owner@example.com',
        ]);

        $this->browse(function (Browser $browser) use ($owner) {
            $this->loginAs($browser, $owner);

            $browser->visit('/team')
                ->assertSee('Team Management')
                ->click('@invite-member-button')
                ->waitForText('Invite Team Member', 10)
                ->type('email', 'newmember@example.com')
                ->type('name', 'New Member')
                ->select('role', 'member')
                ->press('Send Invitation')
                ->waitFor('.alert-success', 10)
                ->assertSee('Invitation sent successfully');

            // Verify invitation was created
            $this->assertDatabaseHas('team_invitations', [
                'organization_id' => $owner->organization_id,
                'email' => 'newmember@example.com',
                'role' => 'member',
                'status' => 'pending',
            ]);

            // Verify invitation email was queued
            $this->assertDatabaseHas('jobs', [
                'queue' => 'emails',
            ]);

            // Verify audit log
            $this->assertDatabaseHas('audit_logs', [
                'user_id' => $owner->id,
                'action' => 'team_invite_sent',
                'resource_type' => 'TeamInvitation',
            ]);
        });
    }

    /**
     * Test 2: Accept invitation (multi-browser).
     *
     * @test
     */
    public function user_can_accept_team_invitation(): void
    {
        $owner = $this->createUser([
            'email' => 'owner@example.com',
        ]);

        // Create invitation
        $invitation = TeamInvitation::create([
            'organization_id' => $owner->organization_id,
            'email' => 'invited@example.com',
            'name' => 'Invited User',
            'role' => 'member',
            'token' => Str::random(32),
            'invited_by' => $owner->id,
            'status' => 'pending',
            'expires_at' => now()->addDays(7),
        ]);

        $this->browse(function (Browser $first, Browser $second) use ($owner, $invitation) {
            // Browser 1: Owner views pending invitations
            $this->loginAs($first, $owner);
            $first->visit('/team')
                ->assertSee('Team Management')
                ->click('@pending-invitations-tab')
                ->assertSee('invited@example.com')
                ->assertSee('Pending');

            // Browser 2: New user accepts invitation
            $second->visit("/team/accept/{$invitation->token}")
                ->assertSee('Join Organization')
                ->assertSee($owner->organization->name)
                ->assertSee('Invited User')
                ->type('email', 'invited@example.com')
                ->type('password', 'SecurePassword123!')
                ->type('password_confirmation', 'SecurePassword123!')
                ->press('Accept Invitation')
                ->waitForLocation('/dashboard', 15)
                ->assertPathIs('/dashboard')
                ->assertSee('Welcome to')
                ->assertSee($owner->organization->name);

            // Verify new user was created and linked to organization
            $this->assertDatabaseHas('users', [
                'email' => 'invited@example.com',
                'organization_id' => $owner->organization_id,
                'role' => 'member',
            ]);

            // Verify invitation status updated
            $this->assertDatabaseHas('team_invitations', [
                'id' => $invitation->id,
                'status' => 'accepted',
            ]);

            // Browser 1: Owner sees new team member
            $first->visit('/team')
                ->waitForText('invited@example.com', 10)
                ->assertSee('invited@example.com')
                ->assertSee('Member');
        });
    }

    /**
     * Test 3: Update member role.
     *
     * @test
     */
    public function owner_can_update_member_role(): void
    {
        $owner = $this->createUser([
            'email' => 'owner@example.com',
        ]);

        $member = User::factory()->create([
            'organization_id' => $owner->organization_id,
            'role' => 'member',
            'email' => 'member@example.com',
        ]);

        $this->browse(function (Browser $browser) use ($owner, $member) {
            $this->loginAs($browser, $owner);

            $browser->visit('/team')
                ->assertSee($member->email)
                ->assertSee('Member')
                ->click('@edit-member-'.$member->id)
                ->waitForText('Update Role', 10)
                ->select('role', 'admin')
                ->press('Update Role')
                ->waitFor('.alert-success', 10)
                ->assertSee('Role updated successfully')
                ->assertSee('Admin');

            // Verify role was updated
            $this->assertDatabaseHas('users', [
                'id' => $member->id,
                'role' => 'admin',
            ]);

            // Verify audit log
            $this->assertDatabaseHas('audit_logs', [
                'user_id' => $owner->id,
                'action' => 'team_member_role_updated',
                'resource_type' => 'User',
                'resource_id' => $member->id,
            ]);
        });
    }

    /**
     * Test 4: Remove team member.
     *
     * @test
     */
    public function owner_can_remove_team_member(): void
    {
        $owner = $this->createUser([
            'email' => 'owner@example.com',
        ]);

        $member = User::factory()->create([
            'organization_id' => $owner->organization_id,
            'role' => 'member',
            'email' => 'remove-me@example.com',
        ]);

        $this->browse(function (Browser $browser) use ($owner, $member) {
            $this->loginAs($browser, $owner);

            $browser->visit('/team')
                ->assertSee($member->email)
                ->click('@remove-member-'.$member->id)
                ->waitForText('Confirm Removal', 10)
                ->assertSee('Are you sure you want to remove this team member?')
                ->press('Remove')
                ->waitFor('.alert-success', 10)
                ->assertSee('Team member removed successfully')
                ->assertDontSee($member->email);

            // Verify member was removed (organization_id set to null)
            $this->assertDatabaseHas('users', [
                'id' => $member->id,
                'organization_id' => null,
            ]);

            // Verify audit log
            $this->assertDatabaseHas('audit_logs', [
                'user_id' => $owner->id,
                'action' => 'team_member_removed',
                'resource_type' => 'User',
                'resource_id' => $member->id,
            ]);
        });
    }

    /**
     * Test 5: Transfer organization ownership.
     *
     * @test
     */
    public function owner_can_transfer_ownership(): void
    {
        $owner = $this->createUser([
            'email' => 'current-owner@example.com',
        ]);

        $admin = User::factory()->create([
            'organization_id' => $owner->organization_id,
            'role' => 'admin',
            'email' => 'new-owner@example.com',
        ]);

        $this->browse(function (Browser $browser) use ($owner, $admin) {
            $this->loginAs($browser, $owner);

            $browser->visit('/team')
                ->assertSee($admin->email)
                ->click('@transfer-ownership-button')
                ->waitForText('Transfer Ownership', 10)
                ->assertSee('This action cannot be undone')
                ->select('new_owner_id', $admin->id)
                ->type('password', 'password') // Require password confirmation
                ->press('Transfer Ownership')
                ->waitFor('.alert-success', 10)
                ->assertSee('Ownership transferred successfully');

            // Verify ownership was transferred
            $this->assertDatabaseHas('users', [
                'id' => $admin->id,
                'role' => 'owner',
            ]);

            // Verify previous owner is now admin
            $this->assertDatabaseHas('users', [
                'id' => $owner->id,
                'role' => 'admin',
            ]);

            // Verify audit log
            $this->assertDatabaseHas('audit_logs', [
                'user_id' => $owner->id,
                'action' => 'ownership_transferred',
                'resource_type' => 'Organization',
                'resource_id' => $owner->organization_id,
            ]);

            // Verify new owner sees ownership in UI
            $browser->visit('/team')
                ->assertSee('Owner')
                ->assertSee($admin->email);
        });
    }

    /**
     * Test: Admin cannot invite members.
     *
     * @test
     */
    public function admin_cannot_invite_members(): void
    {
        $admin = $this->createAdmin();

        $this->browse(function (Browser $browser) use ($admin) {
            $this->loginAs($browser, $admin);

            $browser->visit('/team')
                ->assertDontSee('@invite-member-button')
                ->assertSee('Only owners can invite team members');
        });
    }

    /**
     * Test: Member cannot remove team members.
     *
     * @test
     */
    public function member_cannot_remove_team_members(): void
    {
        $owner = $this->createUser();
        $member = User::factory()->create([
            'organization_id' => $owner->organization_id,
            'role' => 'member',
        ]);

        $this->browse(function (Browser $browser) use ($member, $owner) {
            $this->loginAs($browser, $member);

            $browser->visit('/team')
                ->assertSee($owner->email)
                ->assertDontSee('@remove-member-'.$owner->id);
        });
    }

    /**
     * Test: Cannot accept expired invitation.
     *
     * @test
     */
    public function cannot_accept_expired_invitation(): void
    {
        $owner = $this->createUser();

        $invitation = TeamInvitation::create([
            'organization_id' => $owner->organization_id,
            'email' => 'expired@example.com',
            'name' => 'Expired User',
            'role' => 'member',
            'token' => Str::random(32),
            'invited_by' => $owner->id,
            'status' => 'pending',
            'expires_at' => now()->subDay(), // Expired
        ]);

        $this->browse(function (Browser $browser) use ($invitation) {
            $browser->visit("/team/accept/{$invitation->token}")
                ->assertSee('Invitation Expired')
                ->assertSee('This invitation has expired')
                ->assertDontSee('Accept Invitation');
        });
    }

    /**
     * Test: Multiple invitations workflow.
     *
     * @test
     */
    public function owner_can_manage_multiple_invitations(): void
    {
        $owner = $this->createUser();

        $this->browse(function (Browser $browser) use ($owner) {
            $this->loginAs($browser, $owner);

            // Send multiple invitations
            for ($i = 1; $i <= 3; $i++) {
                $browser->visit('/team')
                    ->click('@invite-member-button')
                    ->waitForText('Invite Team Member', 10)
                    ->type('email', "member{$i}@example.com")
                    ->type('name', "Member {$i}")
                    ->select('role', $i === 1 ? 'admin' : 'member')
                    ->press('Send Invitation')
                    ->waitFor('.alert-success', 10);
            }

            // View all pending invitations
            $browser->visit('/team')
                ->click('@pending-invitations-tab')
                ->assertSee('member1@example.com')
                ->assertSee('member2@example.com')
                ->assertSee('member3@example.com')
                ->assertSee('Admin') // member1's role
                ->assertSee('Member'); // member2 and member3's role

            // Cancel one invitation
            $invitation = TeamInvitation::where('email', 'member2@example.com')->first();

            $browser->click('@cancel-invitation-'.$invitation->id)
                ->waitForText('Confirm Cancellation', 10)
                ->press('Cancel Invitation')
                ->waitFor('.alert-success', 10)
                ->assertSee('Invitation cancelled')
                ->assertDontSee('member2@example.com');

            // Verify cancellation
            $this->assertDatabaseHas('team_invitations', [
                'id' => $invitation->id,
                'status' => 'cancelled',
            ]);
        });
    }
}
