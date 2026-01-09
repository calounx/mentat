<?php

namespace App\Console\Commands;

use App\Models\SystemSetting;
use Illuminate\Console\Command;

class ExportSmtpConfig extends Command
{
    /**
     * The name and signature of the console command.
     *
     * @var string
     */
    protected $signature = 'smtp:export
                            {--format=shell : Output format (shell, yaml, json)}
                            {--file= : Output to file instead of stdout}';

    /**
     * The console command description.
     *
     * @var string
     */
    protected $description = 'Export SMTP configuration from database for deployment scripts and Alertmanager';

    /**
     * Execute the console command.
     */
    public function handle(): int
    {
        try {
            // Get all SMTP settings from database
            $settings = [
                'mailer' => SystemSetting::get('mail.mailer', 'smtp'),
                'host' => SystemSetting::get('mail.host', '127.0.0.1'),
                'port' => SystemSetting::get('mail.port', 587),
                'username' => SystemSetting::get('mail.username', ''),
                'password' => SystemSetting::get('mail.password', ''),
                'encryption' => SystemSetting::get('mail.encryption', 'tls'),
                'from_address' => SystemSetting::get('mail.from_address', 'noreply@example.com'),
                'from_name' => SystemSetting::get('mail.from_name', 'CHOM'),
            ];

            $format = $this->option('format');
            $file = $this->option('file');

            $output = match ($format) {
                'yaml' => $this->formatYaml($settings),
                'json' => $this->formatJson($settings),
                default => $this->formatShell($settings),
            };

            if ($file) {
                file_put_contents($file, $output);
                $this->info("SMTP configuration exported to: {$file}");
            } else {
                $this->line($output);
            }

            return Command::SUCCESS;
        } catch (\Exception $e) {
            $this->error('Failed to export SMTP configuration: ' . $e->getMessage());
            return Command::FAILURE;
        }
    }

    private function formatShell(array $settings): string
    {
        $lines = [
            '# SMTP Configuration - Generated from database',
            '# Source: system_settings table',
            '',
            "MAIL_MAILER=\"{$settings['mailer']}\"",
            "MAIL_HOST=\"{$settings['host']}\"",
            "MAIL_PORT=\"{$settings['port']}\"",
            "MAIL_USERNAME=\"{$settings['username']}\"",
            "MAIL_PASSWORD=\"{$settings['password']}\"",
            "MAIL_ENCRYPTION=\"{$settings['encryption']}\"",
            "MAIL_FROM_ADDRESS=\"{$settings['from_address']}\"",
            "MAIL_FROM_NAME=\"{$settings['from_name']}\"",
        ];

        return implode("\n", $lines) . "\n";
    }

    private function formatYaml(array $settings): string
    {
        // Format for Alertmanager YAML config
        $encryption = $settings['encryption'] === 'null' ? 'false' : 'true';
        $requireTls = $settings['encryption'] !== 'null';

        return <<<YAML
# SMTP Configuration for Alertmanager
# Generated from system_settings database
global:
  smtp_smarthost: '{$settings['host']}:{$settings['port']}'
  smtp_from: '{$settings['from_address']}'
  smtp_auth_username: '{$settings['username']}'
  smtp_auth_password: '{$settings['password']}'
  smtp_require_tls: {$requireTls}

YAML;
    }

    private function formatJson(array $settings): string
    {
        return json_encode($settings, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
    }
}
