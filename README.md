# Mentat - Observability & Hosting Platform

A production-ready monorepo containing:
- **[Observability Stack](#observability-stack)** - Monitor all your servers with Prometheus, Loki, Grafana, and more
- **[CHOM](#chom---cloud-hosting--observability-manager)** - Multi-tenant SaaS platform for WordPress hosting management

Both projects work together to provide a complete hosting infrastructure with integrated observability.

---

## 🎯 Before You Begin

### Prerequisites

**System Requirements:**
- **OS**: Debian 13 or Ubuntu 22.04+ (for production deployment)
- **Access**: Root or sudo privileges
- **Resources**: Minimum 2GB RAM, 20GB disk space, 1-2 vCPU

**For Local Development (CHOM):**
- **PHP** 8.2+
- **Composer** 2.x
- **Node.js** 18+ and npm
- **Database**: SQLite, MySQL, or PostgreSQL

**Technical Knowledge:**
- Basic Linux command line
- SSH and remote server management (for production)
- Understanding of web servers and databases (helpful)

**Estimated Time:**
- Observability Stack deployment: 30-45 minutes
- CHOM development setup: 15-20 minutes
- Full production setup: 1-2 hours

### Not Sure Where to Start?

**Use the interactive deployment wizard:**
```bash
./deployment-wizard.sh
```

The wizard will ask you questions and guide you to the right deployment path.

---

## 📁 Repository Structure

```
mentat/
├── observability-stack/   # Observability infrastructure (Bash, YAML)
│   ├── prometheus/        # Metrics collection & alerting
│   ├── loki/             # Log aggregation
│   ├── grafana/          # Visualization & dashboards
│   ├── deploy/           # Bootstrap installers & deployment
│   └── ...
└── chom/                 # Laravel SaaS application (PHP, JavaScript)
    ├── app/              # Application logic
    ├── resources/        # Frontend assets
    ├── deploy/           # CHOM deployment scripts
    └── ...
```

---

## 🚀 Quick Start - Which Deployment Should I Use?

### Decision Tree

**I want to...**

1. **Monitor existing servers** → Use **Observability Stack**
   - Deploy to a dedicated monitoring VPS
   - Add exporters to servers you want to monitor
   - Access dashboards via Grafana

2. **Build a hosting platform** → Use **CHOM + Observability Stack**
   - Deploy Observability Stack first (monitoring infrastructure)
   - Deploy CHOM on a separate VPS (control plane)
   - CHOM will manage sites and integrate with observability

3. **Just try it locally** → Use **CHOM Development Mode**
   - Clone the repo and run `cd chom && php artisan serve`
   - Great for testing features and development

### Deployment Paths

| What You Need | Deploy Observability Stack | Deploy CHOM | Notes |
|---------------|:-------------------------:|:-----------:|-------|
| **Monitor servers only** | ✅ | ❌ | Use `observability-stack/deploy/bootstrap.sh` |
| **Full hosting platform** | ✅ First | ✅ Second | Deploy obs stack, then configure CHOM to connect |
| **Local development** | ❌ | ✅ | Use `php artisan serve` for CHOM |
| **VPSManager (Laravel + Monitoring)** | ✅ Via installer | ❌ | Use bootstrap.sh and select "VPSManager" role |

### Deployment Directories Explained

**Two separate deployment systems exist:**

1. **`observability-stack/deploy/`** - Standalone monitoring infrastructure
   - Script: `bootstrap.sh` or `install.sh`
   - Uses: Latest versions from this repository
   - For: Dedicated observability VPS or adding exporters to existing servers

2. **`chom/deploy/`** - CHOM infrastructure deployment
   - Scripts: `setup-observability-vps.sh`, `setup-vpsmanager-vps.sh`
   - Uses: Hardcoded stable versions
   - For: Setting up the full CHOM hosting platform

**When to use which:**

- **Use `observability-stack/deploy/`** if you want standalone monitoring
- **Use `chom/deploy/`** if you're deploying the full CHOM platform
- **Don't mix them** - choose one deployment approach per VPS

---

# Observability Stack

**Monitor all your servers from one place.** Get alerts before problems become outages.

This is a production-ready observability platform that installs directly on Debian/Ubuntu—no Docker, no Kubernetes, no complexity. Just run one command and you'll have:

- 📊 **Metrics** — CPU, memory, disk, network, database, web server
- 📝 **Logs** — All your logs in one searchable place
- 🔍 **Traces** — See requests flow through your systems
- 🚨 **Alerts** — Email notifications when things go wrong

## Quick Deploy (Fresh VPS)

```bash
# On a fresh Debian 13 VPS, run:
curl -sSL https://raw.githubusercontent.com/calounx/mentat/master/observability-stack/deploy/bootstrap.sh | sudo bash
```

This interactive installer will guide you through setting up either:
- **Observability VPS** — The central monitoring server
- **VPSManager** — A Laravel app with full LEMP stack + monitoring
- **Monitored Host** — Just the exporters for existing servers

See [observability-stack/deploy/README.md](observability-stack/deploy/README.md) for the full deployment guide.

---

## Stack Components

| Component | Purpose | Port |
|-----------|---------|------|
| **Prometheus** | Metrics collection & alerting | 9090 |
| **Loki** | Log aggregation | 3100 |
| **Tempo** | Distributed tracing | 4317/4318 |
| **Grafana** | Visualization & dashboards | 3000 |
| **Alertmanager** | Alert routing | 9093 |
| **Alloy** | OpenTelemetry collector | 12345 |

## Manual Installation

If you prefer manual setup or already have the repo cloned:

```bash
git clone https://github.com/calounx/mentat.git
cd mentat/observability-stack

# Option 1: Use interactive installer (recommended)
sudo ./deploy/install.sh

# Option 2: Use legacy scripts
cp config/global.yaml.example config/global.yaml
nano config/global.yaml
sudo ./scripts/setup-observability.sh
```

## Available Modules

```
observability-stack/modules/_core/
├── prometheus/        # Metrics server (v3.x)
├── loki/              # Log aggregation (v3.x)
├── tempo/             # Distributed tracing
├── alloy/             # OpenTelemetry collector
├── promtail/          # Log shipper
├── node_exporter/     # System metrics
├── nginx_exporter/    # Nginx metrics
├── mysqld_exporter/   # MySQL/MariaDB metrics
├── phpfpm_exporter/   # PHP-FPM metrics
└── fail2ban_exporter/ # Fail2ban metrics
```

## Pre-built Alert Rules

Ready-to-use alert rules in `observability-stack/prometheus/alerts/`:

| File | Coverage |
|------|----------|
| `node-alerts.yaml` | CPU, memory, disk, network, hardware |
| `prometheus-alerts.yaml` | Self-monitoring, TSDB, scraping |
| `loki-alerts.yaml` | Ingestion, storage, promtail |
| `nginx-alerts.yaml` | Availability, connections, SSL |
| `mysql-alerts.yaml` | Connections, replication, slow queries |
| `application-alerts.yaml` | HTTP, PHP-FPM, containers, fail2ban |
| `tempo-alerts.yaml` | Traces, spans, storage |
| `alloy-alerts.yaml` | Pipelines, components, resources |

## Dashboard Library

Pre-built dashboards in `observability-stack/grafana/dashboards/library/`:

- **Node Exporter Full** - Comprehensive system metrics
- **Nginx Overview** - Web server monitoring
- **MySQL Overview** - Database with replication status
- **Loki Overview** - Log aggregation metrics
- **Prometheus Self-Monitoring** - Prometheus health
- **Tempo Overview** - Distributed tracing
- **Alloy Overview** - Telemetry collector pipelines

## Testing

```bash
# From repository root
cd observability-stack

# Run all tests
make test

# Run specific test suites
make test-unit
make test-integration
make test-security

# Run shellcheck linting
make lint
```

---

# CHOM - Cloud Hosting & Observability Manager

A multi-tenant SaaS platform for WordPress hosting management with integrated observability.

CHOM integrates with the Observability Stack to provide monitoring, logging, and alerting for managed hosting infrastructure.

## Features

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
# Navigate to CHOM directory
cd chom

# Install dependencies
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

# Observability Stack Integration
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
# From chom/ directory

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

## Testing (All Projects)

```bash
# From repository root

# Test observability stack
cd observability-stack && make test

# Test CHOM application
cd chom && php artisan test
```

---

## License

MIT License - see [LICENSE](LICENSE) for details.

Copyright (c) 2025 Mentat & CHOM

---

## Versioning

This is a monorepo with independent versioning for each component:

- **Observability Stack**: v4.0.0
- **CHOM**: v1.1.0

---

## Support

- **Observability Stack**: Open issues at [github.com/calounx/mentat/issues](https://github.com/calounx/mentat/issues)
- **CHOM**: Contact support@chom.io

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and contribution guidelines.
