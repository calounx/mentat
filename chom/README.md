# CHOM - Cloud Hosting & Observability Manager

[![Status](https://img.shields.io/badge/status-production%20ready-success)](https://github.com/calounx/mentat)
[![Laravel](https://img.shields.io/badge/Laravel-12-FF2D20?logo=laravel)](https://laravel.com)
[![PHP](https://img.shields.io/badge/PHP-8.2%2B-777BB4?logo=php)](https://php.net)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

> A modern multi-tenant SaaS platform for WordPress hosting with integrated observability, built with Laravel 12.

---

## What is CHOM?

**CHOM** is a complete hosting control panel that manages customer sites, VPS servers, backups, and billing—all while integrating seamlessly with the Mentat observability stack for comprehensive monitoring.

**Perfect for:**
- 🏢 **Hosting Providers** - Manage customer WordPress/Laravel sites across multiple VPS servers
- 🎨 **Agencies** - Centralized management of client websites with built-in monitoring
- 🚀 **SaaS Operators** - Multi-tenant architecture with Stripe billing integration

---

## ✨ Key Features

### 🌐 Site Management
- **One-Click Deployments** - WordPress, Laravel, and static HTML sites
- **Automatic SSL** - Let's Encrypt integration with auto-renewal
- **Staging Environments** - Test changes safely before production
- **PHP Version Control** - Switch between PHP 8.2 and 8.4

### 🖥️ VPS Fleet Management
- **Intelligent Auto-Allocation** - Sites distributed based on capacity
- **Real-Time Health Monitoring** - Track CPU, memory, disk across all servers
- **Multi-Provider Support** - Works with DigitalOcean, Linode, Vultr, and more
- **Auto-Scaling Thresholds** - Automatic capacity management

### 💾 Backup & Recovery
- **Automated Backups** - Hourly, daily, weekly, monthly retention policies
- **One-Click Restore** - Restore to any point in time
- **Off-Site Storage** - Optional S3/cloud storage integration
- **Backup Validation** - Integrity checks before restore

### 📊 Integrated Observability
- **Metrics Dashboard** - Prometheus metrics from all managed sites
- **Centralized Logs** - Loki log aggregation with search
- **Distributed Tracing** - Laravel application performance tracking
- **Custom Dashboards** - Pre-built Grafana dashboards per site
- **Smart Alerts** - Automatic alerting for site issues

### 💳 Billing & Subscriptions
- **Stripe Integration** - Complete subscription lifecycle management
- **Tiered Pricing** - Starter ($29), Pro ($79), Enterprise ($249)
- **Usage Tracking** - Monitor and bill for resource consumption
- **Automatic Invoicing** - Transparent billing with invoice generation
- **Webhook Handlers** - Real-time payment event processing

### 👥 Team Collaboration
- **Multi-Organization** - Unlimited teams and workspaces
- **Role-Based Access** - Owner, Admin, Member, Viewer permissions
- **Team Invitations** - Email-based onboarding
- **Audit Trails** - Complete activity logging

---

## 🚀 Quick Start (5 Minutes)

### Prerequisites

- **PHP** 8.2+ with required extensions
- **Composer** 2.x
- **Node.js** 18+ and npm
- **Database** (SQLite for development, MySQL/PostgreSQL for production)
- **Redis** (optional but recommended for caching)

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/calounx/mentat.git
cd mentat/chom

# 2. Install dependencies (3-5 minutes)
composer install
npm install

# 3. Configure environment
cp .env.example .env
php artisan key:generate

# 4. Setup database
touch database/database.sqlite  # For SQLite
php artisan migrate

# 5. Build frontend assets
npm run build

# 6. Start development server
php artisan serve
```

🎉 **Done!** Access CHOM at [http://localhost:8000](http://localhost:8000)

### Quick Development Setup

For a full development environment with hot-reload:

```bash
composer run dev
```

This starts:
- 🌐 Web server on http://localhost:8000
- ⚡ Vite dev server with HMR
- 📬 Queue worker for background jobs
- 📋 Log viewer (Laravel Pail)

---

## 📚 Documentation

### For Everyone
- 📖 **[Getting Started Guide](docs/GETTING-STARTED.md)** - Step-by-step setup and first site
- 👥 **[User Guide](docs/USER-GUIDE.md)** - Day-to-day operations for non-technical users
- ❓ **[FAQ & Troubleshooting](docs/USER-GUIDE.md#faq)** - Common questions and solutions

### For Developers
- 💻 **[Developer Guide](docs/DEVELOPER-GUIDE.md)** - Local development setup and workflows
- 🔧 **[API Documentation](docs/API-README.md)** - REST API reference and examples
- 🧪 **[Testing Guide](docs/DEVELOPER-GUIDE.md#testing)** - Running tests and coverage
- 🤝 **[Contributing Guidelines](CONTRIBUTING.md)** - How to contribute

### For Operators
- 🚀 **[Operator Guide](docs/OPERATOR-GUIDE.md)** - Production deployment and maintenance
- ⚙️ **[Configuration Reference](docs/OPERATOR-GUIDE.md#configuration)** - Environment variables
- 📊 **[Monitoring Setup](docs/OPERATOR-GUIDE.md#monitoring)** - Observability stack integration
- 🔐 **[Security Guide](docs/security/application-security.md)** - Security best practices

### Quick Links
| Document | Description | Time |
|----------|-------------|------|
| [Quick Start](#quick-start-5-minutes) | Get running locally | 5 min |
| [Getting Started](docs/GETTING-STARTED.md) | Complete walkthrough | 20 min |
| [Deploy Guide](deploy/QUICKSTART.md) | Production deployment | 30 min |
| [API Guide](docs/API-QUICKSTART.md) | API integration | 15 min |

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      CHOM Control Plane                      │
│                    (Laravel 12 Application)                  │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Frontend: Livewire 3 + Alpine.js + Tailwind CSS            │
│  Backend:  Laravel Services + Jobs + Events                  │
│  Auth:     Laravel Sanctum + 2FA                             │
│  Billing:  Laravel Cashier (Stripe)                          │
│  Data:     SQLite/MySQL/PostgreSQL + Redis                   │
│                                                               │
└────────────┬────────────┬────────────┬───────────────────────┘
             │            │            │
      ┌──────▼──┐  ┌─────▼────┐  ┌───▼────────┐
      │ Managed │  │ Managed  │  │ Managed    │
      │ VPS 1   │  │ VPS 2    │  │ VPS 3      │
      └──────┬──┘  └─────┬────┘  └───┬────────┘
             │            │            │
             └────────────┴────────────┘
                          │
              ┌───────────▼───────────┐
              │ Observability Stack    │
              │ Prometheus + Loki +    │
              │ Grafana                │
              └────────────────────────┘
```

**Data Flow:**
1. **User** → Dashboard → **Site Service** → VPS Bridge → **SSH to Managed VPS**
2. **Managed VPS** → Metrics/Logs → **Observability Stack** → Dashboard
3. **Stripe** → Webhook → Billing Service → **Database** → User Notifications

For detailed architecture diagrams, see [ARCHITECTURE-PATTERNS.md](docs/ARCHITECTURE-PATTERNS.md).

---

## 🛠️ Tech Stack

| Category | Technology |
|----------|-----------|
| **Backend Framework** | Laravel 12 (PHP 8.2+) |
| **Frontend** | Livewire 3, Alpine.js 3, Tailwind CSS 4 |
| **Build Tool** | Vite 7 |
| **Database** | SQLite / MySQL 8+ / PostgreSQL 13+ |
| **Cache/Queue** | Redis 7+ |
| **API Auth** | Laravel Sanctum 4.2 |
| **Payments** | Stripe (Laravel Cashier 16.1) |
| **SSH/CLI** | phpseclib 3.0 |
| **Observability** | Prometheus, Loki, Grafana |
| **Testing** | PHPUnit 11, Pest (optional) |

---

## 💡 Use Cases

### Hosting Provider
```
→ Register VPS servers in CHOM
→ Configure pricing tiers
→ Customers sign up and create sites
→ Automatic billing via Stripe
→ Monitor all sites from single dashboard
```

### Web Agency
```
→ Add client sites to CHOM
→ Invite team members with roles
→ Create staging environments for testing
→ Automated backups before deployments
→ Share Grafana dashboards with clients
```

### SaaS Platform
```
→ Multi-tenant WordPress hosting
→ Usage-based billing integration
→ Centralized log aggregation
→ Performance monitoring per tenant
→ Automated scaling and backups
```

---

## 📊 Pricing Tiers

| Tier | Price/mo | Sites | Storage | Backups | Support |
|------|----------|-------|---------|---------|---------|
| **Starter** | $29 | 5 | 10GB | Daily | Email |
| **Pro** | $79 | 25 | 100GB | Hourly | Priority |
| **Enterprise** | $249 | Unlimited | Unlimited | Real-time | Dedicated |

Configure tiers in `config/chom.php` or override with environment variables.

---

## 🔌 API Quick Reference

### Authentication
```bash
# Register
curl -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Acme Corp","email":"admin@acme.com","password":"secure123"}'

# Login
curl -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@acme.com","password":"secure123"}'
```

### Site Management
```bash
# Create WordPress site
curl -X POST http://localhost:8000/api/v1/sites \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"domain":"example.com","type":"wordpress","php_version":"8.2"}'

# Issue SSL certificate
curl -X POST http://localhost:8000/api/v1/sites/{id}/ssl \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Backups
```bash
# Create backup
curl -X POST http://localhost:8000/api/v1/sites/{id}/backups \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"type":"full","description":"Pre-update backup"}'

# Restore backup
curl -X POST http://localhost:8000/api/v1/backups/{id}/restore \
  -H "Authorization: Bearer YOUR_TOKEN"
```

📘 **Full API Documentation:** [docs/API-README.md](docs/API-README.md)

---

## 🧪 Development

### Running Tests
```bash
# All tests
php artisan test

# With coverage
php artisan test --coverage --min=80

# Specific suite
php artisan test --testsuite=Feature

# Specific test
php artisan test --filter=SiteControllerTest
```

### Code Quality
```bash
# Format code (Laravel Pint)
./vendor/bin/pint

# Static analysis (PHPStan)
./vendor/bin/phpstan analyse

# All checks
composer test && ./vendor/bin/pint && ./vendor/bin/phpstan analyse
```

### Watch Assets
```bash
# Development mode (hot reload)
npm run dev

# Build for production
npm run build

# Build and watch
npm run build -- --watch
```

---

## 🔐 Security

### Security Features
- ✅ **API Authentication** - Laravel Sanctum token-based auth with rotation
- ✅ **Two-Factor Authentication** - TOTP-based 2FA for privileged accounts
- ✅ **Rate Limiting** - 5 req/min (auth), 60 req/min (API)
- ✅ **SSH Key Management** - Encrypted key storage with proper permissions
- ✅ **Tenant Isolation** - Complete data segregation by organization
- ✅ **CSRF Protection** - Enabled for all web routes
- ✅ **Content Security Policy** - XSS protection headers
- ✅ **Audit Logging** - Hash-chained tamper-proof logs

### Reporting Vulnerabilities
Found a security issue? Please **do not** open a public issue. Email security reports to:

📧 **security@chom.io**

See [SECURITY.md](SECURITY.md) for our security policy and response timeline.

---

## 🤝 Contributing

We welcome contributions! Here's how to get started:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Contribution Guidelines
- Follow PSR-12 coding standards
- Write tests for new features
- Update documentation as needed
- Ensure all tests pass before submitting

📖 **Full Guide:** [CONTRIBUTING.md](CONTRIBUTING.md)

---

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and release notes.

**Latest Release:** v1.1.0 (November 2025)

---

## 📄 License

CHOM is open-source software licensed under the [MIT License](LICENSE).

---

## 🆘 Support & Community

### Get Help
- 📖 **Documentation** - [Complete guides](docs/)
- 💬 **GitHub Discussions** - [Ask questions](https://github.com/calounx/mentat/discussions)
- 🐛 **Bug Reports** - [Open an issue](https://github.com/calounx/mentat/issues)
- 📧 **Email Support** - support@chom.io

### Stay Updated
- ⭐ **Star this repo** - Get notified of updates
- 🔔 **Watch releases** - Stay informed of new versions
- 🐦 **Follow on Twitter** - @chom_io (coming soon)

---

## 🙏 Acknowledgments

CHOM integrates with the **Mentat Observability Stack** - a production-ready monitoring platform providing Prometheus, Loki, Grafana, and more.

📊 **Learn more:** [observability-stack/README.md](../observability-stack/README.md)

---

## 📂 Project Structure

```
chom/
├── app/
│   ├── Http/Controllers/     # API and Web Controllers
│   ├── Livewire/             # Livewire Components
│   ├── Models/               # Eloquent Models
│   ├── Services/             # Business Logic Services
│   ├── Jobs/                 # Background Jobs
│   └── Policies/             # Authorization Policies
├── config/
│   └── chom.php              # CHOM Configuration
├── database/
│   ├── migrations/           # Database Migrations
│   └── factories/            # Model Factories
├── deploy/                   # Deployment Scripts
│   ├── QUICKSTART.md         # Quick deploy guide
│   └── deploy-enhanced.sh    # Automated deployment
├── docs/                     # Documentation
│   ├── GETTING-STARTED.md    # Beginner guide
│   ├── DEVELOPER-GUIDE.md    # Developer guide
│   ├── USER-GUIDE.md         # User guide
│   └── OPERATOR-GUIDE.md     # Operations guide
├── resources/
│   ├── views/                # Blade Templates
│   ├── css/                  # Styles
│   └── js/                   # JavaScript
├── routes/
│   ├── web.php               # Web Routes
│   └── api.php               # API Routes (v1)
└── tests/
    ├── Feature/              # Feature Tests
    └── Unit/                 # Unit Tests
```

---

## 🎯 Roadmap

### Version 1.2 (Q1 2025)
- [ ] WordPress auto-update management
- [ ] Multi-region VPS support
- [ ] Advanced caching (Redis/Memcached)
- [ ] Custom domain routing

### Version 1.3 (Q2 2025)
- [ ] Container-based site isolation
- [ ] Kubernetes support
- [ ] Advanced analytics dashboard
- [ ] Mobile app (iOS/Android)

### Version 2.0 (Q3 2025)
- [ ] Multi-cloud support (AWS, GCP, Azure)
- [ ] CDN integration
- [ ] Advanced backup strategies
- [ ] GraphQL API

Vote on features and suggest ideas in [GitHub Discussions](https://github.com/calounx/mentat/discussions).

---

<div align="center">

**Made with ❤️ by the CHOM Team**

[Documentation](docs/) • [API Reference](docs/API-README.md) • [Support](https://github.com/calounx/mentat/issues) • [Contributing](CONTRIBUTING.md)

</div>
