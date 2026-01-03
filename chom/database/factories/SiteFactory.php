<?php

namespace Database\Factories;

use App\Models\Site;
use App\Models\Tenant;
use App\Models\VpsServer;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

class SiteFactory extends Factory
{
    protected $model = Site::class;

    public function definition(): array
    {
        return [
            'id' => Str::uuid()->toString(),
            'tenant_id' => Tenant::factory(),
            'vps_server_id' => VpsServer::factory(),
            'domain' => $this->faker->domainName(),
            'name' => $this->faker->company() . ' Site',
            'site_type' => 'wordpress',
            'php_version' => '8.2',
            'status' => 'active',
            'ssl_enabled' => false,
            'ssl_expires_at' => null,
            'storage_used_mb' => $this->faker->numberBetween(100, 5000),
            'document_root' => '/var/www/html',
            'settings' => [],
            'created_at' => now(),
            'updated_at' => now(),
        ];
    }

    public function withSSL(): static
    {
        return $this->state(fn (array $attributes) => [
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addMonths(3),
        ]);
    }

    public function disabled(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'disabled',
        ]);
    }

    public function laravel(): static
    {
        return $this->state(fn (array $attributes) => [
            'site_type' => 'laravel',
        ]);
    }
}
