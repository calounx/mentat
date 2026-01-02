<?php

namespace App\Mail;

use App\Models\Organization;
use App\Models\TeamInvitation;
use App\Models\User;
use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Address;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

/**
 * Team Invitation Email
 *
 * Sends invitation emails to team members when invited to join an organization.
 *
 * QUEUED: Yes (handles async mail sending via Mail::queue())
 *
 * Template Variables:
 * - invitee_email: Email address of the invitee
 * - inviter_name: Name of the user who sent the invitation
 * - organization_name: Name of the organization
 * - accept_url: URL to accept the invitation
 * - expires_at: When the invitation expires
 * - role: Role being assigned to the invitee
 *
 * Security Considerations:
 * - Invitation tokens are random 64-character strings
 * - Tokens expire after 7 days
 * - Email validation prevents spoofing
 * - Tokens can only be used once
 */
class TeamInvitationMail extends Mailable
{
    use Queueable, SerializesModels;

    /**
     * The team invitation instance.
     *
     * @var TeamInvitation
     */
    public TeamInvitation $invitation;

    /**
     * The organization instance.
     *
     * @var Organization
     */
    public Organization $organization;

    /**
     * The inviter user instance.
     *
     * @var User
     */
    public User $inviter;

    /**
     * The invitation acceptance URL.
     *
     * @var string
     */
    public string $acceptUrl;

    /**
     * Create a new message instance.
     *
     * @param TeamInvitation $invitation
     * @param Organization $organization
     * @param User $inviter
     * @param string $acceptUrl
     */
    public function __construct(
        TeamInvitation $invitation,
        Organization $organization,
        User $inviter,
        string $acceptUrl
    ) {
        $this->invitation = $invitation;
        $this->organization = $organization;
        $this->inviter = $inviter;
        $this->acceptUrl = $acceptUrl;
    }

    /**
     * Get the message envelope.
     *
     * @return Envelope
     */
    public function envelope(): Envelope
    {
        return new Envelope(
            from: new Address(
                config('mail.from.address'),
                config('mail.from.name')
            ),
            subject: "You're invited to join {$this->organization->name} on CHOM"
        );
    }

    /**
     * Get the message content definition.
     *
     * @return Content
     */
    public function content(): Content
    {
        return new Content(
            markdown: 'emails.team-invitation',
            with: [
                'invitee_email' => $this->invitation->email,
                'inviter_name' => $this->inviter->name,
                'organization_name' => $this->organization->name,
                'accept_url' => $this->acceptUrl,
                'expires_at' => $this->invitation->expires_at->format('F d, Y'),
                'role' => ucfirst($this->invitation->role),
                'app_name' => config('app.name'),
                'app_url' => config('app.url'),
            ]
        );
    }

    /**
     * Get the attachments for the message.
     *
     * @return array
     */
    public function attachments(): array
    {
        return [];
    }
}
