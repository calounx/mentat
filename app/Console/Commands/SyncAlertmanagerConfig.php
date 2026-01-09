<?php

namespace App\Console\Commands;

use App\Models\SystemSetting;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Process;

class SyncAlertmanagerConfig extends Command
{
    /**
     * The name and signature of the console command.
     *
     * @var string
     */
    protected $signature = 'alertmanager:sync
                            {--host=mentat.arewel.com : Mentat host to sync to}
                            {--user=stilgar : SSH user for mentat}
                            {--dry-run : Show what would be done without making changes}';

    /**
     * The console command description.
     *
     * @var string
     */
    protected $description = 'Sync SMTP configuration to Alertmanager on mentat server';

    /**
     * Execute the console command.
     */
    public function handle(): int
    {
        $host = $this->option('host');
        $user = $this->option('user');
        $dryRun = $this->option('dry-run');

        $this->info("Syncing Alertmanager SMTP configuration to {$user}@{$host}");

        // Get SMTP settings from database
        $this->info('Fetching SMTP settings from database...');
        $settings = [
            'from_address' => SystemSetting::get('mail.from_address', 'noreply@example.com'),
            'host' => SystemSetting::get('mail.host', '127.0.0.1'),
            'port' => SystemSetting::get('mail.port', 587),
            'username' => SystemSetting::get('mail.username', ''),
            'password' => SystemSetting::get('mail.password', ''),
            'encryption' => SystemSetting::get('mail.encryption', 'tls'),
        ];

        $this->table(
            ['Setting', 'Value'],
            [
                ['From Address', $settings['from_address']],
                ['SMTP Host', $settings['host']],
                ['SMTP Port', $settings['port']],
                ['Username', $settings['username'] ?: '(none)'],
                ['Password', $settings['password'] ? '********' : '(none)'],
                ['Encryption', $settings['encryption']],
            ]
        );

        if ($dryRun) {
            $this->warn('DRY RUN - No changes will be made');
            return Command::SUCCESS;
        }

        // Build SSH command to update alertmanager.yml
        $smarthost = "{$settings['host']}:{$settings['port']}";
        $requireTls = ($settings['encryption'] !== 'null' && $settings['encryption'] !== '') ? 'true' : 'false';

        $sshCommand = implode(' && ', [
            // Backup current config
            'sudo cp /etc/observability/alertmanager/alertmanager.yml /etc/observability/alertmanager/alertmanager.yml.backup',

            // Update SMTP settings using sed
            "sudo sed -i 's|smtp_from:.*|smtp_from: \\'{$settings['from_address']}\\'|g' /etc/observability/alertmanager/alertmanager.yml",
            "sudo sed -i 's|smtp_smarthost:.*|smtp_smarthost: \\'{$smarthost}\\'|g' /etc/observability/alertmanager/alertmanager.yml",
            "sudo sed -i 's|smtp_auth_username:.*|smtp_auth_username: \\'{$settings['username']}\\'|g' /etc/observability/alertmanager/alertmanager.yml",
            "sudo sed -i 's|smtp_auth_password:.*|smtp_auth_password: \\'{$settings['password']}\\'|g' /etc/observability/alertmanager/alertmanager.yml",
            "sudo sed -i 's|smtp_require_tls:.*|smtp_require_tls: {$requireTls}|g' /etc/observability/alertmanager/alertmanager.yml",

            // Validate config
            'sudo /opt/observability/bin/amtool check-config /etc/observability/alertmanager/alertmanager.yml',

            // Reload service
            'sudo systemctl reload alertmanager',

            // Verify service is running
            'sudo systemctl is-active alertmanager',
        ]);

        $fullCommand = "ssh {$user}@{$host} \"{$sshCommand}\"";

        $this->info('Connecting to mentat server...');

        $result = Process::run($fullCommand);

        if ($result->successful()) {
            $this->info('✓ Alertmanager configuration synced successfully');
            $this->line($result->output());
            return Command::SUCCESS;
        }

        $this->error('✗ Failed to sync Alertmanager configuration');
        $this->error($result->errorOutput());

        $this->newLine();
        $this->warn('Troubleshooting:');
        $this->line('1. Check SSH connection: ssh ' . $user . '@' . $host);
        $this->line('2. Verify alertmanager service: sudo systemctl status alertmanager');
        $this->line('3. Check config syntax: sudo /opt/observability/bin/amtool check-config /etc/observability/alertmanager/alertmanager.yml');
        $this->line('4. View logs: sudo journalctl -u alertmanager -n 50');

        return Command::FAILURE;
    }
}
