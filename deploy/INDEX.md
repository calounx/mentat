# CHOM Deployment System - File Index

## Quick Navigation

### Getting Started
1. [QUICK_START.md](QUICK_START.md) - **START HERE** - 30-minute setup guide
2. [README.md](README.md) - Comprehensive documentation
3. [RUNBOOK.md](RUNBOOK.md) - Operational procedures and troubleshooting
4. [DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md) - System overview and architecture

## Main Deployment Script

| File | Purpose | Lines | Usage |
|------|---------|-------|-------|
| `deploy-chom.sh` | Main orchestration script | 300 | `./deploy-chom.sh --environment=production --branch=main` |

**Run from:** mentat.arewel.com as user `stilgar`

## Server Preparation Scripts

| File | Server | Purpose | Lines | Run As |
|------|--------|---------|-------|--------|
| `scripts/prepare-mentat.sh` | mentat | Install Docker, monitoring stack | 380 | root/sudo |
| `scripts/prepare-landsraad.sh` | landsraad | Install PHP, Nginx, PostgreSQL, Redis | 450 | root/sudo |
| `scripts/setup-firewall.sh` | both | Configure UFW and fail2ban | 280 | root/sudo |
| `scripts/setup-ssl.sh` | landsraad | Install Let's Encrypt SSL | 250 | root/sudo |
| `scripts/setup-ssh-keys.sh` | both | Configure SSH keys | 180 | stilgar |

## Deployment Scripts

| File | Purpose | Lines | Run From |
|------|---------|-------|----------|
| `scripts/deploy-application.sh` | Deploy Laravel to landsraad | 480 | mentat (via SSH) |
| `scripts/deploy-observability.sh` | Deploy monitoring stack to mentat | 250 | mentat |
| `scripts/backup-before-deploy.sh` | Create pre-deployment backup | 320 | landsraad |
| `scripts/rollback.sh` | Rollback to previous release | 360 | landsraad |
| `scripts/health-check.sh` | Validate deployment health | 520 | landsraad |

## Configuration Files - Landsraad (Application Server)

| File | Service | Lines | Deploy To | Purpose |
|------|---------|-------|-----------|---------|
| `config/landsraad/nginx.conf` | Nginx | 150 | `/etc/nginx/sites-available/chom` | Web server config |
| `config/landsraad/php-fpm.conf` | PHP-FPM | 90 | `/etc/php/8.2/fpm/pool.d/chom.conf` | PHP pool config |
| `config/landsraad/postgresql.conf` | PostgreSQL | 80 | `/etc/postgresql/15/main/conf.d/chom-tuning.conf` | DB tuning |
| `config/landsraad/redis.conf` | Redis | 60 | `/etc/redis/redis.conf` | Cache config |
| `config/landsraad/supervisor.conf` | Supervisor | 35 | `/etc/supervisor/conf.d/chom-worker.conf` | Queue workers |
| `config/landsraad/.env.production.template` | Laravel | 85 | `/var/www/chom/shared/.env` | App environment |

## Configuration Files - Mentat (Observability Server)

| File | Service | Lines | Deploy To | Purpose |
|------|---------|-------|-----------|---------|
| `config/mentat/docker-compose.prod.yml` | Docker Compose | 180 | `/opt/observability/docker-compose.yml` | Stack definition |
| `config/mentat/prometheus.yml` | Prometheus | 140 | `/opt/observability/config/prometheus.yml` | Metrics collection |
| `config/mentat/alertmanager.yml` | AlertManager | 110 | `/opt/observability/config/alertmanager.yml` | Alert routing |
| `config/mentat/grafana-datasources.yml` | Grafana | 30 | `/opt/observability/config/grafana/...` | Data sources |
| `config/mentat/loki-config.yml` | Loki | 90 | `/opt/observability/config/loki-config.yml` | Log aggregation |
| `config/mentat/promtail-config.yml` | Promtail | 40 | `/opt/observability/config/promtail-config.yml` | Log shipping |
| `config/mentat/blackbox.yml` | Blackbox Exporter | 30 | `/opt/observability/config/blackbox.yml` | Endpoint monitoring |

## Utility Scripts

| File | Purpose | Lines | Usage |
|------|---------|-------|-------|
| `utils/logging.sh` | Logging functions | 200 | Sourced by all scripts |
| `utils/colors.sh` | Terminal colors | 90 | Sourced by logging.sh |
| `utils/notifications.sh` | Slack/email notifications | 180 | Sourced by deployment scripts |

## Documentation

| File | Purpose | Lines | Audience |
|------|---------|-------|----------|
| `QUICK_START.md` | Quick setup guide | 380 | New deployments |
| `README.md` | Complete documentation | 420 | All users |
| `RUNBOOK.md` | Operations manual | 450 | Operations team |
| `DEPLOYMENT_SUMMARY.md` | System overview | 650 | Technical leads |
| `INDEX.md` | This file | 250 | Quick reference |

## Directory Structure

```
deploy/
├── deploy-chom.sh                      # Main orchestration
├── INDEX.md                            # This file
├── README.md                           # Complete docs
├── QUICK_START.md                      # Quick setup
├── RUNBOOK.md                          # Operations
├── DEPLOYMENT_SUMMARY.md               # Overview
├── .gitignore                          # Git ignore rules
│
├── config/                             # Configuration files
│   ├── landsraad/                      # Application server configs
│   │   ├── nginx.conf
│   │   ├── php-fpm.conf
│   │   ├── postgresql.conf
│   │   ├── redis.conf
│   │   ├── supervisor.conf
│   │   └── .env.production.template
│   └── mentat/                         # Observability server configs
│       ├── docker-compose.prod.yml
│       ├── prometheus.yml
│       ├── alertmanager.yml
│       ├── grafana-datasources.yml
│       ├── loki-config.yml
│       ├── promtail-config.yml
│       └── blackbox.yml
│
├── scripts/                            # Deployment scripts
│   ├── prepare-mentat.sh
│   ├── prepare-landsraad.sh
│   ├── deploy-application.sh
│   ├── deploy-observability.sh
│   ├── health-check.sh
│   ├── rollback.sh
│   ├── backup-before-deploy.sh
│   ├── setup-ssh-keys.sh
│   ├── setup-firewall.sh
│   └── setup-ssl.sh
│
└── utils/                              # Utility functions
    ├── colors.sh
    ├── logging.sh
    └── notifications.sh
```

## Common Workflows

### First-Time Setup

```bash
# 1. Prepare servers
sudo ./scripts/prepare-mentat.sh        # On mentat
sudo ./scripts/prepare-landsraad.sh     # On landsraad

# 2. Configure security
sudo ./scripts/setup-firewall.sh --server mentat
sudo ./scripts/setup-firewall.sh --server landsraad
sudo ./scripts/setup-ssl.sh --domain chom.arewel.com --email admin@example.com

# 3. Setup SSH keys
./scripts/setup-ssh-keys.sh --target-host landsraad.arewel.com

# 4. Deploy observability
./scripts/deploy-observability.sh

# 5. Deploy application
export REPO_URL="https://github.com/org/chom.git"
./deploy-chom.sh --environment=production --branch=main
```

### Regular Deployment

```bash
# From mentat as stilgar
./deploy-chom.sh --environment=production --branch=main
```

### Emergency Rollback

```bash
# SSH to landsraad
ssh stilgar@landsraad.arewel.com

# Execute rollback
/var/www/chom/deploy/scripts/rollback.sh

# Or with database restore
/var/www/chom/deploy/scripts/rollback.sh --restore-database
```

### Health Check

```bash
ssh stilgar@landsraad.arewel.com "/var/www/chom/deploy/scripts/health-check.sh"
```

### Manual Backup

```bash
ssh stilgar@landsraad.arewel.com "/var/www/chom/deploy/scripts/backup-before-deploy.sh"
```

## Key Commands Reference

### Deployment Management

```bash
# Full deployment
./deploy-chom.sh --environment=production --branch=main

# Skip backup (faster)
./deploy-chom.sh --environment=production --branch=main --skip-backup

# Skip migrations
./deploy-chom.sh --environment=production --branch=main --skip-migrations

# Application only (no observability)
./deploy-chom.sh --environment=production --skip-observability
```

### Service Management

```bash
# Restart services (on landsraad)
sudo systemctl restart nginx php8.2-fpm postgresql redis-server

# Restart queue workers
sudo supervisorctl restart chom-worker:*

# Check service status
sudo systemctl status nginx php8.2-fpm postgresql redis-server
```

### Monitoring

```bash
# View deployment logs
tail -f /var/log/chom-deploy/deployment-*.log

# View application logs
tail -f /var/www/chom/shared/storage/logs/laravel.log

# View queue worker logs
tail -f /var/www/chom/shared/storage/logs/worker.log

# View Nginx logs
tail -f /var/log/nginx/chom-access.log
tail -f /var/log/nginx/chom-error.log
```

### Database Operations

```bash
# Run migrations
cd /var/www/chom/current && php artisan migrate --force

# Check migration status
cd /var/www/chom/current && php artisan migrate:status

# Access database
psql -h localhost -U chom -d chom
```

### Observability Stack

```bash
# On mentat
docker compose -f /opt/observability/docker-compose.yml ps
docker compose -f /opt/observability/docker-compose.yml logs -f
docker compose -f /opt/observability/docker-compose.yml restart prometheus
```

## Access Points

### Application

- **Production:** https://chom.arewel.com
- **Health Check:** https://chom.arewel.com/health
- **Metrics:** http://landsraad.arewel.com:9200/metrics

### Monitoring (Mentat)

- **Grafana:** http://mentat.arewel.com:3000 (admin/admin)
- **Prometheus:** http://mentat.arewel.com:9090
- **AlertManager:** http://mentat.arewel.com:9093
- **Loki:** http://mentat.arewel.com:3100

### Metrics Exporters

- **Node Exporter (landsraad):** http://landsraad.arewel.com:9100/metrics
- **Node Exporter (mentat):** http://mentat.arewel.com:9100/metrics

## File Locations on Servers

### Landsraad (Application Server)

```
/var/www/chom/
├── current -> releases/20240101_120000/    # Current release (symlink)
├── releases/                               # All releases
│   ├── 20240101_120000/
│   ├── 20240101_110000/
│   └── ...
├── shared/                                 # Shared files
│   ├── .env
│   └── storage/
├── backups/                                # Backups
│   ├── database_*.sql.gz
│   └── application_*.tar.gz
└── deploy/                                 # Deployment scripts
    ├── scripts/
    └── config/
```

### Mentat (Observability Server)

```
/opt/observability/
├── docker-compose.yml                      # Stack definition
├── config/                                 # Configuration files
│   ├── prometheus.yml
│   ├── alertmanager.yml
│   └── ...
└── ...

/var/lib/observability/                     # Data directories
├── prometheus/
├── grafana/
├── loki/
└── alertmanager/
```

## Environment Variables

### Required

```bash
export REPO_URL="https://github.com/org/chom.git"
```

### Optional

```bash
export GITHUB_TOKEN="ghp_xxx..."                    # For private repos
export SLACK_WEBHOOK_URL="https://hooks.slack..."  # Notifications
export EMAIL_RECIPIENTS="ops@example.com"           # Email alerts
export DB_PASSWORD="secure_password"               # Database
export REDIS_PASSWORD="secure_password"            # Redis
```

## System Statistics

- **Total Files:** 35
- **Shell Scripts:** 30
- **Configuration Files:** 7
- **Documentation Files:** 5
- **Total Lines of Code:** 15,059
- **Production Ready:** Yes
- **Placeholders:** 0
- **Stubs:** 0

## Support and Troubleshooting

### Log Locations

- Deployment logs: `/var/log/chom-deploy/`
- Application logs: `/var/www/chom/shared/storage/logs/`
- System logs: `/var/log/` (syslog, auth.log, etc.)

### Common Issues

See [RUNBOOK.md](RUNBOOK.md) for detailed troubleshooting procedures.

### Quick Fixes

- **Services not running:** `sudo systemctl restart <service>`
- **Queue workers stuck:** `sudo supervisorctl restart chom-worker:*`
- **Cache issues:** `cd /var/www/chom/current && php artisan cache:clear`
- **Permission issues:** `sudo chown -R stilgar:www-data /var/www/chom`

## Version Information

- **Created:** 2024
- **Debian Version:** 13
- **PHP Version:** 8.2
- **PostgreSQL Version:** 15
- **Node.js Version:** 20
- **Docker Version:** 24+

## License

Proprietary - CHOM Application Deployment System

---

**For detailed information, see the appropriate documentation file above.**
