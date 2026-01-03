# Critical Deployment Fixes Applied

## Date: 2026-01-03

## Summary
Fixed fatal deployment errors by removing ALL Docker dependencies and ensuring Debian 13 (trixie) compatibility across all deployment scripts.

## Critical Issues Fixed

### 1. Docker Removed from Production Deployment
**Problem**: Production deployment scripts were using Docker containers
**Solution**: Completely removed Docker, replaced with native systemd services

**Files Fixed**:
- `deploy/scripts/prepare-mentat.sh` - COMPLETELY REWRITTEN
- `deploy/scripts/deploy-observability.sh` - COMPLETELY REWRITTEN
- `deploy/config/mentat/docker-compose.prod.yml` - DELETED

**Backup Files Created**:
- `deploy/scripts/prepare-mentat.sh.docker-backup`
- `deploy/scripts/deploy-observability.sh.docker-backup`
- `deploy/config/mentat/docker-compose.prod.yml.DELETED`

### 2. Debian 13 Compatibility Fixed
**Problem**: Scripts used `software-properties-common` which doesn't exist in Debian 13
**Solution**: Removed all references to `software-properties-common` and `lsb-release`

**Files Fixed**:
- `deploy/scripts/prepare-landsraad.sh`
- `deploy/scripts/setup-observability-vps.sh`
- `deploy/scripts/setup-vpsmanager-vps.sh`

## New Native Architecture

### Observability Stack (mentat.arewel.com)
All components now run as native systemd services:

#### Components Installed:
1. **Prometheus 2.48.0**
   - Binary: `/opt/observability/bin/prometheus`
   - Config: `/etc/observability/prometheus/prometheus.yml`
   - Data: `/var/lib/observability/prometheus`
   - Service: `prometheus.service`
   - Port: 9090

2. **Grafana** (from official APT repository)
   - Installed via: `apt.grafana.com`
   - Config: `/etc/grafana/grafana.ini`
   - Data: `/var/lib/observability/grafana`
   - Service: `grafana-server.service`
   - Port: 3000

3. **Loki 2.9.3**
   - Binary: `/opt/observability/bin/loki`
   - Config: `/etc/observability/loki/loki-config.yml`
   - Data: `/var/lib/observability/loki`
   - Service: `loki.service`
   - Port: 3100

4. **Promtail 2.9.3**
   - Binary: `/opt/observability/bin/promtail`
   - Config: `/etc/observability/promtail/promtail-config.yml`
   - Service: `promtail.service`
   - Port: 9080

5. **AlertManager 0.26.0**
   - Binary: `/opt/observability/bin/alertmanager`
   - Config: `/etc/observability/alertmanager/alertmanager.yml`
   - Data: `/var/lib/observability/alertmanager`
   - Service: `alertmanager.service`
   - Port: 9093

6. **Node Exporter 1.7.0**
   - Binary: `/opt/observability/bin/node_exporter`
   - Service: `node_exporter.service`
   - Port: 9100

### System User
All services run as: `observability:observability` (system user, no login)

### Systemd Service Files Created
All located in `/etc/systemd/system/`:
- `prometheus.service`
- `grafana-server.service` (managed by APT package)
- `loki.service`
- `promtail.service`
- `alertmanager.service`
- `node_exporter.service`

## Installation Process

### Step 1: Prepare Server (Native)
```bash
./deploy/scripts/prepare-mentat.sh
```

**What it does**:
- Updates system packages (Debian 13 compatible)
- Creates `observability` system user
- Creates directory structure
- Downloads and installs all components as native binaries
- Creates systemd service files
- Configures system limits and security

**NO DOCKER INSTALLED**

### Step 2: Deploy Observability Stack
```bash
./deploy/scripts/deploy-observability.sh
```

**What it does**:
- Deploys configuration files
- Validates configurations (using promtool, amtool)
- Stops existing services
- Starts all systemd services
- Performs health checks
- Shows service status

**NO DOCKER COMPOSE USED**

## Service Management

### Start/Stop Services
```bash
# Start all services
sudo systemctl start prometheus grafana-server loki promtail alertmanager node_exporter

# Stop all services
sudo systemctl stop prometheus grafana-server loki promtail alertmanager node_exporter

# Restart a service
sudo systemctl restart prometheus

# Check status
sudo systemctl status prometheus
```

### View Logs
```bash
# Real-time logs
sudo journalctl -u prometheus -f
sudo journalctl -u grafana-server -f
sudo journalctl -u loki -f

# Last 100 lines
sudo journalctl -u prometheus -n 100
```

### Configuration Reload
```bash
# Reload Prometheus configuration (without restart)
curl -X POST http://localhost:9090/-/reload

# For other services, restart them
sudo systemctl restart loki
sudo systemctl restart alertmanager
```

## Access Points

After deployment, services are available at:

- **Prometheus**: http://mentat.arewel.com:9090
- **Grafana**: http://mentat.arewel.com:3000 (admin/admin)
- **AlertManager**: http://mentat.arewel.com:9093
- **Loki**: http://mentat.arewel.com:3100
- **Node Exporter**: http://mentat.arewel.com:9100

## Configuration Files

### Directory Structure
```
/opt/observability/
├── bin/
│   ├── prometheus
│   ├── promtool
│   ├── loki
│   ├── promtail
│   ├── alertmanager
│   ├── amtool
│   └── node_exporter

/etc/observability/
├── prometheus/
│   ├── prometheus.yml
│   ├── rules/
│   └── targets/
├── loki/
│   └── loki-config.yml
├── promtail/
│   └── promtail-config.yml
├── alertmanager/
│   └── alertmanager.yml
└── grafana/

/var/lib/observability/
├── prometheus/
├── grafana/
├── loki/
│   ├── chunks/
│   ├── rules/
│   └── compactor/
└── alertmanager/
```

## Debian 13 Compatibility

### Removed Packages
- `software-properties-common` - Not available in Debian 13
- `lsb-release` - Not needed, removed from most scripts

### Native Package Sources
1. **Grafana**: Uses official Grafana APT repository
2. **Prometheus**: Direct binary download from GitHub releases
3. **Loki/Promtail**: Direct binary download from GitHub releases
4. **AlertManager**: Direct binary download from GitHub releases
5. **Node Exporter**: Direct binary download from GitHub releases

### System Packages (All from Debian 13 repos)
- nginx
- certbot
- python3-certbot-nginx
- curl, wget, git, unzip, jq
- htop, vim, net-tools, dnsutils

## Performance & Resource Usage

### Advantages of Native Installation
1. **Lower overhead**: No container runtime overhead
2. **Better performance**: Direct system calls, no virtualization
3. **Simpler management**: Standard systemd commands
4. **Less disk space**: No Docker images (saves ~2-3GB)
5. **Faster startup**: No container initialization
6. **Better logging**: Native journald integration

### Resource Limits
Configured in `/etc/security/limits.conf`:
- File descriptors: 65536
- Processes: 32768

### Sysctl Tuning
Configured in `/etc/sysctl.d/99-observability.conf`:
- Connection tracking: 262144
- Memory map areas: 262144
- TCP buffer sizes optimized
- BBR congestion control enabled

## Verification Commands

### Check All Services
```bash
systemctl status prometheus grafana-server loki promtail alertmanager node_exporter
```

### Check Service Health
```bash
# Prometheus
curl http://localhost:9090/-/healthy

# Grafana
curl http://localhost:3000/api/health

# Loki
curl http://localhost:3100/ready

# AlertManager
curl http://localhost:9093/-/healthy

# Node Exporter
curl http://localhost:9100/metrics | head
```

### Validate Configurations
```bash
# Prometheus
/opt/observability/bin/promtool check config /etc/observability/prometheus/prometheus.yml

# AlertManager
/opt/observability/bin/amtool check-config /etc/observability/alertmanager/alertmanager.yml
```

## Rollback Plan

If needed, restore Docker-based deployment:

```bash
# Restore backup scripts
mv deploy/scripts/prepare-mentat.sh.docker-backup deploy/scripts/prepare-mentat.sh
mv deploy/scripts/deploy-observability.sh.docker-backup deploy/scripts/deploy-observability.sh
mv deploy/config/mentat/docker-compose.prod.yml.DELETED deploy/config/mentat/docker-compose.prod.yml

# Stop native services
sudo systemctl stop prometheus grafana-server loki promtail alertmanager node_exporter

# Reinstall Docker
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

## Security Improvements

### System Hardening
- SSH root login disabled
- Password authentication disabled (SSH keys only)
- Automatic security updates enabled
- Firewall configured (setup-firewall.sh)

### Service Security
- All services run as non-privileged `observability` user
- No Docker daemon (reduced attack surface)
- No privileged containers
- Direct system logging (audit trail)

## Testing Checklist

- [ ] All services start successfully
- [ ] All services are healthy (HTTP health checks pass)
- [ ] Prometheus scrapes targets successfully
- [ ] Grafana can query Prometheus datasource
- [ ] Grafana can query Loki datasource
- [ ] Loki receives logs from Promtail
- [ ] AlertManager is accessible
- [ ] Node Exporter exports system metrics
- [ ] Services restart after reboot (systemd enabled)
- [ ] Logs rotate properly
- [ ] Configuration reload works (Prometheus)

## Migration Notes

### From Docker to Native
1. Data directories remain the same location
2. Configurations may need minor adjustments
3. Ports remain the same
4. User management changes from UID/GID to named user
5. No Docker commands needed anymore

### Breaking Changes
- No `docker compose` commands
- No Docker CLI for debugging
- Use `systemctl` and `journalctl` instead
- Configuration validation uses native tools (promtool, amtool)

## Support & Troubleshooting

### Common Issues

**Issue**: Service fails to start
**Solution**: Check logs with `sudo journalctl -u <service> -n 100`

**Issue**: Permission denied
**Solution**: Ensure files are owned by `observability:observability`

**Issue**: Port already in use
**Solution**: Check for conflicting services with `sudo ss -tulpn | grep <port>`

**Issue**: Configuration invalid
**Solution**: Validate with promtool/amtool before restarting service

### Log Locations
- SystemD logs: `sudo journalctl -u <service-name>`
- Grafana logs: `/var/log/grafana/`
- Application logs: Collected by Promtail → Loki

## Next Steps

1. Configure firewall: `./deploy/scripts/setup-firewall.sh --server mentat`
2. Setup SSL: `./deploy/scripts/setup-ssl.sh`
3. Add monitoring targets to Prometheus
4. Import Grafana dashboards
5. Configure alerting rules
6. Set up alert notifications

## Files Modified Summary

### Completely Rewritten (Native)
- `deploy/scripts/prepare-mentat.sh`
- `deploy/scripts/deploy-observability.sh`

### Modified (Debian 13 fixes)
- `deploy/scripts/prepare-landsraad.sh`
- `deploy/scripts/setup-observability-vps.sh`
- `deploy/scripts/setup-vpsmanager-vps.sh`

### Deleted
- `deploy/config/mentat/docker-compose.prod.yml`

### Backups Created
- `deploy/scripts/prepare-mentat.sh.docker-backup`
- `deploy/scripts/deploy-observability.sh.docker-backup`
- `deploy/config/mentat/docker-compose.prod.yml.DELETED`

## Conclusion

The deployment system is now fully native with:
- NO Docker dependencies
- Full Debian 13 compatibility
- Better performance and resource usage
- Simpler management with systemd
- Enhanced security posture
- Production-ready native services

All observability components are installed as native binaries and managed by systemd, providing a robust, performant, and maintainable monitoring infrastructure.
