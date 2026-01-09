# CHOM - Cloud Hosting & Observability Manager

A multi-tenant SaaS platform for WordPress hosting management with integrated observability.

## New Features (v2.2.0)

**System Health & Self-Healing**
- Production-ready `/health` endpoint for external monitoring
- Automated recovery from common failures (database, cache, services)
- Circuit breakers to prevent cascading failures
- Graceful degradation when full recovery isn't possible

**VPSManager UI Integration**
- Manage infrastructure directly from CHOM dashboard
- Real-time server health monitoring
- Site deployment and management interface
- Visual server resource utilization

**Enhanced Observability**
- Loki multi-tenancy for complete log isolation between organizations
- New Grafana dashboards: System Health, Multi-Tenancy Isolation, Self-Healing Metrics
- Per-tenant resource limits and monitoring
- Blackbox probing for external availability monitoring

## Core Features

- **Multi-tenant Architecture** - Organizations, tenants, and team management with role-based access control
- **Site Management** - WordPress, HTML, and Laravel site provisioning with SSL certificates
- **VPS Fleet Management** - Automated server allocation with health monitoring
- **Backup System** - Automated backups with configurable retention policies
- **Observability** - Integrated Prometheus metrics and Loki logs with Grafana dashboards
- **Stripe Billing** - Subscription management with webhook handlers for lifecycle events
- **Team Collaboration** - Invite team members with Owner, Admin, Member, or Viewer roles

## Tech Stack

| Layer | Technology |
|-------|------------|
| Backend | Laravel 12, PHP 8.2+ |
| Frontend | Livewire 3, Alpine.js, Tailwind CSS 4 |
| Build | Vite |
| Database | SQLite / MySQL / PostgreSQL |
| Billing | Stripe (Laravel Cashier) |
| Observability | Prometheus, Loki, Grafana |

## Quick Start

```bash
# Clone and install
git clone https://github.com/calounx/chom.git
cd chom
composer install
npm install

# Configure environment
cp .env.example .env
php artisan key:generate

# Setup database
php artisan migrate

# Build frontend assets
npm run build

# Start development server
php artisan serve
```

## Configuration

### Environment Variables

```env
# Database
DB_CONNECTION=sqlite
DB_DATABASE=/absolute/path/to/database.sqlite

# Stripe Billing
STRIPE_KEY=pk_test_...
STRIPE_SECRET=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...

# VPS Manager SSH
CHOM_SSH_KEY_PATH=storage/app/ssh/chom_deploy_key

# Observability Stack
CHOM_PROMETHEUS_URL=http://prometheus:9090
CHOM_LOKI_URL=http://loki:3100
CHOM_GRAFANA_URL=http://grafana:3000
CHOM_GRAFANA_API_KEY=your-api-key
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│           SaaS Control Plane (Laravel)                  │
│  ┌─────────────────────────────────────────────────┐   │
│  │ Dashboard (Livewire) │ REST API (Sanctum)       │   │
│  └──────────────────────┴──────────────────────────┘   │
│  ┌─────────────────────────────────────────────────┐   │
│  │ Services: VPSManagerBridge, ObservabilityAdapter│   │
│  └─────────────────────────────────────────────────┘   │
└───────────────────────────┬─────────────────────────────┘
                            │ SSH + HTTP
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
┌──────────────┐   ┌────────────────┐   ┌─────────────┐
│  VPSManager  │   │ Observability  │   │   Stripe    │
│  (SSH+CLI)   │   │ Stack (HTTP)   │   │  (Webhooks) │
└──────────────┘   └────────────────┘   └─────────────┘
```

## Pricing Tiers

| Tier | Price | Sites | Storage | Features |
|------|-------|-------|---------|----------|
| Starter | $29/mo | 5 | 10GB | SSL, Daily backups |
| Pro | $79/mo | 25 | 100GB | + Staging, Priority support |
| Enterprise | $249/mo | Unlimited | Unlimited | + White-label, Dedicated IP |

## Stripe Webhooks

CHOM handles the following Stripe webhook events:

| Event | Action |
|-------|--------|
| `customer.subscription.created` | Creates subscription record, activates tenant |
| `customer.subscription.updated` | Updates tier and status |
| `customer.subscription.deleted` | Marks subscription canceled, suspends tenant |
| `invoice.paid` | Updates subscription status to active |
| `invoice.payment_failed` | Marks subscription past due |
| `charge.refunded` | Logs refund in audit trail |

Configure your webhook endpoint in Stripe Dashboard: `https://yourdomain.com/stripe/webhook`

## API Reference

### Authentication

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/auth/register` | Create new organization and user |
| POST | `/api/v1/auth/login` | Get authentication token |
| GET | `/api/v1/auth/me` | Get current user profile |

### Sites

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/sites` | List all sites |
| POST | `/api/v1/sites` | Create new site |
| GET | `/api/v1/sites/{id}` | Get site details |
| POST | `/api/v1/sites/{id}/ssl` | Issue SSL certificate |

### Backups

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/backups` | List all backups |
| POST | `/api/v1/sites/{id}/backups` | Create backup |
| POST | `/api/v1/backups/{id}/restore` | Restore from backup |

## Development

```bash
# Run all tests
php artisan test

# Run with coverage
php artisan test --coverage

# Watch for changes (development)
npm run dev

# Build for production
npm run build

# Run queue worker
php artisan queue:work

# Clear all caches
php artisan optimize:clear
```

## Project Structure

```
app/
├── Http/Controllers/
│   ├── Api/           # REST API controllers
│   └── Webhooks/      # Stripe webhook handlers
├── Livewire/          # Livewire components
├── Models/            # Eloquent models
├── Policies/          # Authorization policies
└── Services/          # Business logic services

resources/
├── css/app.css        # Tailwind CSS entry
├── js/app.js          # Alpine.js entry
└── views/             # Blade templates

deploy/                # Infrastructure deployment scripts
```

## Security

- **Authentication**: Laravel Sanctum for token-based API auth
- **Rate Limiting**: 5 req/min (auth), 60 req/min (API), 10 req/min (sensitive)
- **SSH**: Key-based authentication for VPS operations
- **Tenant Isolation**: Prometheus/Loki queries scoped by tenant ID
- **CSRF Protection**: Enabled for all web routes (except webhooks)

## License

MIT License - see [LICENSE](LICENSE) for details.

## Documentation

Comprehensive documentation is available in the `/docs` directory:

- **[Documentation Hub](docs/index.md)** - Start here for all documentation
- **[Architecture](docs/architecture/)** - System design and multi-tenancy security
- **[Operations](docs/operations/)** - Health checks, observability, and self-healing
- **[Development](docs/development/)** - Testing and contribution guidelines
- **[Deployment](docs/deployment/)** - Production deployment procedures

Quick links:
- [Multi-Tenancy Security](docs/architecture/multi-tenancy.md)
- [Testing Guide](docs/development/testing.md)
- [Observability Stack](docs/operations/observability.md)
- [Health Checks](docs/operations/health-checks.md)
- [Self-Healing](docs/operations/self-healing.md)

## Support

For support, contact support@chom.io
