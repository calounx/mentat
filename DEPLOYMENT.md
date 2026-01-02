# CHOM/Mentat Deployment Guide

A comprehensive guide for deploying the CHOM VPS Management platform and its observability infrastructure.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Component Deployment](#component-deployment)
   - [Observability Stack (mentat)](#1-observability-stack-deployment)
   - [CHOM Application (landsraad)](#2-chom-application-deployment)
   - [Docker Test Environment](#3-docker-test-environment)
5. [Configuration Reference](#configuration-reference)
6. [Environment Variables](#environment-variables)
7. [Security Considerations](#security-considerations)
8. [Post-Deployment Verification](#post-deployment-verification)
9. [Troubleshooting](#troubleshooting)

---

## Overview

The CHOM/Mentat platform consists of three main components:

| Component | Directory | Purpose | Default VPS |
|-----------|-----------|---------|-------------|
| **Observability Stack** | `observability-stack/` | Prometheus, Grafana, Loki, Tempo, Alertmanager | mentat (10.10.100.10) |
| **CHOM Application** | `chom/` | Laravel VPS management platform | landsraad (10.10.100.20) |
| **Docker Test Environment** | `docker/` | 3-VPS simulation for testing | Local development |

### Architecture

```
                                    Internet
                                        |
        +-------------------------------+-------------------------------+
        |                               |                               |
+-------v-------+            +----------v---------+          +----------v----------+
|   mentat_tst  |            |   landsraad_tst    |          |    richese_tst      |
| Observability |<---------->|   CHOM/VPSManager  |          |    Hosting Node     |
|  10.10.100.10 |   metrics  |    10.10.100.20    |          |    10.10.100.30     |
+---------------+   + logs   +--------------------+          +---------------------+
| - Prometheus  |            | - Nginx            |          | - Nginx             |
| - Grafana     |            | - PHP-FPM 8.4      |          | - PHP-FPM           |
| - Loki        |            | - MariaDB          |          | - MariaDB           |
| - Tempo       |            | - Redis            |          | - Redis             |
| - Alertmanager|            | - Laravel/CHOM     |          | - Customer Sites    |
| - Alloy       |            | - Promtail/Exporters|         | - Promtail/Exporters|
+---------------+            +--------------------+          +---------------------+
```

---

## Prerequisites

### Operating System

| Requirement | Specification |
|-------------|---------------|
| OS | Debian 13 (Trixie) or Ubuntu 22.04+ |
| Architecture | x86_64 (amd64) or ARM64 |
| Kernel | 5.x or newer |

### Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **Observability VPS** | 2 vCPU, 2GB RAM, 40GB disk | 4 vCPU, 4GB RAM, 100GB disk |
| **CHOM VPS** | 2 vCPU, 2GB RAM, 20GB disk | 4 vCPU, 4GB RAM, 50GB disk |
| **Hosting Node** | 2 vCPU, 2GB RAM, 20GB disk | Scales with sites |

### Software Requirements

**For Production Deployment:**
```bash
# Required packages (installed automatically by deployment scripts)
apt-get install -y \
    curl wget gnupg lsb-release ca-certificates \
    git build-essential \
    openssh-server \
    iproute2 iputils-ping dnsutils
```

**For CHOM Development:**
- PHP 8.2+ with extensions: mbstring, xml, curl, zip, bcmath, gd, intl, redis
- Composer 2.x
- Node.js 18+ and npm
- SQLite, MySQL 8.x, or PostgreSQL 15+

**For Docker Test Environment:**
- Docker Engine 24+
- Docker Compose v2+
- 8GB RAM minimum (for all 3 containers)

### Network Requirements

| Port | Service | Direction | Notes |
|------|---------|-----------|-------|
| 22 | SSH | Inbound | Required for deployment |
| 80 | HTTP | Inbound | Web traffic |
| 443 | HTTPS | Inbound | Secure web traffic |
| 3000 | Grafana | Internal | Dashboards |
| 3100 | Loki | Internal | Log ingestion |
| 3200 | Tempo | Internal | Trace queries |
| 4317/4318 | OTLP | Internal | Trace ingestion |
| 9090 | Prometheus | Internal | Metrics API |
| 9093 | Alertmanager | Internal | Alert routing |
| 9100 | Node Exporter | Internal | System metrics |
| 9104 | MySQL Exporter | Internal | Database metrics |
| 9113 | Nginx Exporter | Internal | Web server metrics |
| 9253 | PHP-FPM Exporter | Internal | PHP metrics |

---

## Quick Start

### Option 1: Docker Test Environment (Recommended for First-Time Setup)

```bash
# Clone the repository
git clone https://github.com/calounx/mentat.git
cd mentat

# Start the 3-VPS test environment
cd docker
./scripts/test-env.sh up

# Deploy all components
./scripts/test-env.sh deploy

# Verify deployment
./scripts/test-env.sh status
./scripts/test-env.sh test
```

**Access Points After Deployment:**
- Grafana: http://localhost:3000 (admin/admin)
- Prometheus: http://localhost:9090
- CHOM Web App: http://localhost:8000
- Hosting Node: http://localhost:8010

### Option 2: Production Deployment (Fresh VPS)

**On your Observability VPS (mentat):**
```bash
curl -sSL https://raw.githubusercontent.com/calounx/mentat/master/observability-stack/deploy/bootstrap.sh | sudo bash
```

**On your CHOM VPS (landsraad):**
```bash
# After cloning the repo
cd mentat/observability-stack
sudo ./deploy/install.sh --role vpsmanager
```

---

## Component Deployment

### 1. Observability Stack Deployment

The observability stack provides centralized monitoring for all VPS nodes.

#### Interactive Installation (Recommended)

```bash
# On a fresh Debian 13 VPS
curl -sSL https://raw.githubusercontent.com/calounx/mentat/master/observability-stack/deploy/bootstrap.sh | sudo bash
```

The installer will prompt for:
- Role selection (observability/vpsmanager/monitored)
- IPv6 configuration
- Grafana admin password
- SSL/domain configuration (optional)
- SMTP settings for alerts (optional)

#### Manual Installation

```bash
# Clone repository
git clone https://github.com/calounx/mentat.git
cd mentat/observability-stack

# Install CLI tools
sudo ./install.sh

# Configure global settings
cp config/global.yaml.example config/global.yaml
nano config/global.yaml

# Run setup (interactive)
sudo ./scripts/setup-observability.sh

# Or use the deployment installer
sudo ./deploy/install.sh
```

#### Configuration Files

| File | Purpose |
|------|---------|
| `config/global.yaml` | Global stack settings |
| `config/versions.yaml` | Component version pinning |
| `config/hosts/*.yaml` | Per-host configuration |
| `prometheus/alerts/*.yaml` | Alert rule definitions |
| `grafana/dashboards/library/` | Pre-built dashboards |

#### Environment Variables (Observability)

```bash
# Core Settings
OBSERVABILITY_IP="10.10.100.10"     # This server's IP
GRAFANA_PASSWORD="admin"             # Grafana admin password
DISABLE_IPV6="true"                  # Disable IPv6 if not needed

# Retention Settings
METRICS_RETENTION_DAYS="7"           # Prometheus data retention
LOGS_RETENTION_DAYS="7"              # Loki data retention

# Monitored Hosts
VPSMANAGER_HOST_IP="10.10.100.20"   # CHOM server IP
VPSMANAGER_HOST_NAME="landsraad_tst"
HOSTING_NODE_1_IP="10.10.100.30"    # Additional hosting nodes
HOSTING_NODE_1_NAME="richese_tst"

# Optional: SSL Configuration
USE_SSL="false"                      # Enable HTTPS
GRAFANA_DOMAIN=""                    # Domain for SSL cert
LETSENCRYPT_EMAIL=""                 # Email for Let's Encrypt

# Optional: Alloy (OTEL Collector)
INSTALL_ALLOY="true"
ALLOY_VERSION="1.5.1"
```

#### Installed Services

After deployment, these services will be running:

| Service | Port | Status Check |
|---------|------|--------------|
| prometheus | 9090 | `curl -s http://localhost:9090/-/healthy` |
| grafana-server | 3000 | `curl -s http://localhost:3000/api/health` |
| loki | 3100 | `curl -s http://localhost:3100/ready` |
| tempo | 3200 | `curl -s http://localhost:3200/ready` |
| alertmanager | 9093 | `curl -s http://localhost:9093/-/healthy` |
| node_exporter | 9100 | `curl -s http://localhost:9100/metrics` |
| alloy | 12345 | `curl -s http://localhost:12345/-/ready` |

---

### 2. CHOM Application Deployment

CHOM is a Laravel application for managing VPS hosting infrastructure.

#### Prerequisites

Ensure the observability stack is deployed first so CHOM can connect to it.

#### Interactive Installation

```bash
# On landsraad VPS, clone and run installer
git clone https://github.com/calounx/mentat.git
cd mentat/observability-stack

# Run vpsmanager role installation
sudo ./deploy/install.sh --role vpsmanager
```

#### Manual Installation

```bash
# Install LEMP stack dependencies
apt-get update
apt-get install -y nginx mariadb-server redis-server \
    php8.4-fpm php8.4-cli php8.4-mysql php8.4-redis \
    php8.4-mbstring php8.4-xml php8.4-curl php8.4-zip \
    php8.4-bcmath php8.4-gd php8.4-intl

# Clone application
cd /var/www
git clone https://github.com/calounx/mentat.git
ln -s mentat/chom /var/www/vpsmanager

# Configure application
cd /var/www/vpsmanager
cp .env.example .env
php artisan key:generate

# Install dependencies
composer install --no-dev --optimize-autoloader
npm ci && npm run build

# Setup database
php artisan migrate

# Set permissions
chown -R www-data:www-data storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

# Configure Nginx (see Configuration section)
```

#### Configuration Files

| File | Purpose |
|------|---------|
| `.env` | Application environment configuration |
| `.env.production.example` | Production configuration template |
| `config/database.php` | Database connections |
| `config/cache.php` | Cache configuration |
| `config/session.php` | Session management |

#### Environment Variables (CHOM)

Copy from `.env.example` and configure:

```bash
# Application
APP_NAME="CHOM"
APP_ENV=production
APP_DEBUG=false
APP_URL=https://your-domain.com

# Database (MariaDB/MySQL)
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=chom
DB_USERNAME=chom
DB_PASSWORD=your-secure-password

# Cache & Sessions
CACHE_STORE=redis
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis

# Redis
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

# Observability Integration (connect to mentat)
OBSERVABILITY_ENABLED=true
PROMETHEUS_ENABLED=true
PROMETHEUS_URL=http://10.10.100.10:9090
LOKI_ENABLED=true
LOKI_URL=http://10.10.100.10:3100
TEMPO_ENABLED=true
TEMPO_ENDPOINT=http://10.10.100.10:4318
GRAFANA_ENABLED=true
GRAFANA_URL=http://10.10.100.10:3000

# Security
SESSION_SECURE_COOKIE=true
SESSION_SAME_SITE=strict
AUTH_2FA_ENABLED=true
AUTH_2FA_REQUIRED_ROLES=owner,admin

# Stripe (Optional)
STRIPE_KEY=pk_live_xxxxx
STRIPE_SECRET=sk_live_xxxxx
STRIPE_WEBHOOK_SECRET=whsec_xxxxx
```

#### Nginx Configuration

```nginx
# /etc/nginx/sites-available/vpsmanager
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/vpsmanager/public;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    index index.php index.html;
    charset utf-8;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

    # PHP-FPM status for monitoring (localhost only)
    location ~ ^/(fpm-status|fpm-ping)$ {
        access_log off;
        allow 127.0.0.1;
        deny all;
        fastcgi_pass unix:/var/run/php/php8.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}

# Nginx stub_status for monitoring
server {
    listen 127.0.0.1:8080;
    server_name localhost;

    location /stub_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
```

#### Installed Services (CHOM VPS)

| Service | Port | Status Check |
|---------|------|--------------|
| nginx | 80/443 | `systemctl status nginx` |
| php8.4-fpm | socket | `systemctl status php8.4-fpm` |
| mariadb | 3306 | `systemctl status mariadb` |
| redis-server | 6379 | `redis-cli ping` |
| node_exporter | 9100 | `curl -s http://localhost:9100/metrics` |
| nginx_exporter | 9113 | `curl -s http://localhost:9113/metrics` |
| mysqld_exporter | 9104 | `curl -s http://localhost:9104/metrics` |
| phpfpm_exporter | 9253 | `curl -s http://localhost:9253/metrics` |
| promtail | 9080 | Shipping logs to Loki |

---

### 3. Docker Test Environment

The Docker test environment simulates a 3-VPS infrastructure for testing deployment scripts and application changes.

#### Starting the Environment

```bash
cd docker

# Start all VPS containers
./scripts/test-env.sh up

# View container status
./scripts/test-env.sh status

# Deploy observability stack to mentat_tst
./scripts/test-env.sh deploy observability

# Deploy VPSManager to landsraad_tst
./scripts/test-env.sh deploy vpsmanager

# Deploy all components
./scripts/test-env.sh deploy all
```

#### Container Details

| Container | Role | IP Address | SSH Port | Web Port |
|-----------|------|------------|----------|----------|
| mentat_tst | Observability | 10.10.100.10 | 2210 | 3000 (Grafana), 9090 (Prometheus) |
| landsraad_tst | VPSManager/CHOM | 10.10.100.20 | 2220 | 8000 |
| richese_tst | Hosting Node | 10.10.100.30 | 2230 | 8010 |

#### Test Environment Commands

```bash
# Start containers
./scripts/test-env.sh up

# Stop containers (preserves data)
./scripts/test-env.sh down

# Reset to clean state (deletes all data)
./scripts/test-env.sh reset

# Run deployment scripts
./scripts/test-env.sh deploy [all|observability|vpsmanager]

# Check service status
./scripts/test-env.sh status

# View container logs
./scripts/test-env.sh logs [mentat_tst|landsraad_tst|richese_tst]

# Open shell in container
./scripts/test-env.sh shell [mentat_tst|landsraad_tst|richese_tst]

# Run regression tests
./scripts/test-env.sh test
```

#### Docker Compose Structure

```yaml
# docker/docker-compose.vps.yml (simplified)
services:
  mentat_tst:
    # Observability VPS
    build: ./vps-base
    networks:
      vps-network:
        ipv4_address: 10.10.100.10
    ports:
      - "2210:22"     # SSH
      - "9090:9090"   # Prometheus
      - "3000:3000"   # Grafana
      - "3100:3100"   # Loki
      - "3200:3200"   # Tempo
      - "9093:9093"   # Alertmanager
    environment:
      - DEPLOYMENT_ROLE=observability
      - HOST_IP=10.10.100.10

  landsraad_tst:
    # VPSManager/CHOM VPS
    build: ./vps-base
    networks:
      vps-network:
        ipv4_address: 10.10.100.20
    ports:
      - "2220:22"     # SSH
      - "8000:80"     # HTTP
      - "8443:443"    # HTTPS
      - "3316:3306"   # MySQL
    environment:
      - DEPLOYMENT_ROLE=vpsmanager
      - HOST_IP=10.10.100.20
      - OBSERVABILITY_IP=10.10.100.10
      - DB_DATABASE=chom
      - DB_USERNAME=chom
      - DB_PASSWORD=secret

  richese_tst:
    # Hosting Node
    build: ./vps-base
    networks:
      vps-network:
        ipv4_address: 10.10.100.30
    ports:
      - "2230:22"     # SSH
      - "8010:80"     # HTTP
      - "8453:443"    # HTTPS
    environment:
      - DEPLOYMENT_ROLE=hosting
      - HOST_IP=10.10.100.30
      - OBSERVABILITY_IP=10.10.100.10
```

---

## Configuration Reference

### Host Configuration Files

Host-specific configuration is stored in `observability-stack/config/hosts/*.yaml`:

```yaml
# Example: observability-stack/config/hosts/landsraad_tst.yaml
host:
  name: "landsraad_tst"
  ip: "10.10.100.20"
  description: "CHOM VPS Manager"
  environment: "production"
  role: "monitored"
  os:
    distribution: "debian"
    version: "13"
  labels:
    tier: "application"
    team: "chom"

observability_server:
  ip: "10.10.100.10"
  name: "mentat_tst"

modules:
  node_exporter:
    enabled: true
    thresholds:
      cpu_usage_warning: 80
      cpu_usage_critical: 95
      memory_usage_warning: 80

  nginx_exporter:
    enabled: true

  phpfpm_exporter:
    enabled: true

  mysqld_exporter:
    enabled: true
    config:
      credentials:
        username: "exporter"
        password: "{{ secret:mysql_exporter_password }}"

  promtail:
    enabled: true
    config:
      loki_url: "http://10.10.100.10:3100"
      additional_scrape_configs:
        - job_name: "nginx_access"
          path: "/var/log/nginx/*access*.log"
        - job_name: "nginx_error"
          path: "/var/log/nginx/*error*.log"
        - job_name: "php_fpm"
          path: "/var/log/php*-fpm*.log"
```

### Prometheus Scrape Configuration

Prometheus automatically discovers targets via file-based service discovery:

```yaml
# /etc/prometheus/targets/vpsmanager-node.yaml
- targets:
    - "10.10.100.20:9100"
  labels:
    host: "landsraad_tst"
    env: "production"
    role: "vps"
    app: "vpsmanager"
```

---

## Environment Variables

### Complete Reference

#### Application Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_NAME` | CHOM | Application name |
| `APP_ENV` | local | Environment: local, staging, production |
| `APP_KEY` | (generated) | Application encryption key |
| `APP_DEBUG` | true | Debug mode (set false in production) |
| `APP_URL` | http://localhost:8000 | Application URL |

#### Database

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_CONNECTION` | sqlite | Database driver: sqlite, mysql, pgsql |
| `DB_HOST` | 127.0.0.1 | Database host |
| `DB_PORT` | 3306 | Database port |
| `DB_DATABASE` | chom | Database name |
| `DB_USERNAME` | chom | Database user |
| `DB_PASSWORD` | - | Database password |

#### Redis

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_HOST` | 127.0.0.1 | Redis host |
| `REDIS_PASSWORD` | null | Redis password |
| `REDIS_PORT` | 6379 | Redis port |
| `REDIS_DB` | 0 | Default database |
| `REDIS_CACHE_DB` | 1 | Cache database |
| `REDIS_QUEUE_DB` | 2 | Queue database |
| `REDIS_SESSION_DB` | 3 | Session database |

#### Observability Integration

| Variable | Default | Description |
|----------|---------|-------------|
| `OBSERVABILITY_ENABLED` | false | Master switch for observability |
| `PROMETHEUS_ENABLED` | false | Enable Prometheus integration |
| `PROMETHEUS_URL` | http://localhost:9090 | Prometheus API URL |
| `PROMETHEUS_NAMESPACE` | chom | Metric namespace prefix |
| `LOKI_ENABLED` | false | Enable Loki integration |
| `LOKI_URL` | http://localhost:3100 | Loki API URL |
| `TEMPO_ENABLED` | false | Enable distributed tracing |
| `TEMPO_ENDPOINT` | http://localhost:4318 | Tempo OTLP endpoint |
| `GRAFANA_ENABLED` | false | Enable Grafana integration |
| `GRAFANA_URL` | http://localhost:3000 | Grafana URL |
| `GRAFANA_API_KEY` | - | Grafana API key for dashboards |

#### Security Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `SESSION_SECURE_COOKIE` | true | Require HTTPS for cookies |
| `SESSION_SAME_SITE` | strict | Cookie SameSite policy |
| `AUTH_2FA_ENABLED` | true | Enable two-factor auth |
| `AUTH_2FA_REQUIRED_ROLES` | owner,admin | Roles requiring 2FA |
| `BCRYPT_ROUNDS` | 12 | Password hashing rounds |

---

## Security Considerations

### Secrets Management

**Credentials Location:**
```bash
# Database and Redis credentials
/root/.credentials/mysql
/root/.credentials/redis

# Observability secrets
/etc/observability/secrets/
```

**File Permissions:**
```bash
chmod 700 /root/.credentials
chmod 600 /root/.credentials/*
chmod 750 /etc/observability/secrets
chmod 600 /etc/observability/secrets/*
```

### SSL/TLS Configuration

**For Production with Let's Encrypt:**
```bash
# During deployment, set:
USE_SSL=true
GRAFANA_DOMAIN=grafana.yourdomain.com
LETSENCRYPT_EMAIL=admin@yourdomain.com
```

**Manual Certificate Installation:**
```bash
# Install certbot
apt-get install -y certbot python3-certbot-nginx

# Obtain certificate
certbot --nginx -d your-domain.com

# Auto-renewal is configured automatically
```

### Firewall Configuration

**Recommended UFW Rules:**
```bash
# SSH
ufw allow 22/tcp

# Web traffic
ufw allow 80/tcp
ufw allow 443/tcp

# Monitoring (restrict to observability VPS)
ufw allow from 10.10.100.10 to any port 9100 proto tcp  # node_exporter
ufw allow from 10.10.100.10 to any port 9113 proto tcp  # nginx_exporter
ufw allow from 10.10.100.10 to any port 9104 proto tcp  # mysqld_exporter
ufw allow from 10.10.100.10 to any port 9253 proto tcp  # phpfpm_exporter

# Enable firewall
ufw --force enable
```

### Security Checklist

- [ ] Change default Grafana admin password
- [ ] Set strong database passwords
- [ ] Enable Redis authentication
- [ ] Configure SSL certificates for production
- [ ] Restrict exporter ports to observability VPS
- [ ] Enable 2FA for admin accounts
- [ ] Review and enable security headers in Nginx
- [ ] Set `APP_DEBUG=false` in production
- [ ] Configure proper session security settings
- [ ] Set up log rotation for all services

---

## Post-Deployment Verification

### Observability Stack Health Check

```bash
# Check all services
for svc in prometheus grafana-server loki tempo alertmanager node_exporter; do
    echo -n "$svc: "
    systemctl is-active $svc
done

# Verify endpoints
echo "Prometheus: $(curl -s http://localhost:9090/-/healthy)"
echo "Grafana: $(curl -s http://localhost:3000/api/health | jq -r '.database')"
echo "Loki: $(curl -s http://localhost:3100/ready)"
echo "Tempo: $(curl -s http://localhost:3200/ready)"
echo "Alertmanager: $(curl -s http://localhost:9093/-/healthy)"
```

### CHOM Application Health Check

```bash
# Check services
for svc in nginx php8.4-fpm mariadb redis-server; do
    echo -n "$svc: "
    systemctl is-active $svc
done

# Verify exporters
curl -s http://localhost:9100/metrics | head -5  # Node
curl -s http://localhost:9113/metrics | head -5  # Nginx
curl -s http://localhost:9104/metrics | head -5  # MySQL
curl -s http://localhost:9253/metrics | head -5  # PHP-FPM

# Check Laravel application
curl -s http://localhost/health
php artisan about
```

### Docker Test Environment Health Check

```bash
cd docker

# Run comprehensive tests
./scripts/test-env.sh test

# Expected output:
# Test: VPS containers running... PASS
# Test: Systemd active in mentat_tst... PASS
# Test: Systemd active in landsraad_tst... PASS
# Test: Network connectivity... PASS
# Test: Prometheus responding... PASS
# Test: Grafana responding... PASS
# Test: CHOM Web App responding... PASS
```

### Prometheus Target Verification

Access Prometheus at `http://<observability-ip>:9090/targets` and verify:
- All targets show `UP` status
- No scrape errors
- Metrics are being collected

### Grafana Dashboard Access

1. Open Grafana at `http://<observability-ip>:3000`
2. Login with admin credentials
3. Navigate to Dashboards > Browse
4. Verify pre-built dashboards are available:
   - Node Exporter Full
   - Nginx Overview
   - MySQL Overview
   - Loki Overview

---

## Troubleshooting

### Common Issues

#### Services Not Starting

```bash
# Check service status
systemctl status <service-name>

# View recent logs
journalctl -u <service-name> -n 50 --no-pager

# Check for port conflicts
ss -tlnp | grep <port>
```

#### Prometheus Not Scraping Targets

1. Verify target is reachable:
   ```bash
   curl http://<target-ip>:<port>/metrics
   ```
2. Check Prometheus targets page for errors
3. Verify firewall allows connection from observability VPS
4. Check target service is running

#### Loki Not Receiving Logs

1. Verify Promtail/Alloy is running on source VPS
2. Check Promtail configuration for correct Loki URL
3. Verify network connectivity to Loki port 3100
4. Check Loki logs for ingestion errors

#### PHP-FPM Status Not Available

```bash
# Verify status page is enabled
grep -E "pm.status_path|ping.path" /etc/php/8.4/fpm/pool.d/www.conf

# Test status endpoint
curl http://localhost/fpm-status

# Restart PHP-FPM after configuration changes
systemctl restart php8.4-fpm
```

#### Database Connection Issues

```bash
# Test MySQL connection
mysql -u chom -p -e "SELECT 1;"

# Verify credentials in .env match database
grep ^DB_ /var/www/vpsmanager/.env

# Check MariaDB status
systemctl status mariadb
```

### Log Locations

| Component | Log Location |
|-----------|--------------|
| Prometheus | `journalctl -u prometheus` |
| Grafana | `/var/log/grafana/grafana.log` |
| Loki | `journalctl -u loki` |
| Nginx | `/var/log/nginx/access.log`, `/var/log/nginx/error.log` |
| PHP-FPM | `/var/log/php8.4-fpm.log` |
| Laravel | `/var/www/vpsmanager/storage/logs/laravel.log` |
| MariaDB | `/var/log/mysql/error.log` |

### Getting Help

1. Check existing documentation in `docs/` directory
2. Review security audit findings in `SECURITY_AUDIT_FINDINGS.md`
3. Open an issue at [github.com/calounx/mentat/issues](https://github.com/calounx/mentat/issues)
4. For CHOM-specific issues, contact support@chom.io

---

## Appendix: Quick Reference Commands

### Docker Test Environment

```bash
./scripts/test-env.sh up              # Start containers
./scripts/test-env.sh down            # Stop containers
./scripts/test-env.sh reset           # Reset all data
./scripts/test-env.sh deploy          # Deploy all components
./scripts/test-env.sh status          # Check status
./scripts/test-env.sh logs mentat_tst # View container logs
./scripts/test-env.sh shell mentat_tst # Open shell
./scripts/test-env.sh test            # Run regression tests
```

### Observability Stack (obs CLI)

```bash
obs help                              # Show all commands
obs preflight --observability-vps     # Pre-deployment checks
obs config validate                   # Validate configuration
obs setup --observability             # Install observability stack
obs status                            # Check all services
obs health                            # Comprehensive health check
```

### Laravel Artisan (CHOM)

```bash
php artisan serve                     # Start dev server
php artisan migrate                   # Run migrations
php artisan db:seed                   # Seed test data
php artisan test                      # Run tests
php artisan queue:work                # Process queue jobs
php artisan optimize                  # Cache configuration
php artisan optimize:clear            # Clear all caches
```

---

*Last updated: January 2025*
*Version: 1.0.0*
