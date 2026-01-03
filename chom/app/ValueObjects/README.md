# Value Objects

This directory contains immutable value objects that encapsulate domain concepts and enforce business rules in the CHOM application.

## What are Value Objects?

Value objects are immutable objects that represent descriptive aspects of the domain with no conceptual identity. They are defined by their attributes rather than a unique identifier.

### Key Characteristics

- **Immutable**: Once created, they cannot be modified
- **Self-validating**: Validation happens in the constructor
- **Equality by value**: Two value objects are equal if all their attributes are equal
- **No side effects**: Methods return new instances rather than modifying state

## Available Value Objects

### Core Domain Objects

#### VpsSpecification
Encapsulates VPS server specifications with validation and cost calculation.

```php
use App\ValueObjects\VpsSpecification;

// Create using constructor
$spec = new VpsSpecification(
    cpuCores: 2,
    ramMb: 4096,
    diskGb: 50,
    region: 'us-east-1',
    os: 'debian-12'
);

// Or use factory methods
$spec = VpsSpecification::medium('eu-west-1');

// Calculate costs
echo $spec->getMonthlyCost(); // 14.60
echo $spec->getHourlyCost();  // 0.02

// Check specifications
$minimum = VpsSpecification::small();
if ($spec->isAtLeast($minimum)) {
    echo "Meets minimum requirements";
}
```

#### BackupConfiguration
Encapsulates backup configuration settings.

```php
use App\ValueObjects\BackupConfiguration;
use App\ValueObjects\Enums\BackupSchedule;

// Create full backup configuration
$config = BackupConfiguration::fullBackup(retentionDays: 30);

// Create database-only backup
$config = BackupConfiguration::databaseOnly(retentionDays: 14);

// Customize configuration
$config = $config
    ->withSchedule(BackupSchedule::HOURLY)
    ->withExclusions(['/tmp', '/cache']);

// Estimate backup size
$estimatedSize = $config->estimatedSize(siteSize: 1073741824); // 1GB
echo "Estimated backup size: " . ($estimatedSize / 1024 / 1024) . "MB";
```

#### QuotaLimits
Represents subscription tier limits for resources.

```php
use App\ValueObjects\QuotaLimits;
use App\ValueObjects\UsageStats;

// Get predefined tier limits
$limits = QuotaLimits::professional();

// Check if actions are allowed
if ($limits->canCreateSite(currentCount: 5)) {
    echo "Can create more sites";
}

// Get usage percentages
$usage = UsageStats::forTenant('tenant-123');
$percentages = $limits->getUsagePercentage($usage);

echo "Sites: {$percentages['sites']}%";
echo "Storage: {$percentages['storage']}%";
```

#### SslCertificate
Represents SSL/TLS certificates with expiration tracking.

```php
use App\ValueObjects\SslCertificate;

// Create Let's Encrypt certificate
$cert = SslCertificate::fromLetsEncrypt('example.com');

// Check certificate status
if ($cert->isExpiringSoon()) {
    echo "Certificate needs renewal";
}

if ($cert->needsRenewal()) {
    echo "Renew before: " . $cert->getRenewalDate()->format('Y-m-d');
}

echo "Days until expiration: " . $cert->daysUntilExpiration();
```

### Simple Value Objects

#### DomainName
Validates and manipulates domain names.

```php
use App\ValueObjects\DomainName;

$domain = DomainName::fromString('blog.example.com');

echo $domain->getRoot();      // example.com
echo $domain->getSubdomain(); // blog
echo $domain->getTld();       // com

if ($domain->isSubdomainOf(DomainName::fromString('example.com'))) {
    echo "Is a subdomain";
}

// Create subdomain
$newDomain = $domain->withSubdomain('api'); // api.blog.example.com
```

#### EmailAddress
Validates and represents email addresses.

```php
use App\ValueObjects\EmailAddress;

$email = EmailAddress::fromString('user@example.com');

echo $email->getLocalPart(); // user
echo $email->getDomain();    // example.com
echo $email->mask();         // us***@example.com

if ($email->isDisposable()) {
    throw new Exception('Disposable emails not allowed');
}
```

#### PhpVersion
Represents PHP versions with support tracking.

```php
use App\ValueObjects\PhpVersion;

$version = PhpVersion::fromString('8.2.15');

if ($version->isSupported()) {
    echo "PHP version is supported";
}

if ($version->isEol()) {
    echo "PHP version has reached end of life";
}

echo "Days until EOL: " . $version->daysUntilEol();

// Compare versions
$newer = PhpVersion::php83();
if ($newer->isNewerThan($version)) {
    echo "Upgrade available";
}
```

#### TeamRole
Represents team member roles with hierarchical permissions.

```php
use App\ValueObjects\TeamRole;

$role = TeamRole::admin();

if ($role->canManageSites()) {
    echo "User can manage sites";
}

if ($role->isHigherThan(TeamRole::member())) {
    echo "Has elevated permissions";
}

$permissions = $role->getPermissions();
// ['manage_sites', 'invite_members', 'remove_members', ...]
```

#### Money
Represents monetary amounts with currency.

```php
use App\ValueObjects\Money;

$price = Money::fromDollars(29.99);

// Perform calculations
$tax = $price->multiply(0.1);
$total = $price->add($tax);

echo $total->format(); // $32.99

// Compare amounts
if ($total->isGreaterThan(Money::fromDollars(30.00))) {
    echo "Over budget";
}
```

#### UsageStats
Represents current resource usage statistics.

```php
use App\ValueObjects\UsageStats;
use App\ValueObjects\QuotaLimits;

$usage = new UsageStats(
    siteCount: 5,
    storageUsedMb: 10240,
    backupCount: 15,
    teamMemberCount: 3
);

$limits = QuotaLimits::professional();

if ($usage->isWithinLimits($limits)) {
    echo "Usage is within quota";
}

$overages = $usage->getOverages($limits);
if (!empty($overages)) {
    echo "Quota exceeded";
}
```

## Enumerations

### BackupType
```php
use App\ValueObjects\Enums\BackupType;

$type = BackupType::FULL;

echo $type->label();       // "Full Backup"
echo $type->description(); // "Complete backup including files, database, and configuration"

if ($type->includesDatabase()) {
    echo "Backup includes database";
}
```

### SslProvider
```php
use App\ValueObjects\Enums\SslProvider;

$provider = SslProvider::LETS_ENCRYPT;

if ($provider->supportsAutoRenewal()) {
    echo "Auto-renewal is available";
}

echo "Validity period: " . $provider->validityPeriodDays() . " days";
```

### BackupSchedule
```php
use App\ValueObjects\Enums\BackupSchedule;

$schedule = BackupSchedule::DAILY;

echo $schedule->cronExpression(); // "0 0 * * *"
echo $schedule->intervalHours();  // 24

$backupCount = $schedule->estimatedBackupCount(retentionDays: 30);
echo "Estimated backups: $backupCount";
```

### SiteStatus
```php
use App\ValueObjects\Enums\SiteStatus;

$status = SiteStatus::ACTIVE;

if ($status->isAccessible()) {
    echo "Site is accessible";
}

if ($status->isModifiable()) {
    echo "Site can be modified";
}

echo "Badge color: " . $status->badgeColor();
```

## Best Practices

### 1. Always Validate in Constructor
```php
final class Example
{
    public function __construct(
        public readonly string $value
    ) {
        $this->validate(); // Always validate!
    }

    private function validate(): void
    {
        if (empty($this->value)) {
            throw new InvalidArgumentException('Value cannot be empty');
        }
    }
}
```

### 2. Use Static Factory Methods
```php
// Instead of complex constructors
public static function fromLetsEncrypt(string $domain): self
{
    $issuedAt = new DateTimeImmutable();
    $expiresAt = $issuedAt->modify('+90 days');

    return new self(
        domain: $domain,
        provider: SslProvider::LETS_ENCRYPT,
        issuedAt: $issuedAt,
        expiresAt: $expiresAt,
        issuer: "Let's Encrypt"
    );
}
```

### 3. Return New Instances for Changes
```php
// Don't modify state - return new instance
public function withRetention(int $retentionDays): self
{
    return new self(
        type: $this->type,
        retentionDays: $retentionDays, // Changed
        compressed: $this->compressed,
        encrypted: $this->encrypted,
        schedule: $this->schedule,
        excludePaths: $this->excludePaths
    );
}
```

### 4. Implement Comparison Methods
```php
public function equals(VpsSpecification $other): bool
{
    return $this->cpuCores === $other->cpuCores
        && $this->ramMb === $other->ramMb
        && $this->diskGb === $other->diskGb
        && $this->region === $other->region
        && $this->os === $other->os;
}
```

### 5. Provide Meaningful String Representations
```php
public function __toString(): string
{
    return sprintf(
        '%d vCPU, %dGB RAM, %dGB Disk (%s)',
        $this->cpuCores,
        (int)$this->getRamGb(),
        $this->diskGb,
        $this->region
    );
}
```

## Testing Value Objects

Value objects are easy to test because they're immutable and have no dependencies:

```php
use PHPUnit\Framework\TestCase;

class VpsSpecificationTest extends TestCase
{
    public function test_creates_valid_specification(): void
    {
        $spec = new VpsSpecification(
            cpuCores: 2,
            ramMb: 4096,
            diskGb: 50,
            region: 'us-east-1'
        );

        $this->assertEquals(2, $spec->cpuCores);
        $this->assertEquals(4, $spec->getRamGb());
    }

    public function test_validates_cpu_cores(): void
    {
        $this->expectException(InvalidArgumentException::class);

        new VpsSpecification(
            cpuCores: 0, // Invalid!
            ramMb: 4096,
            diskGb: 50,
            region: 'us-east-1'
        );
    }

    public function test_equality(): void
    {
        $spec1 = VpsSpecification::medium();
        $spec2 = VpsSpecification::medium();

        $this->assertTrue($spec1->equals($spec2));
    }
}
```

## Integration with Laravel

### Model Casts

You can use value objects with Laravel models:

```php
use Illuminate\Database\Eloquent\Model;

class Site extends Model
{
    protected function casts(): array
    {
        return [
            'specification' => VpsSpecification::class,
            'backup_config' => BackupConfiguration::class,
        ];
    }
}
```

### Validation Rules

Create custom validation rules:

```php
use Illuminate\Contracts\Validation\Rule;

class ValidDomain implements Rule
{
    public function passes($attribute, $value): bool
    {
        try {
            DomainName::fromString($value);
            return true;
        } catch (InvalidArgumentException) {
            return false;
        }
    }

    public function message(): string
    {
        return 'The :attribute must be a valid domain name.';
    }
}
```

## Performance Considerations

Value objects are lightweight and designed for frequent instantiation:

- No database queries
- No external dependencies
- Pure validation logic
- Minimal memory overhead

Feel free to create them liberally throughout your application.

## Additional Resources

- [Martin Fowler on Value Objects](https://martinfowler.com/bliki/ValueObject.html)
- [Domain-Driven Design by Eric Evans](https://www.domainlanguage.com/ddd/)
- [PHP 8.1+ Features](https://www.php.net/releases/8.1/en.php)
