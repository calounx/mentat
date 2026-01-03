<?php

declare(strict_types=1);

namespace App\Providers;

use App\Contracts\Infrastructure\CacheInterface;
use App\Contracts\Infrastructure\NotificationInterface;
use App\Contracts\Infrastructure\ObservabilityInterface;
use App\Contracts\Infrastructure\StorageInterface;
use App\Contracts\Infrastructure\VpsProviderInterface;
use App\Infrastructure\Cache\ArrayCacheAdapter;
use App\Infrastructure\Cache\RedisCacheAdapter;
use App\Infrastructure\Notification\EmailNotifier;
use App\Infrastructure\Notification\LogNotifier;
use App\Infrastructure\Notification\MultiChannelNotifier;
use App\Infrastructure\Observability\NullObservability;
use App\Infrastructure\Observability\PrometheusObservability;
use App\Infrastructure\Storage\LocalStorageAdapter;
use App\Infrastructure\Storage\S3StorageAdapter;
use App\Infrastructure\Vps\DigitalOceanVpsProvider;
use App\Infrastructure\Vps\GenericSshVpsProvider;
use App\Infrastructure\Vps\LocalVpsProvider;
use Illuminate\Support\ServiceProvider;

/**
 * Infrastructure Service Provider
 *
 * Registers and binds all infrastructure service implementations.
 * Provides dependency injection for VPS, observability, notifications, storage, and cache.
 *
 * Design Pattern: Service Locator + Dependency Injection
 * SOLID Principles: Dependency Inversion - high-level modules depend on abstractions
 *
 * Configuration:
 * - VPS provider selection via config('services.vps.provider')
 * - Observability backend via config('services.observability.driver')
 * - Storage backend via config('services.storage.driver')
 * - Cache backend via config('cache.default')
 *
 * @package App\Providers
 */
class InfrastructureServiceProvider extends ServiceProvider
{
    /**
     * Register infrastructure services
     *
     * Binds all interface implementations to the service container.
     * Uses configuration to determine which concrete implementations to use.
     *
     * @return void
     */
    public function register(): void
    {
        $this->registerVpsProvider();
        $this->registerObservability();
        $this->registerNotification();
        $this->registerStorage();
        $this->registerCache();
    }

    /**
     * Bootstrap infrastructure services
     *
     * @return void
     */
    public function boot(): void
    {
        // Flush observability metrics on application shutdown
        $this->app->terminating(function () {
            if ($this->app->bound(ObservabilityInterface::class)) {
                $this->app->make(ObservabilityInterface::class)->flush();
            }
        });
    }

    /**
     * Register VPS provider implementation
     *
     * Selects and binds the appropriate VPS provider based on configuration.
     *
     * Supported providers:
     * - local: LocalVpsProvider (Docker-based for development)
     * - digitalocean: DigitalOceanVpsProvider (DigitalOcean API)
     * - ssh: GenericSshVpsProvider (Generic SSH access)
     *
     * @return void
     */
    private function registerVpsProvider(): void
    {
        $this->app->singleton(VpsProviderInterface::class, function ($app) {
            $provider = config('services.vps.provider', 'local');

            return match ($provider) {
                'digitalocean' => new DigitalOceanVpsProvider(
                    apiToken: config('services.vps.digitalocean.token'),
                    sshKeyId: config('services.vps.digitalocean.ssh_key_id'),
                    timeout: config('services.vps.timeout', 60)
                ),

                'ssh' => new GenericSshVpsProvider(
                    sshPort: config('services.vps.ssh.port', 22),
                    timeout: config('services.vps.timeout', 300),
                    privateKeyPath: config('services.vps.ssh.private_key_path')
                ),

                'local' => new LocalVpsProvider(
                    sshUser: config('services.vps.local.user', 'root'),
                    sshPort: config('services.vps.local.port', 22),
                    useDocker: config('services.vps.local.use_docker', true)
                ),

                default => new LocalVpsProvider(),
            };
        });

        // Alias for easier access
        $this->app->alias(VpsProviderInterface::class, 'vps.provider');
    }

    /**
     * Register observability implementation
     *
     * Selects and binds the appropriate observability backend.
     *
     * Supported backends:
     * - prometheus: PrometheusObservability (Prometheus metrics)
     * - null: NullObservability (No-op for testing)
     *
     * @return void
     */
    private function registerObservability(): void
    {
        $this->app->singleton(ObservabilityInterface::class, function ($app) {
            $driver = config('services.observability.driver', 'null');

            return match ($driver) {
                'prometheus' => new PrometheusObservability(
                    pushGatewayUrl: config('services.observability.prometheus.push_gateway_url'),
                    namespace: config('services.observability.prometheus.namespace', 'chom'),
                    bufferSize: config('services.observability.prometheus.buffer_size', 100)
                ),

                'null' => new NullObservability(),

                default => new NullObservability(),
            };
        });

        // Alias for easier access
        $this->app->alias(ObservabilityInterface::class, 'observability');
    }

    /**
     * Register notification implementation
     *
     * Creates a multi-channel notifier with configured channels.
     *
     * Channels:
     * - email: EmailNotifier (Laravel Mail)
     * - log: LogNotifier (Logging for development)
     *
     * @return void
     */
    private function registerNotification(): void
    {
        $this->app->singleton(NotificationInterface::class, function ($app) {
            $channels = [];
            $enabledChannels = config('services.notifications.channels', ['log']);

            if (in_array('email', $enabledChannels, true)) {
                $channels[] = new EmailNotifier();
            }

            if (in_array('log', $enabledChannels, true)) {
                $channels[] = new LogNotifier();
            }

            // If no channels configured, use log notifier
            if (empty($channels)) {
                $channels[] = new LogNotifier();
            }

            return new MultiChannelNotifier(
                channels: $channels,
                failSilently: config('services.notifications.fail_silently', true)
            );
        });

        // Alias for easier access
        $this->app->alias(NotificationInterface::class, 'notifier');
    }

    /**
     * Register storage implementation
     *
     * Selects and binds the appropriate storage backend.
     *
     * Supported backends:
     * - local: LocalStorageAdapter (Local filesystem)
     * - s3: S3StorageAdapter (AWS S3 or compatible)
     *
     * @return void
     */
    private function registerStorage(): void
    {
        $this->app->singleton(StorageInterface::class, function ($app) {
            $driver = config('services.storage.driver', 'local');

            return match ($driver) {
                's3' => new S3StorageAdapter(
                    disk: config('services.storage.s3.disk', 's3'),
                    visibility: config('services.storage.s3.visibility', 'private'),
                    region: config('services.storage.s3.region'),
                    bucket: config('services.storage.s3.bucket')
                ),

                'local' => new LocalStorageAdapter(
                    disk: config('services.storage.local.disk', 'local'),
                    visibility: config('services.storage.local.visibility', 'private')
                ),

                default => new LocalStorageAdapter(),
            };
        });

        // Alias for easier access
        $this->app->alias(StorageInterface::class, 'storage.adapter');
    }

    /**
     * Register cache implementation
     *
     * Selects and binds the appropriate cache backend.
     *
     * Supported backends:
     * - redis: RedisCacheAdapter (Redis)
     * - array: ArrayCacheAdapter (In-memory for testing)
     *
     * @return void
     */
    private function registerCache(): void
    {
        $this->app->singleton(CacheInterface::class, function ($app) {
            $driver = config('cache.default', 'redis');

            return match ($driver) {
                'redis' => new RedisCacheAdapter(
                    connection: config('cache.stores.redis.connection', 'cache'),
                    prefix: config('cache.prefix', 'chom')
                ),

                'array' => new ArrayCacheAdapter(),

                default => new RedisCacheAdapter(),
            };
        });

        // Alias for easier access
        $this->app->alias(CacheInterface::class, 'cache.adapter');
    }

    /**
     * Get the services provided by the provider
     *
     * @return array<string>
     */
    public function provides(): array
    {
        return [
            VpsProviderInterface::class,
            ObservabilityInterface::class,
            NotificationInterface::class,
            StorageInterface::class,
            CacheInterface::class,
            'vps.provider',
            'observability',
            'notifier',
            'storage.adapter',
            'cache.adapter',
        ];
    }
}
