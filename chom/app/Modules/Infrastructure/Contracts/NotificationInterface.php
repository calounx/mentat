<?php

declare(strict_types=1);

namespace App\Modules\Infrastructure\Contracts;

/**
 * Notification Service Contract
 *
 * Defines the contract for notification delivery operations.
 */
interface NotificationInterface
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
    public function sendEmail(string $to, string $subject, string $message, array $data = []): bool;

    /**
     * Send Slack notification.
     *
     * @param string $channel Slack channel
     * @param string $message Message text
     * @param array $data Additional data
     * @return bool Success status
     */
    public function sendSlack(string $channel, string $message, array $data = []): bool;

    /**
     * Send SMS notification.
     *
     * @param string $phone Phone number
     * @param string $message SMS message
     * @return bool Success status
     */
    public function sendSms(string $phone, string $message): bool;

    /**
     * Send webhook notification.
     *
     * @param string $url Webhook URL
     * @param array $payload Webhook payload
     * @return bool Success status
     */
    public function sendWebhook(string $url, array $payload): bool;

    /**
     * Send notification to multiple channels.
     *
     * @param array $channels Channels to notify
     * @param string $message Message text
     * @param array $data Additional data
     * @return array Results per channel
     */
    public function broadcast(array $channels, string $message, array $data = []): array;
}
