# CHOM Developer Documentation

Complete developer documentation index for CHOM.

## Quick Links

- **[Onboarding Guide](../ONBOARDING.md)** - Start here! Get productive in under 1 hour
- **[Development Guide](../DEVELOPMENT.md)** - Detailed development workflows
- **[Contributing Guide](../CONTRIBUTING.md)** - How to contribute
- **[Testing Guide](../TESTING.md)** - Testing best practices
- **[Code Style Guide](../CODE-STYLE.md)** - Code style conventions

## Getting Started

### 1. One-Command Setup

```bash
./scripts/setup-dev.sh
```

This single command:
- Installs all dependencies
- Sets up environment
- Creates database
- Seeds test data
- Runs tests
- Builds assets

### 2. Start Development

```bash
composer run dev
```

Access: http://localhost:8000

Login: `admin@chom.test` / `password`

### 3. Your First Contribution

1. Pick an issue labeled "good first issue"
2. Create a feature branch
3. Make your changes
4. Write tests
5. Submit a pull request

## Project Structure

```
chom/
├── app/                    # Application code
│   ├── Console/           # Artisan commands
│   ├── Http/              # Controllers, middleware
│   ├── Models/            # Eloquent models
│   ├── Services/          # Business logic
│   └── Repositories/      # Data access
├── database/
│   ├── migrations/        # Database migrations
│   └── seeders/           # Test data seeders
├── resources/
│   ├── views/             # Blade templates
│   └── js/                # JavaScript
├── routes/                # Route definitions
├── tests/                 # Test suite
├── scripts/               # Development scripts
└── docs/                  # Documentation
```

## Documentation

### Core Documentation

1. **[ONBOARDING.md](../ONBOARDING.md)**
   - New developer setup
   - First task walkthrough
   - Team resources

2. **[DEVELOPMENT.md](../DEVELOPMENT.md)**
   - Architecture overview
   - Development workflow
   - Common patterns
   - Debugging tools

3. **[CONTRIBUTING.md](../CONTRIBUTING.md)**
   - Contribution guidelines
   - Code of conduct
   - PR process
   - Bug reporting

4. **[TESTING.md](../TESTING.md)**
   - Testing strategies
   - Writing tests
   - Coverage requirements
   - Best practices

5. **[CODE-STYLE.md](../CODE-STYLE.md)**
   - PHP conventions
   - JavaScript style
   - Blade templates
   - Git commits

### API Documentation

- **[Postman Collection](./api/postman_collection.json)** - Complete API collection
- **[Insomnia Workspace](./api/insomnia_workspace.json)** - Insomnia workspace

## Development Tools

### Code Generators

Generate boilerplate code quickly:

```bash
# Service class
php artisan make:service Sites/SiteCreationService

# Repository with interface
php artisan make:repository SiteRepository

# Value object
php artisan make:value-object Domain

# API resource
php artisan make:api-resource SiteResource
```

### Debugging Commands

Debug common issues:

```bash
# Authentication issues
php artisan debug:auth user@example.com

# Tenant issues
php artisan debug:tenant tenant-id

# Cache issues
php artisan debug:cache --flush

# Performance profiling
php artisan debug:performance /api/v1/sites
```

### Database Seeders

Seed test data:

```bash
# Test users (all roles)
php artisan db:seed --class=TestUserSeeder

# Test data (sites, VPS, backups)
php artisan db:seed --class=TestDataSeeder

# Performance test data (large dataset)
php artisan db:seed --class=PerformanceTestSeeder
```

## Docker Services

Local development environment:

```bash
# Start all services
docker-compose up -d

# Stop all services
docker-compose down

# View logs
docker-compose logs -f
```

### Services

| Service | Port | Purpose |
|---------|------|---------|
| MySQL | 3306 | Database |
| Redis | 6379 | Cache/Queue |
| MailHog | 8025 | Email testing |
| Adminer | 8080 | Database GUI |
| Redis Commander | 8081 | Redis GUI |
| MinIO | 9001 | S3-compatible storage |
| Grafana | 3000 | Metrics dashboard |
| Prometheus | 9090 | Metrics collection |

## Quality Tools

### Code Formatting

```bash
# Auto-format PHP
composer run format
vendor/bin/pint

# Check only
vendor/bin/pint --test
```

### Static Analysis

```bash
# PHPStan
composer run analyse
vendor/bin/phpstan analyse

# PHPMD
vendor/bin/phpmd app text phpmd.xml
```

### Git Hooks

Automated quality checks:

```bash
# Install hooks
./scripts/install-hooks.sh
```

Hooks:
- **pre-commit**: Syntax check, formatting, static analysis
- **pre-push**: Full test suite

## Testing

```bash
# Run all tests
composer test

# With coverage
php artisan test --coverage

# Specific test
php artisan test --filter=SiteTest

# Stop on failure
php artisan test --stop-on-failure
```

## Common Commands

### Development

```bash
# Start dev server
php artisan serve

# Watch frontend
npm run dev

# Queue worker
php artisan queue:listen

# View logs
php artisan pail
```

### Database

```bash
# Fresh migration + seed
php artisan migrate:fresh --seed

# Create migration
php artisan make:migration create_sites_table

# Rollback
php artisan migrate:rollback
```

### Cache

```bash
# Clear all caches
php artisan optimize:clear

# Cache config/routes/views
php artisan optimize

# Clear specific cache
php artisan cache:clear
php artisan config:clear
php artisan route:clear
php artisan view:clear
```

## Environment Setup

### Local (.env)

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
```

### Production

```env
APP_ENV=production
APP_DEBUG=false
# Use strong keys and secrets
```

## Architecture Patterns

### Service Layer

Business logic in service classes:

```php
class SiteCreationService
{
    public function execute(array $data): Site
    {
        // Business logic here
    }
}
```

### Repository Pattern

Data access abstraction:

```php
interface SiteRepositoryInterface
{
    public function find(string $id): ?Site;
    public function create(array $data): Site;
}
```

### Value Objects

Immutable value types:

```php
class Domain
{
    public function __construct(
        private readonly string $value
    ) {
        $this->validate($value);
    }
}
```

## Troubleshooting

### Common Issues

**Permission denied on storage**
```bash
chmod -R 775 storage bootstrap/cache
```

**Class not found**
```bash
composer dump-autoload
```

**Redis connection failed**
```bash
docker-compose up -d redis
```

**NPM errors**
```bash
rm -rf node_modules package-lock.json
npm install
```

### Debug Tools

1. **Laravel Telescope**: Request debugging
2. **Laravel Debugbar**: Development toolbar
3. **Laravel Pail**: Log streaming
4. **Debug commands**: Custom debug commands

## Resources

### Laravel Documentation
- [Laravel 12](https://laravel.com/docs/12.x)
- [Livewire 3](https://livewire.laravel.com/docs)
- [Sanctum](https://laravel.com/docs/sanctum)
- [Cashier](https://laravel.com/docs/billing)

### Frontend
- [Alpine.js](https://alpinejs.dev)
- [Tailwind CSS](https://tailwindcss.com)
- [Vite](https://vitejs.dev)

### Testing
- [PHPUnit](https://phpunit.de)
- [Pest](https://pestphp.com) (optional)

## Getting Help

1. Check documentation (you are here!)
2. Review existing code
3. Ask in team chat
4. Create GitHub discussion
5. Check Laravel documentation

## Quick Reference Card

```bash
# Setup
./scripts/setup-dev.sh
composer run dev

# Development
php artisan serve
npm run dev
php artisan queue:listen

# Testing
composer test
php artisan test --coverage

# Debugging
php artisan debug:auth user@example.com
php artisan debug:cache
php artisan tinker

# Database
php artisan migrate:fresh --seed
php artisan db:seed --class=TestUserSeeder

# Code Generation
php artisan make:service MyService
php artisan make:repository MyRepository

# Quality
composer run format
composer run analyse
./scripts/install-hooks.sh

# Docker
docker-compose up -d
docker-compose down
```

## Contributing

We welcome contributions! Please read:

1. [CONTRIBUTING.md](../CONTRIBUTING.md) - Contribution guidelines
2. [CODE-STYLE.md](../CODE-STYLE.md) - Code style guide
3. [TESTING.md](../TESTING.md) - Testing guidelines

## Next Steps

1. **New developers**: Start with [ONBOARDING.md](../ONBOARDING.md)
2. **Understanding the code**: Read [DEVELOPMENT.md](../DEVELOPMENT.md)
3. **Making changes**: Review [CONTRIBUTING.md](../CONTRIBUTING.md)
4. **Writing tests**: Check [TESTING.md](../TESTING.md)

---

Welcome to the CHOM development team! Happy coding!
