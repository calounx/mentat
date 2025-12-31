# CHOM Quick Reference

Essential commands and information for daily development.

## Setup

```bash
# Initial setup
./scripts/setup-dev.sh

# Install git hooks
./scripts/install-hooks.sh

# Start all services
composer run dev
```

## Test Users

```
Owner:  owner@chom.test  / password
Admin:  admin@chom.test  / password
Member: member@chom.test / password
Viewer: viewer@chom.test / password
```

## Service URLs

```
App:            http://localhost:8000
MailHog UI:     http://localhost:8025
Adminer:        http://localhost:8080
Redis GUI:      http://localhost:8081
MinIO Console:  http://localhost:9001
Grafana:        http://localhost:3000
Prometheus:     http://localhost:9090
```

## Development

```bash
# Start services individually
php artisan serve          # Web server
npm run dev                # Vite HMR
php artisan queue:listen   # Queue worker
php artisan pail           # Log viewer

# Docker services
docker-compose up -d       # Start
docker-compose down        # Stop
docker-compose logs -f     # View logs
```

## Code Generation

```bash
php artisan make:service Sites/SiteService
php artisan make:repository SiteRepository
php artisan make:value-object Domain
php artisan make:api-resource SiteResource
php artisan make:api-resource SiteCollection --collection
```

## Debugging

```bash
php artisan debug:auth user@example.com
php artisan debug:tenant tenant-id
php artisan debug:cache
php artisan debug:cache --flush
php artisan debug:performance
php artisan debug:performance /api/v1/sites
```

## Database

```bash
# Reset & seed
php artisan migrate:fresh --seed

# Specific seeders
php artisan db:seed --class=TestUserSeeder
php artisan db:seed --class=TestDataSeeder
php artisan db:seed --class=PerformanceTestSeeder

# Migrations
php artisan migrate
php artisan migrate:rollback
php artisan make:migration create_sites_table
```

## Testing

```bash
# All tests
composer test
php artisan test

# With coverage
php artisan test --coverage

# Specific test
php artisan test --filter=SiteTest

# Stop on failure
php artisan test --stop-on-failure

# Parallel
php artisan test --parallel
```

## Code Quality

```bash
# Format code
composer run format
vendor/bin/pint

# Check style
vendor/bin/pint --test

# Static analysis
composer run analyse
vendor/bin/phpstan analyse

# All checks
composer run check
```

## Cache

```bash
# Clear all
php artisan optimize:clear

# Cache all
php artisan optimize

# Individual
php artisan cache:clear
php artisan config:clear
php artisan route:clear
php artisan view:clear
```

## Git

```bash
# Create feature branch
git checkout -b feature/my-feature

# Commit (hooks run automatically)
git add .
git commit -m "feat: Add feature"

# Push (tests run)
git push origin feature/my-feature

# Bypass hooks (not recommended)
git commit --no-verify
git push --no-verify
```

## Common Issues

```bash
# Permission denied
chmod -R 775 storage bootstrap/cache

# Class not found
composer dump-autoload

# Redis connection failed
docker-compose up -d redis

# NPM errors
rm -rf node_modules package-lock.json
npm install
```

## Documentation

- **Start here**: `ONBOARDING.md`
- **Development**: `DEVELOPMENT.md`
- **Contributing**: `CONTRIBUTING.md`
- **Testing**: `TESTING.md`
- **Code Style**: `CODE-STYLE.md`
- **Full Toolkit**: `DX-TOOLKIT-SUMMARY.md`

## API Testing

```bash
# Import collections
- Postman: docs/api/postman_collection.json
- Insomnia: docs/api/insomnia_workspace.json
```

## Useful Artisan Commands

```bash
php artisan route:list      # List all routes
php artisan tinker          # Interactive shell
php artisan queue:monitor   # Monitor queue
php artisan about           # Application info
php artisan schedule:list   # List scheduled tasks
```

## Environment

```bash
# Local
APP_ENV=local
APP_DEBUG=true
DB_CONNECTION=sqlite

# Staging
APP_ENV=staging
APP_DEBUG=false

# Production
APP_ENV=production
APP_DEBUG=false
```

## Performance

```bash
# Clear + optimize
php artisan optimize

# Queue workers
php artisan queue:work --tries=3

# Horizon (if installed)
php artisan horizon

# Schedule
php artisan schedule:work
```

## Backup

```bash
# Create backup
php artisan backup:run

# List backups
php artisan backup:list

# Clean old backups
php artisan backup:clean
```

---

Keep this reference handy for daily development!
