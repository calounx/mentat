<?php

namespace App\Services\Alerting;

use Exception;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;

class AlertManager
{
    protected array $alertHistory = [];

    /**
     * Send an alert
     */
    public function alert(
        string $rule,
        string $message,
        ?string $severity = null,
        array $context = []
    ): void {
        if (! config('alerting.enabled')) {
            return;
        }

        // Get rule configuration
        $ruleConfig = config("alerting.rules.{$rule}");

        if (! $ruleConfig || ! ($ruleConfig['enabled'] ?? true)) {
            return;
        }

        $severity = $severity ?? $ruleConfig['severity'] ?? 'info';

        // Check if in quiet hours
        if ($this->isQuietHours($severity)) {
            Log::info('Alert suppressed due to quiet hours', [
                'rule' => $rule,
                'severity' => $severity,
            ]);

            return;
        }

        // Check throttling
        if ($this->isThrottled($rule)) {
            Log::info('Alert throttled', ['rule' => $rule]);

            return;
        }

        // Build alert data
        $alert = [
            'rule' => $rule,
            'severity' => $severity,
            'message' => $message,
            'description' => $ruleConfig['description'] ?? $message,
            'context' => $this->buildContext($context),
            'timestamp' => now()->toIso8601String(),
        ];

        // Get channels for this severity
        $channels = config("alerting.channels.{$severity}", []);

        // Send to each channel
        foreach ($channels as $channel) {
            try {
                $this->sendToChannel($channel, $alert);
            } catch (Exception $e) {
                Log::error("Failed to send alert to {$channel}", [
                    'error' => $e->getMessage(),
                    'alert' => $alert,
                ]);
            }
        }

        // Store alert history
        $this->storeAlert($alert);

        // Update throttle cache
        $this->updateThrottle($rule);
    }

    /**
     * Send critical alert
     */
    public function critical(string $rule, string $message, array $context = []): void
    {
        $this->alert($rule, $message, 'critical', $context);
    }

    /**
     * Send warning alert
     */
    public function warning(string $rule, string $message, array $context = []): void
    {
        $this->alert($rule, $message, 'warning', $context);
    }

    /**
     * Send info alert
     */
    public function info(string $rule, string $message, array $context = []): void
    {
        $this->alert($rule, $message, 'info', $context);
    }

    /**
     * Check if an alert condition is met
     */
    public function checkCondition(string $rule, float $value): bool
    {
        $ruleConfig = config("alerting.rules.{$rule}");

        if (! $ruleConfig || ! ($ruleConfig['enabled'] ?? true)) {
            return false;
        }

        $threshold = $ruleConfig['threshold'] ?? 0;

        return $value >= $threshold;
    }

    /**
     * Send alert to specific channel
     */
    protected function sendToChannel(string $channel, array $alert): void
    {
        match ($channel) {
            'slack' => $this->sendToSlack($alert),
            'email' => $this->sendToEmail($alert),
            'pagerduty' => $this->sendToPagerDuty($alert),
            default => Log::warning("Unknown alert channel: {$channel}"),
        };
    }

    /**
     * Send alert to Slack
     */
    protected function sendToSlack(array $alert): void
    {
        if (! config('alerting.slack.enabled')) {
            return;
        }

        $webhookUrl = config('alerting.slack.webhook_url');

        if (! $webhookUrl) {
            Log::warning('Slack webhook URL not configured');

            return;
        }

        $color = match ($alert['severity']) {
            'critical' => 'danger',
            'warning' => 'warning',
            'info' => 'good',
            default => '#808080',
        };

        $emoji = match ($alert['severity']) {
            'critical' => ':rotating_light:',
            'warning' => ':warning:',
            'info' => ':information_source:',
            default => ':bell:',
        };

        $payload = [
            'username' => config('alerting.slack.username', 'Alert Bot'),
            'icon_emoji' => config('alerting.slack.icon_emoji', ':rotating_light:'),
            'channel' => config('alerting.slack.channel'),
            'text' => "{$emoji} *{$alert['severity']}* Alert: {$alert['rule']}",
            'attachments' => [
                [
                    'color' => $color,
                    'title' => $alert['description'],
                    'text' => $alert['message'],
                    'fields' => $this->formatContextForSlack($alert['context']),
                    'footer' => config('app.name'),
                    'ts' => now()->timestamp,
                ],
            ],
        ];

        Http::post($webhookUrl, $payload);
    }

    /**
     * Send alert to email
     */
    protected function sendToEmail(array $alert): void
    {
        if (! config('alerting.email.enabled')) {
            return;
        }

        $recipients = config('alerting.email.recipients', []);

        if (empty($recipients)) {
            Log::warning('No email recipients configured for alerts');

            return;
        }

        $subject = "[{$alert['severity']}] {$alert['rule']}: {$alert['description']}";

        Mail::send('emails.alert', ['alert' => $alert], function ($message) use ($recipients, $subject) {
            $message->to($recipients)
                ->subject($subject)
                ->from(
                    config('alerting.email.from.address'),
                    config('alerting.email.from.name')
                );
        });
    }

    /**
     * Send alert to PagerDuty
     */
    protected function sendToPagerDuty(array $alert): void
    {
        if (! config('alerting.pagerduty.enabled')) {
            return;
        }

        $integrationKey = config('alerting.pagerduty.integration_key');

        if (! $integrationKey) {
            Log::warning('PagerDuty integration key not configured');

            return;
        }

        $severity = match ($alert['severity']) {
            'critical' => 'critical',
            'warning' => 'warning',
            'info' => 'info',
            default => 'error',
        };

        $payload = [
            'routing_key' => $integrationKey,
            'event_action' => 'trigger',
            'dedup_key' => $alert['rule'],
            'payload' => [
                'summary' => $alert['description'],
                'severity' => $severity,
                'source' => config('app.url'),
                'component' => config('app.name'),
                'custom_details' => $alert['context'],
            ],
        ];

        Http::post(config('alerting.pagerduty.api_url'), $payload);
    }

    /**
     * Check if currently in quiet hours
     */
    protected function isQuietHours(string $severity): bool
    {
        if (! config('alerting.quiet_hours.enabled')) {
            return false;
        }

        $suppressedSeverities = config('alerting.quiet_hours.suppress_severities', []);

        if (! in_array($severity, $suppressedSeverities)) {
            return false;
        }

        $timezone = config('alerting.quiet_hours.timezone', 'UTC');
        $now = now($timezone);
        $start = now($timezone)->setTimeFromTimeString(config('alerting.quiet_hours.start'));
        $end = now($timezone)->setTimeFromTimeString(config('alerting.quiet_hours.end'));

        // Handle overnight quiet hours
        if ($start->greaterThan($end)) {
            return $now->greaterThanOrEqualTo($start) || $now->lessThan($end);
        }

        return $now->between($start, $end);
    }

    /**
     * Check if alert is throttled
     */
    protected function isThrottled(string $rule): bool
    {
        if (! config('alerting.throttling.enabled')) {
            return false;
        }

        $window = config('alerting.throttling.window', 3600);
        $maxAlerts = config('alerting.throttling.max_alerts_per_rule', 3);
        $cacheKey = "alert_throttle:{$rule}";

        $count = Cache::get($cacheKey, 0);

        return $count >= $maxAlerts;
    }

    /**
     * Update throttle counter
     */
    protected function updateThrottle(string $rule): void
    {
        if (! config('alerting.throttling.enabled')) {
            return;
        }

        $window = config('alerting.throttling.window', 3600);
        $cacheKey = "alert_throttle:{$rule}";

        Cache::put(
            $cacheKey,
            Cache::get($cacheKey, 0) + 1,
            $window
        );
    }

    /**
     * Build alert context
     */
    protected function buildContext(array $customContext = []): array
    {
        $context = $customContext;

        if (config('alerting.context.include_environment')) {
            $context['environment'] = config('app.env');
            $context['app_name'] = config('app.name');
            $context['app_url'] = config('app.url');
        }

        if (config('alerting.context.include_server_info')) {
            $context['php_version'] = PHP_VERSION;
            $context['laravel_version'] = app()->version();
            $context['server_time'] = now()->toDateTimeString();
        }

        if (config('alerting.context.include_recent_logs')) {
            $context['recent_logs'] = $this->getRecentLogs();
        }

        return $context;
    }

    /**
     * Get recent log entries
     */
    protected function getRecentLogs(): array
    {
        $logFile = storage_path('logs/laravel.log');
        $lines = config('alerting.context.log_lines', 20);

        if (! file_exists($logFile)) {
            return [];
        }

        $logs = [];
        $handle = fopen($logFile, 'r');

        if ($handle) {
            // Read last N lines
            fseek($handle, -1, SEEK_END);
            $lineCount = 0;
            $text = '';

            while (ftell($handle) > 0 && $lineCount < $lines) {
                $char = fgetc($handle);

                if ($char === "\n") {
                    $lineCount++;
                }

                $text = $char.$text;
                fseek($handle, -2, SEEK_CUR);
            }

            fclose($handle);

            $logs = array_filter(explode("\n", $text));
        }

        return $logs;
    }

    /**
     * Format context for Slack
     */
    protected function formatContextForSlack(array $context): array
    {
        $fields = [];

        foreach ($context as $key => $value) {
            if ($key === 'recent_logs') {
                continue; // Skip logs in Slack fields
            }

            if (is_array($value)) {
                $value = json_encode($value);
            }

            $fields[] = [
                'title' => ucwords(str_replace('_', ' ', $key)),
                'value' => $value,
                'short' => strlen($value) < 40,
            ];
        }

        return $fields;
    }

    /**
     * Store alert in database or cache
     */
    protected function storeAlert(array $alert): void
    {
        if (! config('alerting.storage.enabled')) {
            return;
        }

        $driver = config('alerting.storage.driver', 'database');

        match ($driver) {
            'database' => $this->storeInDatabase($alert),
            'cache' => $this->storeInCache($alert),
            default => null,
        };
    }

    /**
     * Store alert in database
     */
    protected function storeInDatabase(array $alert): void
    {
        // This would store in an alerts table
        // For now, just log it
        Log::channel('audit')->info('Alert triggered', $alert);
    }

    /**
     * Store alert in cache
     */
    protected function storeInCache(array $alert): void
    {
        $cacheKey = 'alerts:history:'.now()->timestamp;
        $retention = config('alerting.storage.retention_days', 90) * 86400;

        Cache::put($cacheKey, $alert, $retention);
    }
}
