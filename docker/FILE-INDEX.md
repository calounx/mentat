# CHOM Docker Environment - Complete File Index

Complete index of all configuration files, scripts, and documentation.

**Total Files:** 34
**Last Updated:** 2026-01-01

---

## 📚 Documentation (5 files)

Essential guides and references:

| File | Purpose | Size |
|------|---------|------|
| **START-HERE.md** | ⭐ Quick start guide | First-time users |
| **QUICKSTART.md** | 5-minute setup | Fast deployment |
| **README.md** | Complete documentation | Comprehensive (650+ lines) |
| **OPERATIONS-GUIDE.md** | Daily operations manual | Complete reference |
| **DEPLOYMENT-SUMMARY.md** | Technical architecture | Deep dive |
| **DEPLOYMENT-COMPLETE.md** | Deployment walkthrough | Step-by-step |
| **FILE-INDEX.md** | This file | File reference |

---

## 🐳 Core Docker Files (3 files)

Main orchestration and configuration:

| File | Purpose |
|------|---------|
| **docker-compose.yml** | Main service orchestration (18+ services) |
| **.env.example** | Environment template |
| **.env** | Active environment configuration |

---

## 🔧 Helper Scripts (6 files)

Automation and management scripts:

| Script | Purpose | Usage |
|--------|---------|-------|
| **scripts/setup.sh** | Automated setup | `./scripts/setup.sh` |
| **scripts/validate.sh** | 13 validation tests | `./scripts/validate.sh` |
| **scripts/quick-test.sh** | Fast health check | `./scripts/quick-test.sh` |
| **scripts/monitor.sh** | Real-time monitoring | `./scripts/monitor.sh` |
| **scripts/backup.sh** | Backup volumes | `./scripts/backup.sh` |
| **scripts/cleanup.sh** | Remove environment | `./scripts/cleanup.sh` |

All scripts are executable and include help text.

---

## 🎯 Makefile (1 file)

20+ convenience commands:

| File | Commands |
|------|----------|
| **Makefile** | up, down, logs, health, ps, shell, artisan, migrate, etc. |

Usage: `make help` to see all commands

---

## 📊 Observability Stack (11 files)

Configuration for monitoring and observability:

### Base Configuration

| File | Purpose |
|------|---------|
| **observability/Dockerfile** | Multi-service Debian 12 image |
| **observability/supervisord.conf** | Service manager (7 services) |

### Prometheus

| File | Purpose |
|------|---------|
| **observability/prometheus/prometheus.yml** | Metrics collection config (10+ targets) |
| **observability/prometheus/rules/alerts.yml** | 25+ alert rules |

### Loki

| File | Purpose |
|------|---------|
| **observability/loki/loki-config.yml** | Log aggregation config |

### Tempo

| File | Purpose |
|------|---------|
| **observability/tempo/tempo-config.yml** | Distributed tracing config |

### Alertmanager

| File | Purpose |
|------|---------|
| **observability/alertmanager/alertmanager.yml** | Alert routing config |

### Grafana

| File | Purpose |
|------|---------|
| **observability/grafana/grafana.ini** | Grafana configuration |
| **observability/grafana/datasources/datasources.yml** | Auto-provisioned datasources |
| **observability/grafana/dashboards/dashboards.yml** | Dashboard provisioning |

### Alloy (Collector)

| File | Purpose |
|------|---------|
| **observability/alloy/config.alloy** | Metrics/logs collector config |

---

## 🌐 Web Application Stack (9 files)

Configuration for Laravel web application:

### Base Configuration

| File | Purpose |
|------|---------|
| **web/Dockerfile** | Multi-service Debian 12 image |
| **web/supervisor/supervisord.conf** | Service manager (11 services) |

### Nginx

| File | Purpose |
|------|---------|
| **web/nginx/nginx.conf** | Main nginx config (130 lines) |
| **web/nginx/chom.conf** | Laravel site config (150 lines) |

### PHP

| File | Purpose |
|------|---------|
| **web/php/php.ini** | Production PHP settings |
| **web/php/php-fpm.conf** | Optimized FPM pools (80 lines) |

### MySQL

| File | Purpose |
|------|---------|
| **web/mysql/my.cnf** | Database tuning config |

### Application Scripts

| File | Purpose |
|------|---------|
| **web/scripts/init-app.sh** | App initialization (180 lines) |
| **web/scripts/healthcheck.sh** | Health check script |

### Alloy (Shipper)

| File | Purpose |
|------|---------|
| **web/alloy/config.alloy** | Metrics/logs shipper (230 lines) |

---

## 📁 Directory Structure

```
docker/
├── Documentation (7 MD files)
├── Scripts (6 SH files)
├── Makefile (1 file)
├── Docker Compose (1 YML + 2 ENV files)
│
├── observability/ (11 files)
│   ├── Dockerfile
│   ├── supervisord.conf
│   ├── prometheus/ (2 files)
│   ├── loki/ (1 file)
│   ├── tempo/ (1 file)
│   ├── alertmanager/ (1 file)
│   ├── grafana/ (3 files)
│   └── alloy/ (1 file)
│
└── web/ (9 files)
    ├── Dockerfile
    ├── supervisor/ (1 file)
    ├── nginx/ (2 files)
    ├── php/ (2 files)
    ├── mysql/ (1 file)
    ├── scripts/ (2 files)
    └── alloy/ (1 file)
```

---

## 📊 File Statistics

### By Type

| Type | Count | Purpose |
|------|-------|---------|
| Markdown (.md) | 7 | Documentation |
| Shell Scripts (.sh) | 6 | Automation |
| YAML (.yml/.yaml) | 8 | Configuration |
| Config (.conf) | 4 | Service configs |
| Dockerfile | 2 | Container builds |
| Alloy (.alloy) | 2 | Observability |
| INI (.ini) | 1 | PHP config |
| Makefile | 1 | Commands |
| ENV | 2 | Environment |

**Total:** 34 files

### By Size (Lines of Code)

| Category | Lines |
|----------|-------|
| Documentation | 1,500+ |
| Configuration | 1,200+ |
| Scripts | 800+ |
| **Total** | **3,500+** |

---

## 🎯 File Usage Guide

### For First-Time Users

1. **START-HERE.md** - Read this first
2. **scripts/setup.sh** - Run this to setup
3. **QUICKSTART.md** - 5-minute guide

### For Daily Operations

1. **Makefile** - `make help` for commands
2. **OPERATIONS-GUIDE.md** - Complete operations manual
3. **scripts/quick-test.sh** - Quick validation

### For Advanced Users

1. **README.md** - Complete documentation
2. **DEPLOYMENT-SUMMARY.md** - Architecture details
3. **docker-compose.yml** - Service definitions

### For Troubleshooting

1. **scripts/validate.sh** - 13 validation tests
2. **OPERATIONS-GUIDE.md** - Troubleshooting section
3. **scripts/monitor.sh** - Real-time monitoring

### For Customization

1. **observability/** - Observability configs
2. **web/** - Web application configs
3. **.env** - Environment variables

---

## 🔍 Finding Specific Configuration

### Metrics Collection

- **Prometheus config:** `observability/prometheus/prometheus.yml`
- **Scrape targets:** Same file, `scrape_configs` section
- **Alert rules:** `observability/prometheus/rules/alerts.yml`

### Logging

- **Loki config:** `observability/loki/loki-config.yml`
- **Log shipping:** `web/alloy/config.alloy`

### Web Server

- **Nginx main:** `web/nginx/nginx.conf`
- **Laravel site:** `web/nginx/chom.conf`

### PHP

- **PHP settings:** `web/php/php.ini`
- **PHP-FPM pools:** `web/php/php-fpm.conf`

### Database

- **MySQL tuning:** `web/mysql/my.cnf`

### Service Management

- **Observability services:** `observability/supervisord.conf`
- **Web services:** `web/supervisor/supervisord.conf`

---

## 📝 Configuration Priority

When multiple configs exist, this is the priority order:

1. **Environment variables** (`.env`)
2. **Docker Compose** (`docker-compose.yml`)
3. **Service configs** (`observability/`, `web/`)
4. **Dockerfile defaults**

---

## 🔄 Update History

| Date | Version | Changes |
|------|---------|---------|
| 2026-01-01 | 1.0 | Initial creation - 34 files |

---

## 📚 Quick Reference

### Essential Files

- Start: **START-HERE.md**
- Setup: **scripts/setup.sh**
- Validate: **scripts/validate.sh**
- Monitor: **scripts/monitor.sh**
- Operations: **OPERATIONS-GUIDE.md**

### Configuration Files

- Services: **docker-compose.yml**
- Environment: **.env**
- Prometheus: **observability/prometheus/prometheus.yml**
- Nginx: **web/nginx/chom.conf**

### Helper Tools

- Commands: **Makefile** (`make help`)
- Scripts: **scripts/** directory

---

**For complete documentation, see README.md**

**Last Updated:** 2026-01-01
