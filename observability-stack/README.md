# Observability Stack for Debian 13

A complete, production-ready observability stack without Docker. Features a **modular exporter system** that allows different monitored hosts to run different sets of exporters, with centralized dashboard and alert management.

## Quick Start

```bash
# 1. Install the CLI (optional but recommended)
sudo ./install.sh

# 2. Run pre-flight checks
obs preflight --observability-vps

# 3. Configure and validate
cp config/global.yaml.example config/global.yaml
nano config/global.yaml
obs config validate

# 4. Setup observability VPS
obs setup --observability

# 5. Setup monitored hosts (with auto-detection)
obs setup --monitored-host OBSERVABILITY_VPS_IP
```

For a detailed walkthrough, see [QUICK_START.md](QUICK_START.md).

## Unified CLI

The observability stack includes a unified CLI that simplifies all operations:

```bash
# Install the CLI (creates 'obs' command)
sudo ./install.sh

# Main commands
obs help                          # Show all commands
obs preflight --observability-vps # Run pre-flight checks
obs config validate               # Validate configuration
obs setup --observability         # Setup observability VPS
obs setup --monitored-host IP     # Setup monitored host
obs module list                   # List available modules
obs module install node_exporter  # Install specific module
obs host list                     # List configured hosts
obs health                        # Check system health

# Get help on any command
obs help setup
obs help module
obs help preflight
```

See `obs help` for complete command reference.

## Components

| Component | Purpose | Port |
|-----------|---------|------|
| **Prometheus** | Metrics collection & storage | 9090 |
| **Loki** | Log aggregation | 3100 |
| **Grafana** | Visualization & dashboards | 3000 |
| **Alertmanager** | Alert routing (Email/Slack) | 9093 |
| **Nginx** | Reverse proxy with SSL | 80/443 |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    OBSERVABILITY VPS                            │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌─────────────┐  │
│  │ Prometheus│  │   Loki    │  │  Grafana  │  │Alertmanager │  │
│  │ (metrics) │  │  (logs)   │  │  (viz)    │  │ (alerts)    │  │
│  └─────▲─────┘  └─────▲─────┘  └───────────┘  └─────────────┘  │
│        │ scrape       │ push                                    │
│  ┌─────┴──────────────┴─────────────────────────────────────┐  │
│  │              MODULE REGISTRY                              │  │
│  │  Dashboards │ Alert Rules │ Scrape Configs │ Install     │  │
│  └───────────────────────────────────────────────────────────┘  │
└────────┬──────────────┬─────────────────────────────────────────┘
         │              │
┌────────┴──────────────┴────────────────────────────────────────┐
│               MONITORED HOSTS (per-host configs)               │
│                                                                 │
│  Host A: node │ nginx │ mysql │ phpfpm                         │
│  Host B: node │ nginx │ fail2ban                               │
│  Host C: node │ promtail                                       │
└─────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
observability-stack/
├── config/
│   ├── global.yaml                    # Global settings (retention, SMTP, Slack)
│   └── hosts/                         # Per-host configuration files
│       ├── webserver-01.yaml          # Host-specific modules & thresholds
│       └── example-host.yaml.template # Template for new hosts
│
├── modules/                           # Module registry
│   ├── _core/                         # Core modules (maintained)
│   │   ├── node_exporter/
│   │   ├── nginx_exporter/
│   │   ├── mysqld_exporter/
│   │   ├── phpfpm_exporter/
│   │   ├── fail2ban_exporter/
│   │   └── promtail/
│   ├── _available/                    # Community modules
│   └── _custom/                       # Custom modules (gitignored)
│
├── scripts/
│   ├── lib/                           # Shared libraries
│   │   ├── common.sh                  # Logging, YAML parsing utilities
│   │   ├── module-loader.sh           # Module discovery & loading
│   │   └── config-generator.sh        # Prometheus/Grafana config generation
│   ├── module-manager.sh              # Module management CLI
│   ├── auto-detect.sh                 # Service auto-detection
│   ├── setup-observability.sh         # Main setup script
│   └── setup-monitored-host.sh        # Module-based host setup
│
├── prometheus/
│   ├── prometheus.yml.template
│   └── rules/                         # Generated from modules
│
├── loki/
│   └── loki-config.yaml
│
├── alertmanager/
│   ├── alertmanager.yml.template
│   └── templates/
│       └── email.tmpl
│
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   └── dashboards/
│   └── dashboards/                    # Generated from modules
│
└── nginx/
    └── observability.conf.template
```

## Module System

Each module is a self-contained package containing:
- `module.yaml` - Manifest with version, port, detection rules, configuration schema
- `install.sh` - Installation script
- `uninstall.sh` - Uninstallation script
- `dashboard.json` - Grafana dashboard
- `alerts.yml` - Prometheus alert rules
- `scrape-config.yml` - Prometheus scrape configuration template

### Module Manager CLI

```bash
# List all available modules
./scripts/module-manager.sh list

# List by category
./scripts/module-manager.sh list core
./scripts/module-manager.sh list available
./scripts/module-manager.sh list custom

# Show module details
./scripts/module-manager.sh show node_exporter

# Validate module manifests
./scripts/module-manager.sh validate
./scripts/module-manager.sh validate node_exporter

# Check module installation status
./scripts/module-manager.sh status

# Install a module on current host
./scripts/module-manager.sh install node_exporter
./scripts/module-manager.sh install node_exporter --force

# Uninstall a module
./scripts/module-manager.sh uninstall node_exporter
./scripts/module-manager.sh uninstall node_exporter --purge

# Enable/disable modules for hosts
./scripts/module-manager.sh enable mysql_exporter webserver-01
./scripts/module-manager.sh disable phpfpm_exporter webserver-01

# Generate Prometheus/Grafana configs from enabled modules
./scripts/module-manager.sh generate-config
./scripts/module-manager.sh generate-config --dry-run
```

### Auto-Detection

Auto-detect which modules should be enabled based on running services:

```bash
# Detect services and show recommendations
./scripts/auto-detect.sh

# Generate host config file from detection
./scripts/auto-detect.sh --generate --output=config/hosts/myhost.yaml

# Force overwrite existing config
./scripts/auto-detect.sh --generate --force --output=config/hosts/myhost.yaml
```

### Available Modules

| Module | Description | Port | Detection |
|--------|-------------|------|-----------|
| node_exporter | System metrics (CPU, memory, disk, network) | 9100 | Always applicable |
| nginx_exporter | Nginx server metrics | 9113 | nginx service detected |
| mysqld_exporter | MySQL/MariaDB database metrics | 9104 | mysql/mariadb service detected |
| phpfpm_exporter | PHP-FPM process pool metrics | 9253 | php-fpm socket detected |
| fail2ban_exporter | Fail2ban jail and ban metrics | 9191 | fail2ban service detected |
| promtail | Log shipping to Loki | - | Always applicable |

## Developer Experience Tools

This stack includes powerful DX tools to reduce time-to-success and make operations joyful:

### Setup Wizard

Interactive guided setup for first-time installations:

```bash
sudo ./scripts/setup-wizard.sh
```

Features:
- Prerequisites validation (disk space, ports, commands)
- Interactive configuration with validation
- DNS and SMTP connectivity testing
- Auto-generated strong passwords
- One-command installation
- Clear next steps

### Configuration Validator

Comprehensive validation before deployment:

```bash
# Validate configuration
./scripts/validate-config.sh

# Strict mode (warnings = errors)
./scripts/validate-config.sh --strict
```

Checks:
- No placeholder values (YOUR_VPS_IP, CHANGE_ME, etc.)
- Valid IP addresses and email formats
- DNS resolution for domain
- SMTP server connectivity
- Password strength (minimum 16 characters recommended)
- Required fields present
- Secure file permissions

### Quick Reference Guide

Essential commands and troubleshooting at your fingertips:

```bash
cat QUICKREF.md
```

Includes:
- Common commands for daily operations
- Important file paths and URLs
- Service management commands
- One-liners for quick tasks
- Troubleshooting decision trees
- Emergency procedures

### Improved Error Messages

All scripts provide actionable error messages with:
- Clear explanation of what went wrong
- Step-by-step fix instructions
- Examples of correct usage
- Links to relevant commands

Example:
```
[ERROR] Module 'nginx_exporter' not found

Available modules:
  - node_exporter
  - nginx_exporter
  - mysqld_exporter

To see module details:
  module-manager.sh show <module>
```

### Help System

Every script supports `--help`:

```bash
./scripts/setup-wizard.sh --help
./scripts/validate-config.sh --help
./scripts/module-manager.sh help
./scripts/add-monitored-host.sh --help
```

## Quick Start

### 1. Configure Global Settings

Edit `config/global.yaml`:

```yaml
network:
  observability_vps_ip: "YOUR_VPS_IP"
  grafana_domain: "mentat.arewel.com"
  letsencrypt_email: "admin@arewel.com"

retention:
  metrics_days: 15
  logs_days: 7

smtp:
  host: "smtp-relay.brevo.com"
  port: 587
  username: "your-brevo-email"
  password: "your-brevo-smtp-key"
  from_address: "alerts@yourdomain.com"
  to_addresses:
    - "admin@yourdomain.com"

slack:
  webhook_url: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
  channel: "#alerts"
```

### 2. Setup Observability VPS

```bash
# Copy the entire stack to your VPS
scp -r observability-stack root@YOUR_VPS_IP:/opt/

# SSH and run setup
ssh root@YOUR_VPS_IP
cd /opt/observability-stack
./scripts/setup-observability.sh
```

### 3. Add Monitored Hosts

#### Option A: Auto-detect and configure

```bash
# On the monitored host, run auto-detection
./scripts/auto-detect.sh --generate --output=config/hosts/$(hostname).yaml

# Review and adjust the generated config, then install
./scripts/setup-monitored-host.sh OBSERVABILITY_VPS_IP LOKI_URL LOKI_USER LOKI_PASS
```

#### Option B: Manual configuration

Create a host config file `config/hosts/webserver-01.yaml`:

```yaml
host:
  name: "webserver-01"
  ip: "10.0.0.10"
  description: "Production WordPress server"
  environment: "production"

modules:
  node_exporter:
    enabled: true
    config:
      collectors_enabled:
        - systemd
        - filesystem
        - meminfo
    thresholds:
      cpu_usage_warning: 80
      cpu_usage_critical: 95
      memory_usage_warning: 80
      memory_usage_critical: 95
      disk_usage_warning: 80
      disk_usage_critical: 90

  nginx_exporter:
    enabled: true
    config:
      scrape_uri: "http://127.0.0.1:8080/stub_status"

  mysqld_exporter:
    enabled: true
    config:
      credentials:
        username: "exporter"
        password: "CHANGE_ME"

  phpfpm_exporter:
    enabled: true
    config:
      socket: "/run/php/php8.2-fpm.sock"
      pool_name: "www"

  fail2ban_exporter:
    enabled: true

  promtail:
    enabled: true
    config:
      log_paths:
        - "/var/log/nginx/*.log"
        - "/var/log/syslog"
```

Then run setup on the monitored host:

```bash
./scripts/setup-monitored-host.sh OBSERVABILITY_VPS_IP LOKI_URL LOKI_USER LOKI_PASS
```

### 4. Generate Configurations

After adding or modifying host configs, regenerate Prometheus and Grafana configurations:

```bash
# On observability VPS
./scripts/module-manager.sh generate-config

# Reload services
systemctl reload prometheus
systemctl restart grafana-server
```

## Pre-configured Dashboards

Each module includes a dashboard. When modules are enabled for any host, their dashboards are automatically provisioned.

| Dashboard | Description |
|-----------|-------------|
| **Infrastructure Overview** | High-level view of all hosts, active alerts |
| **Node Exporter Details** | Detailed CPU, memory, disk, network per host |
| **Nginx** | Connections, requests, error rates |
| **MySQL/MariaDB** | Connections, QPS, InnoDB metrics |
| **PHP-FPM** | Process pool, queue, slow requests |
| **Logs Explorer** | Centralized log viewer with filters |

## Alert Rules

Alert rules are also bundled with modules and automatically aggregated.

### System Alerts (node_exporter)
- Instance down
- High CPU (>80%, >95%)
- High memory usage (>80%, >95%)
- Disk space low (>80%, >90%)
- Disk fill prediction (24h)
- High load average
- Systemd service failed

### Service Alerts
- **Nginx**: Down, high connections, 4xx/5xx error rates
- **MySQL**: Down, connection saturation, slow queries, replication lag
- **PHP-FPM**: Down, max children reached, queue filling
- **Fail2ban**: Down, high ban rate, exporter errors

## Security

### Authentication
- **Grafana**: Username/password authentication
- **Prometheus/Loki/Alertmanager**: Protected via Nginx basic auth
- **Exporters**: Only accessible from observability VPS IP (firewall)

### SSL/TLS
- Automatic Let's Encrypt certificates via Certbot
- Auto-renewal enabled

## Ports Reference

### Observability VPS
| Port | Service | Access |
|------|---------|--------|
| 80 | HTTP (redirect to HTTPS) | Public |
| 443 | HTTPS (Grafana/APIs) | Public |
| 3000 | Grafana (internal) | Localhost |
| 9090 | Prometheus (internal) | Localhost |
| 3100 | Loki (internal) | Localhost |
| 9093 | Alertmanager (internal) | Localhost |

### Monitored Hosts
| Port | Exporter | Access |
|------|----------|--------|
| 9100 | node_exporter | From Observability VPS |
| 9113 | nginx_exporter | From Observability VPS |
| 9104 | mysqld_exporter | From Observability VPS |
| 9253 | phpfpm_exporter | From Observability VPS |
| 9191 | fail2ban_exporter | From Observability VPS |

## Troubleshooting

### Check service status
```bash
systemctl status prometheus loki grafana-server alertmanager nginx
```

### View logs
```bash
journalctl -u prometheus -f
journalctl -u loki -f
journalctl -u grafana-server -f
```

### Check module status on host
```bash
./scripts/module-manager.sh status
```

### Test Prometheus targets
```bash
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {instance: .labels.instance, health: .health}'
```

### Validate module manifests
```bash
./scripts/module-manager.sh validate
```

### Test Alertmanager
```bash
curl -X POST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{"labels":{"alertname":"TestAlert","severity":"warning"},"annotations":{"summary":"Test alert"}}]'
```

## Creating Custom Modules

1. Create a directory under `modules/_custom/`:

```bash
mkdir -p modules/_custom/my_exporter
```

2. Create the module manifest `module.yaml`:

```yaml
module:
  name: my_exporter
  display_name: My Custom Exporter
  version: "1.0.0"
  description: Description of what it monitors
  category: custom

detection:
  commands:
    - "which my_service"
  systemd_services:
    - my_service
  files:
    - "/etc/my_service/config"
  confidence: 80

exporter:
  binary_name: my_exporter
  port: 9999
  download_url_template: "https://example.com/releases/v${VERSION}/my_exporter-${VERSION}.linux-${ARCH}.tar.gz"
  flags:
    - "--web.listen-address=:9999"

prometheus:
  job_name: my_exporter
  scrape_interval: 15s

host_config:
  required: []
  optional:
    custom_setting:
      type: string
      default: "value"
```

3. Create `install.sh`, `uninstall.sh`, `dashboard.json`, and `alerts.yml`

4. Validate the module:
```bash
./scripts/module-manager.sh validate my_exporter
```

## Maintenance

### Update retention
Edit `config/global.yaml` and restart services:
```bash
systemctl restart prometheus loki
```

### Regenerate all configs
```bash
./scripts/module-manager.sh generate-config
systemctl reload prometheus
systemctl restart grafana-server
```

### Renew SSL certificate
```bash
certbot renew
systemctl reload nginx
```

### Backup Grafana
```bash
cp -r /var/lib/grafana /backup/grafana-$(date +%Y%m%d)
```

## Upgrade Management

This stack includes a **production-ready idempotent upgrade system** that automatically manages component versions with zero hardcoded values.

### Quick Upgrade Commands

```bash
# Check current versions and available updates
sudo ./scripts/upgrade-orchestrator.sh --status

# Preview what would be upgraded (dry-run)
sudo ./scripts/upgrade-orchestrator.sh --all --dry-run

# Upgrade all components (safe mode)
sudo ./scripts/upgrade-orchestrator.sh --all --mode safe

# Upgrade by phase (recommended for production)
sudo ./scripts/upgrade-orchestrator.sh --phase exporters
sudo ./scripts/upgrade-orchestrator.sh --phase prometheus
sudo ./scripts/upgrade-orchestrator.sh --phase loki

# Rollback if needed
sudo ./scripts/upgrade-orchestrator.sh --rollback
```

### Key Features

- **Dynamic Version Management**: No hardcoded versions, automatically fetches latest stable releases from GitHub
- **True Idempotency**: Safe to run multiple times, detects current state, resumes from crashes
- **Automatic Rollback**: Self-healing on health check failures
- **Phased Upgrades**: Low-risk exporters → High-risk core components
- **State Tracking**: Full visibility into upgrade progress with crash recovery
- **Multiple Modes**: Safe (default), standard, fast, and dry-run modes

### Version Management CLI

```bash
# Check versions for all components
./scripts/version-manager list

# Check specific component
./scripts/version-manager show prometheus

# Update version cache
./scripts/version-manager update --all
```

### Configuration

Version strategies are configured in `config/versions.yaml`:

```yaml
components:
  prometheus:
    strategy: latest        # Always fetch latest stable
    github_repo: prometheus/prometheus
    fallback_version: "2.48.0"

  node_exporter:
    strategy: pinned        # Use exact version
    version: "1.7.0"

  loki:
    strategy: range         # Semver range
    version: ">=3.0.0 <4.0.0"
```

### Upgrade Safety

All upgrades include:
- Pre-flight checks (disk space, dependencies, compatibility)
- Automatic backups before each component upgrade
- Health validation after upgrades
- Automatic rollback on failure
- Detailed upgrade history and audit trail

For complete documentation, see:
- [UPGRADE_QUICKSTART.md](docs/UPGRADE_QUICKSTART.md) - Quick start guide
- [IDEMPOTENT_UPGRADE_COMPLETE.md](docs/IDEMPOTENT_UPGRADE_COMPLETE.md) - Complete system overview
- [UPGRADE_ORCHESTRATION.md](docs/UPGRADE_ORCHESTRATION.md) - Detailed guide

## Troubleshooting & Recovery

### Decision Tree

```
Problem: Can't access Grafana
├─ Is nginx running?
│  ├─ No → systemctl start nginx
│  └─ Yes → Check SSL certificate
│     ├─ Expired → certbot renew && systemctl reload nginx
│     └─ Valid → Check grafana-server status
│        └─ Not running → systemctl start grafana-server

Problem: No data in dashboards
├─ Check Prometheus targets
│  └─ systemctl status prometheus
│     └─ curl localhost:9090/api/v1/targets
│        ├─ Targets down → Check monitored host firewall
│        └─ No targets → Regenerate config
│           └─ ./scripts/module-manager.sh generate-config

Problem: Alerts not being sent
├─ Check Alertmanager
│  └─ systemctl status alertmanager
│     └─ Check logs: journalctl -u alertmanager -n 50
│        ├─ SMTP errors → Verify config/global.yaml SMTP settings
│        └─ Test email: amtool alert add test severity=warning

Problem: Service won't start
├─ Check logs: journalctl -u <service> -n 50
├─ Check config syntax
│  ├─ Prometheus → promtool check config /etc/prometheus/prometheus.yml
│  ├─ Loki → loki -config.file=/etc/loki/loki-config.yaml -verify-config
│  └─ Grafana → grafana-server -config /etc/grafana/grafana.ini -check-config
└─ Check permissions: ls -la /etc/<service> /var/lib/<service>
```

### Common Failure Modes & Fixes

#### 1. Observability VPS Failures

**SSL Certificate Issues**
```bash
# Check certificate validity
openssl x509 -in /etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem -noout -dates

# Manual renewal
certbot renew --force-renewal
systemctl reload nginx

# If Let's Encrypt fails (rate limit)
# Use HTTP-only temporarily by editing nginx config
sed -i 's/443/80/g' /etc/nginx/sites-available/observability
sed -i '/ssl/d' /etc/nginx/sites-available/observability
nginx -t && systemctl reload nginx
```

**Prometheus Data Corruption**
```bash
# Stop Prometheus
systemctl stop prometheus

# Check TSDB
promtool tsdb analyze /var/lib/prometheus

# If corrupted, remove problematic blocks
# Backup first!
mkdir -p /backup/prometheus-recovery
cp -r /var/lib/prometheus /backup/prometheus-recovery/

# Remove latest block (often source of corruption)
ls -t /var/lib/prometheus/01* | head -1 | xargs rm -rf

# Restart
systemctl start prometheus
```

**Disk Full**
```bash
# Check disk usage
df -h
du -sh /var/lib/* | sort -h | tail -10

# Clean old Prometheus data (careful!)
systemctl stop prometheus
find /var/lib/prometheus -name "01*" -mtime +15 -exec rm -rf {} \;
systemctl start prometheus

# Reduce retention in config/global.yaml
# Then: ./observability setup --observability
```

**Port Conflicts**
```bash
# Find what's using the port
lsof -i :9090    # or ss -tlnp | grep 9090

# Stop conflicting service
systemctl stop <conflicting-service>

# Or change port in config/global.yaml
```

#### 2. Monitored Host Failures

**Firewall Blocking Metrics**
```bash
# Check firewall rules
ufw status numbered

# Add rule for observability VPS
ufw allow from OBSERVABILITY_IP to any port 9100 proto tcp
ufw allow from OBSERVABILITY_IP to any port 9113 proto tcp

# Verify connectivity from observability VPS
# On observability VPS:
curl http://MONITORED_HOST:9100/metrics
```

**Exporter Not Running**
```bash
# Check status
./observability module status

# Reinstall specific module
./observability module install node_exporter --force

# Check logs
journalctl -u node_exporter -n 50 --no-pager
```

**Wrong Exporter Configuration**
```bash
# For MySQL exporter with credential issues
# Check credentials file
cat /etc/mysqld_exporter/.my.cnf

# Test MySQL connection
mysql -u exporter -p < /dev/null

# For PHP-FPM exporter with socket issues
# Find correct socket
find /run /var/run -name "php*fpm*.sock" 2>/dev/null

# Update host config
vim config/hosts/$(hostname).yaml
# Then reinstall: ./observability module install phpfpm_exporter --force
```

#### 3. Configuration Errors

**Placeholder Values Still Present**
```bash
# Validate configuration
./observability config validate

# Find placeholders
grep -rn "YOUR_\|CHANGE_ME" config/

# Fix global config
vim config/global.yaml
```

**Invalid YAML Syntax**
```bash
# Check with yamllint (install if needed)
apt-get install yamllint
yamllint config/global.yaml
yamllint config/hosts/*.yaml

# Common issues:
# - Mixed tabs and spaces (use spaces only)
# - Incorrect indentation (use 2 spaces)
# - Missing quotes around special characters
```

**DNS Resolution Issues**
```bash
# Test domain resolution
host YOUR_DOMAIN
dig YOUR_DOMAIN

# If not resolving:
# 1. Create/update DNS A record
# 2. Wait for propagation (up to 48 hours)
# 3. Use /etc/hosts as temporary workaround:
echo "YOUR_VPS_IP YOUR_DOMAIN" >> /etc/hosts
```

### Recovery Procedures

#### Complete Observability VPS Recovery

```bash
# 1. Stop all services
systemctl stop prometheus alertmanager loki grafana-server nginx

# 2. Backup current state
BACKUP_DIR="/backup/recovery-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r /etc/prometheus "$BACKUP_DIR/"
cp -r /etc/alertmanager "$BACKUP_DIR/"
cp -r /etc/loki "$BACKUP_DIR/"
cp -r /etc/grafana "$BACKUP_DIR/"
cp -r /var/lib/grafana "$BACKUP_DIR/"
cp -r /etc/nginx/sites-available/observability "$BACKUP_DIR/"

# 3. Validate config before reinstall
./observability config validate

# 4. Force reinstall
./observability setup --observability --force

# 5. If data needs recovery, restore from backup
# (Grafana dashboards, Prometheus data, etc.)
systemctl stop grafana-server
cp -r "$BACKUP_DIR/grafana/" /var/lib/
chown -R grafana:grafana /var/lib/grafana
systemctl start grafana-server
```

#### Restore from Backups

Automatic backups are created in `/var/backups/observability-stack/` before each setup run.

```bash
# List available backups
ls -la /var/backups/observability-stack/

# Restore specific service config
BACKUP_TIME="20241225_143022"  # Choose from ls output

# Restore Prometheus config
systemctl stop prometheus
cp /var/backups/observability-stack/$BACKUP_TIME/prometheus.yml /etc/prometheus/
systemctl start prometheus

# Restore Grafana settings
systemctl stop grafana-server
cp /var/backups/observability-stack/$BACKUP_TIME/grafana.ini /etc/grafana/
systemctl start grafana-server
```

#### Rollback Procedure

```bash
# 1. Uninstall current setup (keeps data)
./observability setup --observability --uninstall

# 2. Restore from specific backup
BACKUP_TIME="20241225_143022"
BACKUP="/var/backups/observability-stack/$BACKUP_TIME"

# 3. Copy configs back
cp -r "$BACKUP/prometheus.yml" /etc/prometheus/
cp -r "$BACKUP/alertmanager.yml" /etc/alertmanager/
cp -r "$BACKUP/grafana.ini" /etc/grafana/
# ... restore other configs as needed

# 4. Restart services
systemctl daemon-reload
systemctl restart prometheus alertmanager loki grafana-server nginx
```

### Emergency Commands

**Quick Health Check**
```bash
./observability health --verbose
```

**Reset Grafana Admin Password**
```bash
systemctl stop grafana-server
grafana-cli admin reset-admin-password NEW_PASSWORD
systemctl start grafana-server
```

**Force Regenerate All Configs**
```bash
./scripts/module-manager.sh generate-config --force
systemctl reload prometheus
systemctl restart grafana-server
```

**Clear Prometheus Data and Start Fresh**
```bash
# WARNING: This deletes all metrics!
systemctl stop prometheus
rm -rf /var/lib/prometheus/*
systemctl start prometheus
```

**Test Alert Delivery**
```bash
# Send test alert to Alertmanager
curl -X POST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {"alertname":"TestAlert","severity":"warning"},
    "annotations": {"summary":"This is a test alert"}
  }]'

# Check if email was sent (check logs)
journalctl -u alertmanager -n 100 | grep -i smtp
```

### Getting Help

**Collect Diagnostic Information**
```bash
# Service status
systemctl status prometheus alertmanager loki grafana-server nginx > /tmp/diagnostic.txt

# Recent logs
journalctl -u prometheus -n 100 --no-pager >> /tmp/diagnostic.txt
journalctl -u alertmanager -n 100 --no-pager >> /tmp/diagnostic.txt

# Configuration
./observability config validate >> /tmp/diagnostic.txt

# System info
df -h >> /tmp/diagnostic.txt
free -h >> /tmp/diagnostic.txt
uname -a >> /tmp/diagnostic.txt

# Network connectivity
./observability preflight --observability-vps >> /tmp/diagnostic.txt

# Share /tmp/diagnostic.txt for support
```

## License

MIT
