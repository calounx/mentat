# Quick Start Guide

Get your observability stack running in 10 minutes.

## What You'll Get

- **Grafana** dashboards showing all your server metrics
- **Prometheus** collecting CPU, memory, disk, network data
- **Loki** aggregating all your logs in one place
- **Email alerts** when things go wrong

## Prerequisites

- Fresh Debian 13 VPS (Ubuntu 22.04+ also works)
- Root access
- Domain name (optional, for SSL)

| Role | CPU | RAM | Disk |
|------|-----|-----|------|
| Observability VPS | 1-2 vCPU | 2GB | 20GB |
| VPSManager | 2+ vCPU | 4GB | 40GB |
| Monitored Host | any | 512MB | 5GB |

## Step 1: Run the Installer

**Option A: One-command install (recommended)**

```bash
curl -sSL https://raw.githubusercontent.com/calounx/mentat/master/observability-stack/deploy/bootstrap.sh | sudo bash
```

**Option B: Manual clone**

```bash
git clone https://github.com/calounx/mentat.git
cd mentat/observability-stack
sudo ./deploy/install.sh
```

## Step 2: Choose Your Role

The installer will ask which role to install:

1. **Observability VPS** — Central monitoring server (Prometheus, Loki, Grafana)
2. **VPSManager** — Laravel application with full LEMP stack + monitoring
3. **Monitored Host** — Just exporters for existing servers

## Step 3: Answer the Prompts

The installer will ask for:

- **Observability VPS**: Your domain, admin password, retention settings
- **VPSManager**: Your Laravel repo URL, domain, Observability VPS IP
- **Monitored Host**: Observability VPS IP, this server's name

## Step 4: Access Grafana

After installation completes:

1. Open your browser to `https://your-domain.com` (or `http://VPS_IP:3000`)
2. Login with username `admin` and the password you set
3. **Change the admin password immediately**

## Step 5: Connect Monitored Hosts

For each server you want to monitor:

```bash
# On the monitored host, copy the target file to Observability VPS
scp /tmp/HOSTNAME-targets.yaml root@OBSERVABILITY_IP:/etc/prometheus/targets/
```

Then check in Grafana → Status → Targets to verify the connection.

## Troubleshooting

### Services not starting?

```bash
# Check service status
systemctl status prometheus loki grafana-server

# View logs
journalctl -u prometheus -f
```

### Metrics not appearing?

```bash
# Test connectivity from Observability VPS
curl http://MONITORED_IP:9100/metrics

# Check firewall
ufw status
```

### SSL certificate failed?

```bash
# Make sure DNS is pointing to this VPS, then retry
certbot --nginx -d your-domain.com
```

## Next Steps

- Import dashboards from `grafana/dashboards/library/`
- Configure alert notifications in Alertmanager
- Add more monitored hosts

## Full Documentation

- [Deployment Guide](deploy/README.md) — Detailed installation instructions
- [Main README](README.md) — Full feature list and module documentation
- [Security Guide](SECURITY.md) — Security best practices
