# Exporter Auto-Discovery and Configuration System

## Overview

Complete intelligent system for detecting, installing, and configuring Prometheus exporters across your observability infrastructure. This system eliminates manual exporter setup and ensures consistent monitoring coverage.

## Deliverables

### 1. Core Scripts

#### `/scripts/observability/detect-exporters.sh` (30KB)
**Main detection and orchestration engine**

Features:
- Automatic service detection (nginx, mysql, postgresql, mongodb, redis, php-fpm, etc.)
- Exporter installation status checking
- Prometheus configuration validation
- Missing exporter identification
- Dry-run mode for safe preview
- JSON output for automation
- Auto-configuration and installation capabilities

Usage:
```bash
./detect-exporters.sh                    # Scan and report
./detect-exporters.sh --verbose          # Detailed output
./detect-exporters.sh --install          # Install missing exporters
./detect-exporters.sh --auto-configure   # Update Prometheus config
./detect-exporters.sh --format json      # JSON output
```

#### `/scripts/observability/install-exporter.sh` (20KB)
**Automated exporter installer with security**

Features:
- Downloads from official GitHub releases
- SHA256 checksum verification
- Systemd service creation with hardening
- Configuration file generation
- Post-installation verification
- Support for 7+ exporters

Usage:
```bash
sudo ./install-exporter.sh node_exporter
sudo ./install-exporter.sh mysqld_exporter --verify
sudo ./install-exporter.sh nginx_exporter --dry-run
```

Supported exporters:
- node_exporter (system metrics)
- nginx_exporter (web server)
- mysqld_exporter (MySQL/MariaDB)
- postgres_exporter (PostgreSQL)
- redis_exporter (Redis cache)
- phpfpm_exporter (PHP-FPM)
- mongodb_exporter (MongoDB)

#### `/scripts/observability/generate-prometheus-config.sh` (13KB)
**Dynamic Prometheus configuration generator**

Features:
- Multi-host support
- Automatic exporter detection on remote hosts
- Template-based configuration
- Configuration merging
- Validation with promtool

Usage:
```bash
./generate-prometheus-config.sh --host localhost
./generate-prometheus-config.sh --host mentat.arewel.com --host landsraad.arewel.com
./generate-prometheus-config.sh --host localhost --output prometheus.yml
./generate-prometheus-config.sh --merge --output /etc/prometheus/prometheus.yml
```

### 2. Health Check Integration

**Enhanced `/chom/scripts/health-check-enhanced.sh`**

Added features:
- Optional exporter detection scanning
- Automatic remediation capability
- Node exporter health checks
- Integration with detect-exporters.sh

Usage:
```bash
RUN_EXPORTER_SCAN=true ./health-check-enhanced.sh
RUN_EXPORTER_SCAN=true AUTO_REMEDIATE=true ./health-check-enhanced.sh
```

### 3. Documentation

#### `/docs/EXPORTER_AUTO_DISCOVERY.md` (comprehensive guide)
Complete 400+ line documentation including:
- Architecture diagrams
- Component descriptions
- 5 detailed usage scenarios
- Configuration examples
- Troubleshooting guide
- Security best practices
- CI/CD integration examples

#### `/scripts/observability/QUICK_START.md`
Quick reference guide for getting started in 5 minutes

#### `/scripts/observability/README.md` (existing)
Troubleshooting system documentation with auto-remediation

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Detection & Discovery                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    │
│  │   Service    │───▶│   Exporter   │───▶│  Prometheus  │    │
│  │  Detection   │    │   Discovery  │    │    Config    │    │
│  └──────────────┘    └──────────────┘    └──────────────┘    │
│         │                    │                    │            │
│         ▼                    ▼                    ▼            │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    │
│  │   Missing    │───▶│ Installation │───▶│ Verification │    │
│  │  Exporters   │    │  & Setup     │    │  & Health    │    │
│  └──────────────┘    └──────────────┘    └──────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Detection Logic

```
Service Running → Exporter Needed → Status Check → Action
────────────────────────────────────────────────────────────
Nginx:80        → nginx_exporter   → Port 9113    → ✓ OK
MySQL:3306      → mysqld_exporter  → MISSING      → Install + Configure
PostgreSQL:5432 → postgres_exp     → NOT IN PROM  → Add Prometheus Target
Redis:6379      → redis_exporter   → Port 9121    → ✓ OK
PHP-FPM         → phpfpm_exporter  → Port 9253    → ✓ OK
System          → node_exporter    → Port 9100    → ✓ OK
```

## Key Features

### 1. Service Detection Methods
- Command existence checking (nginx, mysql, psql, etc.)
- Systemd service status verification
- Port listening detection (80, 3306, 5432, etc.)
- Configuration file presence (/etc/nginx/nginx.conf, etc.)

### 2. Exporter Management
- Binary installation status
- Service running verification
- Metrics endpoint accessibility
- Prometheus target configuration

### 3. Security Best Practices
- Dedicated system users (no shell, no home directory)
- Checksum verification for downloads
- Systemd hardening (ProtectSystem, NoNewPrivileges)
- Credential file protection (mode 600)

### 4. Safety Features
- Dry-run mode by default
- Configuration backups before changes
- Comprehensive logging
- Rollback capability
- Exit codes for automation

## Usage Scenarios

### Scenario 1: New VPS Setup
```bash
# 1. Scan system
./detect-exporters.sh

# 2. Install all recommended exporters
sudo ./detect-exporters.sh --install

# 3. Generate Prometheus config
./generate-prometheus-config.sh --host $(hostname) --output prometheus.yml

# 4. Deploy to Prometheus server
scp prometheus.yml mentat.arewel.com:/etc/prometheus/
```

### Scenario 2: Add Monitoring to Existing Service
```bash
# MySQL just installed
./detect-exporters.sh  # Shows mysqld_exporter needed
sudo ./install-exporter.sh mysqld_exporter
./generate-prometheus-config.sh --host localhost --merge
```

### Scenario 3: Multi-Host Deployment
```bash
./generate-prometheus-config.sh \
  --host mentat.arewel.com \
  --host landsraad.arewel.com \
  --output /etc/prometheus/prometheus.yml
```

### Scenario 4: CI/CD Integration
```yaml
# In GitHub Actions
- name: Setup Observability
  run: |
    ./scripts/observability/detect-exporters.sh --format json > status.json
    if [ $(jq '.summary.missing_exporters' status.json) -gt 0 ]; then
      sudo ./scripts/observability/detect-exporters.sh --install
    fi
```

### Scenario 5: Automated Health Monitoring
```bash
# Cron job with auto-remediation
*/15 * * * * RUN_EXPORTER_SCAN=true AUTO_REMEDIATE=true /path/to/health-check-enhanced.sh
```

## Quick Start

```bash
# 1. Make scripts executable
cd /home/calounx/repositories/mentat/scripts/observability
chmod +x detect-exporters.sh install-exporter.sh generate-prometheus-config.sh

# 2. Scan your system (30 seconds)
./detect-exporters.sh

# 3. Install missing exporters (2 minutes)
sudo ./detect-exporters.sh --install

# 4. Update Prometheus config (1 minute)
./generate-prometheus-config.sh --host $(hostname)

# 5. Verify (30 seconds)
./detect-exporters.sh --format json | jq '.summary'
```

## Integration Points

### Health Checks
```bash
RUN_EXPORTER_SCAN=true AUTO_REMEDIATE=true ./health-check-enhanced.sh
```

### Deployment Scripts
```bash
# Add to deploy.sh
./scripts/observability/detect-exporters.sh --auto-configure
```

### Monitoring Alerts
```bash
# Alertmanager webhook
./scripts/observability/detect-exporters.sh --exporter $EXPORTER --install
```

## File Structure

```
mentat/
├── scripts/observability/
│   ├── detect-exporters.sh              # Main detection engine (30KB)
│   ├── install-exporter.sh              # Installer with verification (20KB)
│   ├── generate-prometheus-config.sh    # Config generator (13KB)
│   ├── QUICK_START.md                   # Quick reference
│   ├── README.md                        # Troubleshooting guide
│   └── templates/                       # Configuration templates
│
├── chom/scripts/
│   └── health-check-enhanced.sh         # Enhanced with exporter checks
│
└── docs/
    └── EXPORTER_AUTO_DISCOVERY.md       # Complete documentation (400+ lines)
```

## Exporter Port Reference

| Exporter | Port | Service | Config Required |
|----------|------|---------|-----------------|
| node_exporter | 9100 | System | No |
| nginx_exporter | 9113 | Nginx | stub_status |
| mysqld_exporter | 9104 | MySQL | .my.cnf |
| postgres_exporter | 9187 | PostgreSQL | DSN |
| redis_exporter | 9121 | Redis | No |
| phpfpm_exporter | 9253 | PHP-FPM | status page |
| mongodb_exporter | 9216 | MongoDB | Connection URI |

## Troubleshooting

### Quick Diagnostics
```bash
# Check all exporters
systemctl list-units '*_exporter.service'

# Test metrics endpoints
for port in 9100 9113 9104 9121; do
  curl -sf http://localhost:${port}/metrics >/dev/null && echo "Port $port: OK"
done

# View Prometheus targets
curl http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | "\(.labels.job): \(.health)"'
```

### Common Issues

1. **Exporter not starting**
   - Check logs: `journalctl -u <exporter> -n 50`
   - Verify binary: `ls -la /usr/local/bin/<exporter>`
   - Reinstall: `sudo ./install-exporter.sh <exporter> --force`

2. **Metrics not accessible**
   - Check service: `systemctl status <exporter>`
   - Check port: `ss -tulpn | grep <port>`
   - Test: `curl http://localhost:<port>/metrics`

3. **Prometheus not scraping**
   - Validate config: `promtool check config prometheus.yml`
   - Reload: `systemctl reload prometheus`
   - Check connectivity: `curl http://target:port/metrics`

## Benefits

1. **Time Savings**: Reduces manual setup from hours to minutes
2. **Consistency**: Ensures uniform configuration across hosts
3. **Reliability**: Automated installation reduces human error
4. **Security**: Best practices built-in (checksums, hardening, permissions)
5. **Maintainability**: Single source of truth for exporter configuration
6. **Scalability**: Easy to deploy across multiple servers

## Next Steps

1. **Initial Deployment**
   - Run `detect-exporters.sh` on each VPS
   - Install missing exporters
   - Update Prometheus configuration

2. **Integration**
   - Add to deployment scripts
   - Enable health check integration
   - Set up automated monitoring

3. **Monitoring**
   - Create Prometheus alert rules
   - Set up Grafana dashboards
   - Configure Alertmanager

4. **Maintenance**
   - Regular exporter updates
   - Configuration drift detection
   - Performance optimization

## Support

- Full documentation: `/docs/EXPORTER_AUTO_DISCOVERY.md`
- Quick start: `/scripts/observability/QUICK_START.md`
- Troubleshooting: `/scripts/observability/README.md`
- Script help: `./detect-exporters.sh --help`

## Version

- Version: 1.0.0
- Date: 2026-01-02
- Status: Production Ready
