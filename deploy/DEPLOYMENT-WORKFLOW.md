# CHOM Deployment Workflow

Visual guide to the automated deployment process.

## High-Level Workflow

```
┌─────────────────────────────────────────────────────────────┐
│              CHOM Automated Deployment                      │
│                                                             │
│  Run: ./deploy-chom-automated.sh                           │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Phase 1: Pre-flight Checks                                │
│  • Verify running on mentat.arewel.com                     │
│  • Check root/sudo access                                   │
│  • Test internet connectivity                               │
│  • Verify SSH access to landsraad                          │
│  • Check required commands (git, curl, ssh, etc.)          │
│  • Verify disk space                                        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Phase 2: User Setup                                        │
│  ┌───────────────────┐        ┌───────────────────┐        │
│  │  mentat           │        │  landsraad        │        │
│  │  Create stilgar   │───────▶│  Create stilgar   │        │
│  │  Add to sudo      │        │  Add to sudo      │        │
│  │  Setup .ssh       │        │  Setup .ssh       │        │
│  └───────────────────┘        └───────────────────┘        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Phase 3: SSH Automation                                    │
│  ┌───────────────────┐        ┌───────────────────┐        │
│  │  mentat           │        │  landsraad        │        │
│  │  Generate SSH key │───────▶│  Accept public    │        │
│  │  Test connection  │◀───────│  key              │        │
│  └───────────────────┘        └───────────────────┘        │
│  ✓ Passwordless SSH: mentat → landsraad                    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Phase 4: Secrets Generation                                │
│  • APP_KEY (Laravel)                                        │
│  • DB_PASSWORD (PostgreSQL)                                 │
│  • REDIS_PASSWORD                                           │
│  • BACKUP_ENCRYPTION_KEY                                    │
│  • JWT_SECRET                                               │
│  • Prompt for domain, email (if interactive)               │
│  ▼                                                          │
│  .deployment-secrets (chmod 600)                            │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Phase 5: Prepare Mentat (Observability Server)            │
│  ┌─────────────────────────────────────────────────┐       │
│  │  Install Stack:                                 │       │
│  │  • Prometheus 2.48.0 ─┐                        │       │
│  │  • Grafana (latest)   ├─ Native systemd        │       │
│  │  • Loki 2.9.3        │  services               │       │
│  │  • Promtail 2.9.3    ├─ No Docker!             │       │
│  │  • AlertManager      │                          │       │
│  │  • Node Exporter     ┘                          │       │
│  │                                                  │       │
│  │  Configure:                                      │       │
│  │  • System limits (file descriptors, etc.)       │       │
│  │  • Sysctl tuning                                 │       │
│  │  • Log rotation                                  │       │
│  │  • Security hardening                            │       │
│  └─────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Phase 6: Prepare Landsraad (Application Server)           │
│  ┌─────────────────────────────────────────────────┐       │
│  │  Install Stack:                                 │       │
│  │  • PHP 8.2 + FPM + Extensions                   │       │
│  │  • PostgreSQL 15                                │       │
│  │  • Redis                                         │       │
│  │  • Nginx                                         │       │
│  │  • Node.js 20 + NPM                             │       │
│  │  • Composer                                      │       │
│  │  • Supervisor (queue workers)                   │       │
│  │  • Node Exporter                                │       │
│  │                                                  │       │
│  │  Configure:                                      │       │
│  │  • Create database & user                       │       │
│  │  • PHP-FPM pool for CHOM                        │       │
│  │  • Nginx virtual host                           │       │
│  │  • Supervisor workers                            │       │
│  │  • Log rotation                                  │       │
│  │  • Security hardening                            │       │
│  └─────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Phase 7: Deploy Application                                │
│  ┌─────────────────────────────────────────────────┐       │
│  │  1. Backup (pre-deployment safety)              │       │
│  │  2. Create new release directory                │       │
│  │     /var/www/chom/releases/20240115_143022/     │       │
│  │  3. Clone repository                             │       │
│  │  4. Link shared directories                     │       │
│  │     • storage → /var/www/chom/shared/storage   │       │
│  │     • .env → /var/www/chom/shared/.env         │       │
│  │  5. Install Composer dependencies                │       │
│  │  6. Build frontend assets (npm run build)       │       │
│  │  7. Run database migrations                     │       │
│  │  8. Optimize (config, routes, views cache)     │       │
│  │  9. Set permissions                              │       │
│  │  10. Health check (pre-switch)                  │       │
│  │  11. Atomic symlink swap                        │       │
│  │      current → releases/20240115_143022         │       │
│  │  12. Reload services (PHP-FPM, Nginx)          │       │
│  │  13. Health check (post-switch)                 │       │
│  │  14. Clean old releases (keep last 5)          │       │
│  └─────────────────────────────────────────────────┘       │
│                                                             │
│  ✓ Zero Downtime Deployment                                │
│  ✓ Automatic Rollback on Failure                           │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Phase 8: Deploy Observability Stack                       │
│  • Start all observability services                        │
│  • Verify services are running                             │
│  • Configure data retention                                │
│  • Setup initial dashboards                                │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Phase 9: Verification                                      │
│  ┌──────────────────┐     ┌──────────────────┐            │
│  │  mentat          │     │  landsraad       │            │
│  │  ✓ Prometheus    │     │  ✓ Nginx         │            │
│  │  ✓ Grafana       │     │  ✓ PHP-FPM       │            │
│  │  ✓ Loki          │     │  ✓ PostgreSQL    │            │
│  │  ✓ Promtail      │     │  ✓ Redis         │            │
│  │  ✓ AlertManager  │     │  ✓ Supervisor    │            │
│  │  ✓ Node Exporter │     │  ✓ Node Exporter │            │
│  └──────────────────┘     └──────────────────┘            │
│                                                             │
│  HTTP Endpoint Tests:                                       │
│  • http://mentat:9090/-/healthy (Prometheus)              │
│  • http://mentat:3000/api/health (Grafana)                │
│  • https://chom.arewel.com (Application)                   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                 ✓ DEPLOYMENT COMPLETE                       │
│                                                             │
│  Access URLs:                                               │
│  • Application: https://chom.arewel.com                     │
│  • Grafana: http://mentat.arewel.com:3000                  │
│  • Prometheus: http://mentat.arewel.com:9090               │
│                                                             │
│  Deployment Time: ~20 minutes                               │
│  Log: /var/log/chom-deploy/deployment-YYYYMMDD_HHMMSS.log │
└─────────────────────────────────────────────────────────────┘
```

## Idempotency in Action

Every script checks before acting:

```bash
# Example: User Creation (setup-stilgar-user.sh)
if id stilgar &>/dev/null; then
    echo "✓ User already exists - SKIP"
else
    useradd stilgar
    echo "✓ User created - DONE"
fi

# Example: Software Installation (prepare-mentat.sh)
if [[ -f /usr/bin/prometheus ]]; then
    if [[ version == expected ]]; then
        echo "✓ Prometheus already installed - SKIP"
    else
        echo "Upgrading Prometheus..."
    fi
else
    echo "Installing Prometheus..."
fi

# Example: Configuration Files
if [[ -f /etc/config/app.conf ]]; then
    echo "✓ Configuration exists - SKIP"
else
    echo "Creating configuration..."
fi
```

## Error Handling and Rollback

```
┌────────────────────────────────┐
│  Deployment Step               │
└────────────────────────────────┘
              │
              ▼
        ┌──────────┐
        │ Execute  │
        └──────────┘
              │
      ┌───────┴───────┐
      │               │
      ▼               ▼
  ┌────────┐      ┌────────┐
  │Success │      │ Error  │
  └────────┘      └────────┘
      │               │
      │               ▼
      │       ┌────────────────┐
      │       │ Log Error      │
      │       └────────────────┘
      │               │
      │               ▼
      │       ┌────────────────┐
      │       │ Notify         │
      │       └────────────────┘
      │               │
      │               ▼
      │       ┌────────────────┐
      │       │ Auto Rollback  │
      │       └────────────────┘
      │               │
      │               ▼
      │       ┌────────────────┐
      │       │ Restore Prev   │
      │       │ Release        │
      │       └────────────────┘
      │               │
      └───────────────┘
              │
              ▼
      ┌────────────┐
      │  Continue  │
      └────────────┘
```

## File Structure After Deployment

```
mentat.arewel.com
├── /opt/observability/
│   ├── bin/
│   │   ├── prometheus
│   │   ├── loki
│   │   ├── promtail
│   │   └── alertmanager
│   └── config/
│       ├── prometheus/
│       ├── grafana/
│       └── loki/
├── /var/lib/observability/
│   ├── prometheus/  (metrics data)
│   ├── grafana/     (dashboards)
│   └── loki/        (logs)
└── /var/log/chom-deploy/
    └── deployment-*.log

landsraad.arewel.com
├── /var/www/chom/
│   ├── current → releases/20240115_143022/  (symlink)
│   ├── releases/
│   │   ├── 20240115_143022/
│   │   ├── 20240115_120000/
│   │   └── ... (keeps last 5)
│   └── shared/
│       ├── .env
│       └── storage/
│           ├── app/
│           ├── logs/
│           └── framework/
├── /var/log/
│   ├── nginx/
│   ├── php8.2-fpm/
│   └── chom-deploy/
└── /etc/
    ├── nginx/sites-available/chom.conf
    ├── php/8.2/fpm/pool.d/chom.conf
    └── supervisor/conf.d/chom-worker.conf
```

## Component Dependencies

```
Application Stack Dependencies:
Nginx
  ↓
PHP-FPM
  ↓
Laravel Application
  ├─→ PostgreSQL (database)
  ├─→ Redis (cache/sessions/queues)
  └─→ Supervisor (queue workers)

Observability Stack:
Prometheus
  ├─→ Node Exporter (mentat)
  ├─→ Node Exporter (landsraad)
  └─→ AlertManager
Grafana
  ├─→ Prometheus (datasource)
  └─→ Loki (datasource)
Loki
  ←─ Promtail (log shipper)
```

## Security Layers

```
┌─────────────────────────────────────────┐
│  Network Layer                          │
│  • Firewall (ufw)                       │
│  • Fail2ban (brute force protection)   │
└─────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────┐
│  Transport Layer                        │
│  • SSL/TLS (Let's Encrypt)              │
│  • SSH keys only (no passwords)         │
└─────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────┐
│  Application Layer                      │
│  • HTTPS only                            │
│  • Strong passwords (auto-generated)    │
│  • JWT authentication                   │
│  • CSRF protection                      │
└─────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────┐
│  Data Layer                              │
│  • Database user isolation               │
│  • Encrypted backups                     │
│  • Secure credentials storage            │
└─────────────────────────────────────────┘
```

## Monitoring Flow

```
Application (landsraad)
  │
  ├─ Metrics ──→ Node Exporter ──→ Prometheus (mentat)
  │                                      ↓
  │                                  Grafana ← User
  │                                      ↓
  │                                AlertManager → Notifications
  │
  └─ Logs ───→ Promtail ───→ Loki (mentat)
                                   ↓
                               Grafana ← User
```

## Backup Strategy

```
Daily Backups
  │
  ├─ Database
  │   └─ pg_dump → encrypted → remote storage
  │
  ├─ Application Files
  │   └─ tar + gzip → encrypted → remote storage
  │
  └─ Configuration
      └─ /etc, secrets → encrypted → remote storage

Retention:
• Daily backups: 7 days
• Weekly backups: 4 weeks
• Monthly backups: 12 months
```

## Scaling Considerations

```
Current: Single Server Architecture
mentat (1 server) + landsraad (1 server)

Future: Multi-Server Architecture
┌─────────────────────────────────────┐
│  Load Balancer                      │
└─────────────────────────────────────┘
              │
    ┌─────────┴─────────┐
    ↓                   ↓
┌─────────┐       ┌─────────┐
│  App 1  │       │  App 2  │
└─────────┘       └─────────┘
    ↓                   ↓
┌──────────────────────────┐
│  Shared PostgreSQL       │
│  (Primary + Replica)     │
└──────────────────────────┘
    ↓
┌──────────────────────────┐
│  Redis Cluster           │
└──────────────────────────┘
```

---

This workflow ensures:
- **Reliability** - Multiple verification points
- **Security** - Defense in depth
- **Observability** - Full monitoring from day 1
- **Maintainability** - Automated and documented
