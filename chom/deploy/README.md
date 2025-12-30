# CHOM Deployment System

Complete automated deployment orchestrator for CHOM infrastructure with auto-healing, intelligent retry logic, and comprehensive monitoring.

## Quick Navigation

| I want to... | Go to... | Time |
|--------------|----------|------|
| **Deploy quickly** | [QUICK-START.md](./QUICK-START.md) | 30 min |
| **Understand everything** | Read this document | 1-2 hours |
| **Fix a problem** | [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | As needed |
| **Secure my deployment** | [SECURITY-SETUP.md](./SECURITY-SETUP.md) | 30-60 min |
| **Update existing system** | [UPDATE-GUIDE.md](./UPDATE-GUIDE.md) | 30-60 min |

**New to CHOM?** Start with [QUICK-START.md](./QUICK-START.md) for a guided 30-minute deployment.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [What Gets Deployed](#what-gets-deployed)
4. [Prerequisites](#prerequisites)
5. [Deployment Workflow](#deployment-workflow)
6. [Security Best Practices](#security-best-practices)
7. [Monitoring Setup](#monitoring-setup)
8. [Update Procedures](#update-procedures)
9. [Advanced Configuration](#advanced-configuration)
10. [Command Reference](#command-reference)

---

## Overview

CHOM deployment system automates the complete setup of a production-grade infrastructure stack including:

- **Observability Stack**: Prometheus, Grafana, Loki, Alertmanager for comprehensive monitoring
- **Application Stack**: LEMP (Nginx, PHP, MariaDB) with Laravel framework
- **Automated Monitoring**: Pre-configured exporters, dashboards, and alerts
- **Auto-Healing**: Intelligent retry logic with exponential backoff
- **Security**: Hardened configurations, SSL/TLS support, firewall setup

### Key Features

- **Zero-touch deployment** - Fully automated, no manual intervention required
- **Auto-healing** - Automatically recovers from transient failures
- **Idempotent** - Safe to run multiple times, resumes from failures
- **Production-ready** - Secure defaults, monitoring, logging out of the box
- **Validated** - Pre-flight checks prevent common deployment issues

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Control Machine                         │
│                   (Your Local Computer)                      │
│                                                              │
│  ┌────────────────────────────────────────────────────┐   │
│  │           deploy-enhanced.sh                       │   │
│  │  • Pre-flight validation                           │   │
│  │  • Orchestrates deployment                         │   │
│  │  • Auto-healing & retry logic                      │   │
│  │  • State management                                │   │
│  └────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ SSH
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────┐
│ Observability VPS│ │  VPSManager VPS  │ │  Future VPS  │
│                  │ │                  │ │   Expansion  │
│ Prometheus       │ │ Nginx            │ │              │
│ Grafana          │ │ PHP-FPM 8.4      │ │              │
│ Loki             │ │ MariaDB 11.4     │ │              │
│ Alertmanager     │ │ Redis            │ │              │
│ Tempo            │ │ Laravel          │ │              │
│ Alloy            │ │                  │ │              │
│                  │ │ Exporters:       │ │              │
│ Nginx (proxy)    │ │ • Node           │ │              │
│                  │ │ • Nginx          │ │              │
│                  │ │ • MySQL          │ │              │
│                  │ │ • PHP-FPM        │ │              │
└──────────────────┘ └──────────────────┘ └──────────────┘
        │                   │
        │ ← Metrics/Logs ── │
        └───────────────────┘
```

### Data Flow

1. **Metrics Collection**: Exporters on VPSManager send metrics to Prometheus
2. **Log Shipping**: Promtail ships logs from VPSManager to Loki
3. **Visualization**: Grafana queries Prometheus and Loki for dashboards
4. **Alerting**: Alertmanager receives alerts from Prometheus and notifies configured channels

---

## What Gets Deployed

### Observability VPS

| Component | Version | Purpose | Port | Status |
|-----------|---------|---------|------|--------|
| **Prometheus** | 2.54.1 | Metrics storage & querying | 9090 | Public |
| **Grafana** | 11.3.0 | Visualization dashboards | 3000 | Public |
| **Loki** | 3.2.1 | Log aggregation & storage | 3100 | Internal |
| **Alertmanager** | 0.27.0 | Alert routing & notifications | 9093 | Internal |
| **Tempo** | Latest | Distributed tracing | 3200 | Internal |
| **Alloy** | Latest | OpenTelemetry collector | 12345 | Internal |
| **Nginx** | Latest | Reverse proxy & SSL termination | 80/443 | Public |

**Disk Usage**: ~5-10GB (plus metrics retention)
**RAM Usage**: ~1.5-2GB
**CPU Usage**: Low (1-2 vCPU sufficient)

### VPSManager VPS

| Component | Version | Purpose | Port | Status |
|-----------|---------|---------|------|--------|
| **Nginx** | Latest | Web server | 80/443 | Public |
| **PHP-FPM** | 8.4 | PHP processor | 9000 | Internal |
| **MariaDB** | 11.4 | Database server | 3306 | Internal |
| **Redis** | Latest | Cache & session storage | 6379 | Internal |
| **Laravel** | Latest | Application framework | - | - |
| **Node Exporter** | Latest | System metrics | 9100 | Internal |
| **Nginx Exporter** | Latest | Nginx metrics | 9113 | Internal |
| **MySQL Exporter** | Latest | Database metrics | 9104 | Internal |
| **PHP-FPM Exporter** | Latest | PHP-FPM metrics | 9253 | Internal |
| **Promtail** | Latest | Log shipper to Loki | 9080 | Internal |

**Disk Usage**: ~10-15GB (plus application data)
**RAM Usage**: ~2-3GB
**CPU Usage**: Medium (2-4 vCPU recommended)

---

## Prerequisites

### Control Machine Requirements

Your local machine (where you run deployment from):

- **Operating System**: Linux or macOS
- **Shell**: Bash 4.0 or later
- **Network**: Internet connectivity
- **Disk Space**: At least 500MB free for scripts and logs
- **Tools** (auto-installed if missing):
  - `git`
  - `ssh` / `scp` (openssh-client)
  - `yq` (YAML processor)
  - `jq` (JSON processor)
  - `wget` or `curl`

### VPS Server Requirements

You need **2 VPS servers** with:

#### Minimum Specifications

| VPS | vCPU | RAM | Disk | Network |
|-----|------|-----|------|---------|
| **Observability** | 1 | 2GB | 20GB | Public IP |
| **VPSManager** | 1 | 2GB | 20GB | Public IP |

#### Recommended Specifications

| VPS | vCPU | RAM | Disk | Network |
|-----|------|-----|------|---------|
| **Observability** | 2 | 4GB | 40GB SSD | Public IP, 1Gbps |
| **VPSManager** | 2-4 | 4-8GB | 60GB SSD | Public IP, 1Gbps |

#### Operating System

- **Required**: Debian 13 (bookworm) - fresh/vanilla install
- **Not Supported**: Ubuntu, CentOS, older Debian versions
- **Architecture**: x86_64 / amd64

#### Network Access

**Required open ports on Observability VPS:**
- `22` - SSH (restricted to your IP)
- `80` - HTTP (for Let's Encrypt challenges)
- `443` - HTTPS (for web access with SSL)
- `3000` - Grafana (or behind reverse proxy)
- `9090` - Prometheus (or behind reverse proxy)
- `3100` - Loki (internal, from VPSManager IP only)

**Required open ports on VPSManager VPS:**
- `22` - SSH (restricted to your IP)
- `80` - HTTP (for Let's Encrypt challenges)
- `443` - HTTPS (for web access with SSL)
- `8080` - Application (or use 80/443 with virtual hosts)
- `9100-9253` - Exporters (internal, from Observability IP only)

---

## Deployment Workflow

### Overview Diagram

```
┌─────────────────┐
│   Preparation   │
│                 │
│ 1. Provision VPS│
│ 2. Create users │
│ 3. Clone repo   │
│ 4. Configure    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Validation    │
│                 │
│ • Check deps    │
│ • Test SSH      │
│ • Verify OS     │
│ • Check space   │
└────────┬────────┘
         │
         ▼
    ┌────────┐
    │Deploy? │──No──┐
    └────┬───┘      │
         │Yes       │
         ▼          │
┌─────────────────┐ │
│  Observability  │ │
│   Deployment    │ │
│                 │ │
│ • Prometheus    │ │
│ • Grafana       │ │
│ • Loki          │ │
│ • Alertmanager  │ │
└────────┬────────┘ │
         │          │
         ▼          │
┌─────────────────┐ │
│   VPSManager    │ │
│   Deployment    │ │
│                 │ │
│ • LEMP stack    │ │
│ • Laravel       │ │
│ • Exporters     │ │
│ • Promtail      │ │
└────────┬────────┘ │
         │          │
         ▼          │
┌─────────────────┐ │
│  Verification   │ │
│                 │ │
│ • Test services │ │
│ • Check metrics │ │
│ • Verify logs   │ │
└────────┬────────┘ │
         │          │
         ▼          │
    ┌────────┐      │
    │Success?│──No──┘
    └────┬───┘      ↑
         │Yes       │
         │    [Auto-Retry]
         ▼
┌─────────────────┐
│  Post-Deploy    │
│                 │
│ • Configure SSL │
│ • Setup alerts  │
│ • Import dashbd │
│ • Test system   │
└─────────────────┘
```

### Detailed Steps

#### Phase 1: Preparation (10 minutes)

1. **Provision VPS servers**
   - Log into your VPS provider (DigitalOcean, Vultr, Hetzner, etc.)
   - Create 2 new servers with Debian 13
   - Note down IP addresses and root passwords

2. **Create deployment users**
   ```bash
   # On each VPS, create sudo user (NOT root)
   ssh root@VPS_IP
   wget https://raw.githubusercontent.com/calounx/mentat/master/chom/deploy/scripts/create-deploy-user.sh
   chmod +x create-deploy-user.sh
   ./create-deploy-user.sh deploy
   # Set password when prompted
   exit
   ```

3. **Copy SSH keys**
   ```bash
   # From your local machine
   ssh-copy-id deploy@OBSERVABILITY_IP
   ssh-copy-id deploy@VPSMANAGER_IP
   ```

4. **Clone repository**
   ```bash
   git clone https://github.com/calounx/mentat.git
   cd mentat/chom/deploy
   chmod +x deploy-enhanced.sh
   ```

5. **Configure inventory**
   ```bash
   cp configs/inventory.yaml.example configs/inventory.yaml
   nano configs/inventory.yaml
   # Update with your VPS IPs and SSH user
   ```

#### Phase 2: Validation (2-5 minutes)

```bash
./deploy-enhanced.sh --validate
```

**What's checked:**
- ✓ Local dependencies installed
- ✓ Inventory YAML syntax valid
- ✓ SSH connectivity to both VPS
- ✓ Correct OS version (Debian 13)
- ✓ Sufficient disk space
- ✓ Adequate RAM
- ✓ Network connectivity
- ✓ Sudo access configured

**If validation fails**, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

#### Phase 3: Deployment (15-25 minutes)

```bash
./deploy-enhanced.sh all
```

**Deployment sequence:**

1. **Pre-flight checks** (2 min)
   - Re-validates environment
   - Creates deployment state tracking
   - Acquires deployment lock

2. **Observability Stack** (5-10 min)
   - Downloads and installs Prometheus
   - Downloads and installs Grafana
   - Downloads and installs Loki
   - Downloads and installs Alertmanager
   - Configures Nginx reverse proxy
   - Configures datasources in Grafana
   - Sets up systemd services
   - Starts and enables all services

3. **VPSManager Stack** (10-15 min)
   - Installs Nginx web server
   - Installs PHP 8.4 and extensions
   - Installs MariaDB 11.4
   - Installs Redis
   - Deploys Laravel application
   - Installs and configures exporters
   - Configures Promtail for log shipping
   - Sets up systemd services
   - Starts and enables all services

4. **Integration** (1 min)
   - Configures Prometheus to scrape VPSManager
   - Configures Loki to receive logs from VPSManager
   - Validates monitoring data flow
   - Performs health checks

#### Phase 4: Verification (5 minutes)

**Automated checks:**
- All services running
- Prometheus targets UP
- Grafana accessible
- Logs flowing to Loki
- Metrics being collected

**Manual verification:**
```bash
# Check Grafana
open http://OBSERVABILITY_IP:3000
# Login: admin / admin (change immediately)

# Check Prometheus
open http://OBSERVABILITY_IP:9090/targets
# All targets should be UP (green)

# Check VPSManager
open http://VPSMANAGER_IP:8080
# Should show Laravel welcome or configured app

# Verify services
ssh deploy@OBSERVABILITY_IP "systemctl status prometheus grafana-server loki"
ssh deploy@VPSMANAGER_IP "systemctl status nginx php8.4-fpm mariadb redis-server"
```

#### Phase 5: Post-Deployment Configuration (30-60 minutes)

See [SECURITY-SETUP.md](./SECURITY-SETUP.md) for:
- SSL/TLS certificate installation
- Firewall configuration
- 2FA setup for admin accounts
- Secrets management
- Alert notification setup
- Dashboard customization

---

## Security Best Practices

### 1. User Security

**✓ DO:**
- Create dedicated sudo users (not root)
- Use SSH keys (not passwords)
- Configure passwordless sudo for deployment
- Set strong passwords for web interfaces
- Enable 2FA on admin accounts

**✗ DON'T:**
- Use root user for deployment
- Use password-based SSH authentication
- Share SSH keys between users
- Use default passwords

### 2. Network Security

**Firewall Configuration:**

On **Observability VPS**:
```bash
# Allow SSH from your IP only
sudo ufw allow from YOUR_IP to any port 22

# Allow web access
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 3000/tcp  # Grafana
sudo ufw allow 9090/tcp  # Prometheus

# Allow metrics from VPSManager only
sudo ufw allow from VPSMANAGER_IP to any port 3100  # Loki

# Enable firewall
sudo ufw enable
```

On **VPSManager VPS**:
```bash
# Allow SSH from your IP only
sudo ufw allow from YOUR_IP to any port 22

# Allow web access
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8080/tcp

# Allow metrics scraping from Observability only
sudo ufw allow from OBSERVABILITY_IP to any port 9100
sudo ufw allow from OBSERVABILITY_IP to any port 9113
sudo ufw allow from OBSERVABILITY_IP to any port 9104
sudo ufw allow from OBSERVABILITY_IP to any port 9253

# Enable firewall
sudo ufw enable
```

### 3. SSL/TLS Encryption

**Install Let's Encrypt certificates:**

```bash
# On Observability VPS
ssh deploy@OBSERVABILITY_IP
sudo apt-get install -y certbot python3-certbot-nginx

# Get certificate
sudo certbot --nginx -d monitoring.example.com

# Test auto-renewal
sudo certbot renew --dry-run
```

**Configure Nginx for SSL:**
- Force HTTPS redirects
- Enable HSTS
- Use strong cipher suites
- Enable OCSP stapling

See [SECURITY-SETUP.md](./SECURITY-SETUP.md#ssl-tls-setup) for detailed configuration.

### 4. Application Security

**Laravel Security Checklist:**
```bash
# Set environment to production
APP_ENV=production
APP_DEBUG=false

# Generate strong application key
php artisan key:generate

# Use secure session settings
SESSION_SECURE_COOKIE=true
SESSION_HTTP_ONLY=true
SESSION_SAME_SITE=strict

# Enable CSRF protection (enabled by default)

# Use prepared statements (Laravel does this automatically)
```

### 5. Database Security

**MariaDB Hardening:**
```bash
# Run secure installation
sudo mysql_secure_installation

# Create application user (not root)
CREATE USER 'appuser'@'localhost' IDENTIFIED BY 'strong_password';
GRANT SELECT, INSERT, UPDATE, DELETE ON database.* TO 'appuser'@'localhost';
FLUSH PRIVILEGES;

# Disable remote root login
# Bind to localhost only
bind-address = 127.0.0.1
```

### 6. Monitoring & Alerting

**Set up critical alerts:**
- Disk space < 20%
- Memory usage > 90%
- Service down
- SSL certificate expiring < 30 days
- Failed login attempts
- Unusual traffic patterns

See [Monitoring Setup](#monitoring-setup) section below.

### 7. Regular Maintenance

**Security Maintenance Schedule:**

- **Daily**: Review security logs
- **Weekly**: Check for service updates
- **Monthly**: Review access logs, rotate credentials
- **Quarterly**: Security audit, penetration testing
- **Annually**: Full infrastructure review

**Automated tasks:**
```bash
# Enable automatic security updates (Debian)
sudo apt-get install unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades

# Schedule credential rotation
# See SECURITY-SETUP.md
```

---

## Monitoring Setup

### Grafana Dashboards

#### Import Pre-built Dashboards

1. **Log into Grafana**: http://OBSERVABILITY_IP:3000
2. **Navigate to**: Dashboards → Import
3. **Import these dashboard IDs:**

| Dashboard | ID | Purpose |
|-----------|-----|---------|
| Node Exporter Full | 1860 | System metrics (CPU, RAM, disk, network) |
| Nginx Overview | 12708 | Nginx performance and requests |
| MySQL Overview | 7362 | Database performance and queries |
| PHP-FPM Metrics | 11331 | PHP-FPM pool status and performance |
| Redis Overview | 11835 | Redis cache performance |

#### Custom Dashboard Creation

**Create VPSManager overview:**
```
1. Create new dashboard
2. Add panels:
   - Panel 1: System Load (node_load1, node_load5, node_load15)
   - Panel 2: Memory Usage (node_memory_MemAvailable_bytes)
   - Panel 3: Disk Usage (node_filesystem_avail_bytes)
   - Panel 4: Network Traffic (node_network_receive_bytes_total)
   - Panel 5: HTTP Requests (nginx_http_requests_total)
   - Panel 6: MySQL Queries (mysql_global_status_queries)
   - Panel 7: PHP-FPM Processes (phpfpm_active_processes)
3. Save dashboard
```

### Prometheus Alerting

#### Configure Alert Rules

**Edit Prometheus alerts:**
```bash
ssh deploy@OBSERVABILITY_IP
sudo nano /etc/prometheus/alert_rules.yml
```

**Example alerts:**
```yaml
groups:
  - name: infrastructure_alerts
    interval: 30s
    rules:
      # Disk space alert
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 20
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk space low on {{ $labels.instance }}"
          description: "Disk {{ $labels.mountpoint }} has {{ $value }}% free space"

      # Memory alert
      - alert: MemoryUsageHigh
        expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 < 10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Memory usage critical on {{ $labels.instance }}"
          description: "Available memory is {{ $value }}%"

      # Service down alert
      - alert: ServiceDown
        expr: up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.job }} is down"
          description: "{{ $labels.instance }} has been down for 2 minutes"

      # High CPU alert
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is {{ $value }}%"

      # SSL certificate expiring
      - alert: SSLCertExpiringSoon
        expr: probe_ssl_earliest_cert_expiry - time() < 86400 * 30
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "SSL certificate expiring soon"
          description: "SSL cert for {{ $labels.instance }} expires in {{ $value | humanizeDuration }}"
```

**Reload Prometheus:**
```bash
sudo systemctl reload prometheus
```

#### Configure Alertmanager

**Edit Alertmanager config:**
```bash
sudo nano /etc/alertmanager/alertmanager.yml
```

**Email notifications:**
```yaml
global:
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'alerts@example.com'
  smtp_auth_username: 'alerts@example.com'
  smtp_auth_password: 'app_password'

route:
  group_by: ['alertname', 'severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'email'

  routes:
    - match:
        severity: critical
      receiver: 'email-critical'
      repeat_interval: 5m

receivers:
  - name: 'email'
    email_configs:
      - to: 'ops@example.com'
        headers:
          subject: '[Alert] {{ .GroupLabels.alertname }}'

  - name: 'email-critical'
    email_configs:
      - to: 'ops@example.com,oncall@example.com'
        headers:
          subject: '[CRITICAL] {{ .GroupLabels.alertname }}'
```

**Slack notifications:**
```yaml
receivers:
  - name: 'slack'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        channel: '#alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

**Reload Alertmanager:**
```bash
sudo systemctl reload alertmanager
```

### Log Analysis in Loki

**Useful LogQL queries:**

```logql
# All logs from VPSManager
{job="varlogs"}

# Nginx access logs only
{job="varlogs", filename="/var/log/nginx/access.log"}

# Nginx errors
{job="varlogs", filename="/var/log/nginx/error.log"}

# PHP errors
{job="varlogs", filename="/var/log/php8.4-fpm.log"}

# MySQL errors
{job="varlogs", filename="/var/log/mysql/error.log"}

# Filter by log level
{job="varlogs"} |= "ERROR"
{job="varlogs"} |= "WARNING"

# Count errors per minute
sum(count_over_time({job="varlogs"} |= "ERROR" [1m]))

# Laravel logs
{job="varlogs", filename="/var/www/vpsmanager/storage/logs/laravel.log"}

# Failed login attempts
{job="varlogs"} |= "Failed login"

# 404 errors
{job="varlogs"} |~ "HTTP/1.1\" 404"

# 500 errors
{job="varlogs"} |~ "HTTP/1.1\" 5[0-9]{2}"
```

**Create Loki alert rules:**
```yaml
# In Grafana → Alerting → Alert rules
# Example: High error rate
- name: HighErrorRate
  query: sum(count_over_time({job="varlogs"} |= "ERROR" [5m])) > 100
  for: 5m
  annotations:
    summary: "High error rate detected"
    description: "More than 100 errors in the last 5 minutes"
```

---

## Update Procedures

### Updating CHOM Deployment Scripts

```bash
cd mentat/chom/deploy
git pull origin master
chmod +x deploy-enhanced.sh
./deploy-enhanced.sh --validate
```

### Updating Deployed Services

See [UPDATE-GUIDE.md](./UPDATE-GUIDE.md) for detailed procedures.

**Quick updates:**

```bash
# Update system packages
ssh deploy@VPS_IP
sudo apt-get update
sudo apt-get upgrade -y

# Update Prometheus
./deploy-enhanced.sh observability --force

# Update VPSManager stack
./deploy-enhanced.sh vpsmanager --force

# Update Laravel application
ssh deploy@VPSMANAGER_IP
cd /var/www/vpsmanager
git pull
composer install --no-dev --optimize-autoloader
php artisan migrate --force
php artisan config:cache
php artisan route:cache
php artisan view:cache
sudo systemctl reload php8.4-fpm
```

### Rolling Back Updates

```bash
# If something goes wrong, revert to previous version

# For system packages
sudo apt-get install <package>=<previous-version>

# For services, restore from backup
sudo systemctl stop SERVICE
sudo cp /backup/SERVICE /etc/SERVICE/
sudo systemctl start SERVICE

# For Laravel
cd /var/www/vpsmanager
git checkout <previous-commit>
composer install
php artisan migrate:rollback
```

---

## Advanced Configuration

### Custom Prometheus Scrape Configs

Add custom scrape targets:

```bash
ssh deploy@OBSERVABILITY_IP
sudo nano /etc/prometheus/prometheus.yml
```

```yaml
scrape_configs:
  # Add WordPress site monitoring
  - job_name: 'wordpress_site'
    static_configs:
      - targets: ['wordpress.example.com:9100']
        labels:
          site: 'wordpress'
          environment: 'production'

  # Add external API monitoring
  - job_name: 'blackbox'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - https://api.example.com/health
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:9115  # Blackbox exporter
```

### Custom Grafana Datasources

Add additional datasources:

```bash
# Via Grafana UI:
# Configuration → Data sources → Add data source

# Via configuration file:
ssh deploy@OBSERVABILITY_IP
sudo nano /etc/grafana/provisioning/datasources/datasources.yml
```

```yaml
apiVersion: 1

datasources:
  # External Prometheus
  - name: External-Prometheus
    type: prometheus
    access: proxy
    url: http://external-prometheus:9090
    isDefault: false

  # MySQL database direct access
  - name: VPSManager-MySQL
    type: mysql
    url: vpsmanager-ip:3306
    database: vpsmanager
    user: grafana_reader
    secureJsonData:
      password: 'secure_password'
```

### High Availability Setup

For production workloads, consider:

**Prometheus HA:**
```bash
# Deploy 2+ Prometheus instances
# Use federation to aggregate
# Configure load balancer
```

**Grafana HA:**
```bash
# Use shared database (PostgreSQL/MySQL)
# Deploy behind load balancer
# Configure session storage in Redis
```

**Database Replication:**
```bash
# Configure MariaDB master-slave replication
# Set up automatic failover
```

See enterprise deployment guides for detailed HA configuration.

---

## Command Reference

### Deployment Commands

```bash
# Validate environment
./deploy-enhanced.sh --validate

# Preview deployment plan
./deploy-enhanced.sh --plan

# Deploy everything
./deploy-enhanced.sh all

# Deploy specific component
./deploy-enhanced.sh observability
./deploy-enhanced.sh vpsmanager

# Interactive deployment (with prompts)
./deploy-enhanced.sh --interactive all

# Resume failed deployment
./deploy-enhanced.sh --resume

# Deploy with verbose logging
./deploy-enhanced.sh --verbose all

# Debug mode
./deploy-enhanced.sh --debug all

# Force re-deployment (skip state checks)
./deploy-enhanced.sh --force all

# Help
./deploy-enhanced.sh --help
```

### Service Management

```bash
# Check status
sudo systemctl status SERVICE_NAME

# Start service
sudo systemctl start SERVICE_NAME

# Stop service
sudo systemctl stop SERVICE_NAME

# Restart service
sudo systemctl restart SERVICE_NAME

# Reload configuration (no downtime)
sudo systemctl reload SERVICE_NAME

# Enable on boot
sudo systemctl enable SERVICE_NAME

# Disable on boot
sudo systemctl disable SERVICE_NAME

# View logs
sudo journalctl -u SERVICE_NAME
sudo journalctl -u SERVICE_NAME -f  # Follow
sudo journalctl -u SERVICE_NAME -n 100  # Last 100 lines
sudo journalctl -u SERVICE_NAME --since "1 hour ago"
```

### Diagnostic Commands

```bash
# Check disk usage
df -h

# Check memory usage
free -h

# Check CPU usage
top
htop

# Check network connections
sudo netstat -tulpn
sudo ss -tulpn

# Check processes
ps aux | grep SERVICE_NAME

# Check ports
sudo lsof -i :PORT
sudo lsof -i :9090  # Prometheus

# Test endpoint
curl http://localhost:PORT
curl http://localhost:9090/-/healthy

# Check logs
tail -f /var/log/nginx/error.log
tail -f /var/log/mysql/error.log

# Validate configs
promtool check config /etc/prometheus/prometheus.yml
nginx -t
php-fpm8.4 -t
```

### Backup Commands

```bash
# Backup Prometheus data
tar -czf prometheus-data-$(date +%Y%m%d).tar.gz /var/lib/prometheus/

# Backup Grafana dashboards
curl -X GET http://admin:password@localhost:3000/api/dashboards/db/DASHBOARD > dashboard.json

# Backup database
mysqldump -u root -p DATABASE > backup.sql

# Backup Laravel application
tar -czf vpsmanager-$(date +%Y%m%d).tar.gz /var/www/vpsmanager/
```

---

## File Locations

### Observability VPS

```
/opt/observability/
├── bin/
│   ├── prometheus
│   ├── promtool
│   ├── loki
│   ├── logcli
│   ├── grafana-server
│   └── alertmanager
│
/etc/
├── prometheus/
│   ├── prometheus.yml
│   ├── alert_rules.yml
│   └── targets/
├── grafana/
│   ├── grafana.ini
│   └── provisioning/
├── loki/
│   └── local-config.yaml
├── alertmanager/
│   └── alertmanager.yml
└── nginx/
    └── sites-available/
        └── observability

/var/lib/
├── prometheus/  # Metrics storage
├── grafana/     # Grafana data
└── loki/        # Log storage

/var/log/
├── prometheus/
├── grafana/
└── loki/
```

### VPSManager VPS

```
/var/www/
└── vpsmanager/  # Laravel application
    ├── app/
    ├── config/
    ├── database/
    ├── public/
    ├── resources/
    ├── routes/
    ├── storage/
    └── .env

/etc/
├── nginx/
│   └── sites-available/
│       └── vpsmanager
├── php/8.4/
│   └── fpm/
│       └── pool.d/
│           └── www.conf
├── mysql/
│   └── mariadb.conf.d/
│       └── 50-server.cnf
├── redis/
│   └── redis.conf
└── promtail/
    └── config.yml

/var/log/
├── nginx/
├── php8.4-fpm/
├── mysql/
└── promtail/
```

---

## Troubleshooting Quick Reference

| Symptom | Likely Cause | Quick Fix |
|---------|--------------|-----------|
| Can't SSH to VPS | Firewall, wrong IP/user | Check `inventory.yaml`, verify firewall |
| Deployment fails | Network issue, wrong OS | Run `./deploy-enhanced.sh --resume` |
| Grafana won't load | Service down, firewall | `sudo systemctl start grafana-server` |
| Targets DOWN | Exporter not running | `sudo systemctl start EXPORTER_NAME` |
| No logs in Loki | Promtail not sending | Check Promtail config, restart service |
| High CPU | Too many targets | Increase scrape interval |
| High memory | Long retention | Reduce retention period |
| SSL cert expired | Auto-renewal failed | `sudo certbot renew --force-renewal` |

**For detailed troubleshooting, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)**

---

## Best Practices Summary

### Deployment
- ✓ Always run `--validate` before deploying
- ✓ Use dedicated sudo user (not root)
- ✓ Deploy during low-traffic periods
- ✓ Keep backups before major changes
- ✓ Test in staging before production

### Security
- ✓ Enable firewall immediately after deployment
- ✓ Install SSL certificates within 24 hours
- ✓ Change default passwords immediately
- ✓ Enable 2FA for admin accounts
- ✓ Review security logs regularly

### Monitoring
- ✓ Configure critical alerts first
- ✓ Set up notification channels
- ✓ Review dashboards weekly
- ✓ Test alerting monthly
- ✓ Keep Prometheus retention reasonable (15-30 days)

### Maintenance
- ✓ Apply security updates weekly
- ✓ Review logs daily
- ✓ Backup data before updates
- ✓ Test backup restoration quarterly
- ✓ Document all custom changes

---

## Additional Resources

### Documentation
- [QUICK-START.md](./QUICK-START.md) - 30-minute deployment guide
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Problem diagnosis and fixes
- [SECURITY-SETUP.md](./SECURITY-SETUP.md) - Security hardening guide
- [UPDATE-GUIDE.md](./UPDATE-GUIDE.md) - Update procedures

### Official Documentation
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/)
- [Laravel Documentation](https://laravel.com/docs/)
- [Nginx Documentation](https://nginx.org/en/docs/)

### Community
- GitHub Issues: https://github.com/calounx/mentat/issues
- Prometheus Community: https://prometheus.io/community/
- Grafana Community: https://community.grafana.com/

---

## Version History

- **v2.0** - Auto-healing deployment, comprehensive security
- **v1.5** - Added Loki, Tempo, improved monitoring
- **v1.0** - Initial release with basic observability

---

## License

[Add your license here]

---

## Contributing

Contributions welcome! Please see CONTRIBUTING.md for guidelines.

---

**Last Updated:** 2025-12-30
**Maintained by:** CHOM Development Team
