# CHOM v2.0.0 - Complete Hosting & Operations Manager

## Project Overview

CHOM (Complete Hosting & Operations Manager) is a Laravel-based VPS management platform designed to automate hosting operations, monitoring, and site deployment. The system uses a **two-server architecture** with full observability and automated deployment capabilities.

**Repository:** https://github.com/calounx/mentat
**Production URL:** https://chom.arewel.com
**Monitoring URL:** https://mentat.arewel.com

## Architecture

### Two-Server Design (Scalable to N Servers)

1. **mentat.arewel.com** (51.254.139.78)
   - **Role:** Observability & Monitoring Server (Controller)
   - **Services:** Prometheus, Grafana, Loki, Promtail, AlertManager, Node Exporter
   - **Function:** Central monitoring, metrics collection, log aggregation, alerting, deployment orchestration
   - **Access:** SSH as `calounx` or `stilgar`, HTTPS for dashboards

2. **landsraad.arewel.com** (51.254.139.79)
   - **Role:** Application Server
   - **Services:** Nginx, PHP 8.2-FPM, PostgreSQL 15, Redis, Laravel Queue Workers
   - **Function:** CHOM application hosting, database, cache, background jobs
   - **Access:** SSH as `calounx` or `stilgar`, HTTPS for application

### Key Design Principles

- **Single Entry Point:** ALL deployments use `deploy/deploy-chom-automated.sh` from mentat
- **Idempotent:** Safe to run multiple times
- **Fully Automated:** No manual steps, no placeholders
- **User:** Deployments run as `stilgar` user (deployment user, not root)
- **From Mentat:** All operations initiated from mentat server (controller)
- **One-Way SSH:** mentat → VPS servers only (no reverse SSH, better security)
- **Scalable:** Adding new VPS requires only one SSH key setup

## Technology Stack

### Backend (Laravel 11)
- **Framework:** Laravel 11.x
- **PHP:** 8.2+ (FPM)
- **Database:** PostgreSQL 15
- **Cache:** Redis 7
- **Queue:** Redis-based queues
- **Authentication:** Filament admin panel

### Frontend
- **UI Framework:** Livewire 3.x
- **Admin Panel:** Filament 3.x
- **CSS:** Tailwind CSS
- **Build:** Vite

### Monitoring Stack (Native Installation - No Docker)
- **Metrics:** Prometheus 2.48.0
- **Visualization:** Grafana 11.3.0
- **Logs:** Loki 2.9.3 + Promtail
- **Alerts:** AlertManager 0.26.0
- **Exporters:**
  - node_exporter (system metrics)
  - nginx_exporter (web server)
  - postgres_exporter (database)
  - redis_exporter (cache)
  - php-fpm_exporter (PHP runtime)
  - blackbox_exporter (HTTP probing)

### Infrastructure
- **OS:** Debian 13 (Trixie)
- **Web Server:** Nginx
- **Reverse Proxy:** Nginx with SSL (Let's Encrypt)
- **Firewall:** UFW
- **Process Manager:** Systemd

## Deployment System

### Master Deployment Script

**Location:** `deploy/deploy-chom-automated.sh`

**Critical Rule:** ⚠️ ONLY use this script for ALL operations. No manual steps, no helper scripts.

**Usage:**
```bash
# Full deployment (from scratch)
sudo ./deploy/deploy-chom-automated.sh

# Re-deploy application only
sudo ./deploy/deploy-chom-automated.sh \
    --skip-user-setup --skip-ssh --skip-secrets \
    --skip-mentat-prep --skip-landsraad-prep --skip-observability
```

### Deployment Phases

1. **Phase 1: User Setup** - Creates `stilgar` deployment user on both servers
2. **Phase 2: SSH Automation** - Sets up passwordless SSH (mentat → landsraad)
3. **Phase 3: Secrets Generation** - Auto-generates all credentials
4. **Phase 4: Prepare Mentat** - Installs observability stack
5. **Phase 5: Prepare Landsraad** - Installs application dependencies
6. **Phase 6: Deploy Application** - Deploys Laravel app + exporters
7. **Phase 7: Deploy Observability** - Configures monitoring stack
8. **Phase 8: Verification** - Health checks

### Key Deployment Scripts

All scripts in `deploy/scripts/`:

**Server Preparation:**
- `prepare-mentat.sh` - Initial mentat setup (observability tools)
- `prepare-landsraad.sh` - Initial landsraad setup (app stack)
- `setup-observability-vps.sh` - VPS-specific observability setup
- `setup-vpsmanager-vps.sh` - VPSManager installation

**Application Deployment:**
- `deploy-application.sh` - Laravel app deployment (includes exporters)
- `deploy-observability.sh` - Observability config deployment
- `deploy-exporters.sh` - Universal exporter deployment (auto-detects services)

**Utilities:**
- `backup-before-deploy.sh` - Pre-deployment backup
- `health-check.sh` - Post-deployment validation
- `rollback.sh` - Rollback to previous release
- `generate-deployment-secrets.sh` - Secret generation

### Configuration Files

**Mentat (Observability):** `deploy/config/mentat/`
- `prometheus.yml` - Prometheus config with file-based service discovery
- `loki-config.yml` - Loki log aggregation config
- `promtail-config.yml` - Log shipping config
- `grafana-datasources.yml` - Grafana data sources
- `alertmanager.yml` - Alert routing
- `prometheus-alerts/` - Alert rules

**Landsraad (Application):** `deploy/config/landsraad/`
- `nginx-chom.conf` - Nginx virtual host
- `nginx-status.conf` - Nginx stub_status for metrics
- `php-fpm-status.conf` - PHP-FPM status pool
- Environment variables in `/var/www/chom/shared/.env`

## Directory Structure

```
/home/calounx/repositories/mentat/
├── app/                          # Laravel application
│   ├── Http/                     # Controllers, Middleware
│   ├── Jobs/                     # Background jobs
│   ├── Livewire/                 # Livewire components
│   ├── Models/                   # Eloquent models
│   └── Services/                 # Business logic
├── deploy/                       # Deployment automation
│   ├── deploy-chom-automated.sh  # MASTER DEPLOYMENT SCRIPT
│   ├── config/                   # Configuration files
│   │   ├── mentat/              # Observability configs
│   │   └── landsraad/           # Application configs
│   ├── scripts/                 # Deployment scripts
│   ├── utils/                   # Shared utilities
│   ├── vpsmanager/              # VPS management CLI
│   └── security/                # Security configurations
├── resources/                   # Frontend assets
│   ├── views/                   # Blade templates
│   └── js/                      # JavaScript
├── database/                    # Migrations, seeders
└── tests/                       # PHPUnit tests
```

## Server Paths

### Mentat (Observability Server)
```
/opt/observability/bin/          # Binaries (prometheus, loki, etc.)
/etc/observability/              # Configurations
/var/lib/observability/          # Data storage (metrics, logs)
/etc/nginx/sites-available/observability  # Nginx config
/etc/grafana/                    # Grafana config
```

### Landsraad (Application Server)
```
/var/www/chom/                   # Application root
├── current -> releases/20260105-143256/  # Symlink to active release
├── releases/                    # Release history
│   ├── 20260105-143256/
│   ├── 20260105-120430/
│   └── ...
└── shared/                      # Shared across releases
    ├── .env                     # Environment config
    ├── storage/                 # Logs, cache, sessions
    └── uploads/                 # User uploads

/etc/nginx/sites-available/chom  # Nginx config
/etc/php/8.2/fpm/pool.d/chom.conf  # PHP-FPM pool
```

## Monitoring & Observability

### Metrics Collection

**File-Based Service Discovery:** Prometheus uses dynamic target files in `/etc/observability/prometheus/targets/`

Example target files:
- `node_mentat.yml` - System metrics from mentat
- `node_landsraad.yml` - System metrics from landsraad
- `nginx_landsraad.yml` - Nginx metrics
- `postgresql_landsraad.yml` - PostgreSQL metrics
- `redis_landsraad.yml` - Redis metrics
- `phpfpm_landsraad.yml` - PHP-FPM metrics

**Auto-Discovery:** `deploy-exporters.sh` automatically:
1. Detects running services
2. Installs appropriate exporters
3. Creates Prometheus target files
4. Registers via SSH to mentat

### Log Aggregation

**Promtail → Loki Pipeline:**
- System logs: `/var/log/*.log`
- Nginx logs: `/var/log/nginx/*.log`
- PostgreSQL logs: `/var/log/postgresql/*.log`
- Laravel logs: `/var/www/chom/shared/storage/logs/*.log`
- PHP-FPM logs: `/var/log/php8.2-fpm.log`

**Loki Configuration:**
- Storage: `/var/lib/observability/loki/`
- Retention: 720h (30 days)
- Schema: v13 (tsdb)

### Dashboards

**Grafana:** https://mentat.arewel.com
- Default credentials: `admin` / (generated password in `/root/.observability-credentials`)
- Pre-configured datasources: Prometheus, Loki, AlertManager
- Dashboards for: nodes, nginx, PostgreSQL, Redis, PHP-FPM

## Security

### Users & Permissions

**Deployment User:** `stilgar`
- Home: `/home/stilgar`
- SSH keys: passwordless access mentat → landsraad
- Sudo: limited to deployment commands

**Application User:** `stilgar` (PHP-FPM pool owner)
- Owns: `/var/www/chom/`
- Runs: PHP-FPM workers, queue workers

**Observability User:** `observability` (system user)
- Owns: `/opt/observability/`, `/etc/observability/`, `/var/lib/observability/`
- Runs: Prometheus, Loki, Promtail, AlertManager, Grafana

### SSH Configuration

**Hardening:**
- PermitRootLogin: no
- PasswordAuthentication: no
- SSH keys only (Ed25519)

**Key Deployment:**
- Generated on mentat during Phase 2
- Distributed to landsraad automatically
- Stored in `/home/stilgar/.ssh/id_ed25519`
- **One-way trust:** mentat → landsraad only (simpler, more secure)
- No reverse SSH needed (master script retrieves data)

### Firewall Rules (UFW)

**Mentat:**
- 22/tcp - SSH
- 80/tcp - HTTP (redirects to HTTPS)
- 443/tcp - HTTPS (Grafana, Prometheus, AlertManager)
- 3000/tcp - Grafana
- 3100/tcp - Loki (for log ingestion)
- 9090/tcp - Prometheus
- 9093/tcp - AlertManager
- 9100/tcp - Node Exporter

**Landsraad:**
- 22/tcp - SSH
- 80/tcp - HTTP (redirects to HTTPS)
- 443/tcp - HTTPS (CHOM application)
- 9100-9300/tcp - Exporters (only from mentat: 51.254.139.78)

### SSL Certificates

**Let's Encrypt via Certbot:**
- Auto-renewal enabled (certbot timer)
- Certificates: `/etc/letsencrypt/live/`
- mentat: `mentat.arewel.com`
- landsraad: `chom.arewel.com`

## Application Features

### VPS Management
- Site creation (WordPress, Laravel, HTML, PHP)
- SSL certificate management
- Database management
- Backups and restores
- Resource monitoring

### Hosting Operations
- Multi-tenancy support
- Automated deployments
- Health monitoring
- Performance metrics

## Common Operations

### Deploy Application Update
```bash
# On mentat
cd ~/chom-deployment
git pull
sudo ./deploy/deploy-chom-automated.sh \
    --skip-user-setup --skip-ssh --skip-secrets \
    --skip-mentat-prep --skip-landsraad-prep --skip-observability
```

### View Logs
```bash
# Application logs
ssh stilgar@landsraad.arewel.com "tail -f /var/www/chom/current/storage/logs/laravel.log"

# Service logs
ssh stilgar@landsraad.arewel.com "sudo journalctl -u php8.2-fpm -f"

# Via Grafana: https://mentat.arewel.com → Explore → Loki
```

### Restart Services
```bash
# Landsraad
ssh stilgar@landsraad.arewel.com "sudo systemctl restart nginx php8.2-fpm"

# Mentat
sudo systemctl restart prometheus grafana-server loki
```

### Database Access
```bash
ssh stilgar@landsraad.arewel.com "sudo -u postgres psql chom"
```

### Check Service Status
```bash
# All services on landsraad
ssh stilgar@landsraad.arewel.com "systemctl status nginx postgresql redis-server php8.2-fpm"

# All exporters
ssh stilgar@landsraad.arewel.com "sudo netstat -tulpn | grep -E '9100|9113|9187|9121|9253'"
```

### Rollback Deployment
```bash
ssh stilgar@landsraad.arewel.com "cd /tmp/chom-deploy && sudo bash scripts/rollback.sh"
```

## Troubleshooting

### Loki Not Starting
**Symptom:** `mkdir /etc/loki: permission denied`

**Fix:** Already automated in deployment scripts. Loki uses `/var/lib/observability/loki/` (not `/etc/loki/`)

**Verify:**
```bash
sudo systemctl status loki
ls -la /var/lib/observability/loki/
```

### Exporters Not Running on Landsraad
**Cause:** `deploy-exporters.sh` must run after application deployment

**Verify:**
```bash
ssh stilgar@landsraad.arewel.com "sudo netstat -tulpn | grep LISTEN | grep 91"
```

**Should see:** 9100, 9113, 9121, 9187, 9253, 9115, 9080

### Prometheus Not Discovering Targets
**Check target files:**
```bash
ls -la /etc/observability/prometheus/targets/
cat /etc/observability/prometheus/targets/*landsraad*.yml
```

**Reload Prometheus:**
```bash
curl -X POST http://localhost:9090/prometheus/-/reload
```

### Application 500 Error
**Check logs:**
```bash
ssh stilgar@landsraad.arewel.com "tail -100 /var/www/chom/current/storage/logs/laravel.log"
```

**Common causes:**
- Missing .env file
- Database connection failed
- File permissions (must be owned by stilgar)

## Important Files & Locations

### Secrets
- `/opt/chom-deploy/.deployment-secrets` - Generated secrets (mentat)
- `/var/www/chom/shared/.env` - Laravel environment (landsraad)
- `/root/.observability-credentials` - Grafana password (mentat)

### Logs
- `/var/log/chom-deploy/` - Deployment logs
- `/var/www/chom/current/storage/logs/` - Laravel logs
- `/var/log/nginx/` - Web server logs
- `/var/log/postgresql/` - Database logs

### Service Configs
- `/etc/systemd/system/` - Systemd unit files
- `/etc/nginx/sites-available/` - Nginx configs
- `/etc/php/8.2/fpm/pool.d/` - PHP-FPM pools

## Development Workflow

### Local Development
1. Clone repository
2. Copy `.env.example` to `.env`
3. Configure database connection
4. Run migrations: `php artisan migrate`
5. Start dev server: `php artisan serve`

### Deployment to Production
1. Commit changes to `main` branch
2. Push to GitHub
3. Run deployment from mentat (see "Deploy Application Update" above)

### Testing
```bash
# Run tests
php artisan test

# Run specific test
php artisan test --filter=VpsServerTest
```

## Version History

**v2.0.0** (Current)
- Two-server architecture
- Native observability stack (no Docker)
- Automated exporter deployment
- File-based service discovery
- Comprehensive monitoring

**v1.x**
- Single-server setup
- Manual configuration
- Limited monitoring

## Key Contacts & Resources

- **Repository:** https://github.com/calounx/mentat
- **Production:** https://chom.arewel.com
- **Monitoring:** https://mentat.arewel.com
- **Deployment User:** stilgar
- **SSH Access:** calounx@mentat.arewel.com

## Critical Rules

1. ⚠️ **ALWAYS** run deployments from mentat server
2. ⚠️ **NEVER** create manual scripts - use `deploy-chom-automated.sh` only
3. ⚠️ **NO PLACEHOLDERS** - everything must be automated
4. ⚠️ **NO MANUAL STEPS** - deployments must be repeatable
5. ⚠️ All changes via deployment scripts, not manual edits

## Scaling to Multiple VPS Servers

### Current One-Way SSH Architecture (Recommended)

The system uses **centralized orchestration** from mentat with one-way SSH:

```
mentat (controller)
  ├─ SSH → landsraad.arewel.com
  ├─ SSH → vps3.arewel.com (future)
  ├─ SSH → vps4.arewel.com (future)
  └─ SSH → vps5.arewel.com (future)
```

### Adding a New VPS Server

**Steps (5 minutes):**

1. **Setup stilgar user on new VPS:**
   ```bash
   # On new VPS as root
   useradd -m -s /bin/bash stilgar
   mkdir -p /home/stilgar/.ssh
   chmod 700 /home/stilgar/.ssh
   ```

2. **Copy SSH key from mentat:**
   ```bash
   # On mentat
   ssh-copy-id stilgar@newvps.arewel.com
   # Or manually copy /home/stilgar/.ssh/id_ed25519.pub
   ```

3. **Add to deployment script:**
   ```bash
   # Edit deploy/deploy-chom-automated.sh
   VPS_HOSTS=("landsraad.arewel.com" "newvps.arewel.com")
   ```

4. **Run deployment - done!**
   ```bash
   sudo ./deploy/deploy-chom-automated.sh
   ```

### Why One-Way SSH Scales Better

| Factor | One-Way (Current) | Bidirectional |
|--------|-------------------|---------------|
| **SSH Relationships** | N (simple) | 2N (complex) |
| **Security** | VPS isolated from mentat | Every VPS can access mentat |
| **Attack Surface** | Compromised VPS can't access mentat | Compromised VPS = access to mentat |
| **Setup Complexity** | One key per VPS | Two keys per VPS |
| **Orchestration** | Centralized (mentat) | Distributed (complex) |
| **Audit Trail** | All from mentat | Multiple sources |

**Verdict:** ✅ Stick with one-way SSH for multi-VPS scalability

### Multi-VPS Deployment Example

See `future-multi-vps-example.sh` for implementation example.

The master script would loop through all VPS servers:
- Deploy exporters to each VPS
- Retrieve Prometheus targets from each VPS
- Register all targets on mentat
- Prometheus monitors all servers from one dashboard

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Internet (HTTPS)                         │
└────────────┬────────────────────────────────┬───────────────┘
             │                                │
             │                                │
    ┌────────▼────────┐              ┌────────▼────────┐
    │  mentat (78)    │◄─────SSH─────┤landsraad (79)   │
    │  Observability  │              │  Application    │
    ├─────────────────┤              ├─────────────────┤
    │ Prometheus      │◄──Metrics────│ Exporters       │
    │ Grafana         │              │ - node          │
    │ Loki            │◄──Logs───────│ - nginx         │
    │ AlertManager    │              │ - postgres      │
    │ Node Exporter   │              │ - redis         │
    │                 │              │ - php-fpm       │
    │                 │              │ - promtail      │
    │                 │              │                 │
    │                 │              │ Nginx           │
    │                 │              │ PHP 8.2-FPM     │
    │                 │              │ PostgreSQL 15   │
    │                 │              │ Redis 7         │
    │                 │              │ Laravel 11      │
    └─────────────────┘              └─────────────────┘
```

---

**Last Updated:** 2026-01-05
**Version:** 2.0.0
**Maintained By:** Deployment automation (no manual changes)
