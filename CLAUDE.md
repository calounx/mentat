# CHOM - Cloud Hosting & Observability Manager

## Overview

CHOM (codename: Mentat) is a production-ready, multi-tenant SaaS platform for managing WordPress, HTML, and Laravel site hosting with comprehensive built-in observability. It serves as a control plane bridging SaaS billing/management with VPS infrastructure.

**Version:** 2.2.20
**Production URL:** chom.arewel.com
**License:** MIT

## Tech Stack

### Backend
- **Framework:** Laravel 12.0+ with PHP 8.2+
- **Database:** PostgreSQL 15 (production) / SQLite (development/testing)
- **Cache/Queue:** Redis 7+
- **API Auth:** Laravel Sanctum
- **Billing:** Stripe + Laravel Cashier
- **SSH:** phpseclib/phpseclib 3.0

### Frontend
- **Reactive UI:** Livewire 3.7+ with Alpine.js 3.15+
- **Styling:** Tailwind CSS 4.0+
- **Build:** Vite 7+

### Observability Stack
- Prometheus 2.48.0 (metrics)
- Grafana 10.2.2+ (dashboards)
- Loki 2.9.3 (logs)
- Promtail 2.9.3 (log collection)
- AlertManager (alerts)
- Jaeger 1.51 (tracing)

## Architecture

### Multi-Tenancy Hierarchy
```
Organization (billing container)
├── Tenant (billing unit)
│   ├── Site (hosted website)
│   └── VpsAllocation
├── User (team members)
└── Subscription (Stripe)
```

### Two-Server Architecture
- **Mentat (51.254.139.78):** Observability stack (Prometheus, Grafana, Loki)
- **Landsraad (51.254.139.79):** Application server (Laravel, Nginx, PostgreSQL)

### Key Services
- `VPSManagerBridge` - SSH orchestration to VPS servers
- `ObservabilityAdapter` - Prometheus/Loki/Grafana API integration
- `MetricsCollector` - Prometheus metrics export with Redis storage
- `HealthCheckService` - System coherency detection

### Reliability Patterns
- **Circuit Breaker:** Per-service breakers (Prometheus, Grafana, Loki, VPSManager)
- **Retry Manager:** Exponential backoff with jitter
- **Graceful Degradation:** Fallback to cached data when services unavailable
- **Correlation ID:** Request tracking across services via `X-Correlation-ID` header

## Setup & Installation

### Prerequisites
```bash
php >= 8.2
composer
node >= 18
npm
```

### Installation
```bash
git clone <repository>
cd mentat
composer install
npm install
cp .env.example .env
php artisan key:generate
```

### Environment Variables
Key variables to configure:
```env
# Database
DB_CONNECTION=pgsql  # or sqlite for development
DB_DATABASE=chom

# Redis
REDIS_HOST=127.0.0.1
REDIS_PREFIX=chom_database_  # Important: affects metrics key parsing

# Observability
PROMETHEUS_URL=http://51.254.139.78:9090
GRAFANA_URL=http://51.254.139.78:3000
LOKI_URL=http://51.254.139.78:3100
ALERTMANAGER_URL=http://51.254.139.78:9093

# Metrics
METRICS_IP_WHITELIST=127.0.0.1,51.254.139.78
METRICS_NAMESPACE=chom

# SSH (for VPSManager)
CHOM_SSH_KEY_PATH=/path/to/ssh/key
```

### Database Setup
```bash
php artisan migrate
php artisan db:seed  # Optional: seed test data
```

### Running Locally
```bash
php artisan serve
npm run dev  # In separate terminal
php artisan queue:work  # For background jobs
```

## Development Workflow

### Testing
```bash
php artisan test                    # Run all tests
php artisan test --coverage         # With coverage
php artisan test tests/Feature      # Feature tests only
```

**Note:** Tests use SQLite in-memory. Migrations are SQLite-compatible (use Schema builder, not raw SQL).

### Code Quality
```bash
./vendor/bin/pint  # Laravel Pint for code style
```

### Deployment

**Recommended: Local SSH Deployment**
```bash
./deploy-from-local.sh

# With options
./deploy-from-local.sh --dry-run
./deploy-from-local.sh --skip-backup
```

**Manual SSH Deployment**
```bash
ssh stilgar@mentat.arewel.com "cd /var/www/mentat && \
  git pull origin main && \
  composer install --no-dev --optimize-autoloader && \
  php artisan migrate --force && \
  php artisan config:cache && \
  php artisan route:cache && \
  php artisan view:cache && \
  sudo systemctl restart php8.2-fpm nginx"
```

See `DEPLOYMENT-METHODS.md` for all deployment options.

## API Documentation

### Authentication
```
POST   /api/v1/auth/register    # Register organization + user
POST   /api/v1/auth/login       # Login, returns token
GET    /api/v1/auth/me          # Current user info
```

### Sites
```
GET    /api/v1/sites            # List tenant sites
POST   /api/v1/sites            # Create site
GET    /api/v1/sites/{id}       # Site details
POST   /api/v1/sites/{id}/ssl   # Issue SSL certificate
DELETE /api/v1/sites/{id}       # Delete site
```

### Health & Observability
```
GET    /api/v1/health                           # Health check
GET    /api/v1/observability/health             # Stack health
GET    /api/v1/observability/health/{component} # Component health
GET    /prometheus/metrics                       # Prometheus metrics export
```

### Rate Limits
- Auth endpoints: 5 req/min
- API endpoints: 60 req/min per user

## File Structure

```
app/
├── Http/Controllers/Api/V1/    # REST API controllers
├── Http/Middleware/            # Auth, tenant, metrics middleware
├── Livewire/                   # 21 reactive UI components
├── Models/                     # 16 Eloquent models
├── Services/
│   ├── Integration/            # VPSManagerBridge, ObservabilityAdapter
│   └── Reliability/            # Circuit breaker, retry, degradation
├── Jobs/                       # Background jobs (provisioning, backups)
└── Policies/                   # Authorization policies

config/
├── chom.php                    # Platform settings, billing tiers
├── observability.php           # Metrics, tracing config
├── circuit-breaker.php         # Service circuit breakers
├── retry.php                   # Retry policies
└── degradation.php             # Graceful degradation rules

observability-stack/            # Docker Compose for Prometheus/Grafana/Loki
deploy/                         # Deployment scripts and configs
docs/                           # Architecture and operations docs
```

## Recent Updates (2026-01-11)

### v2.2.20 Changes

**Metrics & Observability Fixes**
- Fixed Redis prefix handling in `MetricsCollector` - now properly strips Laravel's `chom_database_` prefix before `Redis::get()` calls
- Registered `PrometheusMetricsMiddleware` in `bootstrap/app.php` for HTTP metrics collection

**Test Infrastructure**
- Major test infrastructure fixes for SQLite compatibility
- Migrations now use Laravel Schema builder instead of raw SQL (PostgreSQL `ALTER TABLE` statements replaced)
- Added `doctrine/dbal` for column modification support
- VpsServer model/factory updated with `ssh_user` and `ssh_port` columns

**Deployment Documentation**
- Added `deploy-from-local.sh` - automated local SSH deployment script
- Added `DEPLOYMENT-METHODS.md` - comprehensive guide with 6 deployment strategies
- Added `QUICK-DEPLOY.md` - quick reference deployment card
- Added `DEPLOY-V2.2.20.md` - version-specific deployment guide

**Database Schema**
- New migration: `add_missing_columns_to_vps_servers` (ssh_user, ssh_port)
- Fixed `add_plan_selection_to_tenants` migration for SQLite compatibility
- Fixed `make_user_name_fields_not_null` migration for SQLite compatibility

## Important Notes

### Security
- All queries MUST filter by `tenant_id` for multi-tenancy isolation
- SSH key-based authentication only (no passwords)
- Metrics endpoint requires IP whitelist (`METRICS_IP_WHITELIST`)

### Metrics Collection
The `MetricsCollector` stores metrics in Redis with keys like `metrics:http_requests_total`. When retrieving, it strips the Laravel Redis prefix to avoid double-prefixing.

### Circuit Breakers
Each external service has its own circuit breaker with tailored thresholds:
- Prometheus/Grafana/Loki: 3 failures, 30s timeout
- Database: 5 failures, 60s timeout
- VPSManager: 3 failures, 60s timeout

### Testing
- Use SQLite for tests (configured in `phpunit.xml`)
- Migrations must be SQLite-compatible (avoid raw SQL, use Schema builder)
- Run `php artisan migrate:fresh` with `--env=testing` for test database

### Billing Tiers
- **Starter:** $29/mo, 5 sites, 10GB storage
- **Pro:** $79/mo, 25 sites, 100GB storage
- **Enterprise:** $249/mo, unlimited
