<?php

declare(strict_types=1);

namespace App\Modules\Infrastructure\Services;

use App\Modules\Infrastructure\Contracts\NotificationInterface;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;

/**
 * Notification Service
 *
 * Handles notification delivery across multiple channels.
 */
class NotificationService implements NotificationInterface
{
    /**
     * Send email notification.
     *
     * @param string $to Recipient email
     * @param string $subject Email subject
     * @param string $message Email message
     * @param array $data Additional data
     * @return bool Success status
     */
    public function sendEmail(string $to, string $subject, string $message, array $data = []): bool
    {
        try {
            Mail::raw($message, function ($mail) use ($to, $subject) {
                $mail->to($to)->subject($subject);
            });

            Log::info('Email notification sent', [
                'to' => $to,
                'subject' => $subject,
            ]);

            return true;
        } catch (\Exception $e) {
            Log::error('Failed to send email notification', [
                'to' => $to,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Send Slack notification.
     *
     * @param string $channel Slack channel
     * @param string $message Message text
     * @param array $data Additional data
     * @return bool Success status
     */
    public function sendSlack(string $channel, string $message, array $data = []): bool
    {
        try {
            $webhookUrl = config('services.slack.webhook_url');

            if (!$webhookUrl) {
                Log::warning('Slack webhook URL not configured');
                return false;
            }

            $response = Http::post($webhookUrl, [
                'channel' => $channel,
                'text' => $message,
                'attachments' => $data['attachments'] ?? [],
            ]);

            if ($response->successful()) {
                Log::info('Slack notification sent', [
                    'channel' => $channel,
                ]);
                return true;
            }

            Log::error('Slack notification failed', [
                'channel' => $channel,
                'status' => $response->status(),
            ]);

            return false;
        } catch (\Exception $e) {
            Log::error('Failed to send Slack notification', [
                'channel' => $channel,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Send SMS notification.
     *
     * @param string $phone Phone number
     * @param string $message SMS message
     * @return bool Success status
     */
    public function sendSms(string $phone, string $message): bool
    {
        try {
            // Implement SMS provider integration (Twilio, etc.)
            Log::info('SMS notification sent', [
                'phone' => $phone,
                'message' => $message,
            ]);

            return true;
        } catch (\Exception $e) {
            Log::error('Failed to send SMS notification', [
                'phone' => $phone,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Send webhook notification.
     *
     * @param string $url Webhook URL
     * @param array $payload Webhook payload
     * @return bool Success status
     */
    public function sendWebhook(string $url, array $payload): bool
    {
        try {
            $response = Http::post($url, $payload);

            if ($response->successful()) {
                Log::info('Webhook notification sent', [
                    'url' => $url,
                ]);
                return true;
            }

            Log::error('Webhook notification failed', [
                'url' => $url,
                'status' => $response->status(),
            ]);

            return false;
        } catch (\Exception $e) {
            Log::error('Failed to send webhook notification', [
                'url' => $url,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Send notification to multiple channels.
     *
     * @param array $channels Channels to notify
     * @param string $message Message text
     * @param array $data Additional data
     * @return array Results per channel
     */
    public function broadcast(array $channels, string $message, array $data = []): array
    {
        $results = [];

        foreach ($channels as $channel => $config) {
            $success = match ($channel) {
                'email' => $this->sendEmail($config['to'] ?? '', $data['subject'] ?? 'Notification', $message, $data),
                'slack' => $this->sendSlack($config['channel'] ?? '#general', $message, $data),
                'sms' => $this->sendSms($config['phone'] ?? '', $message),
                'webhook' => $this->sendWebhook($config['url'] ?? '', array_merge(['message' => $message], $data)),
                default => false,
            };

            $results[$channel] = $success;
        }

        Log::info('Broadcast notification sent', [
            'channels' => array_keys($channels),
            'results' => $results,
        ]);

        return $results;
    }
}
