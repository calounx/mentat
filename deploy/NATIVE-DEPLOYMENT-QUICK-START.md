# Native Deployment Quick Start Guide

## What Changed?

The deployment system has been **completely rewritten** to use native systemd services instead of Docker. This provides better performance, easier management, and full Debian 13 compatibility.

## Key Changes

- **NO DOCKER**: All components run as native binaries with systemd
- **Debian 13 Compatible**: Removed `software-properties-common` and other deprecated packages
- **Better Performance**: Direct system execution, no container overhead
- **Simpler Management**: Standard `systemctl` commands

## Installation (mentat.arewel.com - Observability Stack)

### 1. Prepare Server
```bash
cd /home/calounx/repositories/mentat
./deploy/scripts/prepare-mentat.sh
```

**What it installs**:
- Prometheus 2.48.0 (native binary)
- Grafana (APT package from official repository)
- Loki 2.9.3 (native binary)
- Promtail 2.9.3 (native binary)
- AlertManager 0.26.0 (native binary)
- Node Exporter 1.7.0 (native binary)

**Installation time**: ~5-10 minutes

### 2. Deploy Observability Stack
```bash
./deploy/scripts/deploy-observability.sh
```

**What it does**:
- Deploys configuration files
- Validates configurations
- Starts all systemd services
- Performs health checks

**Deployment time**: ~2-3 minutes

### 3. Verify Installation
```bash
./deploy/scripts/verify-native-deployment.sh
```

All checks should pass with green checkmarks.

## Service Management

### Start/Stop/Restart
```bash
# Start all services
sudo systemctl start prometheus grafana-server loki promtail alertmanager node_exporter

# Stop all services
sudo systemctl stop prometheus grafana-server loki promtail alertmanager node_exporter

# Restart single service
sudo systemctl restart prometheus

# Check service status
sudo systemctl status prometheus
```

### View Logs
```bash
# Real-time logs
sudo journalctl -u prometheus -f

# Last 100 lines
sudo journalctl -u prometheus -n 100

# Logs since boot
sudo journalctl -u prometheus -b
```

### Configuration Reload (Prometheus only)
```bash
# Reload without restart (Prometheus only)
curl -X POST http://localhost:9090/-/reload

# For other services, use restart
sudo systemctl restart loki
```

## Access Points

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| Prometheus | http://mentat.arewel.com:9090 | None |
| Grafana | http://mentat.arewel.com:3000 | admin/admin |
| AlertManager | http://mentat.arewel.com:9093 | None |
| Loki | http://mentat.arewel.com:3100 | None |
| Node Exporter | http://mentat.arewel.com:9100 | None |

## Directory Structure

```
/opt/observability/bin/        # All native binaries
/etc/observability/            # Configuration files
/var/lib/observability/        # Data directories
```

## Configuration Files

| Component | Configuration File |
|-----------|-------------------|
| Prometheus | /etc/observability/prometheus/prometheus.yml |
| Loki | /etc/observability/loki/loki-config.yml |
| Promtail | /etc/observability/promtail/promtail-config.yml |
| AlertManager | /etc/observability/alertmanager/alertmanager.yml |
| Grafana | /etc/grafana/grafana.ini |

## Health Checks

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

## Validate Configurations

```bash
# Prometheus
/opt/observability/bin/promtool check config /etc/observability/prometheus/prometheus.yml

# AlertManager
/opt/observability/bin/amtool check-config /etc/observability/alertmanager/alertmanager.yml
```

## Troubleshooting

### Service won't start
```bash
# Check logs
sudo journalctl -u <service-name> -n 100

# Check configuration
/opt/observability/bin/promtool check config /etc/observability/prometheus/prometheus.yml

# Check permissions
ls -la /var/lib/observability/<service-name>
```

### Permission errors
```bash
# Fix ownership
sudo chown -R observability:observability /var/lib/observability
sudo chown -R observability:observability /etc/observability
```

### Port already in use
```bash
# Check what's using the port
sudo ss -tulpn | grep <port>

# Kill the process or change port in config
```

## Common Tasks

### Add Prometheus target
1. Edit `/etc/observability/prometheus/prometheus.yml`
2. Add target under `scrape_configs`
3. Reload: `curl -X POST http://localhost:9090/-/reload`

### Change Grafana password
```bash
# Via CLI
sudo grafana-cli admin reset-admin-password <new-password>

# Or edit config
sudo vim /etc/grafana/grafana.ini
# Change admin_password
sudo systemctl restart grafana-server
```

### Add alert rules
1. Create rule file in `/etc/observability/prometheus/rules/`
2. Reload Prometheus: `curl -X POST http://localhost:9090/-/reload`

### View metrics
```bash
# All Prometheus metrics
curl http://localhost:9090/api/v1/label/__name__/values | jq

# Node Exporter metrics
curl http://localhost:9100/metrics
```

## Backup & Restore

### Backup
```bash
# Stop services
sudo systemctl stop prometheus loki grafana-server

# Backup data
sudo tar czf observability-backup-$(date +%Y%m%d).tar.gz \
    /var/lib/observability \
    /etc/observability \
    /etc/grafana

# Start services
sudo systemctl start prometheus loki grafana-server
```

### Restore
```bash
# Stop services
sudo systemctl stop prometheus loki grafana-server

# Restore data
sudo tar xzf observability-backup-YYYYMMDD.tar.gz -C /

# Fix permissions
sudo chown -R observability:observability /var/lib/observability
sudo chown -R observability:observability /etc/observability

# Start services
sudo systemctl start prometheus loki grafana-server
```

## Performance Tuning

### Increase retention
```bash
# Edit /etc/systemd/system/prometheus.service
# Change retention time/size:
--storage.tsdb.retention.time=90d
--storage.tsdb.retention.size=100GB

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart prometheus
```

### Optimize Loki
```bash
# Edit /etc/observability/loki/loki-config.yml
# Adjust retention_period under limits_config
retention_period: 1440h  # 60 days

# Restart
sudo systemctl restart loki
```

## Differences from Docker Version

| Aspect | Docker | Native |
|--------|--------|--------|
| Installation | docker-compose | systemd |
| Management | docker compose | systemctl |
| Logs | docker logs | journalctl |
| Restart | docker compose restart | systemctl restart |
| Configuration | docker-compose.yml | systemd unit files |
| Data location | Docker volumes | /var/lib/observability |
| Resource usage | Higher | Lower |
| Startup time | Slower | Faster |

## Migration from Docker

If you have an existing Docker-based deployment:

1. Stop Docker services:
   ```bash
   docker compose -f /opt/observability/docker-compose.yml down
   ```

2. Backup data:
   ```bash
   sudo cp -r /var/lib/observability /var/lib/observability.docker-backup
   ```

3. Run native installation:
   ```bash
   ./deploy/scripts/prepare-mentat.sh
   ./deploy/scripts/deploy-observability.sh
   ```

4. Services will use the same data directories

## Next Steps

1. **Configure Firewall**:
   ```bash
   ./deploy/scripts/setup-firewall.sh --server mentat
   ```

2. **Setup SSL** (optional):
   ```bash
   ./deploy/scripts/setup-ssl.sh
   ```

3. **Add monitoring targets**:
   - Edit `/etc/observability/prometheus/prometheus.yml`
   - Add your servers under `scrape_configs`

4. **Import Grafana dashboards**:
   - Login to Grafana (http://mentat.arewel.com:3000)
   - Go to Dashboards → Import
   - Import Node Exporter dashboard (ID: 1860)

5. **Configure alerts**:
   - Create alert rules in `/etc/observability/prometheus/rules/`
   - Configure notification channels in AlertManager

## Support

For issues or questions:
- Check logs: `sudo journalctl -u <service>`
- Verify config: `/opt/observability/bin/promtool check config <config-file>`
- Review: `/home/calounx/repositories/mentat/deploy/CRITICAL-FIXES-APPLIED.md`

## Verification

Run the verification script to ensure everything is correct:
```bash
./deploy/scripts/verify-native-deployment.sh
```

You should see all green checkmarks indicating:
- No Docker dependencies
- No software-properties-common
- Systemd services configured
- Native binaries installed
- Grafana from APT repository
- Docker Compose file removed
