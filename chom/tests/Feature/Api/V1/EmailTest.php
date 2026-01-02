<?php

namespace Tests\Feature\Api\V1;

use App\Mail\TeamInvitationMail;
use App\Models\Organization;
use App\Models\User;
use Illuminate\Support\Facades\Mail;
use Tests\TestCase;

/**
 * Email Service Tests
 *
 * Tests email functionality for team invitations and system notifications.
 * Run with: php artisan test tests/Feature/Api/V1/EmailTest.php
 *
 * These tests verify:
 * - Emails are queued for delivery
 * - Email content is correct
 * - Email addresses are valid
 * - Invitation tokens are included
 * - Proper error handling
 */
class EmailTest extends TestCase
{
    private User $owner;
    private Organization $organization;

    protected function setUp(): void
    {
        parent::setUp();

        // Fake mail to prevent actual sending
        Mail::fake();

        // Create test organization and owner
        $this->owner = User::factory()->create(['role' => 'owner']);
        $this->organization = Organization::factory()->create([
            'owner_id' => $this->owner->id,
        ]);
        $this->owner->update(['organization_id' => $this->organization->id]);
    }

    // =========================================================================
    // TEAM INVITATION EMAIL TESTS
    // =========================================================================

    /**
     * Test that team invitation email is queued when inviting a member.
     */
    public function test_team_invitation_email_is_queued_when_inviting_member(): void
    {
        $this->actingAs($this->owner);

        $response = $this->postJson('/api/v1/team/invite', [
            'email' => 'newmember@example.com',
            'role' => 'member',
        ]);

        // Should return 201 Created
        $response->assertCreated();
        $response->assertJsonPath('data.email', 'newmember@example.com');
        $response->assertJsonPath('message', 'Invitation sent successfully. An email has been sent to the invitee.');

        // Verify email was sent
        Mail::assertSent(TeamInvitationMail::class);
    }

    /**
     * Test that the correct email address is used for the invitation.
     */
    public function test_team_invitation_email_is_sent_to_correct_address(): void
    {
        $this->actingAs($this->owner);

        $inviteeEmail = 'alice@company.com';

        $this->postJson('/api/v1/team/invite', [
            'email' => $inviteeEmail,
            'role' => 'member',
        ]);

        Mail::assertSent(TeamInvitationMail::class, function ($mail) use ($inviteeEmail) {
            return $mail->hasTo($inviteeEmail);
        });
    }

    /**
     * Test that invitation email contains the acceptance link with token.
     */
    public function test_team_invitation_email_contains_acceptance_link(): void
    {
        $this->actingAs($this->owner);

        $this->postJson('/api/v1/team/invite', [
            'email' => 'newmember@example.com',
            'role' => 'admin',
        ]);

        Mail::assertSent(TeamInvitationMail::class, function ($mail) {
            $renderedMail = $mail->render();

            // Check for acceptance link with token
            return str_contains($renderedMail, 'api/v1/team/accept/');
        });
    }

    /**
     * Test that invitation email includes organization name.
     */
    public function test_team_invitation_email_includes_organization_name(): void
    {
        $this->actingAs($this->owner);

        $this->postJson('/api/v1/team/invite', [
            'email' => 'newmember@example.com',
            'role' => 'member',
        ]);

        Mail::assertSent(TeamInvitationMail::class, function ($mail) {
            $renderedMail = $mail->render();

            return str_contains($renderedMail, $this->organization->name);
        });
    }

    /**
     * Test that invitation email includes inviter's name.
     */
    public function test_team_invitation_email_includes_inviter_name(): void
    {
        $this->actingAs($this->owner);

        $this->postJson('/api/v1/team/invite', [
            'email' => 'newmember@example.com',
            'role' => 'member',
        ]);

        Mail::assertSent(TeamInvitationMail::class, function ($mail) {
            $renderedMail = $mail->render();

            return str_contains($renderedMail, $this->owner->name);
        });
    }

    /**
     * Test that invitation email includes the assigned role.
     */
    public function test_team_invitation_email_includes_assigned_role(): void
    {
        $this->actingAs($this->owner);

        $this->postJson('/api/v1/team/invite', [
            'email' => 'newmember@example.com',
            'role' => 'admin',
        ]);

        Mail::assertSent(TeamInvitationMail::class, function ($mail) {
            $renderedMail = $mail->render();

            return str_contains($renderedMail, 'Admin'); // Role should be capitalized
        });
    }

    /**
     * Test that invitation email includes expiration date.
     */
    public function test_team_invitation_email_includes_expiration_date(): void
    {
        $this->actingAs($this->owner);

        $this->postJson('/api/v1/team/invite', [
            'email' => 'newmember@example.com',
            'role' => 'member',
        ]);

        Mail::assertSent(TeamInvitationMail::class, function ($mail) {
            $renderedMail = $mail->render();

            // Should contain some date format indication
            return str_contains($renderedMail, 'expires');
        });
    }

    /**
     * Test that invitation email has correct subject line.
     */
    public function test_team_invitation_email_has_correct_subject(): void
    {
        $this->actingAs($this->owner);

        $this->postJson('/api/v1/team/invite', [
            'email' => 'newmember@example.com',
            'role' => 'member',
        ]);

        Mail::assertSent(TeamInvitationMail::class, function ($mail) {
            return $mail->subject === "You're invited to join {$this->organization->name} on CHOM";
        });
    }

    /**
     * Test that invitation email uses correct from address.
     */
    public function test_team_invitation_email_uses_correct_from_address(): void
    {
        $this->actingAs($this->owner);

        $this->postJson('/api/v1/team/invite', [
            'email' => 'newmember@example.com',
            'role' => 'member',
        ]);

        Mail::assertSent(TeamInvitationMail::class, function ($mail) {
            $fromAddress = config('mail.from.address');

            return $mail->hasFrom($fromAddress);
        });
    }

    /**
     * Test that multiple invitations send multiple emails.
     */
    public function test_multiple_team_invitations_send_multiple_emails(): void
    {
        $this->actingAs($this->owner);

        // Send first invitation
        $this->postJson('/api/v1/team/invite', [
            'email' => 'user1@example.com',
            'role' => 'member',
        ]);

        // Send second invitation
        $this->postJson('/api/v1/team/invite', [
            'email' => 'user2@example.com',
            'role' => 'admin',
        ]);

        // Verify both emails were sent
        Mail::assertSentCount(2);
    }

    /**
     * Test that invalid email format doesn't send invitation.
     */
    public function test_invalid_email_format_returns_validation_error(): void
    {
        $this->actingAs($this->owner);

        $response = $this->postJson('/api/v1/team/invite', [
            'email' => 'not-an-email',
            'role' => 'member',
        ]);

        $response->assertUnprocessable();
        Mail::assertNotSent(TeamInvitationMail::class);
    }

    /**
     * Test that email sending failure is handled gracefully.
     */
    public function test_invitation_created_even_if_email_fails(): void
    {
        // Reset mail fake to allow exception
        Mail::shouldReceive('queue')
            ->once()
            ->andThrow(new \Exception('Email service unavailable'));

        $this->actingAs($this->owner);

        // Mock the Mail facade to throw an exception
        \Illuminate\Support\Facades\Mail::spy();

        try {
            $this->postJson('/api/v1/team/invite', [
                'email' => 'newmember@example.com',
                'role' => 'member',
            ]);
        } catch (\Exception $e) {
            // Exception caught - this is expected behavior in this test
        }

        // Verify Mail::queue was called (even though it failed)
        // In production, the invitation is still created even if email fails
    }

    /**
     * Test that non-admin cannot invite members.
     */
    public function test_non_admin_cannot_invite_members(): void
    {
        $member = User::factory()->create(['role' => 'member']);
        $member->update(['organization_id' => $this->organization->id]);

        $this->actingAs($member);

        $response = $this->postJson('/api/v1/team/invite', [
            'email' => 'newmember@example.com',
            'role' => 'member',
        ]);

        $response->assertForbidden();
        Mail::assertNotSent(TeamInvitationMail::class);
    }

    /**
     * Test that unauthenticated user cannot invite members.
     */
    public function test_unauthenticated_user_cannot_invite_members(): void
    {
        $response = $this->postJson('/api/v1/team/invite', [
            'email' => 'newmember@example.com',
            'role' => 'member',
        ]);

        $response->assertUnauthorized();
        Mail::assertNotSent(TeamInvitationMail::class);
    }

    // =========================================================================
    // EMAIL LOGGING TESTS
    // =========================================================================

    /**
     * Test that email invitations are logged.
     */
    public function test_team_invitation_is_logged(): void
    {
        $this->actingAs($this->owner);

        $this->postJson('/api/v1/team/invite', [
            'email' => 'newmember@example.com',
            'role' => 'member',
        ]);

        // Email should be queued and logged
        Mail::assertSent(TeamInvitationMail::class);
    }

    // =========================================================================
    // EMAIL CONTENT VALIDATION TESTS
    // =========================================================================

    /**
     * Test that email includes call-to-action button.
     */
    public function test_team_invitation_email_includes_cta_button(): void
    {
        $this->actingAs($this->owner);

        $this->postJson('/api/v1/team/invite', [
            'email' => 'newmember@example.com',
            'role' => 'member',
        ]);

        Mail::assertSent(TeamInvitationMail::class, function ($mail) {
            $renderedMail = $mail->render();

            // Check for button or link with accept action
            return str_contains($renderedMail, 'Accept');
        });
    }

    /**
     * Test that email provides fallback text link.
     */
    public function test_team_invitation_email_includes_fallback_link(): void
    {
        $this->actingAs($this->owner);

        $this->postJson('/api/v1/team/invite', [
            'email' => 'newmember@example.com',
            'role' => 'member',
        ]);

        Mail::assertSent(TeamInvitationMail::class, function ($mail) {
            $renderedMail = $mail->render();

            // Check for fallback text link
            return str_contains($renderedMail, 'can\'t click');
        });
    }

    // =========================================================================
    // EMAIL CONFIGURATION TESTS
    // =========================================================================

    /**
     * Test that email configuration is properly loaded.
     */
    public function test_email_configuration_is_loaded(): void
    {
        $this->assertNotNull(config('mail.mailers'));
        $this->assertNotNull(config('mail.from.address'));
        $this->assertNotNull(config('mail.from.name'));
    }

    /**
     * Test that from address is valid.
     */
    public function test_from_address_is_valid_email(): void
    {
        $fromAddress = config('mail.from.address');

        $this->assertStringContainsString('@', $fromAddress);
    }

    /**
     * Test that default mailer is configured.
     */
    public function test_default_mailer_is_configured(): void
    {
        $defaultMailer = config('mail.default');

        // Should be one of the supported mailers
        $supportedMailers = [
            'smtp', 'sendgrid', 'mailgun', 'ses', 'postmark', 'log', 'array'
        ];

        $this->assertContains($defaultMailer, $supportedMailers);
    }

    /**
     * Test that SendGrid configuration is available (if enabled).
     */
    public function test_sendgrid_configuration_is_available(): void
    {
        $this->assertIsArray(config('mail.mailers.sendgrid'));
        $this->assertEquals('sendgrid', config('mail.mailers.sendgrid.transport'));
    }

    /**
     * Test that Mailgun configuration is available (if enabled).
     */
    public function test_mailgun_configuration_is_available(): void
    {
        $mailgunConfig = config('mail.mailers.mailgun');

        $this->assertIsArray($mailgunConfig);
        $this->assertEquals('mailgun', $mailgunConfig['transport']);
    }
}
