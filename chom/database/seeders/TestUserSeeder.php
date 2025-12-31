<?php

namespace Database\Seeders;

use App\Models\Organization;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class TestUserSeeder extends Seeder
{
    /**
     * Seed test users for development.
     * Creates users with all roles for testing purposes.
     */
    public function run(): void
    {
        $this->command->info('Creating test users...');

        // Create test organization
        $org = Organization::firstOrCreate(
            ['name' => 'Test Organization'],
            [
                'slug' => 'test-org',
                'status' => 'active',
            ]
        );

        // Create default tenant for the organization
        $tenant = Tenant::firstOrCreate(
            [
                'organization_id' => $org->id,
                'name' => 'Test Tenant'
            ],
            [
                'slug' => 'test-tenant',
                'tier' => 'starter',
                'status' => 'active',
            ]
        );

        // Set as default tenant
        $org->update(['default_tenant_id' => $tenant->id]);

        // Create test users with different roles
        $testUsers = [
            [
                'name' => 'Owner User',
                'email' => 'owner@chom.test',
                'role' => 'owner',
                'description' => 'Full system access, billing management'
            ],
            [
                'name' => 'Admin User',
                'email' => 'admin@chom.test',
                'role' => 'admin',
                'description' => 'Site management, user management, no billing'
            ],
            [
                'name' => 'Member User',
                'email' => 'member@chom.test',
                'role' => 'member',
                'description' => 'Site management, deployment, backups'
            ],
            [
                'name' => 'Viewer User',
                'email' => 'viewer@chom.test',
                'role' => 'viewer',
                'description' => 'Read-only access to sites and stats'
            ],
        ];

        foreach ($testUsers as $userData) {
            $user = User::firstOrCreate(
                ['email' => $userData['email']],
                [
                    'name' => $userData['name'],
                    'password' => Hash::make('password'),
                    'organization_id' => $org->id,
                    'role' => $userData['role'],
                    'email_verified_at' => now(),
                ]
            );

            $this->command->info("✓ Created {$userData['role']}: {$userData['email']} / password");
            $this->command->line("  └─ {$userData['description']}");
        }

        // Create additional organization for multi-tenancy testing
        $org2 = Organization::firstOrCreate(
            ['name' => 'Acme Corporation'],
            [
                'slug' => 'acme-corp',
                'status' => 'active',
            ]
        );

        $tenant2 = Tenant::firstOrCreate(
            [
                'organization_id' => $org2->id,
                'name' => 'Acme Tenant'
            ],
            [
                'slug' => 'acme-tenant',
                'tier' => 'pro',
                'status' => 'active',
            ]
        );

        $org2->update(['default_tenant_id' => $tenant2->id]);

        User::firstOrCreate(
            ['email' => 'john@acme.test'],
            [
                'name' => 'John Doe',
                'password' => Hash::make('password'),
                'organization_id' => $org2->id,
                'role' => 'owner',
                'email_verified_at' => now(),
            ]
        );

        $this->command->info('✓ Created john@acme.test / password (Acme Corp)');

        $this->command->newLine();
        $this->command->info('Test users created successfully!');
    }
}
