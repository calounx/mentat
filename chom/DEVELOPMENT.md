# CHOM Development Guide

Comprehensive guide for developing CHOM (CPanel Hosting Operations Manager).

## Quick Start

```bash
./scripts/setup-dev.sh
composer run dev
```

Access: http://localhost:8000

## Architecture Overview

### Technology Stack

- **Backend**: Laravel 12, PHP 8.2+
- **Frontend**: Livewire 3, Alpine.js, Tailwind CSS
- **Database**: SQLite (dev), MySQL (production)
- **Cache/Queue**: Redis
- **Payments**: Stripe + Laravel Cashier
- **SSH**: phpseclib for VPS management

### Directory Structure

```
chom/
├── app/
│   ├── Console/Commands/       # Artisan commands
│   ├── Contracts/              # Interfaces
│   ├── Http/
│   │   ├── Controllers/        # Controllers
│   │   ├── Middleware/         # Middleware
│   │   ├── Resources/          # API resources
│   │   └── Livewire/          # Livewire components
│   ├── Models/                 # Eloquent models
│   ├── Repositories/           # Repository pattern
│   ├── Services/               # Business logic
│   └── ValueObjects/           # Value objects
├── database/
│   ├── migrations/             # Database migrations
│   ├── seeders/               # Database seeders
│   └── factories/             # Model factories
├── resources/
│   ├── views/                 # Blade templates
│   └── js/                    # JavaScript
├── routes/
│   ├── web.php                # Web routes
│   ├── api.php                # API routes
│   └── console.php            # Console routes
├── tests/
│   ├── Feature/               # Feature tests
│   └── Unit/                  # Unit tests
└── scripts/                   # Dev scripts
```

### Key Concepts

#### Multi-Tenancy

CHOM uses organization-based tenancy:

- **Organization**: Top-level entity (company)
- **Tenant**: Subscription unit within organization
- **User**: Belongs to organization, has role (owner/admin/member/viewer)
- **VPS Server**: Belongs to tenant
- **Site**: Belongs to tenant, hosted on VPS

```php
// Access current tenant
$tenant = auth()->user()->currentTenant();

// Scope queries by tenant
$sites = Site::where('tenant_id', $tenant->id)->get();
```

#### Service Layer Pattern

Business logic lives in service classes:

```php
// Generate service
php artisan make:service Sites/SiteCreationService

// Use service
class SiteController extends Controller
{
    public function __construct(
        private SiteCreationService $service
    ) {}

    public function store(Request $request)
    {
        $site = $this->service->execute($request->validated());
        return response()->json($site, 201);
    }
}
```

#### Repository Pattern

Data access abstraction:

```php
// Generate repository
php artisan make:repository SiteRepository

// Register in AppServiceProvider
$this->app->bind(
    SiteRepositoryInterface::class,
    SiteRepository::class
);

// Use in service
class SiteService
{
    public function __construct(
        private SiteRepositoryInterface $repository
    ) {}
}
```

## Development Workflow

### Running the Application

```bash
# All services (recommended)
composer run dev

# Individual services
php artisan serve              # Web server
npm run dev                    # Vite (HMR)
php artisan queue:listen       # Queue worker
php artisan pail               # Log viewer

# Docker services
docker-compose up -d           # Start all
docker-compose down            # Stop all
```

### Database

```bash
# Fresh migration + seed
php artisan migrate:fresh --seed

# Create migration
php artisan make:migration create_sites_table

# Create seeder
php artisan make:seeder TestDataSeeder

# Run specific seeder
php artisan db:seed --class=TestUserSeeder
```

### Code Generation

```bash
# Service class
php artisan make:service Sites/SiteCreationService

# Repository + interface
php artisan make:repository SiteRepository

# Value object
php artisan make:value-object Domain

# API resource
php artisan make:api-resource SiteResource
php artisan make:api-resource SiteCollection --collection
```

### Testing

```bash
# Run all tests
composer test

# With coverage
php artisan test --coverage

# Specific test
php artisan test --filter=SiteTest

# Parallel testing
php artisan test --parallel
```

### Debugging

```bash
# Debug authentication
php artisan debug:auth user@example.com

# Debug tenant
php artisan debug:tenant tenant-id

# Debug cache
php artisan debug:cache
php artisan debug:cache --flush

# Debug performance
php artisan debug:performance
php artisan debug:performance /api/v1/sites
```

### Code Quality

```bash
# Format code
composer run format
vendor/bin/pint

# Static analysis
composer run analyse
vendor/bin/phpstan analyse

# Run all checks
composer run check
```

## API Development

### Creating Endpoints

1. **Define route** (`routes/api.php`):
```php
Route::middleware('auth:sanctum')->group(function () {
    Route::apiResource('sites', SiteController::class);
});
```

2. **Create controller**:
```php
php artisan make:controller Api/SiteController --api
```

3. **Create request validation**:
```php
php artisan make:request StoreSiteRequest
```

4. **Create API resource**:
```php
php artisan make:api-resource SiteResource
```

5. **Implement controller**:
```php
public function store(StoreSiteRequest $request)
{
    $site = $this->service->create($request->validated());
    return SiteResource::make($site);
}
```

### API Testing

Use the included Postman collection:
- `docs/api/postman_collection.json`
- Set environment variables
- Authentication handled via Sanctum tokens

## Frontend Development

### Livewire Components

```bash
# Create component
php artisan make:livewire Sites/SiteList

# Component class: app/Http/Livewire/Sites/SiteList.php
# View: resources/views/livewire/sites/site-list.blade.php
```

### Tailwind CSS

```bash
# Watch for changes
npm run dev

# Build for production
npm run build
```

### Alpine.js

Used for client-side interactivity in Livewire components.

## Performance Optimization

### Caching

```php
// Cache site list for 1 hour
$sites = Cache::remember('tenant.' . $tenantId . '.sites', 3600, function () {
    return Site::with('vpsServer')->get();
});

// Tag-based caching
Cache::tags(['sites', 'tenant:' . $tenantId])
    ->put('sites.list', $sites, 3600);
```

### Database Optimization

- Use indexes on frequently queried columns
- Eager load relationships to avoid N+1
- Use database transactions for data integrity
- Use chunk() for large datasets

```php
// Good: Eager loading
$sites = Site::with('vpsServer', 'backups')->get();

// Bad: N+1 query problem
$sites = Site::all();
foreach ($sites as $site) {
    $vps = $site->vpsServer; // N+1!
}
```

### Queue Jobs

```php
// Create job
php artisan make:job ProcessSiteBackup

// Dispatch job
ProcessSiteBackup::dispatch($site);

// Process queue
php artisan queue:work
```

## Security Best Practices

### Authentication

- Use Sanctum for API authentication
- Enforce 2FA for admin/owner roles
- Implement password confirmation for sensitive operations
- Rotate SSH keys every 90 days

### Authorization

```php
// Use policies
php artisan make:policy SitePolicy --model=Site

// Check permissions
$this->authorize('update', $site);

// Gates
Gate::define('manage-sites', function (User $user) {
    return $user->canManageSites();
});
```

### Input Validation

Always validate and sanitize input:

```php
$request->validate([
    'domain' => 'required|string|max:255|unique:sites',
    'type' => 'required|in:wordpress,laravel,html',
]);
```

### SQL Injection Prevention

Use query builder or Eloquent (never raw queries with user input):

```php
// Good
Site::where('domain', $domain)->first();

// Bad
DB::select("SELECT * FROM sites WHERE domain = '$domain'");
```

## Environment Configuration

### Local Development

`.env` file:
```env
APP_ENV=local
APP_DEBUG=true
DB_CONNECTION=sqlite
CACHE_DRIVER=redis
QUEUE_CONNECTION=redis
```

### Staging

```env
APP_ENV=staging
APP_DEBUG=false
DB_CONNECTION=mysql
CACHE_DRIVER=redis
QUEUE_CONNECTION=redis
```

### Production

```env
APP_ENV=production
APP_DEBUG=false
# Use strong encryption keys
# Enable all security features
```

## Troubleshooting

### Common Issues

**Issue**: "Class not found"
```bash
composer dump-autoload
```

**Issue**: "Permission denied" on storage
```bash
chmod -R 775 storage bootstrap/cache
```

**Issue**: Redis connection failed
```bash
docker-compose up -d redis
# or
sudo systemctl start redis
```

**Issue**: NPM errors
```bash
rm -rf node_modules package-lock.json
npm install
```

## Useful Commands

```bash
# Clear all caches
php artisan optimize:clear

# Cache everything
php artisan optimize

# List all routes
php artisan route:list

# Interactive shell
php artisan tinker

# Monitor queue
php artisan queue:monitor

# View logs in real-time
php artisan pail
```

## Resources

- [Laravel Documentation](https://laravel.com/docs)
- [Livewire Documentation](https://livewire.laravel.com)
- [Tailwind CSS Documentation](https://tailwindcss.com)
- [Alpine.js Documentation](https://alpinejs.dev)

## Getting Help

- Review this documentation
- Check existing issues on GitHub
- Ask in team chat
- Review test examples in `tests/` directory

---

Happy coding!
