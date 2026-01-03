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
use Illuminate\Support\Facades\Mail;
use RuntimeException;

/**
 * Email Notifier
 *
 * Sends notifications via email using Laravel Mail facade.
 * Supports HTML/plain text, attachments, CC/BCC recipients.
 *
 * Pattern: Adapter Pattern - adapts Laravel Mail to notification interface
 *
 * @package App\Infrastructure\Notification
 */
class EmailNotifier implements NotificationInterface
{
    /**
     * {@inheritDoc}
     */
    public function sendEmail(EmailNotification $notification): bool
    {
        Log::info('Sending email notification', [
            'to' => $notification->to,
            'subject' => $notification->subject,
        ]);

        try {
            Mail::send([], [], function ($message) use ($notification) {
                $message->to($notification->to)
                    ->subject($notification->subject);

                if ($notification->from) {
                    $message->from($notification->from);
                }

                if ($notification->replyTo) {
                    $message->replyTo($notification->replyTo);
                }

                if (!empty($notification->cc)) {
                    $message->cc($notification->cc);
                }

                if (!empty($notification->bcc)) {
                    $message->bcc($notification->bcc);
                }

                if ($notification->isHtml) {
                    $message->html($notification->body);
                } else {
                    $message->text($notification->body);
                }

                foreach ($notification->attachments as $attachment) {
                    if (file_exists($attachment)) {
                        $message->attach($attachment);
                    }
                }
            });

            Log::info('Email notification sent successfully', [
                'to' => $notification->to,
            ]);

            return true;
        } catch (\Exception $e) {
            Log::error('Failed to send email notification', [
                'to' => $notification->to,
                'error' => $e->getMessage(),
            ]);

            throw new RuntimeException("Failed to send email: {$e->getMessage()}", 0, $e);
        }
    }

    /**
     * {@inheritDoc}
     */
    public function sendSms(SmsNotification $notification): bool
    {
        throw new RuntimeException('SMS not supported by EmailNotifier');
    }

    /**
     * {@inheritDoc}
     */
    public function sendSlack(SlackNotification $notification): bool
    {
        throw new RuntimeException('Slack not supported by EmailNotifier');
    }

    /**
     * {@inheritDoc}
     */
    public function sendWebhook(WebhookNotification $notification): bool
    {
        throw new RuntimeException('Webhook not supported by EmailNotifier');
    }

    /**
     * {@inheritDoc}
     */
    public function sendInApp(InAppNotification $notification): bool
    {
        throw new RuntimeException('In-app notification not supported by EmailNotifier');
    }

    /**
     * {@inheritDoc}
     */
    public function getSupportedChannels(): array
    {
        return ['email'];
    }
}
