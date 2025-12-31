# CHOM Developer Onboarding Guide

Welcome to the CHOM development team! This guide will get you productive in under 1 hour.

## Prerequisites (15 minutes)

Install these on your machine:

### Required
- **PHP 8.2+**: `php -v` to check
- **Composer**: https://getcomposer.org
- **Node.js 18+**: https://nodejs.org
- **Git**: https://git-scm.com

### Recommended
- **Docker Desktop**: For local Redis/MySQL
- **VS Code**: With PHP Intelephense extension
- **TablePlus/Adminer**: Database GUI

### Optional
- **Redis CLI**: For cache debugging
- **Postman/Insomnia**: API testing

## Setup (10 minutes)

### 1. Clone Repository

```bash
git clone <repository-url>
cd chom
```

### 2. Automated Setup

```bash
./scripts/setup-dev.sh
```

This script will:
- Install PHP dependencies (Composer)
- Install Node dependencies (NPM)
- Create .env file
- Generate application key
- Start Docker services (Redis, MySQL)
- Run migrations
- Seed test data
- Run tests to verify setup
- Build frontend assets

### 3. Manual Setup (if automated fails)

```bash
# Install dependencies
composer install
npm install

# Environment
cp .env.example .env
php artisan key:generate

# Database
touch database/database.sqlite
php artisan migrate --seed

# Start services
docker-compose up -d

# Build assets
npm run build
```

## Test Your Setup (5 minutes)

### 1. Start Development Server

```bash
composer run dev
```

This starts:
- Web server (http://localhost:8000)
- Frontend build with HMR
- Queue worker
- Log viewer

### 2. Access the Application

Open http://localhost:8000

### 3. Login with Test Account

```
Email: admin@chom.test
Password: password
```

### 4. Run Tests

```bash
composer test
```

All tests should pass.

## Understanding CHOM (30 minutes)

### What is CHOM?

CHOM (CPanel Hosting Operations Manager) is a multi-tenant SaaS platform that automates:
- VPS provisioning and management
- cPanel installation and configuration
- WordPress/Laravel site deployment
- Automated backups
- Site monitoring
- Billing via Stripe

### Core Architecture

```
Organizations (Companies)
  └─ Tenants (Subscriptions)
      ├─ Users (owner/admin/member/viewer)
      ├─ VPS Servers
      └─ Sites
          └─ Backups
```

### Key Technologies

- **Backend**: Laravel 12, PHP 8.2
- **Frontend**: Livewire 3, Alpine.js, Tailwind
- **Database**: SQLite (dev), MySQL (prod)
- **Cache/Queue**: Redis
- **Payments**: Stripe
- **VPS Management**: SSH via phpseclib

### Code Organization

```
app/
├── Models/              # Database models
├── Services/            # Business logic
├── Repositories/        # Data access layer
├── Http/
│   ├── Controllers/     # API & web controllers
│   ├── Livewire/       # Interactive components
│   └── Resources/       # API resources
└── Console/Commands/    # Artisan commands
```

### Design Patterns Used

1. **Service Layer**: Business logic in service classes
2. **Repository Pattern**: Data access abstraction
3. **Value Objects**: Immutable value types
4. **Multi-Tenancy**: Organization-based isolation
5. **Queue Jobs**: Async processing

## Your First Task (20 minutes)

Let's create a simple feature together!

### Task: Add a "Site Notes" Field

#### 1. Create Migration

```bash
php artisan make:migration add_notes_to_sites_table
```

Edit migration:
```php
public function up()
{
    Schema::table('sites', function (Blueprint $table) {
        $table->text('notes')->nullable();
    });
}
```

Run it:
```bash
php artisan migrate
```

#### 2. Update Model

Add to `app/Models/Site.php`:
```php
protected $fillable = [
    // ... existing fields
    'notes',
];
```

#### 3. Create Livewire Component

```bash
php artisan make:livewire Sites/SiteNotes
```

Implement in `app/Http/Livewire/Sites/SiteNotes.php`:
```php
class SiteNotes extends Component
{
    public Site $site;
    public string $notes = '';

    public function mount(Site $site)
    {
        $this->site = $site;
        $this->notes = $site->notes ?? '';
    }

    public function save()
    {
        $this->site->update(['notes' => $this->notes]);
        $this->dispatch('notify', 'Notes saved successfully');
    }

    public function render()
    {
        return view('livewire.sites.site-notes');
    }
}
```

#### 4. Create View

Edit `resources/views/livewire/sites/site-notes.blade.php`:
```blade
<div>
    <h3>Site Notes</h3>
    <textarea wire:model="notes" rows="4"></textarea>
    <button wire:click="save">Save Notes</button>
</div>
```

#### 5. Write Test

```bash
php artisan make:test SiteNotesTest
```

```php
public function test_user_can_add_notes_to_site()
{
    $user = User::factory()->create(['role' => 'owner']);
    $site = Site::factory()->create();

    $this->actingAs($user)
        ->post("/sites/{$site->id}/notes", [
            'notes' => 'Test notes'
        ])
        ->assertOk();

    $this->assertEquals('Test notes', $site->fresh()->notes);
}
```

#### 6. Run Test

```bash
php artisan test --filter=SiteNotesTest
```

Congratulations! You just:
- Created a database migration
- Updated a model
- Built a Livewire component
- Created a view
- Wrote a test

## Development Workflow

### Daily Routine

```bash
# Morning: Pull latest changes
git pull origin main

# Start development
composer run dev

# Make changes, run tests
php artisan test

# Commit and push
git add .
git commit -m "feat: Add feature X"
git push origin feature/my-feature
```

### Common Commands

```bash
# Generate code
php artisan make:service MyService
php artisan make:repository MyRepository
php artisan make:api-resource MyResource

# Debug
php artisan debug:auth user@example.com
php artisan debug:cache
php artisan debug:performance

# Database
php artisan migrate:fresh --seed
php artisan db:seed --class=TestDataSeeder

# Testing
composer test
php artisan test --coverage
```

## Code Style

We follow PSR-12 with Laravel conventions:

```php
// Good
public function createSite(array $data): Site
{
    $this->validate($data);

    return DB::transaction(function () use ($data) {
        $site = Site::create($data);
        $this->provisionVPS($site);
        return $site;
    });
}

// Use type hints, meaningful names, and early returns
```

Format code:
```bash
composer run format
```

## Getting Help

### Documentation
1. Read this file (you are here!)
2. Check `DEVELOPMENT.md` for technical details
3. Review `CONTRIBUTING.md` for contribution guidelines

### Code Examples
- Look at existing tests in `tests/`
- Review similar features in the codebase
- Check service classes for business logic patterns

### Ask Questions
- Check team chat for quick questions
- Create GitHub discussion for design questions
- Review existing issues and PRs

### Debugging
- Use `php artisan tinker` for interactive testing
- Use `debug:*` commands for common issues
- Check logs in `storage/logs/`

## Quick Reference

### Test Users
```
Owner:  owner@chom.test  / password
Admin:  admin@chom.test  / password
Member: member@chom.test / password
Viewer: viewer@chom.test / password
```

### URLs
```
App:           http://localhost:8000
MailHog:       http://localhost:8025
Adminer:       http://localhost:8080
Redis GUI:     http://localhost:8081
Grafana:       http://localhost:3000
```

### File Locations
```
Models:        app/Models/
Services:      app/Services/
Controllers:   app/Http/Controllers/
Livewire:      app/Http/Livewire/
Tests:         tests/Feature/, tests/Unit/
Migrations:    database/migrations/
```

## Next Steps

Now that you're set up:

1. **Explore the codebase**: Browse through key files
2. **Pick your first issue**: Look for "good first issue" labels
3. **Ask questions**: Don't hesitate to reach out
4. **Make your first PR**: Start small and iterate

## Resources

- **DEVELOPMENT.md**: Detailed development guide
- **CONTRIBUTING.md**: Contribution guidelines
- **TESTING.md**: Testing best practices
- **CODE-STYLE.md**: Code style guidelines

---

Welcome aboard! We're excited to have you on the team.
