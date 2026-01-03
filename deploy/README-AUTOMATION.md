# CHOM Deployment Automation

🚀 **Production-ready, fully-automated deployment system**

## Quick Start

```bash
# One command to deploy everything!
sudo ./deploy-chom-automated.sh
```

## What You Get

✅ Complete automation from bare servers to production
✅ Idempotent - safe to run multiple times
✅ Zero-downtime deployments
✅ Auto-generated secrets and credentials
✅ Full observability stack (Prometheus, Grafana, Loki)
✅ Production-ready security defaults
✅ Comprehensive logging and monitoring

## Documentation

### Getting Started
1. **[QUICK-START-AUTOMATED.md](QUICK-START-AUTOMATED.md)** - Start here! TL;DR deployment guide
2. **[AUTOMATED-DEPLOYMENT.md](AUTOMATED-DEPLOYMENT.md)** - Complete deployment guide (500+ lines)
3. **[DEPLOYMENT-WORKFLOW.md](DEPLOYMENT-WORKFLOW.md)** - Visual workflow diagrams

### Reference
- **[AUTOMATION-SUMMARY.md](AUTOMATION-SUMMARY.md)** - Implementation overview
- **[.deployment-secrets.template](.deployment-secrets.template)** - Secrets configuration template

## Core Scripts

### Master Orchestrator
- **deploy-chom-automated.sh** - ONE COMMAND DEPLOYMENT
  ```bash
  sudo ./deploy-chom-automated.sh [OPTIONS]

  Options:
    --interactive       Prompt for configuration
    --dry-run           Show what would happen
    --skip-*            Skip specific phases
    --help              Show all options
  ```

### Setup Scripts (New)
- **setup-stilgar-user.sh** - Create deployment user
- **setup-ssh-automation.sh** - Configure passwordless SSH
- **generate-deployment-secrets.sh** - Auto-generate credentials

### Preparation Scripts (Enhanced)
- **prepare-mentat.sh** - Setup observability server (idempotent)
- **prepare-landsraad.sh** - Setup application server (idempotent)

### Deployment Scripts (Existing)
- **deploy-application.sh** - Zero-downtime app deployment
- **deploy-observability.sh** - Deploy monitoring stack
- **rollback.sh** - Rollback to previous release
- **health-check.sh** - Verify deployment health

## Deployment Phases

1. **Pre-flight Checks** - Verify prerequisites
2. **User Setup** - Create stilgar user on both servers
3. **SSH Automation** - Enable passwordless access
4. **Secrets Generation** - Auto-generate passwords and keys
5. **Prepare Mentat** - Install observability stack
6. **Prepare Landsraad** - Install application stack
7. **Deploy Application** - Zero-downtime deployment
8. **Deploy Observability** - Start monitoring services
9. **Verification** - Health checks and validation

## Architecture

```
mentat.arewel.com                landsraad.arewel.com
(Observability)                  (Application)
├── Prometheus                   ├── CHOM Laravel App
├── Grafana                      ├── PostgreSQL 15
├── Loki                         ├── Redis
├── AlertManager                 ├── Nginx
└── Node Exporter               └── PHP 8.2-FPM
```

## Key Features

### Idempotency
Every script checks before acting:
```bash
if ! exists; then create; else skip; fi
```
Safe to run multiple times without side effects.

### Minimal Interaction
Only prompts for essentials:
- Domain name (or use default)
- SSL email (or use default)
- Optional: External API credentials

Everything else is automated!

### Security
- Auto-generated strong passwords
- SSH key-based authentication
- No password auth, no root login
- Secure file permissions (600)
- Secrets excluded from git

### Error Handling
- Automatic rollback on failure
- Comprehensive error logging
- Health checks before/after deployment
- Clear error messages with solutions

## Usage Examples

### First Time Deployment
```bash
# Automated with defaults
sudo ./deploy-chom-automated.sh

# Interactive with custom config
sudo ./deploy-chom-automated.sh --interactive
```

### Re-deploy Application Only
```bash
sudo ./deploy-chom-automated.sh \
  --skip-user-setup \
  --skip-ssh \
  --skip-secrets \
  --skip-mentat-prep \
  --skip-landsraad-prep
```

### Dry Run (Preview)
```bash
sudo ./deploy-chom-automated.sh --dry-run
```

### Individual Scripts
```bash
# Create users
./scripts/setup-stilgar-user.sh

# Generate secrets
./scripts/generate-deployment-secrets.sh --interactive

# Prepare servers
./scripts/prepare-mentat.sh
./scripts/prepare-landsraad.sh
```

## Secrets Management

### Auto-Generated
- Laravel APP_KEY
- Database passwords
- Redis password
- Backup encryption key
- JWT secret

### Manual Configuration (Optional)
- Domain name
- Email credentials
- VPS provider API keys

### File Location
```
deploy/.deployment-secrets
```

**Security:** File is created with 600 permissions and excluded from git.

## Verification

### Service Status
```bash
# Mentat
systemctl status prometheus grafana-server loki

# Landsraad
systemctl status nginx postgresql redis-server php8.2-fpm
```

### HTTP Endpoints
```bash
# Application
curl https://chom.arewel.com

# Grafana
curl http://mentat.arewel.com:3000/api/health

# Prometheus
curl http://mentat.arewel.com:9090/-/healthy
```

### Logs
```bash
# Deployment logs
tail -f /var/log/chom-deploy/deployment.log

# Application logs
tail -f /var/www/chom/shared/storage/logs/laravel.log
```

## Troubleshooting

### Common Issues

**SSH connection failed?**
```bash
ssh-copy-id stilgar@landsraad.arewel.com
```

**Service won't start?**
```bash
systemctl status <service-name>
journalctl -u <service-name> -n 50
```

**Secrets file not found?**
```bash
./scripts/generate-deployment-secrets.sh --interactive
```

**Need to rollback?**
```bash
./scripts/rollback.sh
```

### Get Help
```bash
# View deployment logs
ls -lh /var/log/chom-deploy/
tail -100 /var/log/chom-deploy/deployment-*.log

# Dry run to see what would happen
./deploy-chom-automated.sh --dry-run

# Check script help
./deploy-chom-automated.sh --help
```

## File Structure

```
deploy/
├── README-AUTOMATION.md          ← You are here
├── QUICK-START-AUTOMATED.md      ← Start here!
├── AUTOMATED-DEPLOYMENT.md       ← Complete guide
├── DEPLOYMENT-WORKFLOW.md        ← Visual workflows
├── AUTOMATION-SUMMARY.md         ← Implementation summary
│
├── deploy-chom-automated.sh      ← MASTER SCRIPT
├── .deployment-secrets           ← Generated (git-ignored)
├── .deployment-secrets.template  ← Template
│
├── scripts/
│   ├── setup-stilgar-user.sh        # User creation
│   ├── setup-ssh-automation.sh      # SSH keys
│   ├── generate-deployment-secrets.sh # Secrets
│   ├── prepare-mentat.sh            # Observability
│   ├── prepare-landsraad.sh         # Application
│   ├── deploy-application.sh        # App deploy
│   ├── rollback.sh                  # Rollback
│   └── health-check.sh              # Verification
│
└── utils/
    ├── logging.sh                # Logging
    ├── colors.sh                 # Colors
    └── notifications.sh          # Notifications
```

## Requirements

### Servers
- mentat.arewel.com (2 CPU, 4GB RAM, 20GB disk)
- landsraad.arewel.com (2 CPU, 4GB RAM, 30GB disk)
- Debian 13 (Trixie) or compatible
- Root or sudo access
- Internet connectivity

### Access
- SSH access to both servers
- Git repository access (for app deployment)

## Time to Production

- Pre-deployment: 5 minutes (clone, review)
- Automated deployment: 15-20 minutes
- Post-deployment: 10 minutes (SSL, verify)
- **Total: ~35 minutes**

## Post-Deployment

### Essential Tasks
1. Change Grafana admin password
2. Configure SSL/TLS with Let's Encrypt
3. Setup firewall rules
4. Configure backup schedule
5. Test application functionality

### Optional Tasks
- Custom Grafana dashboards
- Alert notifications (Slack, email)
- CI/CD integration
- Disaster recovery procedures

## Support

### Documentation
- Full guide: [AUTOMATED-DEPLOYMENT.md](AUTOMATED-DEPLOYMENT.md)
- Quick start: [QUICK-START-AUTOMATED.md](QUICK-START-AUTOMATED.md)
- Workflows: [DEPLOYMENT-WORKFLOW.md](DEPLOYMENT-WORKFLOW.md)

### Logs
- `/var/log/chom-deploy/` - Deployment logs
- `/var/www/chom/shared/storage/logs/` - Application logs
- `journalctl -u <service>` - Service logs

### Help
Every script includes `--help` flag with usage information.

## Status

✅ **PRODUCTION READY**

All scripts tested and verified:
- ✅ Idempotent operation
- ✅ Error handling
- ✅ Logging
- ✅ Documentation
- ✅ Security
- ✅ Monitoring

## Next Steps

1. **Deploy:** `sudo ./deploy-chom-automated.sh`
2. **Verify:** Check services and access URLs
3. **Secure:** Configure SSL, firewall, backups
4. **Monitor:** Review Grafana dashboards
5. **Maintain:** Regular updates and monitoring

---

**Need Help?** Start with [QUICK-START-AUTOMATED.md](QUICK-START-AUTOMATED.md)

**Want Details?** Read [AUTOMATED-DEPLOYMENT.md](AUTOMATED-DEPLOYMENT.md)

**Visual Learner?** Check [DEPLOYMENT-WORKFLOW.md](DEPLOYMENT-WORKFLOW.md)

---

Last Updated: 2026-01-03
Version: 1.0.0
