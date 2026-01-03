<?php

namespace Database\Factories;

use App\Models\Site;
use App\Models\SiteBackup;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

class SiteBackupFactory extends Factory
{
    protected $model = SiteBackup::class;

    public function definition(): array
    {
        return [
            'id' => Str::uuid()->toString(),
            'site_id' => Site::factory(),
            'backup_type' => 'full',
            'storage_path' => 'backups/' . Str::uuid() . '.tar.gz',
            'size_bytes' => $this->faker->numberBetween(1000000, 100000000),
            'checksum' => md5($this->faker->text()),
            'status' => 'completed',
            'retention_days' => 30,
            'expires_at' => now()->addDays(30),
            'completed_at' => now(),
            'failed_at' => null,
            'error_message' => null,
            'created_at' => now(),
            'updated_at' => now(),
        ];
    }

    public function pending(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'pending',
            'completed_at' => null,
        ]);
    }

    public function failed(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'failed',
            'completed_at' => null,
            'failed_at' => now(),
            'error_message' => 'Backup failed due to timeout',
        ]);
    }

    public function database(): static
    {
        return $this->state(fn (array $attributes) => [
            'backup_type' => 'database',
        ]);
    }

    public function files(): static
    {
        return $this->state(fn (array $attributes) => [
            'backup_type' => 'files',
        ]);
    }
}
