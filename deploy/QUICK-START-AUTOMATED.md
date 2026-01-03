# CHOM Automated Deployment - Quick Start

**ONE COMMAND TO DEPLOY EVERYTHING**

## TL;DR

```bash
# SSH to mentat.arewel.com as root
ssh root@mentat.arewel.com

# Clone and deploy
cd /opt
git clone <repo-url> chom-deploy
cd chom-deploy/deploy
sudo ./deploy-chom-automated.sh
```

**That's it!** Wait 20 minutes, then access:
- Application: https://chom.arewel.com
- Grafana: http://mentat.arewel.com:3000
- Prometheus: http://mentat.arewel.com:9090

## What Gets Deployed Automatically

### On mentat.arewel.com (Observability)
- Prometheus (metrics)
- Grafana (dashboards)
- Loki (logs)
- AlertManager (alerts)
- Node Exporter

### On landsraad.arewel.com (Application)
- CHOM Laravel Application
- PostgreSQL 15
- Redis
- Nginx + PHP 8.2-FPM
- Queue Workers
- Node Exporter

## Prerequisites

1. **Two Debian 13 servers** (mentat & landsraad)
2. **Root SSH access** to both
3. **Internet connectivity** on both

## Interactive Deployment (Recommended First Time)

For custom configuration during deployment:

```bash
sudo ./deploy-chom-automated.sh --interactive
```

You'll be prompted for:
- Domain name (default: chom.arewel.com)
- SSL email (for Let's Encrypt)
- Email service credentials (optional)

## What This Script Does

1. **Creates deployment user** (stilgar) on both servers
2. **Generates SSH keys** for passwordless access
3. **Auto-generates secrets** (DB passwords, app keys, etc.)
4. **Prepares mentat** (installs monitoring stack)
5. **Prepares landsraad** (installs application stack)
6. **Deploys application** with zero downtime
7. **Starts all services** and verifies health

## Key Features

- **Fully Idempotent** - Safe to run multiple times
- **Zero Touch** - Minimal user interaction
- **Auto-Recovery** - Rolls back on failure
- **Secure by Default** - Strong passwords, SSH keys
- **Production Ready** - Monitoring, logging, backups

## Troubleshooting

### Can't SSH to landsraad?

```bash
# Run setup-stilgar-user.sh on landsraad manually
ssh root@landsraad.arewel.com
bash /tmp/setup-stilgar-user.sh
exit

# Then copy SSH key
ssh-copy-id stilgar@landsraad.arewel.com
```

### Deployment failed?

```bash
# Check logs
tail -100 /var/log/chom-deploy/deployment-*.log

# Run with specific phases
sudo ./deploy-chom-automated.sh --skip-user-setup --skip-ssh
```

### Service not starting?

```bash
# Check status
systemctl status <service-name>

# View logs
journalctl -u <service-name> -n 50
```

## Advanced Usage

### Skip Phases

```bash
# Skip already completed phases
sudo ./deploy-chom-automated.sh \
  --skip-user-setup \
  --skip-ssh \
  --skip-secrets
```

### Dry Run

```bash
# See what would happen without executing
sudo ./deploy-chom-automated.sh --dry-run
```

### Help

```bash
./deploy-chom-automated.sh --help
```

## Post-Deployment

### Change Grafana Password

```bash
grafana-cli admin reset-admin-password YourSecurePassword
```

### Setup SSL

```bash
sudo certbot --nginx -d chom.arewel.com
```

### Configure Firewall

```bash
sudo ./scripts/setup-firewall.sh --server landsraad
```

## Files Created

- `.deployment-secrets` - All credentials (KEEP SECURE!)
- `/var/log/chom-deploy/` - Deployment logs
- `/var/www/chom/` - Application directory
- `/opt/observability/` - Monitoring tools

## Documentation

- **Full Guide:** [AUTOMATED-DEPLOYMENT.md](AUTOMATED-DEPLOYMENT.md)
- **Deployment Runbook:** [RUNBOOK.md](RUNBOOK.md)
- **Security Guide:** [security/README.md](security/README.md)

## Support

**Logs:**
```bash
# Deployment
tail -f /var/log/chom-deploy/deployment.log

# Application
tail -f /var/www/chom/shared/storage/logs/laravel.log
```

**Service Status:**
```bash
# Mentat
systemctl status prometheus grafana-server loki

# Landsraad
systemctl status nginx postgresql redis-server php8.2-fpm
```

---

**Questions?** Check [AUTOMATED-DEPLOYMENT.md](AUTOMATED-DEPLOYMENT.md) for detailed documentation.
