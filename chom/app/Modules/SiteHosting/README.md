# Site Hosting Module

## Overview

The Site Hosting module is a bounded context responsible for all site provisioning, management, and lifecycle operations within the CHOM application. It handles site deployment, PHP version management, SSL certificates, and site monitoring.

## Responsibilities

- Site provisioning and deployment
- PHP version management
- SSL certificate management and renewal
- Site lifecycle management (enable/disable/delete)
- Site configuration management
- Site metrics and monitoring

## Architecture

### Service Contracts

- `SiteProvisionerInterface` - Site provisioning and management operations

### Services

- `SiteProvisioningService` - Orchestrator wrapping existing SiteManagementService

### Value Objects

- `PhpVersion` - Encapsulates PHP version information with validation
- `SslCertificate` - Encapsulates SSL certificate data and status

### Policies

- `SitePolicy` - Authorization policies for site operations (located in app/Policies)

## Usage Examples

### Site Provisioning

```php
use App\Modules\SiteHosting\Contracts\SiteProvisionerInterface;

$provisioner = app(SiteProvisionerInterface::class);

// Provision new site
$site = $provisioner->provision([
    'domain' => 'example.com',
    'site_type' => 'wordpress',
    'php_version' => '8.2',
], $tenantId);
```

### PHP Version Management

```php
use App\Modules\SiteHosting\ValueObjects\PhpVersion;

// Change PHP version
$phpVersion = PhpVersion::fromString('8.3');
$site = $provisioner->changePhpVersion($siteId, $phpVersion);

// Check version support
$supported = $phpVersion->isSupported();
$allVersions = PhpVersion::getSupportedVersions();
```

### SSL Certificate Management

```php
// Enable SSL
$certificate = $provisioner->enableSsl($siteId);

// Check certificate status
$enabled = $certificate->isEnabled();
$expiringSoon = $certificate->isExpiringSoon();
$daysLeft = $certificate->getDaysUntilExpiration();

// Renew certificate
$newCertificate = $provisioner->renewSsl($siteId);
```

### Site Lifecycle

```php
// Enable site
$site = $provisioner->enable($siteId);

// Disable site with reason
$site = $provisioner->disable($siteId, 'Maintenance');

// Delete site
$success = $provisioner->delete($siteId);
```

### Site Metrics

```php
// Get comprehensive site metrics
$metrics = $provisioner->getMetrics($siteId);
// Returns: storage, backups, uptime, SSL status, etc.
```

## Value Objects

### PhpVersion

Provides type-safe PHP version handling:

- Version validation against supported versions
- Version comparison (newer/older)
- Major/minor version extraction
- String representation

### SslCertificate

Encapsulates SSL certificate information:

- Certificate status and validity
- Expiration tracking
- Automatic expiration warnings
- Certificate details (issuer, dates)

## Module Dependencies

This module depends on:

- `SiteManagementService` (existing service)
- Site model and repository
- VPS server management
- Quota service for limits
- Job queue for async operations

## Integration with Existing Code

This module wraps the existing `SiteManagementService` to:

1. Provide a clean module interface
2. Add module-specific logging
3. Implement value objects for type safety
4. Maintain backward compatibility

## Events

The module uses existing site events:

- `SiteProvisioned` - When new site is provisioned
- `SiteUpdated` - When site configuration changes
- `SiteEnabled` - When site is enabled
- `SiteDisabled` - When site is disabled
- `SiteDeleted` - When site is deleted

## Security Considerations

1. All site operations require authentication
2. SitePolicy enforces authorization rules
3. Tenant isolation is maintained
4. SSL certificates are auto-renewed before expiration
5. All operations are logged for auditing

## Testing

Test the module using:

```bash
php artisan test --filter=SiteHosting
```

## Future Enhancements

- Multi-region site deployment
- Auto-scaling based on traffic
- Advanced caching strategies
- CDN integration
- Site cloning/staging environments
- Performance optimization recommendations
