# CHOM Automated Deployment Guide

Complete, idempotent, fully-automated deployment system for CHOM from scratch to production.

## Overview

This deployment automation provides a **zero-touch, one-command deployment** that:

- Creates deployment users automatically on both servers
- Generates and distributes SSH keys for passwordless access
- Auto-generates secure credentials and secrets
- Installs and configures all required software
- Deploys application with zero downtime
- Sets up complete observability stack
- Verifies everything is working

**Key Features:**
- Fully idempotent - safe to run multiple times
- Minimal user interaction - only essential prompts
- Auto-recovery on failures
- Comprehensive logging and verification
- Production-ready security defaults

## Architecture

```
mentat.arewel.com (Observability Server)
├── Prometheus (metrics)
├── Grafana (dashboards)
├── Loki (logs)
├── AlertManager (alerts)
└── Node Exporter (system metrics)

landsraad.arewel.com (Application Server)
├── CHOM Laravel Application
├── PostgreSQL 15 (database)
├── Redis (cache/sessions/queues)
├── Nginx (web server)
├── PHP 8.2-FPM
└── Node Exporter (system metrics)
```

## Prerequisites

### Required Access

1. **SSH access to both servers:**
   - mentat.arewel.com (run deployment from here)
   - landsraad.arewel.com

2. **Root or sudo access** on both servers

3. **Internet connectivity** on both servers for package installation

### Minimum System Requirements

**mentat.arewel.com:**
- 2 CPU cores
- 4GB RAM
- 20GB disk space
- Debian 13 (Trixie) or compatible

**landsraad.arewel.com:**
- 2 CPU cores
- 4GB RAM
- 30GB disk space
- Debian 13 (Trixie) or compatible

## Quick Start (Recommended)

### Step 1: Clone Repository

```bash
# On mentat.arewel.com as root or sudo user
cd /opt
git clone <your-repo-url> chom-deploy
cd chom-deploy/deploy
```

### Step 2: Run Automated Deployment

```bash
# Full automated deployment (recommended for first-time)
sudo ./deploy-chom-automated.sh
```

That's it! The script will:
1. Create stilgar user on both servers
2. Generate SSH keys and distribute them
3. Auto-generate deployment secrets
4. Prepare both servers
5. Deploy application
6. Deploy observability stack
7. Verify everything

**Deployment time:** 15-30 minutes depending on internet speed

### Step 3: Access Your Services

After successful deployment:

- **Application:** https://chom.arewel.com
- **Grafana:** http://mentat.arewel.com:3000
- **Prometheus:** http://mentat.arewel.com:9090

## Detailed Deployment Guide

### Interactive Mode (Recommended for First Time)

If you want to customize settings during deployment:

```bash
sudo ./deploy-chom-automated.sh --interactive
```

You'll be prompted for:
- Domain name
- Email address (for SSL certificates)
- Email service credentials (optional)
- VPS provider API keys (optional)

### Advanced Options

```bash
# Skip specific phases (useful for re-deployment)
sudo ./deploy-chom-automated.sh \
  --skip-user-setup \
  --skip-ssh \
  --skip-secrets \
  --skip-mentat-prep \
  --skip-landsraad-prep

# Dry run (show what would be done)
sudo ./deploy-chom-automated.sh --dry-run

# See all options
sudo ./deploy-chom-automated.sh --help
```

## Component Scripts

The automated deployment orchestrates these individual scripts:

### 1. setup-stilgar-user.sh

Creates the deployment user with sudo access.

```bash
# Create user on local server
./scripts/setup-stilgar-user.sh

# Create user on remote server
./scripts/setup-stilgar-user.sh --remote-host landsraad.arewel.com
```

**What it does:**
- Creates 'stilgar' user if doesn't exist
- Adds to sudo group with NOPASSWD
- Sets up .ssh directory with proper permissions
- Configures bash profile with deployment aliases

**Idempotent:** Safe to run multiple times - skips if already configured.

### 2. setup-ssh-automation.sh

Generates SSH keys and enables passwordless access between servers.

```bash
./scripts/setup-ssh-automation.sh \
  --from mentat.arewel.com \
  --to landsraad.arewel.com
```

**What it does:**
- Generates ed25519 SSH key pair
- Copies public key to destination server
- Configures SSH client settings
- Tests passwordless connection

**Idempotent:** Skips if keys already exist and are configured.

### 3. generate-deployment-secrets.sh

Auto-generates secure credentials and deployment configuration.

```bash
# Automated mode (uses defaults)
./scripts/generate-deployment-secrets.sh

# Interactive mode (prompts for values)
./scripts/generate-deployment-secrets.sh --interactive

# Force regenerate (overwrites existing)
./scripts/generate-deployment-secrets.sh --force
```

**What it generates:**
- Laravel APP_KEY
- Database passwords (PostgreSQL)
- Redis password
- Backup encryption keys
- JWT secrets

**Output:** `/opt/chom-deploy/deploy/.deployment-secrets`

**Security:** File is created with 600 permissions (owner read/write only)

### 4. prepare-mentat.sh

Prepares observability server with monitoring stack.

```bash
./scripts/prepare-mentat.sh
```

**Installs:**
- Prometheus 2.48.0
- Grafana (latest from APT)
- Loki 2.9.3
- Promtail 2.9.3
- AlertManager 0.26.0
- Node Exporter 1.7.0

**All installed natively** (no Docker) using systemd services.

**Idempotent:** Checks versions before installing, skips if up-to-date.

### 5. prepare-landsraad.sh

Prepares application server with full LAMP stack.

```bash
./scripts/prepare-landsraad.sh
```

**Installs:**
- PHP 8.2 + FPM (with all required extensions)
- PostgreSQL 15
- Redis
- Nginx
- Node.js 20
- Composer
- Supervisor (for queue workers)

**Idempotent:** Checks if software already installed before proceeding.

### 6. deploy-application.sh

Deploys CHOM application with zero-downtime blue-green deployment.

```bash
# From landsraad server
REPO_URL="git@github.com:user/chom.git" \
./scripts/deploy-application.sh --branch main
```

**Features:**
- Zero-downtime atomic symlink swap
- Automatic backup before deployment
- Database migrations with safety checks
- Asset compilation (CSS/JS)
- Health checks before and after
- Automatic rollback on failure
- Keeps last 5 releases

**Idempotent:** Each deployment creates a new release, safe to re-run.

## Deployment Secrets

The `.deployment-secrets` file contains all sensitive configuration:

### File Location
```
/opt/chom-deploy/deploy/.deployment-secrets
```

### File Structure

```bash
# Server Configuration
MENTAT_HOST="mentat.arewel.com"
LANDSRAAD_HOST="landsraad.arewel.com"
DEPLOY_USER="stilgar"

# Application
APP_NAME="CHOM"
APP_ENV="production"
APP_DOMAIN="chom.arewel.com"
APP_KEY="base64:..."  # Auto-generated

# Database
DB_NAME="chom"
DB_USER="chom"
DB_PASSWORD="..."  # Auto-generated

# Redis
REDIS_PASSWORD="..."  # Auto-generated

# Email (configure as needed)
MAIL_MAILER="smtp"
MAIL_HOST="smtp.example.com"
# ... etc

# VPS Provider (optional)
OVH_APP_KEY=""
OVH_APP_SECRET=""
# ... etc
```

### Using Secrets

```bash
# Load secrets
source /opt/chom-deploy/deploy/.deployment-secrets

# Use in deployment
source .deployment-secrets && ./deploy-chom-automated.sh
```

### Security Best Practices

1. **Never commit to git:**
   ```bash
   # Already in .gitignore
   echo ".deployment-secrets" >> .gitignore
   ```

2. **Secure permissions:**
   ```bash
   chmod 600 .deployment-secrets
   ```

3. **Backup securely:**
   ```bash
   # Encrypt backup
   gpg -c .deployment-secrets
   # Store .deployment-secrets.gpg in secure location
   ```

## Manual Deployment Steps

If you prefer step-by-step manual deployment:

### Step 1: Create Deployment User

```bash
# On mentat
sudo ./scripts/setup-stilgar-user.sh

# On landsraad (from mentat)
ssh root@landsraad.arewel.com "bash -s" < ./scripts/setup-stilgar-user.sh
```

### Step 2: Setup SSH Keys

```bash
# Generate keys and enable passwordless SSH
sudo -u stilgar ssh-keygen -t ed25519 -f /home/stilgar/.ssh/id_ed25519 -N ''
sudo -u stilgar ssh-copy-id stilgar@landsraad.arewel.com

# Test
sudo -u stilgar ssh stilgar@landsraad.arewel.com 'echo SSH OK'
```

### Step 3: Generate Secrets

```bash
./scripts/generate-deployment-secrets.sh --interactive
source .deployment-secrets
```

### Step 4: Prepare Servers

```bash
# Prepare mentat (observability)
sudo -u stilgar ./scripts/prepare-mentat.sh

# Prepare landsraad (application)
sudo -u stilgar ssh stilgar@landsraad.arewel.com 'bash -s' < ./scripts/prepare-landsraad.sh
```

### Step 5: Configure Firewall

```bash
# On mentat
sudo ./scripts/setup-firewall.sh --server mentat

# On landsraad
sudo ./scripts/setup-firewall.sh --server landsraad
```

### Step 6: Setup SSL

```bash
# On landsraad
sudo ./scripts/setup-ssl.sh \
  --domain chom.arewel.com \
  --email admin@arewel.com
```

### Step 7: Deploy Application

```bash
# Create .env file first
sudo -u stilgar ssh stilgar@landsraad.arewel.com "
  mkdir -p /var/www/chom/shared
  cat > /var/www/chom/shared/.env <<'EOF'
APP_NAME=CHOM
APP_ENV=production
APP_KEY=${APP_KEY}
DB_HOST=127.0.0.1
DB_DATABASE=chom
DB_USERNAME=chom
DB_PASSWORD=${DB_PASSWORD}
# ... etc
EOF
"

# Deploy
sudo -u stilgar ssh stilgar@landsraad.arewel.com \
  "REPO_URL='${REPO_URL}' /tmp/deploy-application.sh"
```

### Step 8: Start Observability Stack

```bash
# On mentat
sudo systemctl start prometheus grafana-server loki promtail alertmanager node_exporter
```

## Verification

### Check Service Status

**On mentat:**
```bash
systemctl status prometheus grafana-server loki promtail alertmanager node_exporter
```

**On landsraad:**
```bash
systemctl status nginx postgresql redis-server php8.2-fpm supervisor
```

### Test HTTP Endpoints

```bash
# Prometheus
curl http://mentat.arewel.com:9090/-/healthy

# Grafana
curl http://mentat.arewel.com:3000/api/health

# Application
curl https://chom.arewel.com
```

### Check Logs

```bash
# Deployment logs
tail -f /var/log/chom-deploy/deployment.log

# Application logs
tail -f /var/www/chom/shared/storage/logs/laravel.log

# System logs
journalctl -u nginx -f
journalctl -u php8.2-fpm -f
```

## Troubleshooting

### Common Issues

#### 1. SSH Connection Failed

**Problem:** Cannot connect to landsraad

**Solution:**
```bash
# Check SSH key
ls -la /home/stilgar/.ssh/

# Test connection
ssh -v stilgar@landsraad.arewel.com

# Copy key manually if needed
ssh-copy-id stilgar@landsraad.arewel.com
```

#### 2. Service Won't Start

**Problem:** Service fails to start after installation

**Solution:**
```bash
# Check service status
systemctl status <service-name>

# View logs
journalctl -u <service-name> -n 50

# Check configuration
systemctl cat <service-name>

# Restart service
systemctl restart <service-name>
```

#### 3. Permission Denied Errors

**Problem:** Scripts fail with permission errors

**Solution:**
```bash
# Make scripts executable
chmod +x deploy/*.sh
chmod +x deploy/scripts/*.sh

# Run with sudo
sudo ./deploy-chom-automated.sh

# Check file ownership
ls -la /var/www/chom
sudo chown -R stilgar:www-data /var/www/chom
```

#### 4. Database Connection Failed

**Problem:** Application cannot connect to database

**Solution:**
```bash
# Check PostgreSQL is running
systemctl status postgresql

# Test connection
sudo -u postgres psql -l

# Verify credentials
cat /var/www/chom/shared/.env | grep DB_

# Check PostgreSQL logs
tail -f /var/log/postgresql/postgresql-15-main.log
```

#### 5. Secrets File Not Found

**Problem:** .deployment-secrets missing

**Solution:**
```bash
# Regenerate secrets
./scripts/generate-deployment-secrets.sh --interactive

# Or copy from template
cp .deployment-secrets.template .deployment-secrets
# Edit manually
vim .deployment-secrets
chmod 600 .deployment-secrets
```

### Getting Help

**Check deployment logs:**
```bash
ls -lh /var/log/chom-deploy/
tail -100 /var/log/chom-deploy/deployment-*.log
```

**Run with verbose logging:**
```bash
export DEBUG=1
./deploy-chom-automated.sh
```

**Dry run to see what would happen:**
```bash
./deploy-chom-automated.sh --dry-run
```

## Rollback Procedure

If deployment fails, automatic rollback is triggered. Manual rollback:

```bash
# On landsraad
cd /var/www/chom
./scripts/rollback.sh

# Or specify release
./scripts/rollback.sh --release 20240115_143022
```

## Post-Deployment Configuration

### 1. Configure SSL/TLS

```bash
# Generate Let's Encrypt certificate
sudo certbot --nginx -d chom.arewel.com -d www.chom.arewel.com

# Auto-renewal
sudo systemctl enable certbot.timer
```

### 2. Configure Firewall

```bash
# Allow only necessary ports
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow https
sudo ufw enable
```

### 3. Setup Grafana

```bash
# Access Grafana
# URL: http://mentat.arewel.com:3000
# Default: admin / (check /etc/grafana/grafana.ini)

# Change admin password
grafana-cli admin reset-admin-password <new-password>
```

### 4. Configure Backups

```bash
# Setup automated backups
sudo crontab -e
# Add:
0 2 * * * /opt/chom-deploy/deploy/scripts/backup-database.sh
0 3 * * * /opt/chom-deploy/deploy/scripts/backup-files.sh
```

### 5. Setup Monitoring Alerts

Edit `/etc/observability/prometheus/rules/alerts.yml`:

```yaml
groups:
  - name: chom_alerts
    interval: 30s
    rules:
      - alert: HighCPUUsage
        expr: node_cpu_seconds_total > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
```

## Maintenance

### Update Application

```bash
# Deploy new version
source .deployment-secrets
sudo -u stilgar ssh stilgar@landsraad.arewel.com \
  "REPO_URL='${REPO_URL}' /tmp/deploy-application.sh --branch main"
```

### Update System Packages

```bash
# On both servers
sudo apt update
sudo apt upgrade -y
sudo reboot
```

### Clean Old Releases

```bash
# On landsraad
cd /var/www/chom
# Keeps last 5 releases by default
ls -dt releases/* | tail -n +6 | xargs rm -rf
```

### Rotate Logs

Logs are automatically rotated by logrotate. Manual rotation:

```bash
sudo logrotate -f /etc/logrotate.d/chom
```

## Security Checklist

After deployment, verify:

- [ ] SSH password authentication disabled
- [ ] Root SSH login disabled
- [ ] Firewall configured and enabled
- [ ] SSL/TLS certificates installed
- [ ] Database passwords are strong and unique
- [ ] .deployment-secrets has 600 permissions
- [ ] Fail2ban is configured and running
- [ ] Automatic security updates enabled
- [ ] Backups are working and tested
- [ ] Monitoring alerts are configured

## File Structure

```
deploy/
├── deploy-chom-automated.sh       # Master orchestration script
├── .deployment-secrets            # Generated secrets (DO NOT COMMIT)
├── .deployment-secrets.template   # Template for secrets
├── scripts/
│   ├── setup-stilgar-user.sh     # Create deployment user
│   ├── setup-ssh-automation.sh   # SSH key management
│   ├── generate-deployment-secrets.sh  # Secrets generator
│   ├── prepare-mentat.sh         # Observability server setup
│   ├── prepare-landsraad.sh      # Application server setup
│   ├── deploy-application.sh     # Application deployment
│   ├── deploy-observability.sh   # Observability deployment
│   ├── rollback.sh               # Rollback script
│   ├── health-check.sh           # Health verification
│   └── backup-before-deploy.sh   # Pre-deployment backup
├── utils/
│   ├── logging.sh                # Logging utilities
│   ├── colors.sh                 # Terminal colors
│   └── notifications.sh          # Deployment notifications
└── AUTOMATED-DEPLOYMENT.md       # This file
```

## Environment Variables

### Required
- `REPO_URL` - Git repository URL
- `APP_DOMAIN` - Application domain name

### Optional
- `DEPLOY_USER` - Deployment user (default: stilgar)
- `APP_ENV` - Environment (default: production)
- `KEEP_RELEASES` - Number of releases to keep (default: 5)
- `SKIP_BACKUP` - Skip pre-deployment backup
- `SKIP_MIGRATIONS` - Skip database migrations

## Support and Documentation

- **Deployment logs:** `/var/log/chom-deploy/`
- **Application logs:** `/var/www/chom/shared/storage/logs/`
- **Service logs:** `journalctl -u <service-name>`

## Summary

This automated deployment system provides:

1. **Idempotency** - Run multiple times safely
2. **Automation** - Minimal manual intervention
3. **Security** - Best practices by default
4. **Observability** - Full monitoring stack
5. **Reliability** - Automatic rollback on failure
6. **Verification** - Health checks throughout
7. **Documentation** - Comprehensive logging

**Time to Production:** ~20 minutes from fresh servers to fully deployed application with monitoring.

---

Last updated: 2026-01-03
Version: 1.0.0
