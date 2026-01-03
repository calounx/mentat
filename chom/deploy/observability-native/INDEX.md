# Native Observability Stack - File Index

## Quick Navigation

**First time? Start here:**
1. Read [QUICK-START.md](QUICK-START.md) for 5-minute installation
2. Review [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) for detailed steps
3. Check [DELIVERABLES.txt](DELIVERABLES.txt) for complete overview

**Need specific information?**
- Architecture and features: [README.md](README.md)
- Technical details: [IMPLEMENTATION-SUMMARY.md](IMPLEMENTATION-SUMMARY.md)
- Complete inventory: [DELIVERABLES.txt](DELIVERABLES.txt)

## File Directory

### Documentation (5 files)

#### [QUICK-START.md](QUICK-START.md) (4.2 KB)
For experienced admins who want to get running quickly.
- One-command installation
- Essential post-install steps
- Quick reference tables
- Common commands

#### [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) (13 KB)
Complete step-by-step deployment instructions.
- Pre-deployment checklist
- Detailed installation steps
- Post-deployment validation
- Security hardening
- Rollback procedures
- Maintenance schedule

#### [README.md](README.md) (11 KB)
Comprehensive project documentation.
- Architecture overview
- Service management
- Configuration examples
- Security practices
- Troubleshooting
- Backup procedures

#### [IMPLEMENTATION-SUMMARY.md](IMPLEMENTATION-SUMMARY.md) (18 KB)
Detailed technical implementation documentation.
- Executive summary
- Component inventory
- Architecture diagrams
- Management procedures
- Cost optimization
- Success metrics

#### [DELIVERABLES.txt](DELIVERABLES.txt) (19 KB)
Complete project deliverables and inventory.
- All files with descriptions
- Configuration details
- Alert rules
- Security features
- Installation commands
- Post-installation tasks

### Installation Scripts (7 files)

#### [install-all.sh](install-all.sh) (17 KB)
Master installation script - installs all components.
```bash
sudo bash install-all.sh
```
Installs: Prometheus, Grafana, Loki, Promtail, AlertManager, Node Exporter

#### [install-prometheus.sh](install-prometheus.sh) (14 KB)
Installs Prometheus metrics server (v2.49.1).
- Direct binary installation
- Alert rules included
- 30-day retention
```bash
sudo bash install-prometheus.sh
```

#### [install-grafana.sh](install-grafana.sh) (11 KB)
Installs Grafana visualization platform (latest stable).
- APT repository installation
- Auto-provisioned datasources
- Plugins included
```bash
sudo bash install-grafana.sh
```

#### [install-loki.sh](install-loki.sh) (12 KB)
Installs Loki log aggregation system (v2.9.4).
- Direct binary installation
- Log-based alerting
- 30-day retention
```bash
sudo bash install-loki.sh
```

#### [install-promtail.sh](install-promtail.sh) (12 KB)
Installs Promtail log shipper (v2.9.4).
- Multi-source log collection
- Laravel log parsing
- Nginx/PHP-FPM support
```bash
sudo bash install-promtail.sh
```

#### [install-alertmanager.sh](install-alertmanager.sh) (14 KB)
Installs AlertManager alert routing (v0.27.0).
- Email notifications
- HTML templates
- Multi-tier routing
```bash
sudo bash install-alertmanager.sh
```

#### [install-node-exporter.sh](install-node-exporter.sh) (10 KB)
Installs Node Exporter system metrics (v1.7.0).
- System metrics
- Custom metrics support
- Textfile collector
```bash
sudo bash install-node-exporter.sh
```

### Management Scripts (2 files)

#### [manage-services.sh](manage-services.sh) (15 KB)
Comprehensive service management tool.
```bash
# Interactive menu
sudo bash manage-services.sh

# Command-line usage
sudo bash manage-services.sh status
sudo bash manage-services.sh health
sudo bash manage-services.sh logs prometheus 100
```

Features:
- Status monitoring
- Health checks
- Log viewing
- Port checking
- Disk usage
- Batch operations

#### [uninstall-all.sh](uninstall-all.sh) (12 KB)
Complete removal with safety checks.
```bash
sudo bash uninstall-all.sh
```

Features:
- Configuration backup
- Safe removal confirmation
- Complete cleanup
- Firewall rule removal

### This File

#### [INDEX.md](INDEX.md)
File navigation and quick reference (this file).

## Installation Workflows

### Scenario 1: Full Stack Installation (Recommended)
```bash
cd /home/calounx/repositories/mentat/chom/deploy/observability-native
sudo bash install-all.sh
```
**Time**: 15-20 minutes
**Components**: All 6 components
**Use case**: Complete monitoring solution

### Scenario 2: Monitoring Server Only
```bash
sudo bash install-prometheus.sh
sudo bash install-grafana.sh
sudo bash install-alertmanager.sh
sudo bash install-node-exporter.sh
```
**Time**: 12-15 minutes
**Components**: Core monitoring
**Use case**: Monitoring without log aggregation

### Scenario 3: Application Server (Log Shipping)
```bash
sudo bash install-promtail.sh
sudo bash install-node-exporter.sh
```
**Time**: 5-8 minutes
**Components**: Log shipping and metrics
**Use case**: Add to existing monitoring stack

### Scenario 4: Selective Installation
```bash
# Install everything except Loki/Promtail
sudo bash install-all.sh --no-loki --no-promtail
```
**Time**: Varies
**Components**: Custom selection
**Use case**: Specific requirements

## Common Tasks Quick Reference

### Installation
```bash
# Full installation
cd /home/calounx/repositories/mentat/chom/deploy/observability-native
sudo bash install-all.sh

# Individual component
sudo bash install-<component>.sh
```

### Service Management
```bash
# Status of all services
sudo bash manage-services.sh status

# Interactive menu
sudo bash manage-services.sh

# Health checks
sudo bash manage-services.sh health

# View logs
sudo bash manage-services.sh logs prometheus 100
sudo bash manage-services.sh follow grafana-server
```

### Direct systemd Commands
```bash
# Individual service
systemctl status prometheus
systemctl restart grafana-server
journalctl -u loki -f

# All services
systemctl status prometheus grafana-server loki promtail alertmanager node_exporter
```

### Configuration
```bash
# Edit configs
sudo nano /etc/prometheus/prometheus.yml
sudo nano /etc/grafana/grafana.ini
sudo nano /etc/loki/loki.yml

# Validate
sudo promtool check config /etc/prometheus/prometheus.yml
sudo amtool check-config /etc/alertmanager/alertmanager.yml

# Reload (no restart)
sudo systemctl reload prometheus
sudo systemctl reload alertmanager
```

### Health Checks
```bash
# Via management script
sudo bash manage-services.sh health

# Manual endpoints
curl http://localhost:9090/-/healthy     # Prometheus
curl http://localhost:3000/api/health    # Grafana
curl http://localhost:3100/ready         # Loki
curl http://localhost:9093/-/healthy     # AlertManager
curl http://localhost:9100/metrics       # Node Exporter
```

### Troubleshooting
```bash
# Check service status
systemctl status <service>

# View logs
journalctl -u <service> -n 100
journalctl -u <service> -f

# Check ports
sudo bash manage-services.sh ports
ss -tlnp | grep <port>

# Check disk usage
sudo bash manage-services.sh disk
du -sh /var/lib/prometheus
```

### Uninstallation
```bash
sudo bash uninstall-all.sh
# Follow prompts for confirmation
```

## Access URLs After Installation

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| Grafana | http://mentat.arewel.com:3000 | admin / changeme |
| Prometheus | http://mentat.arewel.com:9090 | None |
| AlertManager | http://mentat.arewel.com:9093 | None |
| Loki | http://mentat.arewel.com:3100 | None (API only) |

## File Locations Reference

### Binaries
```
/usr/local/bin/prometheus
/usr/local/bin/promtool
/usr/local/bin/loki
/usr/local/bin/promtail
/usr/local/bin/alertmanager
/usr/local/bin/amtool
/usr/local/bin/node_exporter
/usr/sbin/grafana-server (via APT)
```

### Configurations
```
/etc/prometheus/prometheus.yml
/etc/prometheus/rules/
/etc/grafana/grafana.ini
/etc/grafana/provisioning/
/etc/loki/loki.yml
/etc/loki/rules/
/etc/promtail/promtail.yml
/etc/alertmanager/alertmanager.yml
/etc/alertmanager/templates/
```

### Data Directories
```
/var/lib/prometheus/
/var/lib/grafana/
/var/lib/loki/
/var/lib/promtail/
/var/lib/alertmanager/
/var/lib/node_exporter/
```

### Log Directories
```
/var/log/prometheus/
/var/log/grafana/
/var/log/loki/
/var/log/promtail/
/var/log/alertmanager/
```

### Systemd Services
```
/etc/systemd/system/prometheus.service
/etc/systemd/system/loki.service
/etc/systemd/system/promtail.service
/etc/systemd/system/alertmanager.service
/etc/systemd/system/node_exporter.service
/lib/systemd/system/grafana-server.service
```

## Documentation Reading Order

### For Quick Deployment
1. QUICK-START.md (5 minutes read)
2. DEPLOYMENT-GUIDE.md (skim relevant sections)
3. Deploy!

### For Complete Understanding
1. README.md (comprehensive overview)
2. DEPLOYMENT-GUIDE.md (step-by-step)
3. IMPLEMENTATION-SUMMARY.md (technical details)
4. DELIVERABLES.txt (complete inventory)

### For Specific Tasks
- **Installation**: QUICK-START.md or DEPLOYMENT-GUIDE.md
- **Configuration**: README.md
- **Troubleshooting**: README.md or DEPLOYMENT-GUIDE.md
- **Architecture**: IMPLEMENTATION-SUMMARY.md or README.md
- **Inventory**: DELIVERABLES.txt
- **Security**: DEPLOYMENT-GUIDE.md or README.md

## Getting Help

### Built-in Help
```bash
sudo bash manage-services.sh --help
sudo bash install-all.sh --help
```

### Logs and Diagnostics
```bash
# Service logs
journalctl -u <service> -n 100

# Management script
sudo bash manage-services.sh logs <service> 100

# Validation
cd /home/calounx/repositories/mentat/chom/deploy/validation
sudo bash observability-check.sh
```

### Documentation
- Check README.md troubleshooting section
- Review DEPLOYMENT-GUIDE.md troubleshooting
- Check official documentation links in README.md

## Project Statistics

- Total Files: 14
- Total Size: 178 KB
- Total Lines: 5,753
- Scripts: 9 executable
- Documentation: 5 markdown/text files
- Components: 6 services
- Languages: Bash, YAML, Markdown

## Version Information

- Prometheus: 2.49.1
- Grafana: Latest stable (from APT)
- Loki: 2.9.4
- Promtail: 2.9.4
- AlertManager: 0.27.0
- Node Exporter: 1.7.0

## Next Steps After Reading

1. Choose your deployment scenario above
2. Read the relevant documentation
3. Run the installation
4. Follow post-installation checklist in DEPLOYMENT-GUIDE.md
5. Configure and customize as needed

## Support

All documentation is included in this directory. For issues:

1. Check logs: `journalctl -u <service> -f`
2. Review troubleshooting sections in README.md
3. Run health checks: `sudo bash manage-services.sh health`
4. Verify configuration: Use validation tools for each component

---

**Project**: Native Observability Stack for Debian 13
**Status**: Production Ready
**Last Updated**: 2026-01-03
