# CHOM - Cloud Hosting & Observability Manager

## Project Overview

**CHOM** is a production-ready, multi-tenant SaaS platform for managing WordPress, HTML, and Laravel site hosting with comprehensive observability. Built with Laravel 12, it provides VPS fleet management, automated provisioning, monitoring, and backup systems with Stripe billing integration.

- **Version**: 2.2.12
- **Repository**: https://github.com/calounx/mentat
- **Production**: https://chom.arewel.com
- **License**: Proprietary

## Core Capabilities

- **Multi-Tenant SaaS**: Organizations, tenants, teams with RBAC
- **Site Hosting**: WordPress, HTML, Laravel deployment automation
- **VPS Management**: Automated server provisioning and configuration
- **Observability**: Native Prometheus, Loki, Grafana, AlertManager stack
- **Backup System**: Automated backups with encryption and retention policies
- **Billing**: Stripe integration with tiered pricing (Starter/Pro/Enterprise)
- **Production Features**: Health checks, circuit breakers, self-healing, graceful degradation

## Architecture

### Two-Server Infrastructure

**Mentat Server** (Observability Hub) - `mentat.arewel.com` (51.254.139.78)
- Prometheus (metrics collection on :9090)
- Grafana (dashboards on :3000)
- Loki (log aggregation on :3100)
- Promtail (log collection)
- AlertManager (alerting on :9093)
- Node Exporter (system metrics on :9100)
- **Role**: Central monitoring, metrics, logs, deployment orchestration

**Landsraad Server** (Application) - `landsraad.arewel.com` (51.254.139.79)
- Laravel Application (CHOM)
- Nginx (web server)
- PHP 8.2-FPM (application runtime)
- PostgreSQL 15 (database)
- Redis (cache/queue)
- Queue Workers (Supervisor)
- Node Exporter (:9100)
- **Role**: Application hosting, database, cache, background jobs

### System Architecture

```
┌────────────────────────────────────────┐
│    CHOM Laravel Application            │
│  (Multi-Tenant SaaS Control Plane)    │
├────────────────────────────────────────┤
│  Dashboard (Livewire) | API (Sanctum) │
│  VPSManagerBridge | Observability     │
└──────────┬─────────────────────────────┘
           │ SSH + HTTP
    ┌──────┼──────┬──────────────┐
    ▼      ▼      ▼              ▼
VPSManager Obs   Stripe      External
(SSH CLI) Stack (Webhooks)   Monitoring
```

### Modular Design (DDD Bounded Contexts)

The application is organized into 6 domain modules:

1. **Auth** - Authentication, user management, authorization
2. **Tenancy** - Multi-tenant organization and billing
3. **SiteHosting** - Site provisioning and management
4. **Backup** - Backup automation and restoration
5. **Team** - Team collaboration and permissions
6. **Infrastructure** - VPS and observability integration

See `chom/MODULAR-ARCHITECTURE.md` for details.

## Technology Stack

### Backend
- **Framework**: Laravel 12 (PHP 8.2+)
- **Database**: PostgreSQL 15 (production), SQLite (dev)
- **Cache/Queue**: Redis 7
- **Authentication**: Laravel Sanctum (token-based API)
- **Billing**: Stripe with Laravel Cashier
- **SSH**: phpseclib/phpseclib for VPS management

### Frontend
- **UI Framework**: Livewire 3.7 (reactive components)
- **JavaScript**: Alpine.js 3.15.3
- **CSS**: Tailwind CSS 4.0
- **Build Tool**: Vite 7
- **Components**: 21 Livewire components for dashboard

### Infrastructure
- **OS**: Debian 13 (Trixie)
- **Web Server**: Nginx
- **Process Manager**: Systemd
- **Observability**:
  - Prometheus 2.48.0 (metrics)
  - Loki 2.9.3 (logs)
  - Grafana 11.3.0 (visualization)
  - AlertManager 0.26.0 (alerting)
  - Exporters: node, nginx, postgres, redis, php-fpm, blackbox

### DevOps
- **VCS**: Git (GitHub)
- **Deployment**: Bash automation (`deploy-chom-automated.sh`)
- **Testing**: PHPUnit 11.5.3
- **Linting**: Laravel Pint
- **CI/CD**: Ready for GitHub Actions (see `.github/workflows/`)

## Key Concepts

### Multi-Tenancy & Security

**CRITICAL**: All data access MUST be tenant-isolated:

- **Organization** → Top-level container
- **Tenant** → Billing unit within organization (has subscription)
- **User** → Can belong to multiple organizations with roles
- **Site** → Belongs to one tenant

**Security Patterns**:
```php
// ALWAYS filter by tenant in repositories
$sites = Site::where('tenant_id', $tenantId)->get();

// NEVER expose cross-tenant data in queries
// BAD: Site::all() in a multi-tenant context
// GOOD: Site::where('tenant_id', auth()->user()->currentTenant->id)->get()
```

**P0 Security Fixes Applied**:
- Backup repository tenant isolation (app/Repositories/BackupRepository.php:42)
- Form request site lookup validation (app/Http/Requests/StoreBackupRequest.php:28)

See `docs/architecture/multi-tenancy.md` for complete security model.

### Resilience & Reliability

**Circuit Breaker Pattern** (`config/circuit-breaker.php`):
- Prevents cascading failures from external dependencies
- Per-service configuration (Prometheus, Grafana, Loki, DB, Redis, etc.)
- Failure threshold: 3-5 consecutive failures
- Half-open timeout: 15-60 seconds

**Graceful Degradation** (`config/degradation.php`):
- Metrics dashboard → cached data
- Log viewer → cached logs
- Grafana → static placeholders
- VPS provisioning → queued requests
- Email → queued messages

**Self-Healing** (see `docs/operations/self-healing.md`):
- Automated recovery from common failures
- Health check monitoring (`/health` endpoint)
- Correlation IDs for distributed tracing

### VPSManager

Custom bash-based CLI tool for server operations:

**Location**: `deploy/vpsmanager/`

**Capabilities**:
- Site provisioning (create-site.sh)
- SSL certificate management (setup-ssl.sh)
- Backup creation/restoration (create-backup.sh, restore-backup.sh)
- Database management
- User isolation (per-site system users)

**Integration**: `app/Services/Integration/VPSManagerBridge.php`

### Observability Stack

**Metrics** (Prometheus):
- System metrics (node_exporter)
- Application metrics (Laravel custom metrics)
- Database metrics (postgres_exporter)
- Cache metrics (redis_exporter)
- Web server metrics (nginx_exporter)

**Logs** (Loki + Promtail):
- Multi-tenant log isolation
- Application logs (Laravel)
- System logs (syslog)
- Web server logs (Nginx access/error)

**Dashboards** (Grafana):
- Pre-configured dashboards in Livewire components
- API integration via `ObservabilityAdapter.php`

**Alerting** (AlertManager):
- SMTP configuration for email alerts
- Configurable alert rules in Prometheus
- Routing and notification management

See `docs/operations/observability.md` for complete guide.

### Billing & Subscriptions

**Tiers** (config/chom.php):
- **Starter**: $29/mo, 5 sites, 10GB storage
- **Pro**: $79/mo, 25 sites, 100GB storage
- **Enterprise**: $249/mo, unlimited sites/storage

**Stripe Webhooks** (`app/Http/Controllers/Webhooks/StripeWebhookController.php`):
- `customer.subscription.created` → Activate tenant
- `customer.subscription.updated` → Update tier
- `customer.subscription.deleted` → Suspend tenant
- `invoice.paid` → Update billing status
- `invoice.payment_failed` → Mark past due

**Models**:
- `Subscription` - Stripe subscription record
- `TierLimit` - Tier configuration
- `UsageRecord` - Usage tracking for overage

## Common Workflows

### Making Code Changes

1. **Read existing code first** - Never modify code you haven't read
2. **Maintain tenant isolation** - All queries MUST filter by tenant
3. **Use existing patterns** - Follow established conventions
4. **Avoid over-engineering** - Only change what's necessary
5. **Test multi-tenancy** - Run `BackupTenantIsolationTest.php` after changes

### Deployment

**Automated Deployment** (Recommended):
```bash
cd deploy
./deploy-chom-automated.sh
```

**Features**:
- Fully idempotent (safe to run multiple times)
- Phase-based with skip options
- Automatic rollback on failure
- Zero-downtime deployment
- Secrets auto-generation

**Phases**:
1. Pre-flight checks
2. User setup (stilgar deployment user)
3. SSH automation (passwordless SSH)
4. Secrets generation
5. Prepare Mentat (observability stack)
6. Prepare Landsraad (application dependencies)
7. Deploy Application
8. Deploy Observability

See `deploy/QUICK-START-AUTOMATED.md` for details.

### Testing

**Run Tests**:
```bash
composer test                    # All tests
composer test --coverage         # With coverage
php artisan test --filter=Backup # Specific test
```

**Key Test Suites**:
- `tests/Feature/BackupTenantIsolationTest.php` - Multi-tenancy validation (7 test cases)
- `tests/Feature/PasswordResetTest.php` - Authentication
- `deploy/vpsmanager/tests/` - VPSManager integration tests

### Working with Observability

**Access Dashboards**:
- Grafana: http://mentat.arewel.com:3000
- Prometheus: http://mentat.arewel.com:9090
- AlertManager: http://mentat.arewel.com:9093

**Configuration**:
- Prometheus: `deploy/config/prometheus.yml`
- Loki: `deploy/config/loki-config.yml`
- Grafana: `deploy/config/grafana.ini`
- AlertManager: `deploy/config/alertmanager.yml`

**Livewire Integration**:
- `app/Livewire/Observability/MetricsDashboard.php`
- `app/Livewire/Observability/LogViewer.php`
- `app/Services/Integration/ObservabilityAdapter.php`

### Database Migrations

**Create Migration**:
```bash
php artisan make:migration create_table_name
```

**Run Migrations**:
```bash
php artisan migrate                # Run pending
php artisan migrate:fresh --seed  # Fresh with seeders
php artisan migrate:rollback      # Rollback last batch
```

**Important**: Always include `tenant_id` foreign keys for multi-tenant tables.

### Adding New Features

1. **Determine bounded context** - Which module? (Auth, Tenancy, SiteHosting, etc.)
2. **Create migration** - Database schema changes
3. **Create/update model** - Eloquent model with relationships
4. **Create service** - Business logic in `app/Services/`
5. **Create controller/Livewire** - UI or API endpoint
6. **Add routes** - `routes/web.php` or `routes/api.php`
7. **Add tests** - Feature tests in `tests/Feature/`
8. **Update documentation** - Relevant .md files

## Important Patterns & Conventions

### Repository Pattern

Used for data access abstraction:

```php
// app/Repositories/BackupRepository.php
public function getBackupsForTenant(int $tenantId): Collection
{
    return SiteBackup::whereHas('site', function ($query) use ($tenantId) {
        $query->where('tenant_id', $tenantId);
    })->get();
}
```

### Service Layer

Business logic in services:

```php
// app/Services/HealthCheckService.php
public function performHealthCheck(): array
{
    return [
        'status' => 'healthy',
        'services' => $this->checkServices(),
        'timestamp' => now(),
    ];
}
```

### Livewire Components

Real-time reactive UI:

```php
// app/Livewire/Sites/SiteManager.php
class SiteManager extends Component
{
    public $tenantId;
    public Collection $sites;

    public function mount($tenantId)
    {
        $this->tenantId = $tenantId;
        $this->loadSites();
    }

    public function loadSites()
    {
        $this->sites = Site::where('tenant_id', $this->tenantId)->get();
    }
}
```

### API Endpoints

RESTful API v1 with Sanctum:

```php
// routes/api.php
Route::prefix('v1')->middleware('auth:sanctum')->group(function () {
    Route::get('/sites', [SiteController::class, 'index']);
    Route::post('/sites', [SiteController::class, 'store']);
    Route::get('/sites/{site}', [SiteController::class, 'show']);
});
```

### Configuration Files

Environment-specific settings in `config/`:

```php
// config/chom.php
return [
    'ssh' => [
        'key_path' => env('CHOM_SSH_KEY_PATH'),
        'user' => env('CHOM_SSH_USER', 'stilgar'),
    ],
    'observability' => [
        'prometheus_url' => env('CHOM_PROMETHEUS_URL'),
        'grafana_url' => env('CHOM_GRAFANA_URL'),
    ],
];
```

## File Organization

### Key Directories

```
app/
├── Console/Commands/          # Artisan commands
├── Http/
│   ├── Controllers/           # HTTP controllers
│   │   ├── Api/V1/            # REST API v1
│   │   ├── Webhooks/          # Stripe webhooks
│   │   └── Auth/              # Authentication
│   ├── Middleware/            # HTTP middleware
│   └── Requests/              # Form validation
├── Livewire/                  # Livewire components
│   ├── Admin/                 # Admin dashboard
│   ├── Sites/                 # Site management
│   ├── Backups/               # Backup UI
│   ├── Observability/         # Metrics/logs
│   ├── Vps/                   # VPS health
│   └── Team/                  # Team collaboration
├── Models/                    # Eloquent models
├── Policies/                  # Authorization policies
├── Repositories/              # Data access layer
├── Services/                  # Business logic
│   ├── Integration/           # External integrations
│   └── Reliability/           # Circuit breakers, retry, etc.
└── Notifications/             # Email notifications

config/                        # Configuration files
database/
├── migrations/                # 38 migrations
├── factories/                 # Model factories
└── seeders/                   # Database seeders

deploy/                        # Infrastructure automation
├── deploy-chom-automated.sh   # Master deployment script
├── vpsmanager/                # VPS management CLI
├── security/                  # Security hardening (30 scripts)
├── config/                    # Service configs
└── tests/                     # Deployment tests

docs/                          # Documentation
├── architecture/              # Architecture docs
├── operations/                # Ops guides
└── development/               # Dev guides

tests/
├── Feature/                   # Feature tests
├── Unit/                      # Unit tests
└── load/                      # Load testing
```

### Important Files

- `README.md` - Project overview
- `CHANGELOG.md` - Version history
- `ARCHITECTURE_DIAGRAMS.md` - System diagrams
- `.env.example` - Environment template
- `composer.json` - PHP dependencies
- `package.json` - JavaScript dependencies
- `phpunit.xml` - Test configuration
- `deploy/RUNBOOK.md` - Operations runbook
- `chom/MODULAR-ARCHITECTURE.md` - Module structure

## Development Setup

### Prerequisites

- PHP 8.2+
- Composer
- Node.js 20+
- PostgreSQL 15 (or SQLite for dev)
- Redis 7

### Local Installation

```bash
# Clone repository
git clone git@github.com:calounx/mentat.git
cd mentat

# Install dependencies
composer install
npm install

# Environment setup
cp .env.example .env
php artisan key:generate

# Database setup
php artisan migrate --seed

# Build frontend assets
npm run build

# Start development server
php artisan serve
```

### Running Queue Workers

```bash
php artisan queue:work
```

### Running Tests

```bash
composer test
php artisan test --coverage
```

## Environment Variables

Key environment variables (see `.env.example` for complete list):

```bash
# Application
APP_NAME=CHOM
APP_ENV=production
APP_KEY=base64:...
APP_URL=https://chom.arewel.com

# Database
DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=chom
DB_USERNAME=chom_user
DB_PASSWORD=...

# Cache/Queue
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

# Stripe
STRIPE_KEY=pk_live_...
STRIPE_SECRET=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...

# SSH/VPS
CHOM_SSH_KEY_PATH=/var/www/chom/shared/storage/app/ssh/chom_deploy_key
CHOM_SSH_USER=stilgar

# Observability
CHOM_PROMETHEUS_URL=http://mentat.arewel.com:9090
CHOM_LOKI_URL=http://mentat.arewel.com:3100
CHOM_GRAFANA_URL=http://mentat.arewel.com:3000
CHOM_GRAFANA_API_KEY=...
```

## Security Considerations

### Multi-Tenancy

- **ALWAYS** filter queries by `tenant_id`
- **NEVER** expose cross-tenant data
- Use policies for authorization
- Test with `BackupTenantIsolationTest.php`

### Authentication

- Session-based for web routes
- Token-based (Sanctum) for API routes
- Email verification on login
- Admin approval workflow

### SSH Key Management

- Centralized deployment key at `CHOM_SSH_KEY_PATH`
- Dedicated deployment user (stilgar)
- Key-based authentication only

### Backup Encryption

- OpenSSL-based encryption
- Encryption keys in shared storage
- Per-site isolation

### Rate Limiting

- 5 req/min for auth endpoints
- 60 req/min for API
- 10 req/min for sensitive operations

## Troubleshooting

### Common Issues

**Queue not processing**:
```bash
php artisan queue:restart
supervisorctl restart laravel-worker:*
```

**Migration errors**:
```bash
php artisan migrate:fresh --seed  # WARNING: Destroys data
```

**Cache issues**:
```bash
php artisan cache:clear
php artisan config:clear
php artisan route:clear
php artisan view:clear
```

**Observability stack down**:
```bash
sudo systemctl restart prometheus grafana-server loki promtail alertmanager
```

### Logs

- **Application**: `storage/logs/laravel.log`
- **Nginx**: `/var/log/nginx/error.log`, `/var/log/nginx/access.log`
- **PHP-FPM**: `/var/log/php8.2-fpm.log`
- **Queue**: `storage/logs/worker.log`
- **Observability**: Check Loki via Grafana

### Health Checks

**Application Health**:
```bash
curl http://landsraad.arewel.com/health
```

**Observability Health**:
```bash
curl http://mentat.arewel.com:9090/-/healthy  # Prometheus
curl http://mentat.arewel.com:3100/ready      # Loki
curl http://mentat.arewel.com:3000/api/health # Grafana
```

## Additional Resources

### Documentation

- **Full Project Context**: `chom.claude.md`
- **Architecture**: `ARCHITECTURE_DIAGRAMS.md`
- **Deployment**: `deploy/QUICK-START-AUTOMATED.md`
- **Observability**: `docs/operations/observability.md`
- **Security**: `docs/architecture/multi-tenancy.md`
- **Runbook**: `deploy/RUNBOOK.md`

### External Links

- [Laravel Documentation](https://laravel.com/docs/12.x)
- [Livewire Documentation](https://livewire.laravel.com/docs)
- [Stripe API](https://stripe.com/docs/api)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)

## Version Information

- **Current Version**: 2.2.12
- **Last Updated**: 2025-01-10
- **Laravel Version**: 12.x
- **PHP Version**: 8.2+
- **Node Version**: 20+

---

**When working with this codebase**:
1. Always read files before modifying
2. Maintain multi-tenant isolation patterns
3. Use existing service and repository patterns
4. Follow DDD bounded context organization
5. Test thoroughly with feature tests
6. Document significant changes in CHANGELOG.md
