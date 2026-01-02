# Automated Exporter Troubleshooting System

Comprehensive diagnostics and auto-remediation system for Prometheus exporter issues.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Diagnostic Capabilities](#diagnostic-capabilities)
- [Auto-Remediation](#auto-remediation)
- [Examples](#examples)
- [Integration](#integration)
- [Troubleshooting](#troubleshooting)

## Overview

The automated troubleshooting system detects, diagnoses, and fixes common exporter issues including:
- Silent failures
- Configuration drift
- Network and firewall issues
- Permission problems
- Service crashes
- Resource exhaustion

## Features

### Diagnostic Modes

1. **Quick Scan** (< 30 seconds)
   - Service status checks
   - Port accessibility
   - Metrics endpoint validation
   - Prometheus target verification

2. **Deep Diagnostics** (comprehensive)
   - All quick scan checks
   - Permission analysis
   - Resource usage monitoring
   - Crash log analysis
   - Configuration validation
   - Security policy checks (SELinux/AppArmor)

### Auto-Discovery

- Automatic exporter discovery
- Service detection (MySQL, Redis, Nginx, etc.)
- Missing exporter identification
- Configuration drift detection

### Multi-Host Support

- Parallel host checking
- SSH-based remote diagnostics
- Configurable parallelism
- Aggregated reporting

### Safety Features

- Dry-run mode by default
- Configuration backups before changes
- Rollback capability
- Detailed logging

## Installation

### Prerequisites

```bash
# Required tools
sudo apt-get install -y curl netstat ss systemd

# Optional for enhanced features
sudo apt-get install -y bc firewalld ufw
```

### Setup

```bash
# Make scripts executable
chmod +x /home/calounx/repositories/mentat/scripts/observability/troubleshoot-exporters.sh
chmod +x /home/calounx/repositories/mentat/scripts/observability/quick-check.sh
chmod +x /home/calounx/repositories/mentat/scripts/observability/lib/diagnostic-helpers.sh

# Create prometheus user if not exists
sudo useradd --system --no-create-home --shell /bin/false prometheus
```

## Usage

### Basic Usage

```bash
# Quick scan of all exporters
./troubleshoot-exporters.sh --quick

# Deep diagnostics
./troubleshoot-exporters.sh --deep

# Check specific exporter
./troubleshoot-exporters.sh --exporter node_exporter

# Apply fixes automatically
./troubleshoot-exporters.sh --apply-fix

# Install missing exporters
./troubleshoot-exporters.sh --install-missing
```

### Multi-Host Diagnostics

```bash
# Check multiple hosts in parallel
./troubleshoot-exporters.sh --multi-host --remote host1,host2,host3

# Control parallelism
./troubleshoot-exporters.sh --multi-host --remote host1,host2,host3 --parallel 8

# Check remote host
./troubleshoot-exporters.sh --remote server.example.com
```

### Advanced Options

```bash
# Verbose output with logging
./troubleshoot-exporters.sh --deep --verbose --log /var/log/exporter-diagnostics.log

# JSON output for automation
./troubleshoot-exporters.sh --output json

# Combined options
./troubleshoot-exporters.sh --deep --apply-fix --install-missing --verbose
```

## Diagnostic Capabilities

### Network Diagnostics

The system checks:

1. **Port Listening**
   - Verifies exporter is bound to correct port
   - Detects bind address issues (127.0.0.1 vs 0.0.0.0)
   - Identifies port conflicts

2. **Firewall Rules**
   - Checks firewalld, UFW, iptables
   - Detects blocked ports
   - Auto-fix: Opens required ports

3. **Connectivity**
   - Tests metrics endpoint accessibility
   - Validates HTTP responses
   - DNS resolution checks

4. **Bind Address Issues**
   - Detects localhost-only binding
   - Auto-fix: Updates systemd service to bind 0.0.0.0
   - Restarts service safely

### Permission Diagnostics

The system checks:

1. **File Permissions**
   - Configuration file readability
   - Credentials file access
   - Log directory write permissions

2. **Process Permissions**
   - Service user validation
   - Resource access (e.g., /proc, /sys for node_exporter)
   - MySQL/Redis connection permissions

3. **Security Policies**
   - SELinux denials
   - AppArmor profile conflicts
   - Systemd security restrictions

4. **Auto-Fixes**
   - Sets correct file ownership
   - Adjusts permissions (600 for credentials)
   - Recommends policy changes

### Service Diagnostics

The system checks:

1. **Service State**
   - Running/stopped status
   - Auto-start configuration
   - Systemd service health

2. **Crash Detection**
   - Analyzes journalctl logs
   - Detects segfaults, OOM kills
   - Exit code analysis

3. **Resource Usage**
   - CPU utilization
   - Memory consumption
   - Process limits

4. **Auto-Fixes**
   - Starts stopped services
   - Enables auto-start
   - Restarts crashed services

### Configuration Diagnostics

The system checks:

1. **Exporter Configuration**
   - Command-line flags
   - Configuration files
   - Credentials validity

2. **Prometheus Integration**
   - Target configuration
   - Scrape job validation
   - Label consistency

3. **Service-Specific**
   - Nginx stub_status
   - MySQL user grants
   - PHP-FPM status page
   - Redis connectivity

4. **Auto-Fixes**
   - Adds missing Prometheus targets
   - Updates configuration files
   - Reloads services

## Auto-Remediation

### Supported Fixes

| Issue | Detection | Auto-Fix |
|-------|-----------|----------|
| Service not running | systemctl status | systemctl start |
| Auto-start disabled | systemctl is-enabled | systemctl enable |
| Port blocked by firewall | firewall rules check | firewall-cmd/ufw allow |
| Wrong bind address | netstat/ss analysis | Update systemd service |
| Not in Prometheus config | prometheus.yml parsing | Add target configuration |
| File permissions | Access tests | chown/chmod |
| Missing binary | File existence | Install from GitHub |
| Crashed service | Log analysis | Restart service |

### Safety Mechanisms

1. **Dry-Run Default**
   ```bash
   # Shows what would be done, doesn't execute
   ./troubleshoot-exporters.sh --deep

   # Actually applies fixes
   ./troubleshoot-exporters.sh --apply-fix
   ```

2. **Configuration Backups**
   ```bash
   # Automatic backups before changes
   /etc/prometheus/prometheus.yml.bak.1234567890
   /etc/systemd/system/nginx_exporter.service.bak.1234567890
   ```

3. **Rollback**
   ```bash
   # Manual rollback if needed
   cp /etc/prometheus/prometheus.yml.bak.1234567890 /etc/prometheus/prometheus.yml
   systemctl reload prometheus
   ```

## Examples

### Example 1: Quick Health Check

```bash
$ ./troubleshoot-exporters.sh --quick

================================================================================
  Exporter Troubleshooting System
================================================================================

▶ Diagnostics: node_exporter
────────────────────────────────────────────────────────────────────────────────
  ✓ node_exporter: Service running
  ✓ node_exporter: Binary installed
  ✓ node_exporter: Port 9100 listening
  ✓ node_exporter: Port 9100 accessible
  ✓ node_exporter: Metrics endpoint responding
  ✓ node_exporter: Configured in Prometheus

▶ Diagnostics: nginx_exporter
────────────────────────────────────────────────────────────────────────────────
  ✗ nginx_exporter: Service inactive
  ✓ nginx_exporter: Binary installed
  ✗ nginx_exporter: Port 9113 not listening
  ✓ nginx_exporter: Port 9113 accessible
  ✗ nginx_exporter: Metrics endpoint failed
  ⚠ nginx_exporter: Not in Prometheus configuration

================================================================================
  DIAGNOSTIC SUMMARY
================================================================================

Scan completed in 12s
Total checks: 2
Total issues: 4

Exporter Status:
────────────────────────────────────────────────────────────────────────────────
✓ node_exporter
✗ nginx_exporter
    Issues: Service not running: inactive Port 9113 not listening
    Fixes: systemctl start nginx_exporter add_prometheus_target nginx_exporter localhost 9113

▶ Recommendations
────────────────────────────────────────────────────────────────────────────────
  → Run with --apply-fix to auto-remediate issues
  → Run with --deep for comprehensive diagnostics
  → Check logs with: journalctl -u nginx_exporter -n 50
```

### Example 2: Apply Automatic Fixes

```bash
$ ./troubleshoot-exporters.sh --exporter nginx_exporter --apply-fix

▶ Auto-Remediation: nginx_exporter
────────────────────────────────────────────────────────────────────────────────
  ✓ nginx_exporter: Applied fix: systemctl start nginx_exporter
  ✓ nginx_exporter: Applied fix: systemctl enable nginx_exporter
  ✓ nginx_exporter: Applied fix: add_prometheus_target nginx_exporter localhost 9113

Total fixes applied: 3
```

### Example 3: Multi-Host Check

```bash
$ ./troubleshoot-exporters.sh --multi-host --remote web1,web2,db1

================================================================================
  Multi-Host Diagnostics
================================================================================

▶ Host: web1
────────────────────────────────────────────────────────────────────────────────
  ✓ web1: SSH connection established
  ✓ node_exporter: Service running
  ✓ nginx_exporter: Service running
  ✗ mysql_exporter: Not installed

▶ Host: web2
────────────────────────────────────────────────────────────────────────────────
  ✓ web2: SSH connection established
  ✓ node_exporter: Service running
  ✓ nginx_exporter: Service running

▶ Host: db1
────────────────────────────────────────────────────────────────────────────────
  ✓ db1: SSH connection established
  ✓ node_exporter: Service running
  ✓ mysql_exporter: Service running
```

### Example 4: Deep Diagnostics with Verbose Output

```bash
$ ./troubleshoot-exporters.sh --deep --exporter mysql_exporter --verbose

[2026-01-02 10:30:45] [INFO] Running diagnostics for mysql_exporter on localhost
[2026-01-02 10:30:45] [DEBUG] Checking service status...
[2026-01-02 10:30:45] [DEBUG] Checking binary existence...
[2026-01-02 10:30:45] [DEBUG] Checking port 9104...
[2026-01-02 10:30:46] [DEBUG] Checking metrics endpoint...
[2026-01-02 10:30:46] [DEBUG] Checking Prometheus configuration...
[2026-01-02 10:30:46] [DEBUG] Checking permissions...
[2026-01-02 10:30:47] [WARN] Permission issues: MySQL credentials file not readable
[2026-01-02 10:30:47] [DEBUG] Checking resource usage...
[2026-01-02 10:30:47] [INFO] Diagnostics complete: 1 issues found
```

## Integration

### With Existing Health Checks

```bash
# Add to existing health check script
/home/calounx/repositories/mentat/scripts/observability/quick-check.sh
exit_code=$?

if [ $exit_code -ne 0 ]; then
    echo "Exporter issues detected!"
    # Trigger alerts or auto-remediation
fi
```

### Cron Job for Scheduled Monitoring

```bash
# Add to crontab: Check every 5 minutes
*/5 * * * * /home/calounx/repositories/mentat/scripts/observability/quick-check.sh --log /var/log/exporter-check.log

# Deep scan daily at 2 AM
0 2 * * * /home/calounx/repositories/mentat/scripts/observability/troubleshoot-exporters.sh --deep --apply-fix --log /var/log/exporter-fix.log
```

### Alert Handler Integration

```bash
# Alertmanager webhook receiver
#!/bin/bash
# When alert fires, run diagnostics and attempt fix

ALERT_NAME="$1"
EXPORTER="$2"

if [[ "$ALERT_NAME" == "ExporterDown" ]]; then
    /home/calounx/repositories/mentat/scripts/observability/troubleshoot-exporters.sh \
        --exporter "$EXPORTER" \
        --apply-fix \
        --log "/var/log/auto-remediation-${EXPORTER}.log"
fi
```

### Systemd Service

```bash
# Create systemd service for continuous monitoring
# /etc/systemd/system/exporter-watchdog.service

[Unit]
Description=Exporter Health Watchdog
After=network-online.target

[Service]
Type=simple
ExecStart=/home/calounx/repositories/mentat/scripts/observability/troubleshoot-exporters.sh --quick --apply-fix
Restart=always
RestartSec=300

[Install]
WantedBy=multi-user.target
```

## Troubleshooting

### Common Issues

#### 1. "Diagnostic library not found"

```bash
# Ensure library exists
ls -la /home/calounx/repositories/mentat/scripts/observability/lib/diagnostic-helpers.sh

# Make executable
chmod +x /home/calounx/repositories/mentat/scripts/observability/lib/diagnostic-helpers.sh
```

#### 2. "SSH connection failed" for multi-host

```bash
# Setup SSH key authentication
ssh-copy-id user@remote-host

# Test connection
ssh remote-host "echo ok"
```

#### 3. "Permission denied" when applying fixes

```bash
# Run with sudo for system changes
sudo ./troubleshoot-exporters.sh --apply-fix

# Or grant specific sudo permissions
# Add to /etc/sudoers.d/prometheus-tools:
# prometheus ALL=(ALL) NOPASSWD: /bin/systemctl, /usr/bin/firewall-cmd
```

#### 4. "Prometheus config not found"

```bash
# Update diagnostic-helpers.sh with your Prometheus config path
# Edit the prom_configs array in get_prometheus_config_path()
```

### Debug Mode

```bash
# Enable verbose logging
./troubleshoot-exporters.sh --verbose --log /tmp/debug.log

# Check script execution
bash -x ./troubleshoot-exporters.sh --quick
```

### Manual Testing

```bash
# Test individual diagnostic functions
source /home/calounx/repositories/mentat/scripts/observability/lib/diagnostic-helpers.sh

# Test service check
check_service_status "node_exporter"

# Test port check
check_port_listening 9100

# Test metrics endpoint
check_metrics_endpoint "localhost" 9100 "/metrics"
```

## Directory Structure

```
scripts/observability/
├── troubleshoot-exporters.sh          # Main troubleshooting script
├── quick-check.sh                      # Quick health check wrapper
├── lib/
│   └── diagnostic-helpers.sh           # Diagnostic function library
├── templates/
│   ├── systemd/                        # Systemd service templates
│   │   ├── node_exporter.service
│   │   ├── nginx_exporter.service
│   │   ├── mysqld_exporter.service
│   │   ├── redis_exporter.service
│   │   └── phpfpm_exporter.service
│   └── config/                         # Configuration templates
│       ├── mysqld_exporter.cnf
│       ├── nginx-stub-status.conf
│       └── php-fpm-status.conf
└── README.md                           # This file
```

## Supported Exporters

| Exporter | Port | Service Detection | Auto-Install | Config Template |
|----------|------|-------------------|--------------|-----------------|
| node_exporter | 9100 | ✓ | Planned | ✓ |
| nginx_exporter | 9113 | ✓ | Planned | ✓ |
| mysqld_exporter | 9104 | ✓ | Planned | ✓ |
| redis_exporter | 9121 | ✓ | Planned | ✓ |
| phpfpm_exporter | 9253 | ✓ | Planned | ✓ |
| postgres_exporter | 9187 | ✓ | Planned | - |
| apache_exporter | 9117 | ✓ | Planned | - |
| blackbox_exporter | 9115 | ✓ | Planned | - |
| promtail | 9080 | ✓ | Planned | - |

## Contributing

To add support for a new exporter:

1. Add entry to `EXPORTER_CONFIG` in `troubleshoot-exporters.sh`
2. Add service detection in `discover_services_needing_exporters()`
3. Add exporter-specific checks in `check_permissions()`
4. Create systemd service template in `templates/systemd/`
5. Create configuration template in `templates/config/` if needed

## License

Part of the Mentat project.

## Support

For issues or questions:
1. Check this README
2. Review script logs with `--verbose --log`
3. Test individual functions manually
4. Check GitHub issues

## Version History

- v1.0.0 (2026-01-02): Initial release
  - Quick and deep diagnostic modes
  - Auto-remediation capabilities
  - Multi-host support
  - 9 supported exporters
  - Comprehensive documentation
