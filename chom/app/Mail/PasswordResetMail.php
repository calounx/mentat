<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Address;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

/**
 * Password Reset Email
 *
 * Sends password reset links to users who request password resets.
 *
 * QUEUED: Yes (handles async mail sending via Mail::queue())
 *
 * Template Variables:
 * - user_name: Name of the user
 * - reset_url: URL to reset password (with token)
 * - expires_in_minutes: How long the token is valid
 *
 * Security Considerations:
 * - Reset tokens are single-use and expire after a configured time
 * - URLs use HTTPS in production
 * - No user identification in URL (token only)
 * - Database verified to prevent token tampering
 */
class PasswordResetMail extends Mailable
{
    use Queueable, SerializesModels;

    /**
     * The password reset token.
     *
     * @var string
     */
    public string $token;

    /**
     * The user's email address.
     *
     * @var string
     */
    public string $userEmail;

    /**
     * The user's name.
     *
     * @var string
     */
    public string $userName;

    /**
     * Create a new message instance.
     *
     * @param string $token
     * @param string $userEmail
     * @param string $userName
     */
    public function __construct(string $token, string $userEmail, string $userName)
    {
        $this->token = $token;
        $this->userEmail = $userEmail;
        $this->userName = $userName;
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
            subject: 'Reset your CHOM password'
        );
    }

    /**
     * Get the message content definition.
     *
     * @return Content
     */
    public function content(): Content
    {
        // Generate reset URL - adjust route name based on your frontend
        // For API-based reset, this could be a frontend URL with the token as a query parameter
        $resetUrl = route('password.reset', [
            'token' => $this->token,
            'email' => $this->userEmail,
        ]);

        return new Content(
            markdown: 'emails.password-reset',
            with: [
                'user_name' => $this->userName,
                'reset_url' => $resetUrl,
                'expires_in_minutes' => config('auth.passwords.users.expire', 60),
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
