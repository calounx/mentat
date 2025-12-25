# Quick Start Guide

Get your observability stack running in 5 minutes.

## Prerequisites

- Debian 13 or Ubuntu 22.04+ server
- Root access
- Domain name pointing to your server (for Grafana)
- 20GB disk space, 2GB RAM (for observability VPS)
- 5GB disk space, 512MB RAM (for monitored hosts)

## Step 1: Clone Repository

```bash
git clone <repository-url> /opt/observability-stack
cd /opt/observability-stack
```

## Step 2: Configure

Edit the global configuration:

```bash
cp config/global.yaml.example config/global.yaml
nano config/global.yaml
```

**Required changes:**
- `network.observability_vps_ip`: Your VPS public IP
- `network.grafana_domain`: Your domain (e.g., monitor.example.com)
- `network.letsencrypt_email`: Your email for SSL notifications
- `smtp.username`: Your SMTP username (e.g., Brevo email)
- `smtp.password`: Your SMTP password (e.g., Brevo API key)
- `grafana.admin_password`: Strong password (16+ characters)
- `security.prometheus_basic_auth_password`: Strong password
- `security.loki_basic_auth_password`: Strong password

## Step 3: Pre-flight Check

Verify your system meets requirements:

```bash
./observability preflight --observability-vps
```

Fix any issues before proceeding.

## Step 4: Validate Configuration

```bash
./observability config validate
```

Make sure there are no errors.

## Step 5: Setup Observability VPS

```bash
./observability setup --observability
```

This will:
- Install Prometheus, Loki, Grafana, Alertmanager
- Configure Nginx reverse proxy
- Obtain SSL certificate
- Set up firewall rules

Takes 5-10 minutes.

## Step 6: Add Monitored Hosts

On each server you want to monitor:

```bash
# Copy the observability-stack directory
scp -r /opt/observability-stack root@monitored-host:/opt/

# SSH to the monitored host
ssh root@monitored-host
cd /opt/observability-stack

# Auto-detect services
./observability host detect --generate --output=config/hosts/$(hostname).yaml

# Review the generated config
cat config/hosts/$(hostname).yaml

# Run pre-flight check
./observability preflight --monitored-host

# Install exporters
./observability setup --monitored-host YOUR_OBSERVABILITY_VPS_IP
```

## Step 7: Access Grafana

1. Open browser to `https://your-domain.com`
2. Login with:
   - Username: `admin`
   - Password: (from your config/global.yaml)
3. **Important:** Change the admin password immediately!

## Step 8: Verify Everything Works

```bash
# On observability VPS
./observability health --verbose

# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {instance: .labels.instance, health: .health}'

# Send test alert
curl -X POST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{"labels":{"alertname":"TestAlert","severity":"warning"},"annotations":{"summary":"Test alert"}}]'
```

## Common Next Steps

**Add more monitored hosts:**
```bash
./observability host add webserver-02
./observability host list
```

**Install specific modules only:**
```bash
./observability module list
./observability module install nginx_exporter
./observability module status
```

**Update configuration:**
```bash
./observability config validate
./observability config edit
```

**Check system health:**
```bash
./observability health
```

## Getting Help

- **Troubleshooting:** See [Troubleshooting & Recovery](README.md#troubleshooting--recovery) in README.md
- **Command help:** `./observability help <command>`
- **Module help:** `./observability module help`
- **Diagnostics:** Run `./observability preflight --observability-vps` or `--monitored-host`

## Useful Commands

```bash
# Show all available commands
./observability help

# Validate configuration
./observability config validate

# List all modules
./observability module list

# Show module details
./observability module show node_exporter

# Check system health
./observability health

# Run pre-flight checks
./observability preflight --observability-vps

# Force reinstall
./observability setup --observability --force
```

## What You Get

- **Grafana Dashboards:**
  - Infrastructure Overview
  - Node Exporter Details
  - Nginx Metrics
  - MySQL/MariaDB Metrics
  - PHP-FPM Metrics
  - Logs Explorer

- **Alerts (via Email):**
  - Instance down
  - High CPU/memory/disk
  - Service failures
  - Error rate spikes
  - And more...

- **Secure Access:**
  - HTTPS with Let's Encrypt
  - Basic auth for APIs
  - Firewall rules
  - Isolated metrics collection

## Support & Documentation

- Full documentation: [README.md](README.md)
- Module system: [Module System](README.md#module-system)
- Custom modules: [Creating Custom Modules](README.md#creating-custom-modules)
- Recovery procedures: [Troubleshooting & Recovery](README.md#troubleshooting--recovery)
