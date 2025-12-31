# CHOM Developer Guide

Welcome to the CHOM development guide! This document covers everything you need to know to contribute to CHOM, from local setup to testing and deployment.

## Table of Contents

1. [Development Environment Setup](#development-environment-setup)
2. [Project Architecture](#project-architecture)
3. [Code Organization](#code-organization)
4. [Development Workflow](#development-workflow)
5. [Testing Guide](#testing-guide)
6. [Frontend Development](#frontend-development)
7. [Backend Development](#backend-development)
8. [Database Management](#database-management)
9. [API Development](#api-development)
10. [Contributing Guidelines](#contributing-guidelines)
11. [Code Style and Standards](#code-style-and-standards)
12. [Debugging Tips](#debugging-tips)

---

## Development Environment Setup

### Prerequisites

Ensure you have installed:
- **PHP 8.2+** with extensions: mbstring, xml, mysql, curl, zip, gd, redis
- **Composer 2.x**
- **Node.js 18+** and npm
- **Redis** (for caching and queues)
- **Git**
- **IDE** (recommended: VS Code, PHPStorm)

### Quick Setup

```bash
# Clone repository
git clone https://github.com/calounx/mentat.git
cd mentat/chom

# Run setup script (installs everything)
composer run setup

# Start all development services
composer run dev
```

The `composer run dev` command starts:
- Laravel development server (http://localhost:8000)
- Vite dev server with HMR (hot module replacement)
- Queue worker for background jobs
- Laravel Pail for real-time log viewing

### Manual Setup (Step-by-Step)

If you prefer manual setup or need to customize:

#### 1. Install Dependencies

```bash
# PHP dependencies
composer install

# JavaScript dependencies
npm install
```

#### 2. Environment Configuration

```bash
# Create environment file
cp .env.example .env

# Generate application key
php artisan key:generate

# Configure database (SQLite for development)
touch database/database.sqlite

# Or use MySQL
# Update .env with your MySQL credentials:
# DB_CONNECTION=mysql
# DB_HOST=127.0.0.1
# DB_DATABASE=chom_dev
# DB_USERNAME=your_username
# DB_PASSWORD=your_password
```

#### 3. Setup Redis (Optional but Recommended)

```bash
# Ubuntu/Debian
sudo apt-get install redis-server
sudo systemctl start redis

# macOS
brew install redis
brew services start redis

# Update .env
CACHE_STORE=redis
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis
```

#### 4. Database Migrations

```bash
# Run migrations
php artisan migrate

# (Optional) Seed with test data
php artisan db:seed
```

#### 5. Build Assets

```bash
# Development build (unminified)
npm run dev

# Or build once
npm run build
```

### Development Tools

#### VS Code Extensions (Recommended)

```json
{
  "recommendations": [
    "bmewburn.vscode-intelephense-client",    // PHP IntelliSense
    "amirrizvi.laravel-extra-intellisense",   // Laravel autocomplete
    "onecentlin.laravel-blade",               // Blade syntax
    "bradlc.vscode-tailwindcss",              // Tailwind CSS IntelliSense
    "esbenp.prettier-vscode",                 // Code formatter
    "dbaeumer.vscode-eslint",                 // JavaScript linter
    "eamodio.gitlens"                         // Git integration
  ]
}
```

Save as `.vscode/extensions.json` in the project root.

#### PHPStorm Configuration

1. **Enable Laravel Plugin**
   - File → Settings → Plugins → Search "Laravel" → Install

2. **Configure Code Style**
   - File → Settings → Editor → Code Style → PHP
   - Set to PSR-12

3. **Setup Xdebug**
   - Install Xdebug: `pecl install xdebug`
   - Configure `php.ini`:
   ```ini
   [xdebug]
   zend_extension=xdebug.so
   xdebug.mode=debug
   xdebug.start_with_request=yes
   ```

---

## Project Architecture

### High-Level Architecture

```
┌──────────────────────────────────────────────────┐
│              Frontend Layer                       │
│  Livewire Components + Alpine.js + Tailwind      │
└────────────┬─────────────────────────────────────┘
             │
┌────────────▼─────────────────────────────────────┐
│          Application Layer                        │
│  Controllers, Livewire Components, Middleware    │
└────────────┬─────────────────────────────────────┘
             │
┌────────────▼─────────────────────────────────────┐
│          Service Layer                            │
│  Business Logic (Services, Jobs, Events)         │
└────────────┬─────────────────────────────────────┘
             │
┌────────────▼─────────────────────────────────────┐
│          Data Layer                               │
│  Models, Repositories, Database                  │
└──────────────────────────────────────────────────┘
```

### Design Patterns Used

1. **Service Layer Pattern** - Business logic in dedicated service classes
2. **Repository Pattern** (partial) - Complex queries abstracted
3. **Job/Queue Pattern** - Long-running tasks in background jobs
4. **Event/Listener Pattern** - Decoupled application events
5. **Policy Pattern** - Authorization logic in dedicated policies

### Key Technologies

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Frontend** | Livewire 3 | Reactive components without JavaScript |
| | Alpine.js | Lightweight JavaScript framework |
| | Tailwind CSS | Utility-first CSS |
| **Backend** | Laravel 12 | PHP framework |
| | Laravel Sanctum | API authentication |
| | Laravel Cashier | Stripe billing |
| **Data** | Eloquent ORM | Database abstraction |
| | Redis | Cache/Queue backend |
| **Build** | Vite 7 | Frontend build tool |

---

## Code Organization

### Directory Structure

```
chom/
├── app/
│   ├── Console/              # Artisan commands
│   │   └── Commands/
│   ├── Exceptions/           # Custom exceptions
│   ├── Http/
│   │   ├── Controllers/      # HTTP controllers
│   │   │   ├── Api/V1/      # API v1 controllers
│   │   │   └── Webhooks/    # Webhook handlers
│   │   ├── Middleware/       # Custom middleware
│   │   └── Requests/         # Form requests (validation)
│   ├── Jobs/                 # Queue jobs
│   │   ├── CreateBackupJob.php
│   │   ├── RestoreBackupJob.php
│   │   └── IssueSslCertificateJob.php
│   ├── Livewire/             # Livewire components
│   │   ├── Sites/
│   │   ├── Backups/
│   │   └── Team/
│   ├── Models/               # Eloquent models
│   │   ├── Site.php
│   │   ├── VpsServer.php
│   │   ├── SiteBackup.php
│   │   └── Organization.php
│   ├── Policies/             # Authorization policies
│   │   ├── SitePolicy.php
│   │   ├── BackupPolicy.php
│   │   └── TeamPolicy.php
│   ├── Providers/            # Service providers
│   │   ├── AppServiceProvider.php
│   │   └── EventServiceProvider.php
│   └── Services/             # Business logic services
│       ├── Sites/
│       │   ├── SiteService.php
│       │   └── DeploymentService.php
│       ├── VPS/
│       │   ├── VpsService.php
│       │   └── VpsManagerBridge.php
│       ├── Backup/
│       │   ├── BackupService.php
│       │   └── RestoreService.php
│       ├── Observability/
│       │   ├── PrometheusService.php
│       │   └── GrafanaService.php
│       └── Billing/
│           └── SubscriptionService.php
├── config/                   # Configuration files
│   ├── app.php
│   ├── chom.php             # CHOM-specific config
│   ├── database.php
│   └── services.php
├── database/
│   ├── factories/           # Model factories for testing
│   ├── migrations/          # Database migrations
│   └── seeders/             # Database seeders
├── resources/
│   ├── css/                 # Stylesheets
│   │   └── app.css
│   ├── js/                  # JavaScript
│   │   ├── app.js
│   │   └── bootstrap.js
│   └── views/               # Blade templates
│       ├── livewire/        # Livewire views
│       ├── layouts/         # Layout templates
│       └── components/      # Blade components
├── routes/
│   ├── web.php              # Web routes
│   ├── api.php              # API routes
│   └── console.php          # Console routes
├── tests/
│   ├── Feature/             # Feature tests
│   │   ├── SiteManagementTest.php
│   │   └── BackupTest.php
│   └── Unit/                # Unit tests
│       ├── Services/
│       └── Models/
└── public/                  # Public assets
    ├── index.php            # Entry point
    └── assets/              # Built assets (generated)
```

### Service Layer Organization

Services follow a consistent pattern:

```
app/Services/
├── Sites/
│   ├── SiteService.php          # Main site operations
│   ├── DeploymentService.php    # Deployment logic
│   └── SslService.php           # SSL certificate management
├── VPS/
│   ├── VpsService.php           # VPS management
│   ├── VpsManagerBridge.php     # SSH communication
│   └── HealthCheckService.php   # Server monitoring
├── Backup/
│   ├── BackupService.php        # Backup creation
│   ├── RestoreService.php       # Restore logic
│   └── RetentionService.php     # Cleanup old backups
└── Observability/
    ├── MetricsService.php       # Metrics collection
    └── AlertService.php         # Alert management
```

---

## Development Workflow

### Daily Workflow

1. **Start development services**
   ```bash
   composer run dev
   ```

2. **Make changes** to code

3. **Test changes** in browser at http://localhost:8000

4. **Run tests** before committing
   ```bash
   php artisan test
   ```

5. **Format code**
   ```bash
   ./vendor/bin/pint
   ```

6. **Commit changes**
   ```bash
   git add .
   git commit -m "Add feature: description"
   ```

### Creating a New Feature

#### 1. Create Feature Branch

```bash
git checkout -b feature/site-cloning
```

#### 2. Plan the Feature

Example: Add site cloning feature

**Components needed:**
- Service: `CloneSiteService.php`
- Job: `CloneSiteJob.php`
- Livewire Component: `SiteClone.php`
- API Endpoint: `POST /api/v1/sites/{id}/clone`
- Tests: `CloneSiteTest.php`

#### 3. Implement Backend

**Create Service:**

```bash
# Generate service class
touch app/Services/Sites/CloneSiteService.php
```

```php
<?php

namespace App\Services\Sites;

use App\Models\Site;
use App\Jobs\CloneSiteJob;

class CloneSiteService
{
    public function clone(Site $sourceSite, string $newDomain): Site
    {
        // Validation
        $this->validateClone($sourceSite, $newDomain);

        // Create new site record
        $newSite = Site::create([
            'organization_id' => $sourceSite->organization_id,
            'domain' => $newDomain,
            'type' => $sourceSite->type,
            'php_version' => $sourceSite->php_version,
            'vps_server_id' => $sourceSite->vps_server_id,
            'status' => 'cloning',
        ]);

        // Dispatch background job
        CloneSiteJob::dispatch($sourceSite, $newSite);

        return $newSite;
    }

    private function validateClone(Site $sourceSite, string $newDomain): void
    {
        if (Site::where('domain', $newDomain)->exists()) {
            throw new \Exception("Domain already exists");
        }
    }
}
```

**Create Job:**

```bash
php artisan make:job CloneSiteJob
```

```php
<?php

namespace App\Jobs;

use App\Models\Site;
use App\Services\VPS\VpsManagerBridge;

class CloneSiteJob implements ShouldQueue
{
    public function __construct(
        public Site $sourceSite,
        public Site $targetSite
    ) {}

    public function handle(VpsManagerBridge $vpsManager): void
    {
        try {
            // Clone files via VPS manager
            $vpsManager->cloneSite(
                $this->sourceSite,
                $this->targetSite
            );

            // Update status
            $this->targetSite->update(['status' => 'active']);
        } catch (\Exception $e) {
            $this->targetSite->update(['status' => 'failed']);
            throw $e;
        }
    }
}
```

#### 4. Implement Frontend

**Create Livewire Component:**

```bash
php artisan make:livewire Sites/SiteClone
```

```php
<?php

namespace App\Livewire\Sites;

use Livewire\Component;
use App\Models\Site;
use App\Services\Sites\CloneSiteService;

class SiteClone extends Component
{
    public Site $site;
    public string $newDomain = '';

    public function clone(CloneSiteService $cloneService)
    {
        $this->validate([
            'newDomain' => 'required|string|unique:sites,domain',
        ]);

        try {
            $newSite = $cloneService->clone($this->site, $this->newDomain);

            session()->flash('message', 'Site cloning started!');
            return redirect()->route('sites.show', $newSite);
        } catch (\Exception $e) {
            session()->flash('error', $e->getMessage());
        }
    }

    public function render()
    {
        return view('livewire.sites.site-clone');
    }
}
```

**Create View:**

```blade
<!-- resources/views/livewire/sites/site-clone.blade.php -->
<div>
    <h2 class="text-xl font-bold mb-4">Clone Site</h2>

    <form wire:submit.prevent="clone">
        <div class="mb-4">
            <label class="block text-sm font-medium mb-2">
                New Domain
            </label>
            <input
                type="text"
                wire:model="newDomain"
                class="w-full px-4 py-2 border rounded"
                placeholder="newsite.example.com"
            />
            @error('newDomain')
                <span class="text-red-500 text-sm">{{ $message }}</span>
            @enderror
        </div>

        <button
            type="submit"
            class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
        >
            Clone Site
        </button>
    </form>
</div>
```

#### 5. Add API Endpoint

**In `routes/api.php`:**

```php
Route::post('/sites/{site}/clone', [SiteController::class, 'clone'])
    ->middleware('auth:sanctum');
```

**In `app/Http/Controllers/Api/V1/SiteController.php`:**

```php
public function clone(Site $site, CloneSiteService $cloneService)
{
    $this->authorize('clone', $site);

    $validated = request()->validate([
        'new_domain' => 'required|string|unique:sites,domain',
    ]);

    $newSite = $cloneService->clone($site, $validated['new_domain']);

    return response()->json([
        'message' => 'Site cloning started',
        'site' => $newSite,
    ], 202);
}
```

#### 6. Write Tests

```bash
php artisan make:test CloneSiteTest
```

```php
<?php

namespace Tests\Feature;

use Tests\TestCase;
use App\Models\Site;
use App\Models\User;

class CloneSiteTest extends TestCase
{
    public function test_user_can_clone_site()
    {
        $user = User::factory()->create();
        $site = Site::factory()->create([
            'organization_id' => $user->organization_id,
        ]);

        $response = $this->actingAs($user, 'sanctum')
            ->postJson("/api/v1/sites/{$site->id}/clone", [
                'new_domain' => 'cloned-site.example.com',
            ]);

        $response->assertStatus(202);
        $this->assertDatabaseHas('sites', [
            'domain' => 'cloned-site.example.com',
            'status' => 'cloning',
        ]);
    }

    public function test_cannot_clone_to_existing_domain()
    {
        $user = User::factory()->create();
        $site = Site::factory()->create([
            'organization_id' => $user->organization_id,
        ]);
        $existingSite = Site::factory()->create([
            'domain' => 'existing.example.com',
        ]);

        $response = $this->actingAs($user, 'sanctum')
            ->postJson("/api/v1/sites/{$site->id}/clone", [
                'new_domain' => 'existing.example.com',
            ]);

        $response->assertStatus(422);
    }
}
```

#### 7. Run Tests

```bash
# Run all tests
php artisan test

# Run specific test
php artisan test --filter=CloneSiteTest

# Run with coverage
php artisan test --coverage
```

#### 8. Format and Commit

```bash
# Format code
./vendor/bin/pint

# Commit changes
git add .
git commit -m "Add site cloning feature

- Add CloneSiteService for business logic
- Add CloneSiteJob for background processing
- Add Livewire component for UI
- Add API endpoint POST /api/v1/sites/{id}/clone
- Add comprehensive tests
"
```

---

## Testing Guide

### Test Structure

```
tests/
├── Feature/              # End-to-end feature tests
│   ├── Auth/
│   ├── Sites/
│   ├── Backups/
│   └── Billing/
└── Unit/                 # Unit tests for individual classes
    ├── Services/
    ├── Models/
    └── Jobs/
```

### Running Tests

```bash
# All tests
php artisan test

# Specific test file
php artisan test tests/Feature/SiteManagementTest.php

# Specific test method
php artisan test --filter=test_user_can_create_site

# With coverage
php artisan test --coverage --min=80

# Parallel testing (faster)
php artisan test --parallel

# Stop on first failure
php artisan test --stop-on-failure
```

### Writing Tests

#### Feature Test Example

```php
<?php

namespace Tests\Feature;

use Tests\TestCase;
use App\Models\User;
use App\Models\Site;
use Illuminate\Foundation\Testing\RefreshDatabase;

class SiteManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_authenticated_user_can_create_site()
    {
        // Arrange
        $user = User::factory()->create();

        // Act
        $response = $this->actingAs($user, 'sanctum')
            ->postJson('/api/v1/sites', [
                'domain' => 'test.example.com',
                'type' => 'wordpress',
                'php_version' => '8.2',
            ]);

        // Assert
        $response->assertStatus(201);
        $this->assertDatabaseHas('sites', [
            'domain' => 'test.example.com',
        ]);
    }

    public function test_unauthenticated_user_cannot_create_site()
    {
        $response = $this->postJson('/api/v1/sites', [
            'domain' => 'test.example.com',
        ]);

        $response->assertStatus(401);
    }
}
```

#### Unit Test Example

```php
<?php

namespace Tests\Unit\Services;

use Tests\TestCase;
use App\Services\Sites\SiteService;
use App\Models\Site;
use Mockery;

class SiteServiceTest extends TestCase
{
    public function test_site_validation_rejects_invalid_domain()
    {
        $service = new SiteService();

        $this->expectException(\InvalidArgumentException::class);

        $service->validateDomain('invalid domain with spaces');
    }

    public function test_site_validation_accepts_valid_domain()
    {
        $service = new SiteService();

        $result = $service->validateDomain('valid-domain.com');

        $this->assertTrue($result);
    }
}
```

### Test Database

By default, tests use an in-memory SQLite database:

```php
// phpunit.xml
<php>
    <env name="DB_CONNECTION" value="sqlite"/>
    <env name="DB_DATABASE" value=":memory:"/>
</php>
```

### Mocking External Services

When testing code that interacts with external services (VPS, Stripe, etc.):

```php
public function test_site_creation_triggers_vps_deployment()
{
    // Mock VPS bridge
    $vpsMock = Mockery::mock(VpsManagerBridge::class);
    $vpsMock->shouldReceive('deploySite')
        ->once()
        ->with(Mockery::type(Site::class))
        ->andReturn(true);

    $this->app->instance(VpsManagerBridge::class, $vpsMock);

    // Test site creation
    $response = $this->postJson('/api/v1/sites', [
        'domain' => 'test.com',
    ]);

    $response->assertStatus(201);
}
```

---

## Frontend Development

### Livewire Components

CHOM uses Livewire 3 for reactive components without writing JavaScript.

#### Component Structure

```php
<?php

namespace App\Livewire\Sites;

use Livewire\Component;
use Livewire\WithPagination;
use App\Models\Site;

class SiteList extends Component
{
    use WithPagination;

    public string $search = '';
    public string $filter = 'all';

    // Real-time search
    public function updatedSearch()
    {
        $this->resetPage();
    }

    public function render()
    {
        $sites = Site::query()
            ->when($this->search, fn($q) => $q->where('domain', 'like', "%{$this->search}%"))
            ->when($this->filter !== 'all', fn($q) => $q->where('status', $this->filter))
            ->paginate(15);

        return view('livewire.sites.site-list', [
            'sites' => $sites,
        ]);
    }
}
```

#### Corresponding View

```blade
<div>
    <!-- Search and Filter -->
    <div class="mb-6 flex gap-4">
        <input
            type="text"
            wire:model.live="search"
            placeholder="Search sites..."
            class="flex-1 px-4 py-2 border rounded"
        />

        <select wire:model.live="filter" class="px-4 py-2 border rounded">
            <option value="all">All Sites</option>
            <option value="active">Active</option>
            <option value="suspended">Suspended</option>
        </select>
    </div>

    <!-- Sites Table -->
    <div class="bg-white shadow rounded">
        <table class="w-full">
            <thead>
                <tr class="border-b">
                    <th class="px-6 py-3 text-left">Domain</th>
                    <th class="px-6 py-3 text-left">Type</th>
                    <th class="px-6 py-3 text-left">Status</th>
                    <th class="px-6 py-3 text-left">Actions</th>
                </tr>
            </thead>
            <tbody>
                @foreach($sites as $site)
                    <tr class="border-b hover:bg-gray-50">
                        <td class="px-6 py-4">{{ $site->domain }}</td>
                        <td class="px-6 py-4">{{ $site->type }}</td>
                        <td class="px-6 py-4">
                            <span class="px-2 py-1 text-sm rounded
                                {{ $site->status === 'active' ? 'bg-green-100 text-green-800' : 'bg-gray-100' }}">
                                {{ $site->status }}
                            </span>
                        </td>
                        <td class="px-6 py-4">
                            <a href="{{ route('sites.show', $site) }}" class="text-blue-600 hover:underline">
                                View
                            </a>
                        </td>
                    </tr>
                @endforeach
            </tbody>
        </table>
    </div>

    <!-- Pagination -->
    <div class="mt-6">
        {{ $sites->links() }}
    </div>
</div>
```

### Tailwind CSS

CHOM uses Tailwind CSS 4 for styling.

#### Common Patterns

**Button Styles:**
```html
<!-- Primary Button -->
<button class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition">
    Click Me
</button>

<!-- Secondary Button -->
<button class="px-4 py-2 border border-gray-300 rounded hover:bg-gray-50 transition">
    Cancel
</button>

<!-- Danger Button -->
<button class="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 transition">
    Delete
</button>
```

**Form Inputs:**
```html
<div class="mb-4">
    <label class="block text-sm font-medium text-gray-700 mb-2">
        Domain Name
    </label>
    <input
        type="text"
        class="w-full px-4 py-2 border border-gray-300 rounded focus:ring-2 focus:ring-blue-500 focus:border-transparent"
        placeholder="example.com"
    />
</div>
```

### Building Assets

```bash
# Development (watch mode with HMR)
npm run dev

# Production build (minified)
npm run build

# Build and watch for changes
npm run build -- --watch
```

---

## Backend Development

### Service Pattern

Services encapsulate business logic:

```php
<?php

namespace App\Services\Sites;

use App\Models\Site;
use App\Services\VPS\VpsManagerBridge;
use App\Jobs\DeploySiteJob;

class SiteService
{
    public function __construct(
        private VpsManagerBridge $vpsManager
    ) {}

    public function createSite(array $data): Site
    {
        // Validate
        $this->validateSiteData($data);

        // Create database record
        $site = Site::create([
            'organization_id' => auth()->user()->organization_id,
            'domain' => $data['domain'],
            'type' => $data['type'],
            'php_version' => $data['php_version'] ?? '8.2',
            'status' => 'creating',
        ]);

        // Dispatch deployment job
        DeploySiteJob::dispatch($site);

        return $site;
    }

    private function validateSiteData(array $data): void
    {
        // Custom validation logic
        if (Site::where('domain', $data['domain'])->exists()) {
            throw new \Exception('Domain already exists');
        }
    }
}
```

### Job Pattern

Long-running tasks use queued jobs:

```php
<?php

namespace App\Jobs;

use App\Models\Site;
use App\Services\VPS\VpsManagerBridge;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

class DeploySiteJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public $tries = 3;
    public $timeout = 300; // 5 minutes

    public function __construct(
        public Site $site
    ) {}

    public function handle(VpsManagerBridge $vpsManager): void
    {
        try {
            // Update status
            $this->site->update(['status' => 'deploying']);

            // Deploy to VPS
            $vpsManager->deploySite($this->site);

            // Success
            $this->site->update(['status' => 'active']);
        } catch (\Exception $e) {
            // Failed
            $this->site->update([
                'status' => 'failed',
                'error_message' => $e->getMessage(),
            ]);

            throw $e;
        }
    }

    public function failed(\Throwable $exception): void
    {
        // Send notification, log error, etc.
        logger()->error("Site deployment failed: {$exception->getMessage()}", [
            'site_id' => $this->site->id,
        ]);
    }
}
```

### Event/Listener Pattern

Decouple actions with events:

```php
// Event
<?php

namespace App\Events;

use App\Models\Site;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class SiteCreated
{
    use Dispatchable, SerializesModels;

    public function __construct(
        public Site $site
    ) {}
}

// Listener
<?php

namespace App\Listeners;

use App\Events\SiteCreated;
use App\Services\Observability\MetricsService;

class CreateGrafanaDashboard
{
    public function __construct(
        private MetricsService $metricsService
    ) {}

    public function handle(SiteCreated $event): void
    {
        $this->metricsService->createDashboardForSite($event->site);
    }
}

// Register in EventServiceProvider
protected $listen = [
    SiteCreated::class => [
        CreateGrafanaDashboard::class,
        SendWelcomeEmail::class,
    ],
];
```

---

## Database Management

### Migrations

#### Creating Migrations

```bash
# Create table migration
php artisan make:migration create_sites_table

# Add column migration
php artisan make:migration add_ssl_status_to_sites_table
```

#### Migration Example

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('sites', function (Blueprint $table) {
            $table->id();
            $table->foreignId('organization_id')->constrained()->cascadeOnDelete();
            $table->foreignId('vps_server_id')->nullable()->constrained();
            $table->string('domain')->unique();
            $table->enum('type', ['wordpress', 'laravel', 'html']);
            $table->string('php_version')->default('8.2');
            $table->enum('status', ['creating', 'active', 'suspended', 'failed'])->default('creating');
            $table->text('error_message')->nullable();
            $table->timestamps();
            $table->softDeletes();

            $table->index(['organization_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sites');
    }
};
```

#### Running Migrations

```bash
# Run all pending migrations
php artisan migrate

# Rollback last batch
php artisan migrate:rollback

# Reset and re-run all migrations
php artisan migrate:fresh

# Reset and seed
php artisan migrate:fresh --seed
```

### Seeders

```bash
# Create seeder
php artisan make:seeder SiteSeeder
```

```php
<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use App\Models\Site;

class SiteSeeder extends Seeder
{
    public function run(): void
    {
        Site::factory()->count(10)->create();
    }
}
```

### Factories

```bash
# Create factory
php artisan make:factory SiteFactory
```

```php
<?php

namespace Database\Factories;

use App\Models\Organization;
use App\Models\VpsServer;
use Illuminate\Database\Eloquent\Factories\Factory;

class SiteFactory extends Factory
{
    public function definition(): array
    {
        return [
            'organization_id' => Organization::factory(),
            'vps_server_id' => VpsServer::factory(),
            'domain' => fake()->domainName(),
            'type' => fake()->randomElement(['wordpress', 'laravel', 'html']),
            'php_version' => '8.2',
            'status' => 'active',
        ];
    }
}
```

---

## API Development

### API Structure

All API routes are versioned and use Sanctum authentication:

```php
// routes/api.php
Route::prefix('v1')->group(function () {
    // Public routes
    Route::post('/auth/register', [AuthController::class, 'register']);
    Route::post('/auth/login', [AuthController::class, 'login']);

    // Protected routes
    Route::middleware('auth:sanctum')->group(function () {
        Route::apiResource('sites', SiteController::class);
        Route::apiResource('backups', BackupController::class);

        Route::post('/sites/{site}/ssl', [SiteController::class, 'issueSSL']);
        Route::post('/backups/{backup}/restore', [BackupController::class, 'restore']);
    });
});
```

### API Controller Example

```php
<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreSiteRequest;
use App\Models\Site;
use App\Services\Sites\SiteService;

class SiteController extends Controller
{
    public function __construct(
        private SiteService $siteService
    ) {}

    public function index()
    {
        $this->authorize('viewAny', Site::class);

        $sites = auth()->user()->organization->sites()
            ->with(['vpsServer'])
            ->paginate(15);

        return response()->json($sites);
    }

    public function store(StoreSiteRequest $request)
    {
        $site = $this->siteService->createSite($request->validated());

        return response()->json([
            'message' => 'Site creation started',
            'site' => $site,
        ], 201);
    }

    public function show(Site $site)
    {
        $this->authorize('view', $site);

        return response()->json($site->load(['vpsServer', 'backups']));
    }
}
```

### Form Request Validation

```bash
php artisan make:request StoreSiteRequest
```

```php
<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StoreSiteRequest extends FormRequest
{
    public function authorize(): bool
    {
        return auth()->check();
    }

    public function rules(): array
    {
        return [
            'domain' => 'required|string|unique:sites,domain',
            'type' => 'required|in:wordpress,laravel,html',
            'php_version' => 'nullable|in:8.2,8.4',
            'vps_server_id' => 'nullable|exists:vps_servers,id',
        ];
    }

    public function messages(): array
    {
        return [
            'domain.unique' => 'This domain is already in use.',
            'type.in' => 'Site type must be wordpress, laravel, or html.',
        ];
    }
}
```

---

## Contributing Guidelines

### Before Contributing

1. Read the [Code of Conduct](../CODE_OF_CONDUCT.md)
2. Check [existing issues](https://github.com/calounx/mentat/issues)
3. Discuss major changes in a GitHub issue first

### Pull Request Process

1. **Fork the repository**
2. **Create a feature branch** from `master`
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes**
4. **Write/update tests**
5. **Ensure tests pass**
   ```bash
   php artisan test
   ```
6. **Format code**
   ```bash
   ./vendor/bin/pint
   ```
7. **Commit with clear messages**
   ```bash
   git commit -m "Add feature: description"
   ```
8. **Push to your fork**
9. **Open a Pull Request** with:
   - Clear description of changes
   - Link to related issues
   - Screenshots (if UI changes)
   - Test results

### Code Review Checklist

Before submitting, ensure:
- ✅ All tests pass
- ✅ Code follows PSR-12 style
- ✅ Documentation is updated
- ✅ No console errors or warnings
- ✅ Backward compatibility maintained
- ✅ Security considerations addressed

---

## Code Style and Standards

### PHP Standards

CHOM follows **PSR-12** coding style.

#### Format Code

```bash
# Format all code
./vendor/bin/pint

# Check without fixing
./vendor/bin/pint --test

# Format specific file
./vendor/bin/pint app/Services/Sites/SiteService.php
```

#### Key Conventions

```php
<?php

// Namespace and imports
namespace App\Services\Sites;

use App\Models\Site;
use Illuminate\Support\Collection;

// Type hints everywhere
class SiteService
{
    // Constructor property promotion
    public function __construct(
        private VpsManagerBridge $vpsManager,
        private MetricsService $metrics
    ) {}

    // Return types
    public function getSites(int $organizationId): Collection
    {
        return Site::where('organization_id', $organizationId)->get();
    }

    // Named arguments for clarity
    public function createSite(
        string $domain,
        string $type,
        string $phpVersion = '8.2'
    ): Site {
        return Site::create([
            'domain' => $domain,
            'type' => $type,
            'php_version' => $phpVersion,
        ]);
    }
}
```

### JavaScript/TypeScript

```javascript
// Use ES6+ syntax
const sites = await fetchSites();

// Arrow functions
const formatDomain = (domain) => domain.toLowerCase();

// Destructuring
const { id, domain, status } = site;

// Template literals
const message = `Site ${domain} is ${status}`;
```

### Blade Templates

```blade
{{-- Use Blade directives --}}
@if($sites->isNotEmpty())
    @foreach($sites as $site)
        <div>{{ $site->domain }}</div>
    @endforeach
@else
    <p>No sites found</p>
@endif

{{-- Use components --}}
<x-card>
    <x-slot:header>
        Site Details
    </x-slot:header>

    {{ $site->domain }}
</x-card>
```

---

## Debugging Tips

### Laravel Debugging Tools

#### 1. Laravel Pail (Real-time Logs)

```bash
# Watch logs in real-time
php artisan pail

# Filter by level
php artisan pail --level=error

# Filter by channel
php artisan pail --channel=stack
```

#### 2. Tinker (Interactive Shell)

```bash
# Start tinker
php artisan tinker

# Query models
>>> App\Models\Site::count()
=> 42

>>> App\Models\Site::where('status', 'active')->get()
=> Illuminate\Database\Eloquent\Collection

# Test services
>>> app(App\Services\Sites\SiteService::class)->getSites(1)
```

#### 3. Route Debugging

```bash
# List all routes
php artisan route:list

# Filter routes
php artisan route:list --path=api

# Show route details
php artisan route:list --name=sites.index
```

#### 4. Database Debugging

```bash
# Show database connection
php artisan db:show

# Run raw query
php artisan db:show --database=mysql
```

### Logging

```php
// Log levels
use Illuminate\Support\Facades\Log;

Log::emergency('System is down!');
Log::alert('Action must be taken immediately');
Log::critical('Critical condition');
Log::error('Error condition');
Log::warning('Warning condition');
Log::notice('Normal but significant');
Log::info('Informational message');
Log::debug('Debug information');

// Contextual logging
Log::info('Site created', [
    'site_id' => $site->id,
    'domain' => $site->domain,
    'user_id' => auth()->id(),
]);

// Channel logging
Log::channel('slack')->error('Payment failed', [
    'user_id' => $user->id,
]);
```

### Debugging Livewire

```php
// In component
public function mount()
{
    dd($this->site); // Dump and die
    ray($this->site); // Ray debugging (if installed)
}

// In view
<div>
    @dump($sites)  {{-- Dump variable --}}
    @dd($sites)    {{-- Dump and die --}}
</div>
```

### Performance Profiling

```bash
# Install Laravel Debugbar
composer require barryvdh/laravel-debugbar --dev

# Enable in .env
DEBUGBAR_ENABLED=true
```

---

## Summary

You now have a complete guide to developing with CHOM. Key takeaways:

- ✅ Use Laravel best practices and patterns
- ✅ Write tests for all new features
- ✅ Follow PSR-12 coding standards
- ✅ Use Livewire for reactive UI
- ✅ Implement service layer for business logic
- ✅ Use jobs for background processing
- ✅ Version all API endpoints

**Need help?**
- 📖 [User Guide](USER-GUIDE.md)
- 🚀 [Operator Guide](OPERATOR-GUIDE.md)
- 💬 [GitHub Discussions](https://github.com/calounx/mentat/discussions)

Happy coding! 🚀
