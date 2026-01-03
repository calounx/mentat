<?php

declare(strict_types=1);

/**
 * Value Objects Usage Examples
 *
 * This file demonstrates how to use the CHOM value objects.
 * Run with: php app/ValueObjects/examples.php
 */

require __DIR__ . '/../../vendor/autoload.php';

use App\ValueObjects\VpsSpecification;
use App\ValueObjects\BackupConfiguration;
use App\ValueObjects\QuotaLimits;
use App\ValueObjects\SslCertificate;
use App\ValueObjects\PhpVersion;
use App\ValueObjects\DomainName;
use App\ValueObjects\EmailAddress;
use App\ValueObjects\TeamRole;
use App\ValueObjects\Money;
use App\ValueObjects\UsageStats;
use App\ValueObjects\Enums\BackupType;
use App\ValueObjects\Enums\BackupSchedule;
use App\ValueObjects\Enums\SslProvider;

echo "=== CHOM Value Objects Examples ===\n\n";

// Example 1: VpsSpecification
echo "1. VPS Specification\n";
echo str_repeat("-", 40) . "\n";

$spec = VpsSpecification::medium('us-east-1');
echo "Specification: {$spec}\n";
echo "Monthly Cost: \${$spec->getMonthlyCost()}\n";
echo "Hourly Cost: \${$spec->getHourlyCost()}\n";
echo "RAM in GB: {$spec->getRamGb()}GB\n";
echo "OS: {$spec->getOsName()}\n\n";

// Example 2: BackupConfiguration
echo "2. Backup Configuration\n";
echo str_repeat("-", 40) . "\n";

$backup = BackupConfiguration::fullBackup(30)
    ->withSchedule(BackupSchedule::DAILY)
    ->withExclusions(['/tmp', '/cache']);

echo "Configuration: {$backup}\n";
echo "Type: {$backup->type->label()}\n";
echo "Schedule: {$backup->schedule?->label()}\n";
echo "Cron: {$backup->schedule?->cronExpression()}\n";
echo "Retention: {$backup->retentionDays} days\n";
echo "Estimated backups: {$backup->estimatedBackupCount()}\n\n";

// Example 3: QuotaLimits
echo "3. Quota Limits\n";
echo str_repeat("-", 40) . "\n";

$limits = QuotaLimits::professional();
echo "Limits: {$limits}\n";
echo "Max Sites: " . ($limits->allowsUnlimitedSites() ? 'Unlimited' : $limits->maxSites) . "\n";
echo "Max Storage: " . ($limits->allowsUnlimitedStorage() ? 'Unlimited' : ($limits->maxStorageMb / 1024) . 'GB') . "\n";
echo "SSL Included: " . ($limits->sslIncluded ? 'Yes' : 'No') . "\n";
echo "Auto Backups: " . ($limits->automaticBackups ? 'Yes' : 'No') . "\n\n";

// Example 4: SslCertificate
echo "4. SSL Certificate\n";
echo str_repeat("-", 40) . "\n";

$ssl = SslCertificate::fromLetsEncrypt('example.com');
echo "Certificate: {$ssl}\n";
echo "Provider: {$ssl->provider->label()}\n";
echo "Expires: {$ssl->expiresAt->format('Y-m-d')}\n";
echo "Days until expiration: {$ssl->daysUntilExpiration()}\n";
echo "Needs renewal: " . ($ssl->needsRenewal() ? 'Yes' : 'No') . "\n";
echo "Supports auto-renewal: " . ($ssl->supportsAutoRenewal() ? 'Yes' : 'No') . "\n\n";

// Example 5: PhpVersion
echo "5. PHP Version\n";
echo str_repeat("-", 40) . "\n";

$php = PhpVersion::fromString('8.2.15');
echo "Version: {$php}\n";
echo "Major.Minor: {$php->getMajorMinor()}\n";
echo "Is Supported: " . ($php->isSupported() ? 'Yes' : 'No') . "\n";
echo "Is EOL: " . ($php->isEol() ? 'Yes' : 'No') . "\n";
echo "Days until EOL: {$php->daysUntilEol()}\n\n";

// Example 6: DomainName
echo "6. Domain Name\n";
echo str_repeat("-", 40) . "\n";

$domain = DomainName::fromString('blog.example.com');
echo "Domain: {$domain}\n";
echo "Root: {$domain->getRoot()}\n";
echo "Subdomain: {$domain->getSubdomain()}\n";
echo "TLD: {$domain->getTld()}\n";
echo "Is Wildcard: " . ($domain->isWildcard() ? 'Yes' : 'No') . "\n\n";

// Example 7: EmailAddress
echo "7. Email Address\n";
echo str_repeat("-", 40) . "\n";

$email = EmailAddress::fromString('user@example.com');
echo "Email: {$email}\n";
echo "Local Part: {$email->getLocalPart()}\n";
echo "Domain: {$email->getDomain()}\n";
echo "Masked: {$email->mask()}\n";
echo "Is Disposable: " . ($email->isDisposable() ? 'Yes' : 'No') . "\n\n";

// Example 8: TeamRole
echo "8. Team Role\n";
echo str_repeat("-", 40) . "\n";

$role = TeamRole::admin();
echo "Role: {$role->label()}\n";
echo "Level: {$role->getLevel()}\n";
echo "Can manage sites: " . ($role->canManageSites() ? 'Yes' : 'No') . "\n";
echo "Can manage team: " . ($role->canManageTeam() ? 'Yes' : 'No') . "\n";
echo "Permissions count: " . count($role->getPermissions()) . "\n\n";

// Example 9: Money
echo "9. Money\n";
echo str_repeat("-", 40) . "\n";

$price = Money::fromDollars(29.99);
$tax = $price->multiply(0.1);
$total = $price->add($tax);

echo "Price: {$price->format()}\n";
echo "Tax (10%): {$tax->format()}\n";
echo "Total: {$total->format()}\n";
echo "In Cents: {$total->toCents()}\n\n";

// Example 10: UsageStats
echo "10. Usage Stats\n";
echo str_repeat("-", 40) . "\n";

$usage = new UsageStats(
    siteCount: 5,
    storageUsedMb: 10240,
    backupCount: 15,
    teamMemberCount: 3
);

echo "Usage: {$usage}\n";
echo "Storage (GB): {$usage->getStorageUsedGb()}GB\n";

$percentages = $usage->getUsagePercentage($limits);
echo "Site usage: " . number_format($percentages['sites'], 1) . "%\n";
echo "Storage usage: " . number_format($percentages['storage'], 1) . "%\n";
echo "Within limits: " . ($usage->isWithinLimits($limits) ? 'Yes' : 'No') . "\n\n";

// Example 11: JSON Serialization
echo "11. JSON Serialization\n";
echo str_repeat("-", 40) . "\n";

echo "VPS Spec JSON:\n";
echo json_encode($spec, JSON_PRETTY_PRINT) . "\n\n";

echo "Quota Limits JSON:\n";
echo json_encode($limits, JSON_PRETTY_PRINT) . "\n\n";

// Example 12: Immutability
echo "12. Immutability Example\n";
echo str_repeat("-", 40) . "\n";

$original = VpsSpecification::small();
$modified = $original->withCpuCores(4);

echo "Original CPU: {$original->cpuCores}\n";
echo "Modified CPU: {$modified->cpuCores}\n";
echo "Objects are different: " . ($original !== $modified ? 'Yes' : 'No') . "\n";
echo "Original unchanged: " . ($original->cpuCores === 1 ? 'Yes' : 'No') . "\n\n";

// Example 13: Validation
echo "13. Validation Example\n";
echo str_repeat("-", 40) . "\n";

try {
    $invalid = new VpsSpecification(
        cpuCores: 100, // Invalid!
        ramMb: 4096,
        diskGb: 50,
        region: 'us-east-1'
    );
} catch (InvalidArgumentException $e) {
    echo "Validation caught: {$e->getMessage()}\n";
}

try {
    $invalidEmail = EmailAddress::fromString('not-an-email');
} catch (InvalidArgumentException $e) {
    echo "Email validation caught: {$e->getMessage()}\n";
}

echo "\n=== All Examples Complete ===\n";
