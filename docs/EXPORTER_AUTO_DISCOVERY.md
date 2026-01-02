# Exporter Auto-Discovery and Configuration System

Complete guide for the intelligent exporter auto-discovery and configuration system.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Core Components](#core-components)
- [Usage Scenarios](#usage-scenarios)
- [Configuration](#configuration)
- [Advanced Features](#advanced-features)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Overview

The Exporter Auto-Discovery System provides intelligent detection, installation, and configuration of Prometheus exporters across your infrastructure. It eliminates manual exporter setup and ensures consistent observability coverage.

### Key Features

- **Automatic Service Detection**: Scans for running services (nginx, mysql, postgresql, mongodb, redis, PHP-FPM, etc.)
- **Smart Exporter Mapping**: Automatically determines which exporters are needed for detected services
- **Installation Automation**: Downloads, verifies, and installs missing exporters with security best practices
- **Configuration Generation**: Creates Prometheus scrape configs and systemd services
- **Health Integration**: Integrates with existing health check scripts
- **Multi-Host Support**: Manages exporters across multiple VPS servers

### Detection Logic Example

```
Service Detected → Exporter Needed → Status Check → Action
─────────────────────────────────────────────────────────────
Nginx:80        → nginx_exporter   → Port 9113    → ✓ OK
MySQL:3306      → mysqld_exporter  → MISSING      → Install + Configure
PostgreSQL:5432 → postgres_exp     → NOT IN PROM  → Add Prometheus Target
Redis:6379      → redis_exporter   → Port 9121    → ✓ OK
System          → node_exporter    → Port 9100    → ✓ OK
```

## Quick Start

### 1. Basic Detection

Scan your system to see what services and exporters exist:

```bash
cd /home/calounx/repositories/mentat/scripts/observability

# Simple scan
./detect-exporters.sh

# Verbose output
./detect-exporters.sh --verbose

# JSON output for automation
./detect-exporters.sh --format json
```

**Example Output:**
```
===============================================================================
  EXPORTER AUTO-DISCOVERY REPORT
===============================================================================

Hostname: landsraad.arewel.com
Date: 2026-01-02 10:00:00

DETECTED SERVICES (5)
-------------------------------------------------------------------------------
  ✓ system
      Info: type=node
      Exporter: node_exporter
  ✓ nginx
      Info: version=1.24.0,port=80
      Exporter: nginx_exporter
  ✓ mysql
      Info: version=8.0.35,port=3306
      Exporter: mysqld_exporter
  ✓ redis
      Info: version=7.0.12,port=6379
      Exporter: redis_exporter
  ✓ php-fpm
      Info: version=8.2.15,socket=/var/run/php/php8.2-fpm.sock
      Exporter: phpfpm_exporter

EXPORTER STATUS
-------------------------------------------------------------------------------
Installed and Running:
  ✓ node_exporter (port 9100)
  ✓ nginx_exporter (port 9113)
      ⚠ Missing from Prometheus config

Missing Exporters (service running but no exporter):
  ✗ mysqld_exporter
      Needed for: service=mysql
  ✗ redis_exporter
      Needed for: service=redis
  ✗ phpfpm_exporter
      Needed for: service=php-fpm

RECOMMENDATIONS
-------------------------------------------------------------------------------
Install missing exporters:
  ./detect-exporters.sh --install

Update Prometheus configuration:
  ./detect-exporters.sh --auto-configure
```

### 2. Install Missing Exporters

```bash
# Preview what would be installed (dry-run)
./detect-exporters.sh --install --dry-run

# Actually install missing exporters (requires sudo)
sudo ./detect-exporters.sh --install
```

### 3. Generate Prometheus Configuration

```bash
# Generate config for localhost
./generate-prometheus-config.sh --host localhost

# Generate for multiple hosts
./generate-prometheus-config.sh \
  --host mentat.arewel.com \
  --host landsraad.arewel.com \
  --output prometheus-auto.yml

# Merge with existing config
./generate-prometheus-config.sh \
  --host localhost \
  --merge \
  --output /etc/prometheus/prometheus.yml
```

### 4. Verify Installation

```bash
# Check all exporters are working
./detect-exporters.sh --verify

# Test specific exporter
curl http://localhost:9100/metrics | head -20

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq
```

## Architecture

### System Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    AUTO-DISCOVERY WORKFLOW                       │
└─────────────────────────────────────────────────────────────────┘

1. Service Detection
   ├── Command Existence (nginx, mysql, psql, etc.)
   ├── Systemd Service Status (active/inactive)
   ├── Port Listening (80, 3306, 5432, etc.)
   └── Configuration Files (/etc/nginx/nginx.conf, etc.)
          │
          ▼
2. Exporter Mapping
   ├── Service → Exporter Match (nginx → nginx_exporter)
   ├── Port Assignment (nginx_exporter → 9113)
   └── Configuration Requirements (mysqld_exporter → .my.cnf)
          │
          ▼
3. Status Validation
   ├── Binary Installation Check
   ├── Service Running Check
   ├── Metrics Endpoint Accessibility
   └── Prometheus Configuration Check
          │
          ▼
4. Auto-Remediation
   ├── Install Missing Exporters
   ├── Generate Configurations
   ├── Update Prometheus Scrape Configs
   └── Start/Enable Services
          │
          ▼
5. Verification
   ├── Metrics Collection Test
   ├── Prometheus Scraping Test
   └── Health Check Integration
```

### Component Interaction

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│ detect-exporters │────▶│ install-exporter │────▶│ generate-prom-   │
│ .sh              │     │ .sh              │     │ config.sh        │
└──────────────────┘     └──────────────────┘     └──────────────────┘
         │                        │                         │
         │                        │                         │
         ▼                        ▼                         ▼
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│ Service          │     │ Exporter         │     │ Prometheus       │
│ Detection Engine │     │ Installer        │     │ Config Generator │
└──────────────────┘     └──────────────────┘     └──────────────────┘
         │                        │                         │
         └────────────────────────┴─────────────────────────┘
                                  │
                                  ▼
                      ┌──────────────────────┐
                      │ Health Check         │
                      │ Integration          │
                      └──────────────────────┘
```

## Core Components

### 1. detect-exporters.sh

**Purpose**: Main detection and orchestration engine

**Key Functions:**
- `detect_all_services()` - Scans for running services
- `detect_all_exporters()` - Checks exporter installation/status
- `check_all_prometheus_targets()` - Validates Prometheus config
- `install_exporter()` - Installs missing exporters
- `generate_prometheus_scrape_config()` - Creates scrape configs

**Command Line Options:**
```bash
--scan              # Scan for services and exporters (default)
--auto-configure    # Apply configuration changes
--install           # Install missing exporters
--dry-run           # Preview without applying (default)
--format FORMAT     # Output: text, json
--prometheus-config # Path to prometheus.yml
--verbose           # Detailed output
```

**Exit Codes:**
- `0` - All systems operational
- `1` - Missing exporters or not running
- `2` - Configuration errors

### 2. install-exporter.sh

**Purpose**: Downloads and installs Prometheus exporters

**Installation Process:**
1. Fetch latest version from GitHub API
2. Download release archive
3. Verify SHA256 checksum
4. Extract and install binary
5. Create system user/group
6. Generate configuration files
7. Create systemd service with hardening
8. Enable and start service
9. Verify metrics endpoint

**Security Features:**
- Checksum verification
- Dedicated system users (no shell, no home)
- Systemd hardening (`ProtectSystem=strict`, `NoNewPrivileges=true`)
- Credential file permissions (mode 600)
- Private temp directories

**Supported Exporters:**
```bash
node_exporter       # System metrics
nginx_exporter      # Nginx web server
mysqld_exporter     # MySQL/MariaDB database
postgres_exporter   # PostgreSQL database
redis_exporter      # Redis cache
phpfpm_exporter     # PHP-FPM runtime
mongodb_exporter    # MongoDB NoSQL
```

### 3. generate-prometheus-config.sh

**Purpose**: Creates Prometheus scrape configurations

**Features:**
- Auto-detects exporters on target hosts
- Generates properly formatted scrape configs
- Supports multi-host deployments
- Merges with existing configurations
- Validates with promtool

**Configuration Template:**
```yaml
scrape_configs:
  - job_name: 'nginx-hostname'
    scrape_interval: 15s
    scrape_timeout: 10s
    static_configs:
      - targets: ['hostname:9113']
        labels:
          service: 'nginx'
          tier: 'webserver'
          host: 'hostname'
```

### 4. Health Check Integration

**Purpose**: Continuous monitoring of exporter health

**Environment Variables:**
```bash
RUN_EXPORTER_SCAN=true    # Enable exporter detection
AUTO_REMEDIATE=true       # Auto-fix issues
```

**Integration Example:**
```bash
# In health-check-enhanced.sh
RUN_EXPORTER_SCAN=true AUTO_REMEDIATE=true ./health-check-enhanced.sh
```

## Usage Scenarios

### Scenario 1: New VPS Setup

Setting up observability on a fresh VPS:

```bash
# 1. Initial scan
./detect-exporters.sh --verbose

# 2. Install all recommended exporters
sudo ./detect-exporters.sh --install

# 3. Generate Prometheus config
./generate-prometheus-config.sh \
  --host $(hostname) \
  --output /tmp/prometheus-new.yml

# 4. Review generated config
cat /tmp/prometheus-new.yml

# 5. Deploy to Prometheus server
scp /tmp/prometheus-new.yml mentat.arewel.com:/etc/prometheus/prometheus.yml
ssh mentat.arewel.com "sudo systemctl reload prometheus"

# 6. Verify targets
curl http://mentat.arewel.com:9090/api/v1/targets | jq '.data.activeTargets[] | {job, health}'
```

### Scenario 2: Add Service to Existing Server

You just installed MySQL on a server that already has monitoring:

```bash
# 1. Detect the new service
./detect-exporters.sh
# Output shows: "✗ mysqld_exporter - Needed for: service=mysql"

# 2. Install MySQL exporter
sudo ./install-exporter.sh mysqld_exporter

# 3. Configure MySQL user for monitoring
mysql -u root -p << 'EOF'
CREATE USER 'exporter'@'localhost' IDENTIFIED BY 'secure_password_here';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';
FLUSH PRIVILEGES;
EOF

# 4. Update exporter credentials
sudo vi /etc/mysqld_exporter/.my.cnf
# Update password

# 5. Restart exporter
sudo systemctl restart mysqld_exporter

# 6. Verify metrics
curl http://localhost:9104/metrics | grep mysql_up

# 7. Add to Prometheus
./generate-prometheus-config.sh --host localhost | grep -A 10 mysql
```

### Scenario 3: Multi-Host Deployment

Deploy monitoring across multiple servers:

```bash
# On observability server (mentat.arewel.com)

# 1. Generate unified config
./generate-prometheus-config.sh \
  --host mentat.arewel.com \
  --host landsraad.arewel.com \
  --output prometheus-multi.yml

# 2. Validate config
promtool check config prometheus-multi.yml

# 3. Backup existing config
sudo cp /etc/prometheus/prometheus.yml \
        /etc/prometheus/prometheus.yml.backup.$(date +%s)

# 4. Deploy new config
sudo cp prometheus-multi.yml /etc/prometheus/prometheus.yml

# 5. Reload Prometheus
sudo systemctl reload prometheus

# 6. Verify all targets
curl http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | {job, instance, health}' | \
  grep -v '"up"'
```

### Scenario 4: Automated Health Monitoring

Set up continuous monitoring with auto-remediation:

```bash
# 1. Create monitoring script
cat > /usr/local/bin/exporter-watchdog.sh << 'EOF'
#!/bin/bash
SCRIPT_DIR="/home/calounx/repositories/mentat/scripts/observability"

# Run detection with auto-remediation
RUN_EXPORTER_SCAN=true AUTO_REMEDIATE=true \
  "${SCRIPT_DIR}/../chom/scripts/health-check-enhanced.sh" \
  >> /var/log/exporter-watchdog.log 2>&1

# Check exit code
if [ $? -ne 0 ]; then
  # Alert via webhook or email
  curl -X POST https://alerts.example.com/webhook \
    -d '{"alert":"ExporterIssues","host":"'$(hostname)'"}'
fi
EOF

chmod +x /usr/local/bin/exporter-watchdog.sh

# 2. Create systemd service
sudo cat > /etc/systemd/system/exporter-watchdog.service << 'EOF'
[Unit]
Description=Exporter Health Watchdog
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/exporter-watchdog.sh
User=prometheus
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 3. Create timer (runs every 5 minutes)
sudo cat > /etc/systemd/system/exporter-watchdog.timer << 'EOF'
[Unit]
Description=Exporter Watchdog Timer
Requires=exporter-watchdog.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Unit=exporter-watchdog.service

[Install]
WantedBy=timers.target
EOF

# 4. Enable and start
sudo systemctl daemon-reload
sudo systemctl enable exporter-watchdog.timer
sudo systemctl start exporter-watchdog.timer

# 5. Check status
sudo systemctl list-timers exporter-watchdog.timer
```

### Scenario 5: CI/CD Integration

Integrate into deployment pipeline:

```yaml
# .github/workflows/deploy.yml
name: Deploy with Observability

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Deploy Application
        run: |
          # Your deployment steps here
          ./deploy.sh

      - name: Setup Observability
        run: |
          # Scan for services
          ./scripts/observability/detect-exporters.sh \
            --format json > exporters.json

          # Check if any exporters are missing
          MISSING=$(jq '.summary.missing_exporters' exporters.json)

          if [ "$MISSING" -gt 0 ]; then
            echo "Installing $MISSING missing exporter(s)"

            # Install missing exporters
            ssh ${{ secrets.VPS_HOST }} "sudo /path/to/detect-exporters.sh --install"
          fi

      - name: Update Prometheus
        run: |
          # Generate new config
          ./scripts/observability/generate-prometheus-config.sh \
            --host ${{ secrets.VPS_HOST }} \
            --output prometheus-new.yml

          # Deploy to Prometheus server
          scp prometheus-new.yml \
            ${{ secrets.PROMETHEUS_HOST }}:/etc/prometheus/prometheus.yml

          # Reload Prometheus
          ssh ${{ secrets.PROMETHEUS_HOST }} \
            "sudo systemctl reload prometheus"

      - name: Verify Metrics
        run: |
          # Wait for Prometheus to scrape
          sleep 30

          # Check target health
          curl -sf http://${{ secrets.PROMETHEUS_HOST }}:9090/api/v1/targets | \
            jq '.data.activeTargets[] | select(.health != "up")'
```

## Configuration

### Exporter Ports

Default ports used by exporters:

| Exporter | Port | Protocol |
|----------|------|----------|
| node_exporter | 9100 | HTTP |
| nginx_exporter | 9113 | HTTP |
| mysqld_exporter | 9104 | HTTP |
| postgres_exporter | 9187 | HTTP |
| redis_exporter | 9121 | HTTP |
| phpfpm_exporter | 9253 | HTTP |
| mongodb_exporter | 9216 | HTTP |

### Service-Specific Configuration

#### Nginx Exporter

Requires stub_status module:

```nginx
# /etc/nginx/conf.d/status.conf
server {
    listen 8080;
    server_name localhost;

    location /stub_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
```

Test: `curl http://127.0.0.1:8080/stub_status`

#### MySQL Exporter

Requires MySQL user with monitoring privileges:

```sql
CREATE USER 'exporter'@'localhost' IDENTIFIED BY 'secure_password';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';
FLUSH PRIVILEGES;
```

Config file: `/etc/mysqld_exporter/.my.cnf`
```ini
[client]
user=exporter
password=secure_password
host=127.0.0.1
port=3306
```

#### PostgreSQL Exporter

Requires connection string in environment:

```bash
# Edit systemd service
sudo systemctl edit postgres_exporter

[Service]
Environment="DATA_SOURCE_NAME=postgresql://exporter:password@localhost:5432/postgres?sslmode=disable"
```

#### PHP-FPM Exporter

Requires status page enabled:

```ini
# /etc/php/8.2/fpm/pool.d/www.conf
pm.status_path = /status
```

Test: `curl http://127.0.0.1:9000/status` (if using TCP)

## Advanced Features

### Custom Detection Rules

Extend detection for custom services:

```bash
# Add to detect-exporters.sh

detect_custom_app() {
    log_verbose "Detecting Custom Application..."

    if port_listening 8080 && [[ -f /etc/custom/app.conf ]]; then
        SERVICES_DETECTED[custom_app]="version=1.0,port=8080"
        SERVICES_COUNT=$((SERVICES_COUNT + 1))
        return 0
    fi
    return 1
}

# Add custom exporter mapping
get_exporter_for_service() {
    case "$service" in
        # ... existing cases ...
        custom_app) echo "custom_app_exporter" ;;
    esac
}
```

### Prometheus Federation

For large-scale deployments:

```yaml
# prometheus-federation.yml
scrape_configs:
  - job_name: 'federate'
    scrape_interval: 15s
    honor_labels: true
    metrics_path: '/federate'
    params:
      'match[]':
        - '{job=~"node.*"}'
        - '{job=~"nginx.*"}'
        - '{job=~"mysql.*"}'
    static_configs:
      - targets:
        - 'prometheus-region1:9090'
        - 'prometheus-region2:9090'
```

### Custom Metrics Relabeling

Modify labels for better organization:

```yaml
scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['host1:9100', 'host2:9100']
    metric_relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: '([^:]+):.*'
        replacement: '$1'
      - source_labels: [job]
        target_label: environment
        replacement: 'production'
```

## Troubleshooting

### Common Issues

#### Issue: Exporter not starting

**Symptoms:**
```bash
$ systemctl status node_exporter
● node_exporter.service - Prometheus Node Exporter
   Loaded: loaded
   Active: failed (Result: exit-code)
```

**Diagnosis:**
```bash
# Check logs
sudo journalctl -u node_exporter -n 50

# Check if port is in use
sudo ss -tulpn | grep 9100

# Verify binary
ls -la /usr/local/bin/node_exporter
/usr/local/bin/node_exporter --version
```

**Solutions:**
```bash
# Port conflict - change port
sudo systemctl edit node_exporter
[Service]
ExecStart=
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9101

# Permission issue - reinstall
sudo ./install-exporter.sh node_exporter --force

# Missing dependencies
sudo apt-get install -y libc6
```

#### Issue: Metrics not accessible

**Symptoms:**
```bash
$ curl http://localhost:9100/metrics
curl: (7) Failed to connect to localhost port 9100: Connection refused
```

**Diagnosis:**
```bash
# Check if service is running
systemctl is-active node_exporter

# Check bind address
sudo ss -tulpn | grep 9100
# Look for 127.0.0.1:9100 (local only) vs 0.0.0.0:9100 (all interfaces)

# Check firewall
sudo ufw status
sudo firewall-cmd --list-all
```

**Solutions:**
```bash
# Start service
sudo systemctl start node_exporter

# Fix bind address
sudo systemctl edit node_exporter
[Service]
ExecStart=
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9100

# Open firewall
sudo ufw allow 9100/tcp
sudo firewall-cmd --add-port=9100/tcp --permanent
sudo firewall-cmd --reload
```

#### Issue: Prometheus not scraping

**Symptoms:**
- Target shows as "DOWN" in Prometheus
- No metrics in Grafana dashboards

**Diagnosis:**
```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.job == "node")'

# Test from Prometheus server
curl http://target-host:9100/metrics

# Check Prometheus config
promtool check config /etc/prometheus/prometheus.yml
```

**Solutions:**
```bash
# Add target to Prometheus config
./generate-prometheus-config.sh --host target-host --merge

# Reload Prometheus
sudo systemctl reload prometheus

# Check connectivity
ping target-host
telnet target-host 9100
```

#### Issue: MySQL exporter shows mysql_up 0

**Symptoms:**
```bash
$ curl http://localhost:9104/metrics | grep mysql_up
mysql_up 0
```

**Diagnosis:**
```bash
# Check credentials
sudo cat /etc/mysqld_exporter/.my.cnf

# Test MySQL connection
mysql -u exporter -p -h 127.0.0.1 -e "SELECT 1"

# Check grants
mysql -u root -p -e "SHOW GRANTS FOR 'exporter'@'localhost'"

# Check logs
sudo journalctl -u mysqld_exporter -n 50
```

**Solutions:**
```bash
# Fix credentials
sudo vi /etc/mysqld_exporter/.my.cnf

# Recreate MySQL user
mysql -u root -p << 'EOF'
DROP USER IF EXISTS 'exporter'@'localhost';
CREATE USER 'exporter'@'localhost' IDENTIFIED BY 'new_password';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';
FLUSH PRIVILEGES;
EOF

# Update config and restart
sudo vi /etc/mysqld_exporter/.my.cnf
sudo systemctl restart mysqld_exporter
```

### Debug Mode

Enable verbose logging:

```bash
# Set debug environment variables
export VERBOSE=true
export DEBUG=true

# Run with verbose output
./detect-exporters.sh --verbose 2>&1 | tee debug.log

# Check specific function
bash -x ./detect-exporters.sh --verbose 2>&1 | grep "detect_mysql"
```

### Health Check Verification

```bash
# Manual health check
for port in 9100 9113 9104 9187 9121 9253; do
    echo "Testing port $port..."
    curl -sf http://localhost:${port}/metrics >/dev/null && \
        echo "  ✓ OK" || \
        echo "  ✗ FAILED"
done

# Automated check
./detect-exporters.sh --format json | \
    jq -r '.exporters.running[]'
```

## Best Practices

### 1. Security

**Always use dedicated users:**
```bash
# Exporters run as system users
id node_exporter
# uid=999(node_exporter) gid=999(node_exporter) groups=999(node_exporter)
```

**Protect credentials:**
```bash
# MySQL exporter config should be:
ls -la /etc/mysqld_exporter/.my.cnf
# -rw------- 1 mysqld_exporter mysqld_exporter 89 Jan 02 10:00 .my.cnf
```

**Use firewall rules:**
```bash
# Allow only Prometheus server
sudo ufw allow from prometheus-server-ip to any port 9100 proto tcp
sudo ufw deny 9100/tcp
```

### 2. Resource Management

**Monitor exporter resource usage:**
```bash
# Check memory usage
ps aux | grep exporter | awk '{print $2, $4, $11}' | column -t

# Set memory limits in systemd
sudo systemctl edit node_exporter
[Service]
MemoryLimit=100M
```

**Optimize scrape intervals:**
```yaml
# Adjust based on service type
scrape_configs:
  - job_name: 'node'
    scrape_interval: 15s    # System metrics
  - job_name: 'mysql'
    scrape_interval: 30s    # Database metrics
  - job_name: 'nginx'
    scrape_interval: 10s    # Web server metrics
```

### 3. Reliability

**Enable auto-restart:**
```ini
# All exporters should have:
[Service]
Restart=on-failure
RestartSec=5s
```

**Implement health monitoring:**
```bash
# Automated health checks
*/5 * * * * /usr/local/bin/exporter-health-check.sh
```

**Set up alerting:**
```yaml
# Prometheus alert rules
groups:
  - name: exporter_alerts
    rules:
      - alert: ExporterDown
        expr: up{job=~"node|nginx|mysql"} == 0
        for: 5m
        annotations:
          summary: "Exporter {{ $labels.job }} is down on {{ $labels.instance }}"
```

### 4. Documentation

**Keep inventory:**
```bash
# Create and maintain exporter inventory
./detect-exporters.sh --format json > /var/lib/prometheus/inventory.json

# Update after changes
git commit -am "Update exporter inventory"
```

**Document customizations:**
```bash
# Track custom configurations
echo "Custom stub_status location: /custom/status" >> /etc/nginx/README-monitoring.txt
```

### 5. Maintenance

**Regular updates:**
```bash
# Check for updates
./scripts/observability/check-exporter-versions.sh

# Update specific exporter
sudo ./install-exporter.sh node_exporter --version 1.8.0 --force
```

**Cleanup old exporters:**
```bash
# Remove deprecated exporters
sudo systemctl stop old_exporter
sudo systemctl disable old_exporter
sudo rm /etc/systemd/system/old_exporter.service
sudo systemctl daemon-reload
```

---

## Summary

The Exporter Auto-Discovery System provides:

- **Automation**: Reduces manual setup from hours to minutes
- **Reliability**: Ensures consistent configuration across hosts
- **Safety**: Dry-run mode and validation prevent mistakes
- **Flexibility**: Supports multiple deployment scenarios
- **Integration**: Works with existing health checks and CI/CD

For support or questions, refer to:
- Main README: `/scripts/observability/README.md`
- Troubleshooting guide: This document
- Script help: `./detect-exporters.sh --help`
