<?php

declare(strict_types=1);

namespace App\Contracts\Infrastructure;

use App\ValueObjects\EmailNotification;
use App\ValueObjects\InAppNotification;
use App\ValueObjects\SlackNotification;
use App\ValueObjects\SmsNotification;
use App\ValueObjects\WebhookNotification;

/**
 * Notification Interface
 *
 * Defines the contract for sending notifications across multiple channels.
 * Provides abstraction over notification services (Email, SMS, Slack, Webhooks, etc.)
 *
 * Design Pattern: Strategy Pattern - different notification channels
 * SOLID Principle: Single Responsibility - focused on notification delivery
 *
 * @package App\Contracts\Infrastructure
 */
interface NotificationInterface
{
    /**
     * Send an email notification
     *
     * @param EmailNotification $notification Email details
     * @return bool True if email was sent successfully
     * @throws \RuntimeException If email sending fails
     */
    public function sendEmail(EmailNotification $notification): bool;

    /**
     * Send an SMS notification
     *
     * @param SmsNotification $notification SMS details
     * @return bool True if SMS was sent successfully
     * @throws \RuntimeException If SMS sending fails
     */
    public function sendSms(SmsNotification $notification): bool;

    /**
     * Send a Slack notification
     *
     * @param SlackNotification $notification Slack message details
     * @return bool True if Slack message was sent successfully
     * @throws \RuntimeException If Slack sending fails
     */
    public function sendSlack(SlackNotification $notification): bool;

    /**
     * Send a webhook notification
     *
     * @param WebhookNotification $notification Webhook details
     * @return bool True if webhook was triggered successfully
     * @throws \RuntimeException If webhook fails
     */
    public function sendWebhook(WebhookNotification $notification): bool;

    /**
     * Send an in-app notification
     *
     * @param InAppNotification $notification In-app notification details
     * @return bool True if notification was created successfully
     * @throws \RuntimeException If notification creation fails
     */
    public function sendInApp(InAppNotification $notification): bool;

    /**
     * Get supported notification channels
     *
     * @return array<string> List of supported channels
     */
    public function getSupportedChannels(): array;
}
