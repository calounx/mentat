<?php

declare(strict_types=1);

namespace App\Infrastructure\Notification;

use App\Contracts\Infrastructure\NotificationInterface;
use App\ValueObjects\EmailNotification;
use App\ValueObjects\InAppNotification;
use App\ValueObjects\SlackNotification;
use App\ValueObjects\SmsNotification;
use App\ValueObjects\WebhookNotification;
use Illuminate\Support\Facades\Log;

/**
 * Log Notifier
 *
 * Logs all notifications instead of sending them.
 * Useful for testing and development environments.
 *
 * Pattern: Null Object Pattern (variation) - logs instead of no-op
 * Use Case: Testing, development, debugging
 *
 * @package App\Infrastructure\Notification
 */
class LogNotifier implements NotificationInterface
{
    /**
     * {@inheritDoc}
     */
    public function sendEmail(EmailNotification $notification): bool
    {
        Log::info('EMAIL NOTIFICATION', [
            'to' => $notification->to,
            'subject' => $notification->subject,
            'body' => substr($notification->body, 0, 200),
            'cc' => $notification->cc,
            'bcc' => $notification->bcc,
            'attachments_count' => count($notification->attachments),
        ]);

        return true;
    }

    /**
     * {@inheritDoc}
     */
    public function sendSms(SmsNotification $notification): bool
    {
        Log::info('SMS NOTIFICATION', [
            'phone' => $notification->phone,
            'message' => $notification->message,
            'segments' => $notification->getSegmentCount(),
        ]);

        return true;
    }

    /**
     * {@inheritDoc}
     */
    public function sendSlack(SlackNotification $notification): bool
    {
        Log::info('SLACK NOTIFICATION', [
            'channel' => $notification->channel,
            'message' => $notification->message,
            'attachments_count' => count($notification->attachments),
            'blocks_count' => count($notification->blocks),
        ]);

        return true;
    }

    /**
     * {@inheritDoc}
     */
    public function sendWebhook(WebhookNotification $notification): bool
    {
        Log::info('WEBHOOK NOTIFICATION', [
            'url' => $notification->url,
            'method' => $notification->method,
            'payload' => $notification->payload,
        ]);

        return true;
    }

    /**
     * {@inheritDoc}
     */
    public function sendInApp(InAppNotification $notification): bool
    {
        Log::info('IN-APP NOTIFICATION', [
            'user_id' => $notification->userId,
            'title' => $notification->title,
            'body' => $notification->body,
            'type' => $notification->type,
            'has_action' => $notification->hasAction(),
        ]);

        return true;
    }

    /**
     * {@inheritDoc}
     */
    public function getSupportedChannels(): array
    {
        return ['email', 'sms', 'slack', 'webhook', 'in_app'];
    }
}
