# CHOM Developer Cheat Sheets

Quick reference for common commands and operations. Bookmark this page!

## Table of Contents

- [Artisan Commands](#artisan-commands)
- [Database Operations](#database-operations)
- [Testing Commands](#testing-commands)
- [Git Workflow](#git-workflow)
- [Debugging Tips](#debugging-tips)
- [Queue & Jobs](#queue--jobs)
- [API Testing](#api-testing)
- [Code Quality](#code-quality)
- [Docker & Services](#docker--services)
- [Performance](#performance)

---

## Artisan Commands

### Application Management

```bash
# Start development server
php artisan serve
php artisan serve --port=8001              # Different port
php artisan serve --host=0.0.0.0           # Expose to network

# Clear all caches (fix 90% of weird issues)
php artisan optimize:clear

# Individual cache clearing
php artisan cache:clear                    # Application cache
php artisan config:clear                   # Config cache
php artisan route:clear                    # Route cache
php artisan view:clear                     # Compiled views
php artisan event:clear                    # Event cache

# Optimization (production)
php artisan optimize                       # Cache everything
php artisan config:cache                   # Cache config
php artisan route:cache                    # Cache routes
php artisan view:cache                     # Cache views
php artisan event:cache                    # Cache events
```

### Code Generation

```bash
# Models
php artisan make:model Site                # Just model
php artisan make:model Site -m             # Model + migration
php artisan make:model Site -f             # Model + factory
php artisan make:model Site -mf            # Model + migration + factory
php artisan make:model Site -mfc           # Model + migration + factory + controller
php artisan make:model Site --all          # Everything (migration, factory, seeder, policy, controller, requests)

# Controllers
php artisan make:controller SiteController                    # Basic controller
php artisan make:controller Api/SiteController --api          # API controller
php artisan make:controller SiteController --resource         # Resource controller
php artisan make:controller SiteController --invokable        # Single action

# Requests (Form validation)
php artisan make:request CreateSiteRequest
php artisan make:request UpdateSiteRequest

# Middleware
php artisan make:middleware CheckOrganization

# Jobs
php artisan make:job ProvisionSiteJob
php artisan make:job BackupSiteJob --sync          # Synchronous job

# Events & Listeners
php artisan make:event SiteCreated
php artisan make:listener SendSiteCreatedNotification --event=SiteCreated

# Policies
php artisan make:policy SitePolicy --model=Site

# Rules (Custom validation)
php artisan make:rule ValidDomain

# Commands
php artisan make:command CleanupOldBackups

# Livewire Components
php artisan make:livewire SiteList                 # Creates component + view
php artisan make:livewire sites/create             # Nested component
```

### Information & Debugging

```bash
# List all routes
php artisan route:list
php artisan route:list --path=api                  # Filter by path
php artisan route:list --method=POST               # Filter by method
php artisan route:list --name=sites                # Filter by name

# View configuration
php artisan config:show                            # All config
php artisan config:show database                   # Specific config

# Database info
php artisan db:show                                # Show connection info
php artisan db:table sites                         # Show table structure
php artisan db:monitor                             # Monitor connections

# View application info
php artisan about                                  # Application summary
php artisan env                                    # Show environment

# Interactive console
php artisan tinker
```

### Logs & Monitoring

```bash
# Real-time log viewer (Laravel Pail)
php artisan pail
php artisan pail --filter=error                    # Only errors
php artisan pail --filter=query                    # Only queries
php artisan pail --timeout=0                       # No timeout

# Traditional log viewing
tail -f storage/logs/laravel.log
tail -f storage/logs/laravel.log | grep ERROR     # Only errors
```

---

## Database Operations

### Migrations

```bash
# Create migration
php artisan make:migration create_sites_table
php artisan make:migration add_status_to_sites_table --table=sites

# Run migrations
php artisan migrate                                # Run pending migrations
php artisan migrate --force                        # Force in production
php artisan migrate --pretend                      # Show SQL without running
php artisan migrate --step                         # Run one at a time

# Rollback migrations
php artisan migrate:rollback                       # Rollback last batch
php artisan migrate:rollback --step=1              # Rollback one migration
php artisan migrate:reset                          # Rollback all migrations

# Reset & refresh
php artisan migrate:fresh                          # Drop all tables and re-migrate
php artisan migrate:fresh --seed                   # Drop, migrate, and seed
php artisan migrate:refresh                        # Rollback and re-migrate
php artisan migrate:refresh --seed                 # Rollback, migrate, seed

# Status
php artisan migrate:status                         # Show migration status
```

### Seeders

```bash
# Create seeder
php artisan make:seeder SitesTableSeeder

# Run seeders
php artisan db:seed                                # Run DatabaseSeeder
php artisan db:seed --class=SitesTableSeeder       # Run specific seeder
php artisan migrate:fresh --seed                   # Fresh migration + seed
```

### Factories

```bash
# Create factory
php artisan make:factory SiteFactory

# Using in Tinker
php artisan tinker
>>> Site::factory()->count(10)->create()           // Create 10 sites
>>> User::factory()->create(['email' => 'test@example.com'])
```

### Quick Database Tasks

```bash
# Backup database (SQLite)
cp database/database.sqlite database/backup-$(date +%Y%m%d).sqlite

# Reset to clean state
php artisan migrate:fresh --seed

# Create test user in Tinker
php artisan tinker
>>> User::factory()->create(['email' => 'admin@test.com', 'password' => bcrypt('password'), 'role' => 'owner'])
```

---

## Testing Commands

### Running Tests

```bash
# All tests
php artisan test
composer test                                      # Same as above

# Specific test suite
php artisan test --testsuite=Unit
php artisan test --testsuite=Feature
php artisan test --testsuite=Integration

# Specific test file
php artisan test tests/Feature/SiteControllerTest.php

# Specific test method
php artisan test --filter=test_user_can_create_site
php artisan test --filter=SiteControllerTest::test_user_can_create_site

# Parallel testing (faster)
php artisan test --parallel
php artisan test --parallel --processes=4

# With coverage
php artisan test --coverage
php artisan test --coverage --min=80               # Minimum 80% coverage
```

### Test Options

```bash
# Verbose output
php artisan test -v
php artisan test -vvv                              # Very verbose

# Stop on failure
php artisan test --stop-on-failure
php artisan test --stop-on-error

# Only run previously failed tests
php artisan test --retry

# Output formats
php artisan test --compact                         # Minimal output
php artisan test --log-junit=results.xml          # JUnit XML format
```

### Creating Tests

```bash
# Create test
php artisan make:test SiteControllerTest                      # Feature test
php artisan make:test SiteServiceTest --unit                  # Unit test
php artisan make:test SiteIntegrationTest --integration       # Integration test
```

---

## Git Workflow

### Branch Management

```bash
# Create and switch to new branch
git checkout -b feature/my-feature

# Switch branches
git checkout master
git checkout develop

# List branches
git branch                                         # Local branches
git branch -r                                      # Remote branches
git branch -a                                      # All branches

# Delete branch
git branch -d feature/my-feature                   # Safe delete
git branch -D feature/my-feature                   # Force delete
```

### Daily Workflow

```bash
# Start of day: Update from remote
git checkout master
git pull origin master

# Create feature branch
git checkout -b feature/add-backup-retention

# Make changes...
# ...

# Check status
git status
git diff                                           # Unstaged changes
git diff --staged                                  # Staged changes

# Stage changes
git add .                                          # All changes
git add app/Services/BackupService.php             # Specific file

# Commit
git commit -m "Add backup retention policy

- Add retention_days column to backups table
- Implement cleanup job for old backups
- Add tests for retention logic

Closes #123"

# Push to remote
git push origin feature/add-backup-retention
```

### Fixing Mistakes

```bash
# Undo last commit (keep changes)
git reset --soft HEAD~1

# Undo last commit (discard changes)
git reset --hard HEAD~1

# Amend last commit message
git commit --amend -m "Better commit message"

# Unstage file
git restore --staged filename.php

# Discard changes to file
git restore filename.php

# Stash changes temporarily
git stash                                          # Stash all changes
git stash pop                                      # Restore stashed changes
git stash list                                     # List stashes
git stash drop                                     # Delete latest stash
```

### Syncing with Upstream

```bash
# Update local master from remote
git checkout master
git pull origin master

# Rebase feature branch on latest master
git checkout feature/my-feature
git rebase master

# If conflicts occur
git status                                         # See conflicts
# Fix conflicts in files...
git add .
git rebase --continue

# Abort rebase if needed
git rebase --abort
```

### Useful Git Aliases

Add to `~/.gitconfig`:

```ini
[alias]
    co = checkout
    br = branch
    ci = commit
    st = status
    unstage = restore --staged
    last = log -1 HEAD
    visual = log --graph --oneline --all
    amend = commit --amend --no-edit
```

---

## Debugging Tips

### Laravel Debugging Helpers

```php
// In code:
dump($variable);                           // Print and continue
dd($variable);                             // Print and die
ddd($var1, $var2, $var3);                 // Dump multiple and die

// In Blade templates:
@dump($variable)
@dd($variable)

// Ray (if installed)
ray($variable);
ray($user)->blue()->label('User data');
```

### Database Debugging

```bash
# Enable query logging in Tinker
php artisan tinker
>>> DB::enableQueryLog();
>>> User::where('email', 'test@test.com')->first();
>>> DB::getQueryLog();

# In code (config/database.php):
'mysql' => [
    // ...
    'dump' => [
        'dump_binary_path' => '/usr/bin',
    ],
    'options' => [
        PDO::ATTR_EMULATE_PREPARES => true,
    ],
],
```

```php
// Log all queries
DB::listen(function ($query) {
    Log::info($query->sql, $query->bindings);
});

// See SQL without executing
User::where('active', true)->toSql();
```

### API Debugging

```bash
# Test API endpoints with curl
curl -X GET http://localhost:8000/api/v1/sites \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Accept: application/json"

# Pretty print JSON response
curl -X GET http://localhost:8000/api/v1/sites \
  -H "Authorization: Bearer YOUR_TOKEN" | jq

# Save response to file
curl -X GET http://localhost:8000/api/v1/sites \
  -H "Authorization: Bearer YOUR_TOKEN" > response.json
```

### Livewire Debugging

```php
// In Livewire component
public function mount()
{
    ray($this->user);                      // Ray debugger
    logger()->info('Component mounted', [
        'user_id' => $this->user->id,
    ]);
}

// Check Livewire events in browser console
window.livewire.hook('message.sent', (message) => {
    console.log('Message sent:', message);
});
```

### Performance Debugging

```bash
# Enable debugbar (in .env)
DEBUGBAR_ENABLED=true

# Check slow queries
php artisan db:monitor --max=100                   # Alert if > 100 connections

# Profile code
php artisan tinker
>>> $start = microtime(true);
>>> // Code to profile
>>> echo (microtime(true) - $start) . " seconds";
```

---

## Queue & Jobs

### Queue Workers

```bash
# Start queue worker
php artisan queue:work
php artisan queue:work --queue=high,default        # Priority queues
php artisan queue:work --tries=3                   # Retry failed jobs 3 times
php artisan queue:work --timeout=60                # Timeout after 60 seconds
php artisan queue:work --memory=512                # Restart if > 512MB

# Process single job then exit
php artisan queue:work --once

# Listen mode (restarts on code changes)
php artisan queue:listen

# Stop workers gracefully
php artisan queue:restart
```

### Job Management

```bash
# View failed jobs
php artisan queue:failed

# Retry failed job
php artisan queue:retry 5                          # Retry job ID 5
php artisan queue:retry all                        # Retry all failed

# Delete failed job
php artisan queue:forget 5                         # Delete job ID 5

# Clear all failed jobs
php artisan queue:flush

# Monitor queue
php artisan queue:monitor redis:default --max=100  # Alert if queue > 100
```

### Dispatching Jobs

```bash
# In Tinker
php artisan tinker
>>> dispatch(new ProvisionSiteJob($site));
>>> ProvisionSiteJob::dispatch($site);
>>> ProvisionSiteJob::dispatch($site)->onQueue('provisioning');
```

---

## API Testing

### Using cURL

```bash
# Register user
curl -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test User",
    "email": "test@example.com",
    "password": "password123"
  }'

# Login and get token
curl -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123"
  }' | jq -r '.token'

# Store token in variable
TOKEN=$(curl -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}' \
  | jq -r '.token')

# Use token in requests
curl -X GET http://localhost:8000/api/v1/sites \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/json"

# Create site
curl -X POST http://localhost:8000/api/v1/sites \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "domain": "example.com",
    "type": "wordpress",
    "php_version": "8.2"
  }'
```

### Using HTTPie (more user-friendly)

```bash
# Install
pip install httpie

# Login
http POST :8000/api/v1/auth/login email=test@example.com password=password123

# Authenticated request
http GET :8000/api/v1/sites "Authorization:Bearer $TOKEN"

# Create site (auto-sets Content-Type)
http POST :8000/api/v1/sites \
  "Authorization:Bearer $TOKEN" \
  domain=example.com \
  type=wordpress \
  php_version=8.2
```

---

## Code Quality

### Laravel Pint (Code Formatting)

```bash
# Format all files
./vendor/bin/pint

# Format specific directory
./vendor/bin/pint app/Services

# Format specific file
./vendor/bin/pint app/Services/SiteService.php

# Dry run (show what would change)
./vendor/bin/pint --test

# Different preset
./vendor/bin/pint --preset laravel
./vendor/bin/pint --preset psr12
```

### PHPStan (Static Analysis)

```bash
# Analyze all code
./vendor/bin/phpstan analyse

# Analyze specific directory
./vendor/bin/phpstan analyse app/Services

# Different levels (0-9, higher = stricter)
./vendor/bin/phpstan analyse --level=5

# Generate baseline (ignore existing issues)
./vendor/bin/phpstan analyse --generate-baseline
```

### Security Audit

```bash
# Check for vulnerable dependencies
composer audit
composer audit --format=json

# Update dependencies
composer update                                    # All packages
composer update laravel/framework                  # Specific package
composer update --dry-run                          # Preview changes
```

### All Quality Checks

```bash
# Run everything
composer test && \
./vendor/bin/pint && \
./vendor/bin/phpstan analyse && \
composer audit
```

---

## Docker & Services

### Docker Compose

```bash
# Start all services
docker-compose up -d

# Start specific service
docker-compose up -d redis
docker-compose up -d mysql

# View logs
docker-compose logs
docker-compose logs -f redis                       # Follow logs

# Stop services
docker-compose down

# Stop and remove volumes
docker-compose down -v

# Rebuild containers
docker-compose up -d --build

# View running containers
docker-compose ps
```

### Individual Services

```bash
# Redis
docker-compose up -d redis
redis-cli ping                                     # Test connection
redis-cli                                          # Interactive CLI
redis-cli FLUSHALL                                 # Clear all data

# MySQL
docker-compose up -d mysql
docker-compose exec mysql mysql -uroot -p          # Connect to MySQL

# MailHog (email testing)
docker-compose up -d mailhog
# View emails at http://localhost:8025
```

---

## Performance

### Optimization Commands

```bash
# Production optimization
php artisan optimize
php artisan config:cache
php artisan route:cache
php artisan view:cache
composer install --optimize-autoloader --no-dev

# Clear optimization (development)
php artisan optimize:clear
```

### Performance Testing

```bash
# Benchmark endpoint
ab -n 1000 -c 10 http://localhost:8000/api/v1/sites

# Install Apache Bench
sudo apt-get install apache2-utils                 # Linux
brew install apache-bench                          # macOS

# Stress test
ab -n 10000 -c 100 http://localhost:8000/
```

### Query Performance

```php
// Enable query logging
DB::enableQueryLog();

// Run your code
$sites = Site::with('organization', 'vps')->get();

// View queries
dump(DB::getQueryLog());

// N+1 query detection
// Use Laravel Debugbar or:
DB::listen(function ($query) {
    if ($query->time > 100) {  // Queries over 100ms
        Log::warning('Slow query', [
            'sql' => $query->sql,
            'time' => $query->time,
        ]);
    }
});
```

---

## Quick Wins

### Fix Most Issues

```bash
# The magic combo (fixes 90% of weird issues)
php artisan optimize:clear
composer dump-autoload
npm run build
```

### Reset Everything

```bash
# Nuclear option - fresh start
rm -rf vendor node_modules
rm database/database.sqlite
composer install
npm install
touch database/database.sqlite
php artisan migrate:fresh --seed
npm run build
```

### Quick Test Data

```bash
php artisan tinker
>>> User::factory()->count(10)->create();
>>> Site::factory()->count(50)->create();
>>> VPS::factory()->count(5)->create();
```

### Environment Switching

```bash
# Copy environment files
cp .env.example .env.local
cp .env.example .env.testing

# Switch environments
php artisan config:clear
export APP_ENV=testing
php artisan config:cache
```

---

## Keyboard Shortcuts

### VS Code (with PHP extensions)

```
Ctrl+Shift+P        Command palette
Ctrl+P              Quick file open
Ctrl+Shift+F        Search in files
F12                 Go to definition
Alt+F12             Peek definition
Shift+F12           Find references
Ctrl+Space          Trigger suggestions
```

### PHPStorm

```
Double Shift        Search everywhere
Ctrl+N              Go to class
Ctrl+Shift+N        Go to file
Ctrl+B              Go to declaration
Ctrl+Alt+B          Go to implementation
Ctrl+Shift+F        Find in path
```

---

## Environment Variables Quick Reference

```bash
# Database
DB_CONNECTION=sqlite|mysql|pgsql
DB_DATABASE=database/database.sqlite

# Cache & Queue
CACHE_STORE=file|redis|array
QUEUE_CONNECTION=sync|redis|database

# Services
REDIS_HOST=127.0.0.1
REDIS_PORT=6379

# Debugging
APP_DEBUG=true|false
LOG_LEVEL=debug|info|warning|error

# Features
TELESCOPE_ENABLED=true|false
DEBUGBAR_ENABLED=true|false
```

---

## Useful One-Liners

```bash
# Count lines of code
find app -name "*.php" | xargs wc -l

# Find todos in code
grep -r "TODO" app/

# Find all Livewire components
find app/Livewire -name "*.php" -exec basename {} .php \;

# List all migrations
ls -1 database/migrations/

# Count tests
find tests -name "*Test.php" | wc -l

# Find large files
find . -type f -size +1M -ls

# Check PHP memory usage
php -r "echo ini_get('memory_limit').PHP_EOL;"
```

---

## Pro Tips

1. **Alias common commands** in `~/.bashrc` or `~/.zshrc`:
   ```bash
   alias art="php artisan"
   alias pint="./vendor/bin/pint"
   alias test="php artisan test"
   alias tinker="php artisan tinker"
   ```

2. **Use command history**: Press `Ctrl+R` and type to search previous commands

3. **Chain commands** with `&&`:
   ```bash
   php artisan test && ./vendor/bin/pint && git commit
   ```

4. **Background processes** with `&`:
   ```bash
   php artisan queue:work &
   ```

5. **Watch files** for changes:
   ```bash
   # Install fswatch
   fswatch -o app/ | xargs -n1 -I{} php artisan test
   ```

---

**Remember:** When in doubt, run `php artisan` to see all available commands!

**Bookmark this page** - you'll reference it constantly!
