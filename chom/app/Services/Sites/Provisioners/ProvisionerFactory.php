<?php

namespace App\Services\Sites\Provisioners;

use App\Contracts\SiteProvisionerInterface;
use Illuminate\Support\Facades\App;
use InvalidArgumentException;

/**
 * Factory for creating site provisioners.
 *
 * Implements the Factory pattern to create appropriate provisioners
 * based on site type. Follows Open/Closed Principle - open for extension,
 * closed for modification.
 */
class ProvisionerFactory
{
    /**
     * Map of site types to provisioner classes.
     *
     * To add a new site type:
     * 1. Create a new provisioner class implementing SiteProvisionerInterface
     * 2. Add the mapping here
     * 3. Register the provisioner in AppServiceProvider if needed
     *
     * @var array<string, class-string<SiteProvisionerInterface>>
     */
    private const PROVISIONER_MAP = [
        'wordpress' => WordPressSiteProvisioner::class,
        'html' => HtmlSiteProvisioner::class,
        'laravel' => LaravelSiteProvisioner::class,
    ];

    /**
     * Create a provisioner for the given site type.
     *
     * @param string $siteType The type of site (wordpress, html, laravel, etc.)
     * @return SiteProvisionerInterface
     * @throws InvalidArgumentException If site type is not supported
     */
    public function make(string $siteType): SiteProvisionerInterface
    {
        $provisionerClass = self::PROVISIONER_MAP[$siteType] ?? null;

        if ($provisionerClass === null) {
            throw new InvalidArgumentException(
                "Unsupported site type: {$siteType}. Supported types: " .
                implode(', ', $this->getSupportedTypes())
            );
        }

        // Resolve the provisioner from the container to support dependency injection
        return App::make($provisionerClass);
    }

    /**
     * Get all supported site types.
     *
     * @return array<string>
     */
    public function getSupportedTypes(): array
    {
        return array_keys(self::PROVISIONER_MAP);
    }

    /**
     * Check if a site type is supported.
     *
     * @param string $siteType
     * @return bool
     */
    public function supports(string $siteType): bool
    {
        return isset(self::PROVISIONER_MAP[$siteType]);
    }

    /**
     * Get all available provisioners.
     *
     * Useful for administrative purposes or displaying available options.
     *
     * @return array<string, SiteProvisionerInterface>
     */
    public function all(): array
    {
        $provisioners = [];

        foreach (self::PROVISIONER_MAP as $type => $class) {
            $provisioners[$type] = App::make($class);
        }

        return $provisioners;
    }
}
