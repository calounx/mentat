# Code Style Guide

Code style guidelines for CHOM development.

## PHP

### Standards

We follow **PSR-12** with Laravel conventions.

### Formatting

```bash
# Auto-format code
composer run format
vendor/bin/pint
```

### Class Structure

```php
<?php

namespace App\Services;

use App\Models\Site;
use Illuminate\Support\Facades\Log;

/**
 * Service for managing site operations.
 */
class SiteService
{
    // 1. Constants
    private const MAX_SITES = 100;

    // 2. Properties
    private bool $enabled = true;

    // 3. Constructor
    public function __construct(
        private readonly SiteRepository $repository
    ) {}

    // 4. Public methods
    public function createSite(array $data): Site
    {
        $this->validateData($data);

        return $this->repository->create($data);
    }

    // 5. Private methods
    private function validateData(array $data): void
    {
        // Validation logic
    }
}
```

### Type Hints

Always use type hints:

```php
// Good
public function findById(string $id): ?Site
{
    return Site::find($id);
}

// Bad
public function findById($id)
{
    return Site::find($id);
}
```

### Return Types

Always declare return types:

```php
// Good
public function getSites(): Collection
{
    return Site::all();
}

// Bad
public function getSites()
{
    return Site::all();
}
```

### Nullable Types

Use nullable types explicitly:

```php
public function findUser(string $email): ?User
{
    return User::where('email', $email)->first();
}
```

### Arrays

Use type declarations:

```php
/**
 * @param  array<string, mixed>  $data
 * @return array<int, Site>
 */
public function processSites(array $data): array
{
    // ...
}
```

### Comments

```php
// Single-line comments use //

/**
 * Multi-line comments use PHPDoc format.
 *
 * Explain WHY, not WHAT.
 *
 * @param  string  $domain
 * @return Site
 * @throws ValidationException
 */
public function createSite(string $domain): Site
{
    // ...
}
```

### Naming Conventions

```php
// Classes: PascalCase
class SiteService {}

// Methods: camelCase
public function createSite() {}

// Variables: camelCase
$siteCount = 10;

// Constants: SCREAMING_SNAKE_CASE
const MAX_SITES = 100;

// Properties: camelCase
private string $siteName;
```

### Early Returns

Prefer early returns over nested conditions:

```php
// Good
public function process(Site $site): bool
{
    if (!$site->isActive()) {
        return false;
    }

    if (!$site->hasVps()) {
        return false;
    }

    return $this->deploy($site);
}

// Bad
public function process(Site $site): bool
{
    if ($site->isActive()) {
        if ($site->hasVps()) {
            return $this->deploy($site);
        }
    }

    return false;
}
```

### Avoid Magic Numbers

```php
// Good
private const CACHE_TTL_HOURS = 24;
Cache::put('key', 'value', self::CACHE_TTL_HOURS * 3600);

// Bad
Cache::put('key', 'value', 86400);
```

## JavaScript

### Style

Use modern ES6+:

```javascript
// Good: Arrow functions
const getSites = () => {
    return fetch('/api/sites');
};

// Good: Const/Let
const MAX_SITES = 100;
let currentCount = 0;

// Bad: Var
var count = 0;
```

### Alpine.js

```html
<!-- Component initialization -->
<div x-data="siteManager()">
    <button @click="createSite">Create Site</button>
    <template x-for="site in sites">
        <div x-text="site.domain"></div>
    </template>
</div>

<script>
function siteManager() {
    return {
        sites: [],

        async createSite() {
            // Implementation
        }
    };
}
</script>
```

## Blade Templates

### Structure

```blade
{{-- Clear, semantic structure --}}
<div class="container">
    <h1>{{ $title }}</h1>

    @if ($sites->count() > 0)
        @foreach ($sites as $site)
            <x-site-card :site="$site" />
        @endforeach
    @else
        <p>No sites found.</p>
    @endif
</div>
```

### Components

```blade
{{-- Use components for reusability --}}
<x-button variant="primary" size="lg">
    Create Site
</x-button>

{{-- Not --}}
<button class="btn btn-primary btn-lg">
    Create Site
</button>
```

### Directives

```blade
{{-- Prefer @auth over @if(auth()->check()) --}}
@auth
    Welcome, {{ auth()->user()->name }}!
@endauth

{{-- Use @props in components --}}
@props(['type' => 'info'])

<div class="alert alert-{{ $type }}">
    {{ $slot }}
</div>
```

## Database

### Migrations

```php
// Clear, descriptive names
2024_01_01_000001_create_sites_table.php
2024_01_01_000002_add_notes_to_sites_table.php

// Good migration
public function up(): void
{
    Schema::create('sites', function (Blueprint $table) {
        $table->uuid('id')->primary();
        $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
        $table->string('domain')->unique();
        $table->string('type');
        $table->string('status');
        $table->timestamps();

        $table->index(['tenant_id', 'status']);
    });
}
```

### Models

```php
// Use $fillable
protected $fillable = [
    'domain',
    'type',
    'status',
];

// Use $casts
protected function casts(): array
{
    return [
        'created_at' => 'datetime',
        'ssl_enabled' => 'boolean',
    ];
}

// Clear relationships
public function vpsServer(): BelongsTo
{
    return $this->belongsTo(VpsServer::class);
}
```

### Queries

```php
// Good: Use Eloquent
$sites = Site::where('status', 'active')
    ->with('vpsServer')
    ->latest()
    ->get();

// Bad: Raw queries with user input
$sites = DB::select("SELECT * FROM sites WHERE status = '$status'");
```

## Git Commits

### Format

```
<type>: <subject>

<body>

<footer>
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Formatting
- `refactor`: Code refactoring
- `test`: Tests
- `chore`: Maintenance

### Examples

```
feat: Add site backup scheduling

Implement automated backup scheduling with customizable intervals.
Users can now set daily, weekly, or monthly backup schedules.

Closes #123
```

```
fix: Resolve VPS connection timeout

Increase SSH connection timeout from 30s to 60s to handle
slow network connections.

Fixes #456
```

## Tools

### Auto-formatting

```bash
# PHP
vendor/bin/pint

# JavaScript (if using Prettier)
npm run format
```

### Static Analysis

```bash
# PHPStan
vendor/bin/phpstan analyse

# PHPMD
vendor/bin/phpmd app text phpmd.xml
```

### Pre-commit Hooks

Install git hooks:

```bash
./scripts/install-hooks.sh
```

## IDE Configuration

### VS Code

Install extensions:
- PHP Intelephense
- Laravel Blade Snippets
- Tailwind CSS IntelliSense
- ESLint
- Prettier

Settings:

```json
{
  "editor.formatOnSave": true,
  "editor.codeActionsOnSave": {
    "source.fixAll": true
  },
  "[php]": {
    "editor.defaultFormatter": "open-southeners.laravel-pint"
  }
}
```

### PHPStorm

- Enable Laravel plugin
- Configure Pint as external formatter
- Enable code inspections

## Review Checklist

Before submitting PR:

- [ ] Code follows PSR-12
- [ ] All tests pass
- [ ] No debug statements
- [ ] Type hints on all methods
- [ ] Comments explain WHY, not WHAT
- [ ] No magic numbers
- [ ] Early returns used
- [ ] Meaningful variable names
- [ ] No security vulnerabilities

---

Consistent code style makes collaboration easier!
