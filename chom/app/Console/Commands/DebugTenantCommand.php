<?php

namespace App\Console\Commands;

use App\Models\Tenant;
use Illuminate\Console\Command;

class DebugTenantCommand extends Command
{
    protected $signature = 'debug:tenant {tenant : Tenant ID or slug}';

    protected $description = 'Debug tenant-related issues';

    public function handle(): int
    {
        $identifier = $this->argument('tenant');

        $this->components->info("Debugging tenant: {$identifier}");
        $this->newLine();

        // Find tenant by ID or slug
        $tenant = Tenant::where('id', $identifier)
            ->orWhere('slug', $identifier)
            ->first();

        if (! $tenant) {
            $this->components->error("Tenant not found: {$identifier}");

            return self::FAILURE;
        }

        // Display tenant information
        $this->components->info('Tenant Information:');
        $this->table(
            ['Property', 'Value'],
            [
                ['ID', $tenant->id],
                ['Name', $tenant->name],
                ['Slug', $tenant->slug],
                ['Tier', $tenant->tier],
                ['Status', $tenant->status],
                ['Organization ID', $tenant->organization_id],
                ['Created At', $tenant->created_at],
            ]
        );

        // Display organization
        if ($tenant->organization) {
            $this->newLine();
            $this->components->info('Organization:');
            $this->table(
                ['Property', 'Value'],
                [
                    ['ID', $tenant->organization->id],
                    ['Name', $tenant->organization->name],
                    ['Slug', $tenant->organization->slug],
                    ['Status', $tenant->organization->status],
                ]
            );
        }

        // Display users
        $users = $tenant->organization?->users ?? collect();
        $this->newLine();
        $this->components->info("Users: {$users->count()}");

        if ($users->count() > 0) {
            $this->table(
                ['ID', 'Name', 'Email', 'Role'],
                $users->map(fn ($user) => [
                    substr($user->id, 0, 8).'...',
                    $user->name,
                    $user->email,
                    $user->role,
                ])
            );
        }

        // Display VPS servers
        $vpsServers = $tenant->vpsServers ?? collect();
        $this->newLine();
        $this->components->info("VPS Servers: {$vpsServers->count()}");

        if ($vpsServers->count() > 0) {
            $this->table(
                ['ID', 'Name', 'IP Address', 'Status', 'Sites'],
                $vpsServers->map(fn ($vps) => [
                    substr($vps->id, 0, 8).'...',
                    $vps->name,
                    $vps->ip_address,
                    $vps->status,
                    $vps->sites->count(),
                ])
            );
        }

        // Display sites
        $sites = $tenant->sites ?? collect();
        $this->newLine();
        $this->components->info("Sites: {$sites->count()}");

        if ($sites->count() > 0) {
            $this->table(
                ['ID', 'Domain', 'Type', 'Status', 'VPS'],
                $sites->take(10)->map(fn ($site) => [
                    substr($site->id, 0, 8).'...',
                    $site->domain,
                    $site->type,
                    $site->status,
                    $site->vpsServer?->name ?? 'N/A',
                ])
            );

            if ($sites->count() > 10) {
                $this->line('... and '.($sites->count() - 10).' more');
            }
        }

        // Display tier limits if available
        if (method_exists($tenant, 'tierLimits') && $tenant->tierLimits) {
            $this->newLine();
            $this->components->info('Tier Limits:');
            $limits = $tenant->tierLimits;
            $this->table(
                ['Limit', 'Value', 'Current', 'Status'],
                [
                    ['Max Sites', $limits->max_sites, $sites->count(), $sites->count() >= $limits->max_sites ? 'At limit' : 'OK'],
                    ['Max Storage (GB)', $limits->max_storage_gb, round($sites->sum('disk_used_mb') / 1024, 2), 'OK'],
                    ['Max Bandwidth (GB)', $limits->max_bandwidth_gb, round($sites->sum('bandwidth_used_mb') / 1024, 2), 'OK'],
                ]
            );
        }

        // Recommendations
        $this->newLine();
        $this->components->info('Recommendations:');

        $issues = [];

        if ($tenant->status !== 'active') {
            $issues[] = "Tenant status is '{$tenant->status}' - may not be able to provision resources";
        }

        if ($users->count() === 0) {
            $issues[] = 'No users assigned to this tenant';
        }

        if ($vpsServers->where('status', 'active')->count() === 0 && $sites->count() > 0) {
            $issues[] = 'Sites exist but no active VPS servers available';
        }

        if (count($issues) > 0) {
            foreach ($issues as $issue) {
                $this->components->warn("- {$issue}");
            }
        } else {
            $this->components->info('No issues found!');
        }

        return self::SUCCESS;
    }
}
