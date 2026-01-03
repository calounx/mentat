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
 * Multi-Channel Notifier
 *
 * Composite implementation that delegates to multiple notification channels.
 * Allows sending notifications across email, SMS, Slack, webhooks, and in-app.
 *
 * Pattern: Composite Pattern - combines multiple notifiers
 * SOLID: Open/Closed - can add new channels without modifying existing code
 *
 * @package App\Infrastructure\Notification
 */
class MultiChannelNotifier implements NotificationInterface
{
    /**
     * @param array<NotificationInterface> $channels Notification channel implementations
     * @param bool $failSilently Whether to continue on channel failures
     */
    public function __construct(
        private readonly array $channels = [],
        private readonly bool $failSilently = true
    ) {
    }

    /**
     * {@inheritDoc}
     */
    public function sendEmail(EmailNotification $notification): bool
    {
        return $this->sendToChannels('sendEmail', $notification);
    }

    /**
     * {@inheritDoc}
     */
    public function sendSms(SmsNotification $notification): bool
    {
        return $this->sendToChannels('sendSms', $notification);
    }

    /**
     * {@inheritDoc}
     */
    public function sendSlack(SlackNotification $notification): bool
    {
        return $this->sendToChannels('sendSlack', $notification);
    }

    /**
     * {@inheritDoc}
     */
    public function sendWebhook(WebhookNotification $notification): bool
    {
        return $this->sendToChannels('sendWebhook', $notification);
    }

    /**
     * {@inheritDoc}
     */
    public function sendInApp(InAppNotification $notification): bool
    {
        return $this->sendToChannels('sendInApp', $notification);
    }

    /**
     * {@inheritDoc}
     */
    public function getSupportedChannels(): array
    {
        $channels = [];

        foreach ($this->channels as $channel) {
            $channels = array_merge($channels, $channel->getSupportedChannels());
        }

        return array_unique($channels);
    }

    /**
     * Send notification to all applicable channels
     *
     * @param string $method
     * @param object $notification
     * @return bool
     */
    private function sendToChannels(string $method, object $notification): bool
    {
        $results = [];

        foreach ($this->channels as $channel) {
            try {
                if (method_exists($channel, $method)) {
                    $results[] = $channel->$method($notification);
                }
            } catch (\Exception $e) {
                Log::error("Notification channel failed", [
                    'channel' => get_class($channel),
                    'method' => $method,
                    'error' => $e->getMessage(),
                ]);

                if (!$this->failSilently) {
                    throw $e;
                }

                $results[] = false;
            }
        }

        return !empty($results) && in_array(true, $results, true);
    }
}
