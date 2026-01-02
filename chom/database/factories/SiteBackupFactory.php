<?php

namespace Database\Factories;

use App\Models\Site;
use App\Models\SiteBackup;
use Illuminate\Database\Eloquent\Factories\Factory;

class SiteBackupFactory extends Factory
{
    protected $model = SiteBackup::class;

    public function definition(): array
    {
        return [
            'site_id' => Site::factory(),
            'filename' => 'backup-'.now()->format('Y-m-d-His').'.tar.gz',
            'size_mb' => $this->faker->numberBetween(10, 1000),
            'status' => 'completed',
            'backup_type' => $this->faker->randomElement(['manual', 'scheduled']),
            'storage_path' => '/backups/'.$this->faker->uuid().'.tar.gz',
            'completed_at' => now(),
        ];
    }

    public function completed(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'completed',
            'completed_at' => now(),
        ]);
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
            'error_message' => 'Backup operation failed',
            'completed_at' => null,
        ]);
    }
}
