<?php

namespace Database\Factories;

use App\Models\Site;
use App\Models\SiteBackup;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends \Illuminate\Database\Eloquent\Factories\Factory<\App\Models\SiteBackup>
 */
class SiteBackupFactory extends Factory
{
    protected $model = SiteBackup::class;

    /**
     * Define the model's default state.
     *
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $backupTypes = ['full', 'database', 'files'];
        $retentionDays = fake()->randomElement([7, 14, 30, 60, 90]);

        return [
            'site_id' => Site::factory(),
            'backup_type' => fake()->randomElement($backupTypes),
            'storage_path' => '/backups/' . fake()->uuid() . '.tar.gz',
            'size_bytes' => fake()->numberBetween(10485760, 1073741824), // 10MB to 1GB
            'checksum' => hash('sha256', Str::random(32)),
            'retention_days' => $retentionDays,
            'expires_at' => now()->addDays($retentionDays),
            'status' => 'completed',
        ];
    }

    /**
     * Indicate that the backup is in progress.
     */
    public function inProgress(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'in_progress',
            'storage_path' => null,
            'size_bytes' => 0,
            'checksum' => null,
        ]);
    }

    /**
     * Indicate that the backup has failed.
     */
    public function failed(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'failed',
            'storage_path' => null,
            'size_bytes' => 0,
            'checksum' => null,
        ]);
    }

    /**
     * Indicate that the backup has expired.
     */
    public function expired(): static
    {
        return $this->state(fn (array $attributes) => [
            'expires_at' => now()->subDays(5),
            'retention_days' => 7,
        ]);
    }

    /**
     * Set a specific backup type.
     */
    public function ofType(string $type): static
    {
        return $this->state(fn (array $attributes) => [
            'backup_type' => $type,
        ]);
    }

    /**
     * Set a specific site.
     */
    public function forSite(Site $site): static
    {
        return $this->state(fn (array $attributes) => [
            'site_id' => $site->id,
        ]);
    }

    /**
     * Set a specific retention period.
     */
    public function withRetention(int $days): static
    {
        return $this->state(fn (array $attributes) => [
            'retention_days' => $days,
            'expires_at' => now()->addDays($days),
        ]);
    }

    /**
     * Set a specific size.
     */
    public function withSize(int $bytes): static
    {
        return $this->state(fn (array $attributes) => [
            'size_bytes' => $bytes,
        ]);
    }
}
