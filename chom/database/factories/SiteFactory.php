<?php

namespace Database\Factories;

use App\Models\Site;
use App\Models\Tenant;
use App\Models\VpsServer;
use Illuminate\Database\Eloquent\Factories\Factory;

class SiteFactory extends Factory
{
    protected $model = Site::class;

    public function definition(): array
    {
        return [
            'tenant_id' => Tenant::factory(),
            'vps_id' => VpsServer::factory(),
            'domain' => $this->faker->unique()->domainName(),
            'site_type' => $this->faker->randomElement(['wordpress', 'html', 'laravel']),
            'php_version' => $this->faker->randomElement(['8.2', '8.4']),
            'ssl_enabled' => $this->faker->boolean(80),
            'ssl_expires_at' => $this->faker->optional()->dateTimeBetween('now', '+90 days'),
            'status' => $this->faker->randomElement(['creating', 'active', 'disabled', 'error']),
            'document_root' => '/var/www/'.$this->faker->slug,
            'db_name' => 'db_'.$this->faker->uuid(),
            'db_user' => 'user_'.$this->faker->uuid(),
            'storage_used_mb' => $this->faker->numberBetween(100, 5000),
            'settings' => [],
        ];
    }

    /**
     * Indicate that the site is active.
     */
    public function active(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'active',
        ]);
    }

    /**
     * Indicate that the site is disabled.
     */
    public function disabled(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'disabled',
        ]);
    }

    /**
     * Indicate that the site has SSL enabled.
     */
    public function withSsl(): static
    {
        return $this->state(fn (array $attributes) => [
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addDays(60),
        ]);
    }

    /**
     * Indicate that the site is WordPress.
     */
    public function wordpress(): static
    {
        return $this->state(fn (array $attributes) => [
            'site_type' => 'wordpress',
        ]);
    }
}
