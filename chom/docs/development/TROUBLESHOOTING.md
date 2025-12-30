# CHOM Development Troubleshooting Guide

Common issues and their solutions. Use this as your first stop when something goes wrong.

## Table of Contents

- [Environment Setup Issues](#environment-setup-issues)
- [Database Problems](#database-problems)
- [Testing Failures](#testing-failures)
- [Build & Asset Errors](#build--asset-errors)
- [Performance Issues](#performance-issues)
- [Authentication & Authorization](#authentication--authorization)
- [API Issues](#api-issues)
- [Queue & Job Problems](#queue--job-problems)
- [Livewire Issues](#livewire-issues)
- [Git & Version Control](#git--version-control)

---

## Environment Setup Issues

### Issue: PHP version mismatch

**Symptoms:**
```
Your PHP version (8.1.x) does not satisfy the requirement (^8.2)
```

**Solution:**

<details>
<summary>Ubuntu/Debian</summary>

```bash
# Add PHP repository
sudo add-apt-repository ppa:ondrej/php
sudo apt-get update

# Install PHP 8.2
sudo apt-get install php8.2 php8.2-cli php8.2-fpm php8.2-common

# Set as default
sudo update-alternatives --set php /usr/bin/php8.2

# Verify
php -v
```
</details>

<details>
<summary>macOS</summary>

```bash
# Using Homebrew
brew install php@8.2

# Link it
brew link php@8.2 --force

# Verify
php -v
```
</details>

---

### Issue: Missing PHP Extensions

**Symptoms:**
```
The requested PHP extension ext-redis is missing from your system
The requested PHP extension ext-gd is missing from your system
```

**Solution:**

```bash
# Ubuntu/Debian
sudo apt-get install php8.2-redis php8.2-gd php8.2-mysql \
  php8.2-xml php8.2-mbstring php8.2-curl php8.2-zip

# macOS (via PECL)
pecl install redis
pecl install gd

# Verify installed extensions
php -m | grep -E 'redis|gd|mysql'
```

**Decision Tree:**

```
Is extension available via package manager?
├─ Yes → Use apt/brew/yum
│   └─ sudo apt-get install php8.2-{extension}
└─ No → Use PECL
    ├─ pecl install {extension}
    └─ Add to php.ini: extension={extension}.so
```

---

### Issue: Composer install fails

**Symptoms:**
```
Your requirements could not be resolved to an installable set of packages
mmap() failed: [12] Cannot allocate memory
```

**Solutions:**

**Problem 1: Dependency conflicts**
```bash
# Clear Composer cache
composer clear-cache

# Try with --ignore-platform-reqs (development only!)
composer install --ignore-platform-reqs

# Update a specific package
composer update vendor/package --with-dependencies
```

**Problem 2: Out of memory**
```bash
# Increase PHP memory limit temporarily
php -d memory_limit=2G /usr/local/bin/composer install

# Or permanently in php.ini
# memory_limit = 2G
```

---

### Issue: NPM install fails

**Symptoms:**
```
npm ERR! code EACCES
npm ERR! syscall access
npm ERR! ENOSPC: no space left on device
```

**Solutions:**

**Problem 1: Permission errors**
```bash
# Fix npm permissions (DO NOT use sudo npm install!)
mkdir ~/.npm-global
npm config set prefix '~/.npm-global'
export PATH=~/.npm-global/bin:$PATH

# Add to ~/.bashrc or ~/.zshrc
echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc
```

**Problem 2: Disk space**
```bash
# Clear npm cache
npm cache clean --force

# Check disk space
df -h

# Remove old node_modules
rm -rf node_modules package-lock.json
npm install
```

**Problem 3: Network issues**
```bash
# Increase timeout
npm install --timeout=60000

# Use different registry
npm install --registry=https://registry.npmjs.org/
```

---

### Issue: Port 8000 already in use

**Symptoms:**
```
[Symfony\Component\Process\Exception\RuntimeException]
Failed to listen on "127.0.0.1:8000"
```

**Solution:**

```bash
# Find what's using port 8000
lsof -ti:8000                                  # macOS/Linux

# Kill the process
kill -9 $(lsof -ti:8000)

# Or use a different port
php artisan serve --port=8001

# Update .env
APP_URL=http://localhost:8001
```

---

### Issue: Redis connection refused

**Symptoms:**
```
Connection refused [tcp://127.0.0.1:6379]
```

**Solution:**

```bash
# Check if Redis is running
redis-cli ping
# Should return: PONG

# If not running:
# Ubuntu/Debian
sudo systemctl start redis
sudo systemctl enable redis  # Auto-start on boot

# macOS
brew services start redis

# Verify connection
redis-cli ping

# Check Redis is listening
netstat -an | grep 6379

# If still failing, disable Redis temporarily in .env
CACHE_STORE=file
QUEUE_CONNECTION=sync
SESSION_DRIVER=file
```

---

## Database Problems

### Issue: Database not found

**Symptoms:**
```
SQLSTATE[HY000] [1049] Unknown database 'chom'
SQLSTATE[HY000] [14] unable to open database file
```

**Solution:**

**For SQLite:**
```bash
# Create the database file
touch database/database.sqlite

# Verify .env points to it
DB_CONNECTION=sqlite
# DB_DATABASE line should be commented out or removed

# Run migrations
php artisan migrate
```

**For MySQL:**
```bash
# Create database
mysql -u root -p
mysql> CREATE DATABASE chom;
mysql> CREATE USER 'chom'@'localhost' IDENTIFIED BY 'secret';
mysql> GRANT ALL PRIVILEGES ON chom.* TO 'chom'@'localhost';
mysql> FLUSH PRIVILEGES;
mysql> exit;

# Update .env
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=chom
DB_USERNAME=chom
DB_PASSWORD=secret

# Test connection
php artisan db:show

# Run migrations
php artisan migrate
```

---

### Issue: Migration failed

**Symptoms:**
```
SQLSTATE[42S01]: Base table or view already exists
SQLSTATE[42S02]: Base table or view not found
```

**Solutions:**

**Decision Tree:**

```
Is this development?
├─ Yes → Safe to reset
│   ├─ php artisan migrate:fresh
│   └─ php artisan migrate:fresh --seed
└─ No (production/staging) → Careful!
    ├─ Check migration status
    │   └─ php artisan migrate:status
    ├─ Rollback specific migration
    │   └─ php artisan migrate:rollback --step=1
    └─ Fix and re-run
        └─ php artisan migrate
```

**Fresh start (development only):**
```bash
# WARNING: Deletes all data!
php artisan migrate:fresh
php artisan migrate:fresh --seed
```

**Safe rollback:**
```bash
# Rollback last batch
php artisan migrate:rollback

# Rollback specific number of migrations
php artisan migrate:rollback --step=1

# Check what will run
php artisan migrate --pretend
```

---

### Issue: Foreign key constraint fails

**Symptoms:**
```
SQLSTATE[23000]: Integrity constraint violation: 1452 Cannot add or update a child row
SQLSTATE[23000]: Integrity constraint violation: 1451 Cannot delete or update a parent row
```

**Solution:**

**Understanding the problem:**
```
Foreign key constraints ensure data integrity:
- Parent table must exist before child
- Cannot delete parent if children exist
```

**Migration order fix:**
```bash
# Check migration timestamps
ls -l database/migrations/

# Example problem:
# 2024_01_01_000001_create_sites_table.php
# 2024_01_01_000000_create_organizations_table.php
# ^^^ sites runs BEFORE organizations (wrong!)

# Solution: Rename files to fix order
mv 2024_01_01_000001_create_sites_table.php \
   2024_01_01_000002_create_sites_table.php

# Now organizations runs first
```

**Quick fix (development):**
```bash
# Reset and re-run in correct order
php artisan migrate:fresh
```

---

### Issue: Column not found

**Symptoms:**
```
SQLSTATE[42S22]: Column not found: 1054 Unknown column 'status' in 'field list'
```

**Solutions:**

```bash
# Clear config cache (might be using old schema)
php artisan config:clear

# Check if migration ran
php artisan migrate:status

# Run pending migrations
php artisan migrate

# If column should exist, check migration file
php artisan db:table sites  # See actual table structure
```

---

## Testing Failures

### Issue: Tests use production database

**Symptoms:**
```
Tests delete/modify production data
SQLSTATE[HY000]: General error: 8 attempt to write a readonly database
```

**Solution:**

```bash
# Check phpunit.xml has correct test DB config
# Should have:
<env name="DB_CONNECTION" value="sqlite"/>
<env name="DB_DATABASE" value=":memory:"/>

# Verify tests use correct DB
php artisan config:show database --env=testing

# Clear config before testing
php artisan config:clear
php artisan test
```

**In test files:**
```php
use RefreshDatabase;  // ALWAYS use this trait

class MyTest extends TestCase
{
    use RefreshDatabase;  // Resets DB for each test

    public function test_something()
    {
        // Test code
    }
}
```

---

### Issue: Tests fail but code works

**Symptoms:**
```
Expected status code 200 but received 500
Expected response to be successful but got 403
```

**Debugging steps:**

```php
// Add debugging to test
public function test_user_can_create_site()
{
    $response = $this->post('/api/v1/sites', $data);

    // Debug the response
    dump($response->getContent());
    dump($response->status());

    $response->assertStatus(201);
}
```

**Common causes:**

```
1. Missing authentication
   → Add: $this->actingAs($user)

2. Missing organization context
   → Attach user to organization first

3. Validation failing
   → Check $response->json() for errors

4. Authorization failing (Policy)
   → Ensure user has correct role/permissions

5. Missing factory relationships
   → Use ->for() or ->has() in factories
```

**Example fix:**
```php
// Before (fails)
$user = User::factory()->create();
$response = $this->actingAs($user)->post('/api/v1/sites', $data);

// After (works)
$user = User::factory()->create();
$organization = Organization::factory()->create();
$user->organizations()->attach($organization, ['role' => 'owner']);
$user->setCurrentOrganization($organization);

$response = $this->actingAs($user)->post('/api/v1/sites', $data);
```

---

### Issue: Parallel tests fail

**Symptoms:**
```
Tests pass individually but fail when run in parallel
Database conflicts, race conditions
```

**Solution:**

```bash
# Disable parallel testing temporarily
php artisan test

# Or reduce parallel processes
php artisan test --parallel --processes=2

# Check for shared state issues
# Common problems:
# - Static properties
# - Shared cache/session
# - Hardcoded IDs
```

**Fix shared state:**
```php
// Bad (shared state)
class MyTest extends TestCase
{
    private static $user;  // Shared across tests!

    public function test_a()
    {
        self::$user = User::factory()->create();
    }
}

// Good (isolated)
class MyTest extends TestCase
{
    public function test_a()
    {
        $user = User::factory()->create();  // New for each test
    }
}
```

---

## Build & Asset Errors

### Issue: Vite not running / HMR not working

**Symptoms:**
```
Vite manifest not found
[vite] connecting...  (never completes)
Changes don't reflect in browser
```

**Solutions:**

**Problem 1: Vite not started**
```bash
# Check if Vite is running
lsof -ti:5173  # Should return process ID

# Start Vite
npm run dev

# Or use composer dev (starts everything)
composer run dev
```

**Problem 2: Port conflict**
```bash
# Kill process on port 5173
kill -9 $(lsof -ti:5173)

# Restart Vite
npm run dev
```

**Problem 3: CORS issues**
```bash
# In vite.config.js, ensure server settings:
export default defineConfig({
    server: {
        host: true,
        strictPort: true,
        port: 5173,
        hmr: {
            host: 'localhost',
        },
    },
});
```

**Problem 4: Build instead of dev**
```bash
# If you ran 'npm run build', assets are compiled
# To get HMR back, restart dev server:
rm -rf public/build
npm run dev
```

---

### Issue: CSS not loading / Tailwind not working

**Symptoms:**
```
Unstyled HTML
Tailwind classes not applied
```

**Solutions:**

```bash
# Rebuild assets
npm run build

# Check Tailwind config exists
ls -la tailwind.config.js

# Verify CSS is imported in app.js
# Should have:
import '../css/app.css';

# Clear browser cache (hard refresh)
# Chrome/Firefox: Ctrl+Shift+R
# Safari: Cmd+Shift+R

# Restart Vite
npm run dev
```

**Tailwind not detecting classes:**
```js
// In tailwind.config.js, ensure content paths include your files
export default {
    content: [
        './resources/**/*.blade.php',
        './resources/**/*.js',
        './app/Livewire/**/*.php',
    ],
    // ...
}
```

---

### Issue: JavaScript errors in browser

**Symptoms:**
```
Uncaught ReferenceError: Alpine is not defined
Uncaught TypeError: Cannot read property 'addEventListener' of null
```

**Solutions:**

```bash
# Check browser console (F12) for detailed errors

# Rebuild assets
npm run build

# Clear browser cache
Ctrl+Shift+R (hard refresh)

# Check if JavaScript is imported correctly
# In resources/views/layouts/app.blade.php:
@vite(['resources/css/app.css', 'resources/js/app.js'])
```

**Alpine.js not working:**
```js
// In resources/js/app.js, ensure Alpine is initialized:
import Alpine from 'alpinejs';
window.Alpine = Alpine;
Alpine.start();
```

---

## Performance Issues

### Issue: Slow page loads

**Symptoms:**
```
Pages take 3-5+ seconds to load
Laravel Debugbar shows many queries
```

**Diagnosis:**

```bash
# Enable Debugbar
DEBUGBAR_ENABLED=true

# Check for N+1 queries in Debugbar's "Queries" tab
# Look for repeated similar queries
```

**Solutions:**

**Problem 1: N+1 Queries**
```php
// Bad (N+1 query)
$sites = Site::all();
foreach ($sites as $site) {
    echo $site->organization->name;  // Query for EACH site!
}

// Good (eager loading)
$sites = Site::with('organization')->get();
foreach ($sites as $site) {
    echo $site->organization->name;  // No extra queries
}
```

**Problem 2: Missing indexes**
```bash
# Add index to frequently queried columns
php artisan make:migration add_index_to_sites_organization_id

# In migration:
public function up()
{
    Schema::table('sites', function (Blueprint $table) {
        $table->index('organization_id');
        $table->index('status');
    });
}
```

**Problem 3: No caching**
```php
// Before (always queries DB)
$sites = Site::where('status', 'active')->get();

// After (caches for 1 hour)
$sites = Cache::remember('active-sites', 3600, function () {
    return Site::where('status', 'active')->get();
});
```

---

### Issue: Queue jobs not processing

**Symptoms:**
```
Jobs stuck in queue
No queue worker output
Background tasks never complete
```

**Diagnosis:**

```bash
# Check queue worker is running
ps aux | grep "queue:work"

# Check failed jobs
php artisan queue:failed

# Monitor queue
redis-cli
> LLEN queues:default  # See queue length
```

**Solutions:**

```bash
# Start queue worker
php artisan queue:work

# Or use listen (auto-restarts on code changes)
php artisan queue:listen

# Restart workers (if code changed)
php artisan queue:restart

# Retry failed jobs
php artisan queue:retry all

# Clear failed jobs
php artisan queue:flush
```

**Job failing silently:**
```php
// Add logging to job
public function handle()
{
    Log::info('Job started', ['site_id' => $this->site->id]);

    try {
        // Job logic
    } catch (\Exception $e) {
        Log::error('Job failed', [
            'error' => $e->getMessage(),
            'trace' => $e->getTraceAsString(),
        ]);
        throw $e;  // Re-throw to mark as failed
    }
}
```

---

## Authentication & Authorization

### Issue: Cannot login / Session lost immediately

**Symptoms:**
```
Login succeeds but redirects back to login
Session not persisting
```

**Solutions:**

```bash
# Check session driver in .env
SESSION_DRIVER=file  # Use file for testing
# SESSION_DRIVER=redis  # Ensure Redis is running if using

# Clear sessions
php artisan session:clear
rm -rf storage/framework/sessions/*

# Check session config
php artisan config:show session

# Disable secure cookies for local HTTP
SESSION_SECURE_COOKIE=false  # In .env (only for local!)
SESSION_SAME_SITE=lax
```

**Chrome SameSite cookie issues:**
```
# In .env for local development:
SESSION_SECURE_COOKIE=false
SESSION_SAME_SITE=lax
APP_URL=http://localhost:8000  # Ensure matches actual URL
```

---

### Issue: 403 Forbidden / Authorization failed

**Symptoms:**
```
User authenticated but cannot access resource
403 Forbidden error
This action is unauthorized
```

**Diagnosis:**

```php
// In your controller/test
dump(auth()->user()->role);
dump(auth()->user()->currentOrganization);
dump($resource->organization_id);
```

**Common causes:**

```
1. User not in organization
   → $user->organizations()->attach($org)

2. Wrong role
   → Check Policy's role requirements

3. No current organization set
   → $user->setCurrentOrganization($org)

4. Resource belongs to different organization
   → Verify $resource->organization_id matches
```

**Fix example:**
```php
// Setup user correctly
$user = User::factory()->create();
$organization = Organization::factory()->create();
$user->organizations()->attach($organization, ['role' => 'owner']);
$user->setCurrentOrganization($organization);

// Now authorized
$this->actingAs($user)->get('/sites')->assertOk();
```

---

## API Issues

### Issue: 401 Unauthorized

**Symptoms:**
```
{"message": "Unauthenticated."}
```

**Solution:**

```bash
# Ensure token is sent correctly
curl -X GET http://localhost:8000/api/v1/sites \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Accept: application/json"

# Note: Must include 'Bearer ' prefix!
# Note: Must include 'Accept: application/json' header

# Create a token in Tinker
php artisan tinker
>>> $user = User::first();
>>> $token = $user->createToken('test-token')->plainTextToken;
>>> echo $token;
```

---

### Issue: 422 Validation Error

**Symptoms:**
```
{"message": "The given data was invalid.", "errors": {...}}
```

**Solution:**

```bash
# Check the errors object for details
curl -X POST http://localhost:8000/api/v1/sites \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"domain": "invalid"}' | jq

# Example response:
{
  "message": "The given data was invalid.",
  "errors": {
    "type": ["The type field is required."],
    "php_version": ["The php version field is required."]
  }
}

# Fix: Include all required fields
curl -X POST http://localhost:8000/api/v1/sites \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "domain": "example.com",
    "type": "wordpress",
    "php_version": "8.2"
  }'
```

---

### Issue: CORS errors

**Symptoms:**
```
Access to fetch at 'http://localhost:8000/api/v1/sites' from origin 'http://localhost:3000' has been blocked by CORS policy
```

**Solution:**

```bash
# In .env, add your frontend URL to allowed origins
CORS_ALLOWED_ORIGINS=http://localhost:3000,http://localhost:5173,http://localhost:8000

# Clear config cache
php artisan config:clear

# Restart server
php artisan serve
```

---

## Queue & Job Problems

### Issue: Jobs fail silently

**Symptoms:**
```
Job dispatched but nothing happens
No error logs
```

**Solution:**

```php
// Add comprehensive logging
public function handle()
{
    Log::info('Job started', [
        'job' => static::class,
        'data' => $this->site->toArray(),
    ]);

    try {
        $this->process();
        Log::info('Job completed successfully');
    } catch (\Exception $e) {
        Log::error('Job failed', [
            'error' => $e->getMessage(),
            'trace' => $e->getTraceAsString(),
        ]);
        throw $e;
    }
}

// Add failed() method
public function failed(\Throwable $exception)
{
    Log::error('Job marked as failed', [
        'job' => static::class,
        'exception' => $exception->getMessage(),
    ]);

    // Notify admins, etc.
}
```

---

## Livewire Issues

### Issue: Livewire component not updating

**Symptoms:**
```
Click button but nothing happens
Component doesn't re-render
```

**Solutions:**

```bash
# Check browser console for JavaScript errors

# Ensure Livewire is loaded
# In layout file:
@livewireScripts

# Clear Livewire cached views
php artisan view:clear

# Rebuild assets
npm run build
```

**Component state not updating:**
```php
// Ensure properties are public
class SiteList extends Component
{
    public $sites;  // Must be public!

    public function mount()
    {
        $this->sites = Site::all();
    }
}
```

---

## Git & Version Control

### Issue: Merge conflicts

**Symptoms:**
```
CONFLICT (content): Merge conflict in app/Services/SiteService.php
Automatic merge failed; fix conflicts and then commit the result.
```

**Solution:**

```bash
# See conflicted files
git status

# Open conflicted file, look for:
<<<<<<< HEAD
Your changes
=======
Their changes
>>>>>>> branch-name

# Choose which to keep or merge manually
# Remove conflict markers (<<<, ===, >>>)

# Stage resolved files
git add app/Services/SiteService.php

# Continue merge
git merge --continue

# Or abort if needed
git merge --abort
```

---

## Nuclear Options (Last Resort)

### Complete Reset

```bash
# WARNING: Deletes everything and starts fresh!

# 1. Delete all dependencies
rm -rf vendor node_modules

# 2. Delete database
rm database/database.sqlite

# 3. Clear all caches
rm -rf bootstrap/cache/*
rm -rf storage/framework/cache/*
rm -rf storage/framework/sessions/*
rm -rf storage/framework/views/*

# 4. Reinstall everything
composer install
npm install
touch database/database.sqlite
php artisan key:generate
php artisan migrate:fresh --seed
npm run build

# 5. Restart server
composer run dev
```

---

## Getting Help

### Before asking for help

**Collect this information:**

```bash
# 1. Environment details
php -v
composer --version
node -v
npm -v

# 2. Error messages
# Copy exact error from terminal/browser console

# 3. What you tried
# List steps you've already attempted

# 4. Minimal reproduction
# Simplest code that shows the issue
```

### Create a good bug report

```markdown
### Issue
Brief description of the problem

### Steps to Reproduce
1. Step one
2. Step two
3. Error occurs

### Expected Behavior
What should happen

### Actual Behavior
What actually happens (include error messages)

### Environment
- OS: Ubuntu 22.04
- PHP: 8.2.0
- Laravel: 12.0.0
- Node: 18.19.0

### What I've Tried
- Cleared cache
- Reset database
- etc.
```

---

## Quick Diagnostic Checklist

When something breaks, run through this:

```bash
# 1. Clear all caches
php artisan optimize:clear

# 2. Check logs
tail -50 storage/logs/laravel.log

# 3. Check environment
php artisan about

# 4. Verify database
php artisan db:show

# 5. Check dependencies
composer validate
npm audit

# 6. Run tests
php artisan test

# 7. Check code style
./vendor/bin/pint --test
```

**90% of issues are solved by steps 1-3!**

---

## Remember

1. **Read the error message carefully** - It usually tells you what's wrong
2. **Check the logs** - `storage/logs/laravel.log` is your friend
3. **Clear caches first** - `php artisan optimize:clear` fixes most issues
4. **Search GitHub issues** - Someone probably had this problem before
5. **Use `dd()` and `dump()`** - Debug by inspecting variables
6. **Ask for help** - The team is here to support you!

---

**Still stuck?** Check [GitHub Discussions](https://github.com/calounx/mentat/discussions) or create an issue!
