<?php

namespace Database\Seeders;

use App\Models\Organization;
use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\Tenant;
use App\Models\User;
use App\Models\VpsServer;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class PerformanceTestSeeder extends Seeder
{
    /**
     * Seed large dataset for performance testing.
     * Creates hundreds of sites, thousands of backups, and hundreds of users.
     */
    public function run(): void
    {
        $this->command->warn('⚠️  This seeder creates a LARGE dataset for performance testing!');
        $this->command->warn('   It will create:');
        $this->command->warn('   - 50 organizations');
        $this->command->warn('   - 100 tenants');
        $this->command->warn('   - 200 users');
        $this->command->warn('   - 50 VPS servers');
        $this->command->warn('   - 500 sites');
        $this->command->warn('   - 2000+ backups');
        $this->command->newLine();

        if (!$this->command->confirm('Do you want to continue?', false)) {
            $this->command->info('Cancelled.');
            return;
        }

        $this->command->info('Starting performance test data generation...');
        $this->command->newLine();

        // Create organizations
        $this->command->info('[1/6] Creating organizations...');
        $organizations = [];
        for ($i = 1; $i <= 50; $i++) {
            $organizations[] = Organization::create([
                'name' => "Organization {$i}",
                'slug' => "org-{$i}",
                'status' => 'active',
            ]);

            if ($i % 10 === 0) {
                $this->command->line("  Progress: {$i}/50");
            }
        }
        $this->command->info("✓ Created 50 organizations");
        $this->command->newLine();

        // Create tenants
        $this->command->info('[2/6] Creating tenants...');
        $tenants = [];
        $tiers = ['starter', 'pro', 'enterprise'];
        for ($i = 1; $i <= 100; $i++) {
            $org = $organizations[array_rand($organizations)];
            $tenant = Tenant::create([
                'organization_id' => $org->id,
                'name' => "Tenant {$i}",
                'slug' => "tenant-{$i}",
                'tier' => $tiers[array_rand($tiers)],
                'status' => 'active',
            ]);
            $tenants[] = $tenant;

            if ($i % 20 === 0) {
                $this->command->line("  Progress: {$i}/100");
            }
        }
        $this->command->info("✓ Created 100 tenants");
        $this->command->newLine();

        // Create users
        $this->command->info('[3/6] Creating users...');
        $roles = ['owner', 'admin', 'member', 'viewer'];
        for ($i = 1; $i <= 200; $i++) {
            $org = $organizations[array_rand($organizations)];
            User::create([
                'name' => "Test User {$i}",
                'email' => "user{$i}@test.chom",
                'password' => Hash::make('password'),
                'organization_id' => $org->id,
                'role' => $roles[array_rand($roles)],
                'email_verified_at' => now(),
            ]);

            if ($i % 40 === 0) {
                $this->command->line("  Progress: {$i}/200");
            }
        }
        $this->command->info("✓ Created 200 users");
        $this->command->newLine();

        // Create VPS servers
        $this->command->info('[4/6] Creating VPS servers...');
        $vpsServers = [];
        $providers = ['digitalocean', 'linode', 'vultr', 'aws', 'hetzner'];
        $regions = ['us-east', 'us-west', 'eu-west', 'eu-central', 'ap-southeast'];
        $statuses = ['active', 'active', 'active', 'provisioning', 'maintenance'];

        for ($i = 1; $i <= 50; $i++) {
            $tenant = $tenants[array_rand($tenants)];
            $vpsServers[] = VpsServer::create([
                'tenant_id' => $tenant->id,
                'name' => "VPS-{$i}",
                'hostname' => "vps-{$i}.example.com",
                'ip_address' => "192.0.2." . ($i % 255),
                'provider' => $providers[array_rand($providers)],
                'region' => $regions[array_rand($regions)],
                'vcpus' => [2, 4, 8][array_rand([2, 4, 8])],
                'memory_mb' => [2048, 4096, 8192][array_rand([2048, 4096, 8192])],
                'disk_gb' => [40, 80, 160][array_rand([40, 80, 160])],
                'ssh_port' => 22,
                'status' => $statuses[array_rand($statuses)],
                'cpanel_installed' => true,
                'cpanel_version' => '110.0.15',
                'os' => 'AlmaLinux 8',
                'monitoring_enabled' => true,
                'last_monitored_at' => now()->subMinutes(rand(1, 60)),
            ]);

            if ($i % 10 === 0) {
                $this->command->line("  Progress: {$i}/50");
            }
        }
        $this->command->info("✓ Created 50 VPS servers");
        $this->command->newLine();

        // Create sites
        $this->command->info('[5/6] Creating sites...');
        $sites = [];
        $types = ['wordpress', 'woocommerce', 'laravel', 'html', 'static'];
        $phpVersions = ['7.4', '8.0', '8.1', '8.2'];
        $activeVpsServers = array_filter($vpsServers, fn($vps) => $vps->status === 'active');

        for ($i = 1; $i <= 500; $i++) {
            $tenant = $tenants[array_rand($tenants)];
            $vps = $activeVpsServers[array_rand($activeVpsServers)] ?? $vpsServers[array_rand($vpsServers)];

            $site = Site::create([
                'tenant_id' => $tenant->id,
                'vps_server_id' => $vps->id,
                'domain' => "site-{$i}.example.test",
                'cpanel_account' => "site{$i}",
                'type' => $types[array_rand($types)],
                'php_version' => $phpVersions[array_rand($phpVersions)],
                'status' => rand(1, 100) > 10 ? 'active' : 'suspended',
                'disk_used_mb' => rand(100, 5000),
                'bandwidth_used_mb' => rand(500, 50000),
                'ssl_enabled' => rand(1, 100) > 20,
                'ssl_provider' => 'letsencrypt',
                'ssl_expires_at' => now()->addMonths(rand(1, 3)),
                'last_deployed_at' => now()->subDays(rand(1, 90)),
            ]);
            $sites[] = $site;

            if ($i % 100 === 0) {
                $this->command->line("  Progress: {$i}/500");
            }
        }
        $this->command->info("✓ Created 500 sites");
        $this->command->newLine();

        // Create backups
        $this->command->info('[6/6] Creating backups...');
        $backupTypes = ['full', 'database', 'files'];
        $backupStatuses = ['completed', 'completed', 'completed', 'failed', 'in_progress'];
        $backupCount = 0;

        // Create 4-5 backups per site on average
        for ($i = 0; $i < 500; $i++) {
            $site = $sites[$i];
            $numBackups = rand(3, 6);

            for ($j = 0; $j < $numBackups; $j++) {
                $createdAt = now()->subDays($j * rand(3, 10));
                $status = $backupStatuses[array_rand($backupStatuses)];

                SiteBackup::create([
                    'site_id' => $site->id,
                    'type' => $backupTypes[array_rand($backupTypes)],
                    'status' => $status,
                    'size_mb' => rand(50, 2000),
                    'storage_path' => "backups/{$site->domain}/" . $createdAt->format('Y-m-d') . ".tar.gz",
                    'created_at' => $createdAt,
                    'completed_at' => $status === 'completed' ? $createdAt->addMinutes(rand(5, 60)) : null,
                ]);
                $backupCount++;
            }

            if (($i + 1) % 100 === 0) {
                $this->command->line("  Progress: " . ($i + 1) . "/500 sites");
            }
        }
        $this->command->info("✓ Created {$backupCount} backups");
        $this->command->newLine();

        // Summary
        $this->command->info('========================================');
        $this->command->info('Performance Test Data Summary:');
        $this->command->info('========================================');
        $this->command->info("Organizations: 50");
        $this->command->info("Tenants:       100");
        $this->command->info("Users:         200");
        $this->command->info("VPS Servers:   50");
        $this->command->info("Sites:         500");
        $this->command->info("Backups:       {$backupCount}");
        $this->command->info('========================================');
        $this->command->newLine();
        $this->command->info('✓ Performance test data created successfully!');
        $this->command->warn('⚠️  Remember to clear this data before going to production!');
    }
}
