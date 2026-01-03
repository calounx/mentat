<?php

namespace Database\Seeders;

use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    /**
     * Seed the application's database.
     */
    public function run(): void
    {
        // Seed test users with all roles
        $this->call(TestUserSeeder::class);

        // Seed test data (sites, backups, VPS servers)
        if ($this->command->confirm('Would you like to seed test data (sites, VPS, backups)?', true)) {
            $this->call(TestDataSeeder::class);
        }

        // Optional: Seed large dataset for performance testing
        if ($this->command->confirm('Would you like to seed performance test data? (WARNING: Large dataset)', false)) {
            $this->call(PerformanceTestSeeder::class);
        }
    }
}
