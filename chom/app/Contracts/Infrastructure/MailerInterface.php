<?php

declare(strict_types=1);

namespace App\Contracts\Infrastructure;

/**
 * Mailer Interface
 *
 * Defines the contract for email delivery operations.
 * Provides abstraction over email services (SMTP, SendGrid, Mailgun, SES, etc.)
 *
 * Design Pattern: Adapter Pattern - adapts different mail providers
 * SOLID Principle: Single Responsibility - focused on email delivery
 *
 * @package App\Contracts\Infrastructure
 */
interface MailerInterface
{
    /**
     * Send an email
     *
     * @param array<string>|string $to Recipient email address(es)
     * @param string $subject Email subject
     * @param string $body Email body (HTML or plain text)
     * @param array<string, mixed> $options Additional options (from, cc, bcc, attachments, etc.)
     * @return bool True if email was sent successfully
     * @throws \RuntimeException If sending fails
     */
    public function send(array|string $to, string $subject, string $body, array $options = []): bool;

    /**
     * Send a templated email
     *
     * @param array<string>|string $to Recipient email address(es)
     * @param string $template Template name
     * @param array<string, mixed> $data Template data
     * @param array<string, mixed> $options Additional options
     * @return bool True if email was sent successfully
     * @throws \RuntimeException If sending fails
     */
    public function sendTemplate(array|string $to, string $template, array $data = [], array $options = []): bool;

    /**
     * Queue an email for later delivery
     *
     * @param array<string>|string $to Recipient email address(es)
     * @param string $subject Email subject
     * @param string $body Email body
     * @param array<string, mixed> $options Additional options
     * @return bool True if email was queued successfully
     * @throws \RuntimeException If queuing fails
     */
    public function queue(array|string $to, string $subject, string $body, array $options = []): bool;

    /**
     * Send email with attachments
     *
     * @param array<string>|string $to Recipient email address(es)
     * @param string $subject Email subject
     * @param string $body Email body
     * @param array<string> $attachments File paths to attach
     * @param array<string, mixed> $options Additional options
     * @return bool True if email was sent successfully
     * @throws \RuntimeException If sending fails
     */
    public function sendWithAttachments(
        array|string $to,
        string $subject,
        string $body,
        array $attachments,
        array $options = []
    ): bool;

    /**
     * Get mailer name/driver
     *
     * @return string Mailer name (e.g., 'smtp', 'sendgrid', 'mailgun')
     */
    public function getMailerName(): string;
}
