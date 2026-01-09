<?php

namespace Database\Factories;

use App\Models\Site;
use App\Models\Tenant;
use App\Models\VpsServer;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends \Illuminate\Database\Eloquent\Factories\Factory<\App\Models\Site>
 */
class SiteFactory extends Factory
{
    protected $model = Site::class;

    /**
     * Define the model's default state.
     *
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $domain = fake()->domainName();
        $siteTypes = ['wordpress', 'laravel', 'static', 'php'];
        $phpVersions = ['8.1', '8.2', '8.3'];

        return [
            'tenant_id' => Tenant::factory(),
            'vps_id' => VpsServer::factory(),
            'domain' => $domain,
            'site_type' => fake()->randomElement($siteTypes),
            'php_version' => fake()->randomElement($phpVersions),
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addMonths(3),
            'status' => 'active',
            'failure_reason' => null,
            'healing_attempts' => [],
            'last_healing_at' => null,
            'provision_attempts' => 1,
            'document_root' => '/var/www/sites/' . $domain . '/public',
            'db_name' => 'site_' . Str::slug($domain, '_'),
            'db_user' => 'site_' . Str::slug(Str::substr($domain, 0, 20), '_'),
            'storage_used_mb' => fake()->numberBetween(10, 500),
            'settings' => [],
        ];
    }

    /**
     * Indicate that the site is provisioning.
     */
    public function provisioning(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'provisioning',
        ]);
    }

    /**
     * Indicate that the site has failed.
     */
    public function failed(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'failed',
            'failure_reason' => 'Provisioning timeout',
        ]);
    }

    /**
     * Indicate that the site has been suspended.
     */
    public function suspended(): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => 'suspended',
        ]);
    }

    /**
     * Indicate that SSL is not enabled.
     */
    public function withoutSsl(): static
    {
        return $this->state(fn (array $attributes) => [
            'ssl_enabled' => false,
            'ssl_expires_at' => null,
        ]);
    }

    /**
     * Indicate that SSL certificate is expiring soon.
     */
    public function sslExpiringSoon(): static
    {
        return $this->state(fn (array $attributes) => [
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->addDays(10),
        ]);
    }

    /**
     * Indicate that SSL certificate has expired.
     */
    public function sslExpired(): static
    {
        return $this->state(fn (array $attributes) => [
            'ssl_enabled' => true,
            'ssl_expires_at' => now()->subDays(5),
        ]);
    }

    /**
     * Set a specific site type.
     */
    public function ofType(string $type): static
    {
        return $this->state(fn (array $attributes) => [
            'site_type' => $type,
        ]);
    }

    /**
     * Set a specific tenant.
     */
    public function forTenant(Tenant $tenant): static
    {
        return $this->state(fn (array $attributes) => [
            'tenant_id' => $tenant->id,
        ]);
    }

    /**
     * Set a specific VPS.
     */
    public function onVps(VpsServer $vps): static
    {
        return $this->state(fn (array $attributes) => [
            'vps_id' => $vps->id,
        ]);
    }

    /**
     * Set a specific domain.
     */
    public function withDomain(string $domain): static
    {
        return $this->state(fn (array $attributes) => [
            'domain' => $domain,
            'document_root' => '/var/www/sites/' . $domain . '/public',
            'db_name' => 'site_' . Str::slug($domain, '_'),
            'db_user' => 'site_' . Str::slug(Str::substr($domain, 0, 20), '_'),
        ]);
    }
}
