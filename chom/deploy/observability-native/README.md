# Native Observability Stack for Debian 13

Complete observability solution with **NO DOCKER** - all services run as native systemd services.

## Components

- **Prometheus** - Metrics collection and storage
- **Grafana** - Visualization and dashboards
- **Loki** - Log aggregation
- **Promtail** - Log shipping
- **AlertManager** - Alert routing and notifications
- **Node Exporter** - System metrics

## Quick Start

### Full Stack Installation

```bash
cd /home/calounx/repositories/mentat/chom/deploy/observability-native

# Install all components
sudo bash install-all.sh

# Access services
# Grafana: http://mentat.arewel.com:3000 (admin/changeme)
# Prometheus: http://mentat.arewel.com:9090
# AlertManager: http://mentat.arewel.com:9093
```

### Individual Component Installation

```bash
# Install components individually
sudo bash install-prometheus.sh
sudo bash install-grafana.sh
sudo bash install-loki.sh
sudo bash install-promtail.sh
sudo bash install-alertmanager.sh
sudo bash install-node-exporter.sh
```

## Installation Scripts

| Script | Description |
|--------|-------------|
| `install-all.sh` | Master installation script - installs all components |
| `install-prometheus.sh` | Prometheus metrics server |
| `install-grafana.sh` | Grafana visualization platform |
| `install-loki.sh` | Loki log aggregation system |
| `install-promtail.sh` | Promtail log shipper |
| `install-alertmanager.sh` | AlertManager alert routing |
| `install-node-exporter.sh` | Node Exporter system metrics |

## Management Scripts

### Service Management

```bash
# Interactive management interface
sudo bash manage-services.sh

# Command-line operations
sudo bash manage-services.sh status      # Show all service status
sudo bash manage-services.sh start       # Start all services
sudo bash manage-services.sh stop        # Stop all services
sudo bash manage-services.sh restart     # Restart all services
sudo bash manage-services.sh reload      # Reload configurations
sudo bash manage-services.sh health      # Check health endpoints
sudo bash manage-services.sh ports       # Show listening ports
sudo bash manage-services.sh disk        # Show disk usage

# View logs
sudo bash manage-services.sh logs prometheus 100
sudo bash manage-services.sh follow grafana-server
```

## Architecture

### Directory Structure

```
/etc/prometheus/          # Prometheus configuration
├── prometheus.yml        # Main config
├── rules/               # Alert rules
└── file_sd/             # File-based service discovery

/etc/grafana/            # Grafana configuration
├── grafana.ini          # Main config
└── provisioning/        # Datasources and dashboards

/etc/loki/               # Loki configuration
├── loki.yml            # Main config
└── rules/              # Log-based alert rules

/etc/promtail/           # Promtail configuration
└── promtail.yml        # Main config

/etc/alertmanager/       # AlertManager configuration
├── alertmanager.yml    # Main config
└── templates/          # Email templates

/var/lib/prometheus/     # Prometheus data
/var/lib/grafana/        # Grafana data
/var/lib/loki/           # Loki data
/var/lib/alertmanager/   # AlertManager data
```

### Service Ports

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| Prometheus | 9090 | HTTP | Metrics API and UI |
| Grafana | 3000 | HTTP | Dashboard UI |
| Loki | 3100 | HTTP | Log ingestion API |
| Loki | 9096 | gRPC | Loki gRPC |
| Promtail | 9080 | HTTP | Metrics endpoint |
| AlertManager | 9093 | HTTP | Alert management |
| Node Exporter | 9100 | HTTP | System metrics |

## Service Management

### Systemd Commands

```bash
# Individual service control
systemctl status prometheus
systemctl start prometheus
systemctl stop prometheus
systemctl restart prometheus
systemctl reload prometheus

# View logs
journalctl -u prometheus -f
journalctl -u grafana-server -n 100
journalctl -u loki --since "1 hour ago"

# Enable/disable on boot
systemctl enable prometheus
systemctl disable prometheus
```

### Configuration Validation

```bash
# Prometheus
promtool check config /etc/prometheus/prometheus.yml
promtool check rules /etc/prometheus/rules/*.yml

# AlertManager
amtool check-config /etc/alertmanager/alertmanager.yml

# Reload configurations (no restart)
systemctl reload prometheus
systemctl reload alertmanager
```

## Configuration

### Prometheus Targets

Edit `/etc/prometheus/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'my-app'
    static_configs:
      - targets: ['app-server:9090']
        labels:
          environment: 'production'
```

Then reload:
```bash
systemctl reload prometheus
```

### Grafana Datasources

Datasources are auto-provisioned at:
`/etc/grafana/provisioning/datasources/prometheus.yml`

### Alert Rules

Create alert rules in `/etc/prometheus/rules/`:

```yaml
groups:
  - name: example_alerts
    rules:
      - alert: HighMemoryUsage
        expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 < 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Memory usage critical"
```

Reload Prometheus after adding rules:
```bash
systemctl reload prometheus
```

### AlertManager Receivers

Edit `/etc/alertmanager/alertmanager.yml`:

```yaml
receivers:
  - name: 'email'
    email_configs:
      - to: 'ops@example.com'
        from: 'alertmanager@example.com'
        smarthost: 'smtp.example.com:587'
        auth_username: 'alertmanager'
        auth_password: 'password'
```

## Monitoring

### Health Checks

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

### Query Examples

```bash
# Prometheus - Query via HTTP API
curl 'http://localhost:9090/api/v1/query?query=up'

# Loki - Query logs
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="chom"}' \
  --data-urlencode 'limit=10'

# AlertManager - View alerts
curl http://localhost:9093/api/v2/alerts
```

## Security

### Firewall Configuration

The installation scripts automatically configure firewall rules. To manually adjust:

```bash
# UFW
ufw allow from 192.168.0.0/16 to any port 9090  # Prometheus (internal only)
ufw allow 3000                                   # Grafana (public)

# Firewalld
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.0.0/16 port port=9090 protocol=tcp accept'
firewall-cmd --reload
```

### Authentication

- **Grafana**: Change default password immediately after installation
  ```bash
  grafana-cli admin reset-admin-password <new-password>
  ```

- **Prometheus**: Consider adding reverse proxy with authentication for production

### File Permissions

All services run as dedicated system users with minimal permissions:
- `prometheus:prometheus`
- `grafana:grafana`
- `loki:loki`
- `promtail:promtail`
- `alertmanager:alertmanager`
- `node_exporter:node_exporter`

## Backup and Recovery

### Backup Configurations

```bash
# Create backup
tar czf observability-backup-$(date +%Y%m%d).tar.gz \
  /etc/prometheus \
  /etc/grafana \
  /etc/loki \
  /etc/promtail \
  /etc/alertmanager

# Backup data directories (larger)
tar czf observability-data-$(date +%Y%m%d).tar.gz \
  /var/lib/prometheus \
  /var/lib/grafana \
  /var/lib/loki
```

### Restore

```bash
# Stop services
systemctl stop prometheus grafana-server loki promtail alertmanager

# Restore configurations
tar xzf observability-backup-*.tar.gz -C /

# Restore data
tar xzf observability-data-*.tar.gz -C /

# Fix permissions
chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
chown -R grafana:grafana /etc/grafana /var/lib/grafana
chown -R loki:loki /etc/loki /var/lib/loki

# Start services
systemctl start prometheus grafana-server loki promtail alertmanager
```

## Troubleshooting

### Service Won't Start

```bash
# Check service status
systemctl status prometheus

# View detailed logs
journalctl -u prometheus -n 100 --no-pager

# Check configuration
promtool check config /etc/prometheus/prometheus.yml

# Check permissions
ls -la /etc/prometheus
ls -la /var/lib/prometheus
```

### High Disk Usage

```bash
# Check disk usage
du -sh /var/lib/prometheus
du -sh /var/lib/loki

# Adjust retention (Prometheus)
# Edit /etc/systemd/system/prometheus.service
# Change --storage.tsdb.retention.time=30d to desired value
systemctl daemon-reload
systemctl restart prometheus

# Adjust retention (Loki)
# Edit /etc/loki/loki.yml
# Update retention_period under table_manager
systemctl restart loki
```

### Port Conflicts

```bash
# Check what's using a port
ss -tlnp | grep 9090

# Change port in configuration
# Edit /etc/prometheus/prometheus.yml or service file
# Edit /etc/systemd/system/prometheus.service
systemctl daemon-reload
systemctl restart prometheus
```

## Uninstallation

```bash
# Complete removal with confirmation
sudo bash uninstall-all.sh

# This will:
# 1. Create backup of configurations
# 2. Stop all services
# 3. Remove binaries and configurations
# 4. Remove data directories
# 5. Remove systemd service files
# 6. Clean up firewall rules
```

## Cost Optimization

### Prometheus Data Retention

```bash
# Reduce retention period to save disk
# Edit /etc/systemd/system/prometheus.service
--storage.tsdb.retention.time=15d
--storage.tsdb.retention.size=5GB

systemctl daemon-reload
systemctl restart prometheus
```

### Loki Compaction

Loki automatically compacts data. Monitor compaction:

```bash
# Check Loki logs for compaction
journalctl -u loki | grep compaction
```

### Resource Limits

Add resource limits to systemd services if needed:

```ini
[Service]
MemoryLimit=1G
CPUQuota=50%
```

## Monitoring Best Practices

1. **Set up alerts** for critical metrics
2. **Regular backups** of configurations
3. **Monitor disk usage** - set up alerts when > 80%
4. **Review logs** regularly for errors
5. **Update components** periodically
6. **Test alert routing** regularly
7. **Document custom changes** to configurations

## Versions Installed

- Prometheus: 2.49.1
- Grafana: Latest from official APT repo
- Loki: 2.9.4
- Promtail: 2.9.4
- AlertManager: 0.27.0
- Node Exporter: 1.7.0

## Support and Documentation

- Prometheus: https://prometheus.io/docs/
- Grafana: https://grafana.com/docs/
- Loki: https://grafana.com/docs/loki/
- AlertManager: https://prometheus.io/docs/alerting/alertmanager/

## Files in This Directory

- `install-all.sh` - Master installer
- `install-prometheus.sh` - Prometheus installer
- `install-grafana.sh` - Grafana installer
- `install-loki.sh` - Loki installer
- `install-promtail.sh` - Promtail installer
- `install-alertmanager.sh` - AlertManager installer
- `install-node-exporter.sh` - Node Exporter installer
- `manage-services.sh` - Service management tool
- `uninstall-all.sh` - Complete uninstaller
- `README.md` - This file

## License

Part of the CHOM project.
