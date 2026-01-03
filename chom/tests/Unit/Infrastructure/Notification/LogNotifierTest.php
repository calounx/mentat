<?php

declare(strict_types=1);

namespace Tests\Unit\Infrastructure\Notification;

use App\Infrastructure\Notification\LogNotifier;
use App\ValueObjects\EmailNotification;
use App\ValueObjects\InAppNotification;
use App\ValueObjects\SlackNotification;
use App\ValueObjects\SmsNotification;
use App\ValueObjects\WebhookNotification;
use PHPUnit\Framework\TestCase;

/**
 * Log Notifier Tests
 *
 * Tests LogNotifier implementation.
 *
 * @package Tests\Unit\Infrastructure\Notification
 */
class LogNotifierTest extends TestCase
{
    private LogNotifier $notifier;

    protected function setUp(): void
    {
        parent::setUp();
        $this->notifier = new LogNotifier();
    }

    public function test_sends_email_notification(): void
    {
        $notification = new EmailNotification(
            to: ['test@example.com'],
            subject: 'Test Email',
            body: 'Test body'
        );

        $result = $this->notifier->sendEmail($notification);

        $this->assertTrue($result);
    }

    public function test_sends_sms_notification(): void
    {
        $notification = new SmsNotification(
            phone: '+1234567890',
            message: 'Test SMS'
        );

        $result = $this->notifier->sendSms($notification);

        $this->assertTrue($result);
    }

    public function test_sends_slack_notification(): void
    {
        $notification = new SlackNotification(
            channel: '#general',
            message: 'Test Slack message'
        );

        $result = $this->notifier->sendSlack($notification);

        $this->assertTrue($result);
    }

    public function test_sends_webhook_notification(): void
    {
        $notification = new WebhookNotification(
            url: 'https://example.com/webhook',
            payload: ['event' => 'test']
        );

        $result = $this->notifier->sendWebhook($notification);

        $this->assertTrue($result);
    }

    public function test_sends_in_app_notification(): void
    {
        $notification = new InAppNotification(
            userId: 1,
            title: 'Test Notification',
            body: 'Test body'
        );

        $result = $this->notifier->sendInApp($notification);

        $this->assertTrue($result);
    }

    public function test_returns_supported_channels(): void
    {
        $channels = $this->notifier->getSupportedChannels();

        $this->assertIsArray($channels);
        $this->assertContains('email', $channels);
        $this->assertContains('sms', $channels);
        $this->assertContains('slack', $channels);
        $this->assertContains('webhook', $channels);
        $this->assertContains('in_app', $channels);
    }
}
