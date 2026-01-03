<?php

namespace Database\Seeders;

use App\Models\Organization;
use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\Tenant;
use App\Models\VpsServer;
use Illuminate\Database\Seeder;

class TestDataSeeder extends Seeder
{
    /**
     * Seed test data for development.
     * Creates sample sites, backups, and VPS servers.
     */
    public function run(): void
    {
        $this->command->info('Creating test data...');

        // Get test organization and tenant
        $org = Organization::where('slug', 'test-org')->first();
        $tenant = Tenant::where('slug', 'test-tenant')->first();

        if (! $org || ! $tenant) {
            $this->command->error('Test organization not found. Run TestUserSeeder first.');

            return;
        }

        $this->command->info('Creating VPS servers...');

        // Create test VPS servers
        $vpsServers = [
            [
                'name' => 'VPS-NYC-01',
                'hostname' => 'vps-nyc-01.example.com',
                'ip_address' => '192.0.2.10',
                'provider' => 'digitalocean',
                'region' => 'nyc3',
                'vcpus' => 2,
                'memory_mb' => 4096,
                'disk_gb' => 80,
                'status' => 'active',
            ],
            [
                'name' => 'VPS-SFO-01',
                'hostname' => 'vps-sfo-01.example.com',
                'ip_address' => '192.0.2.20',
                'provider' => 'linode',
                'region' => 'us-west',
                'vcpus' => 4,
                'memory_mb' => 8192,
                'disk_gb' => 160,
                'status' => 'active',
            ],
            [
                'name' => 'VPS-LON-01',
                'hostname' => 'vps-lon-01.example.com',
                'ip_address' => '192.0.2.30',
                'provider' => 'vultr',
                'region' => 'london',
                'vcpus' => 2,
                'memory_mb' => 2048,
                'disk_gb' => 40,
                'status' => 'provisioning',
            ],
        ];

        foreach ($vpsServers as $vpsData) {
            $vps = VpsServer::firstOrCreate(
                ['hostname' => $vpsData['hostname']],
                array_merge($vpsData, [
                    'tenant_id' => $tenant->id,
                    'ssh_port' => 22,
                    'cpanel_installed' => true,
                    'cpanel_version' => '110.0.15',
                    'os' => 'AlmaLinux 8',
                    'monitoring_enabled' => true,
                    'last_monitored_at' => now(),
                ])
            );

            $this->command->info("✓ Created VPS: {$vpsData['name']} ({$vpsData['status']})");
        }

        $this->command->newLine();
        $this->command->info('Creating test sites...');

        // Get first active VPS
        $vps = VpsServer::where('status', 'active')->first();

        if (! $vps) {
            $this->command->warn('No active VPS servers available. Skipping site creation.');

            return;
        }

        // Create test sites
        $sites = [
            [
                'domain' => 'example-blog.test',
                'type' => 'wordpress',
                'status' => 'active',
            ],
            [
                'domain' => 'shop.example.test',
                'type' => 'woocommerce',
                'status' => 'active',
            ],
            [
                'domain' => 'app.example.test',
                'type' => 'laravel',
                'status' => 'active',
            ],
            [
                'domain' => 'staging.example.test',
                'type' => 'wordpress',
                'status' => 'active',
            ],
            [
                'domain' => 'maintenance.example.test',
                'type' => 'html',
                'status' => 'suspended',
            ],
        ];

        foreach ($sites as $siteData) {
            $site = Site::firstOrCreate(
                ['domain' => $siteData['domain']],
                array_merge($siteData, [
                    'tenant_id' => $tenant->id,
                    'vps_server_id' => $vps->id,
                    'cpanel_account' => str_replace(['.', '-'], '', explode('.', $siteData['domain'])[0]),
                    'php_version' => '8.2',
                    'disk_used_mb' => rand(100, 2000),
                    'bandwidth_used_mb' => rand(500, 5000),
                    'ssl_enabled' => true,
                    'ssl_provider' => 'letsencrypt',
                    'ssl_expires_at' => now()->addMonths(3),
                    'last_deployed_at' => now()->subDays(rand(1, 30)),
                ])
            );

            $this->command->info("✓ Created site: {$siteData['domain']} ({$siteData['type']})");

            // Create backups for active sites
            if ($site->status === 'active') {
                $this->createBackupsForSite($site);
            }
        }

        $this->command->newLine();
        $this->command->info('Test data created successfully!');
    }

    /**
     * Create sample backups for a site.
     */
    private function createBackupsForSite(Site $site): void
    {
        $backupTypes = ['full', 'database', 'files'];
        $backupCount = rand(2, 5);

        for ($i = 0; $i < $backupCount; $i++) {
            $createdAt = now()->subDays($i * 7);
            $type = $backupTypes[array_rand($backupTypes)];

            SiteBackup::firstOrCreate(
                [
                    'site_id' => $site->id,
                    'created_at' => $createdAt,
                ],
                [
                    'type' => $type,
                    'status' => 'completed',
                    'size_mb' => rand(50, 1000),
                    'storage_path' => "backups/{$site->domain}/".$createdAt->format('Y-m-d')."_{$type}.tar.gz",
                    'completed_at' => $createdAt->addMinutes(rand(5, 30)),
                ]
            );
        }

        $this->command->line("  └─ Created {$backupCount} backups");
    }
}
