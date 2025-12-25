# Observability Stack - Quick Reference

Essential commands and information for daily operations.

## Quick Start

```bash
# 1. Validate configuration
./scripts/validate-config.sh

# 2. Install observability server
sudo ./scripts/setup-observability.sh

# 3. Add monitored hosts
sudo ./scripts/add-monitored-host.sh --name webserver1 --ip 10.0.0.5

# 4. Install agents on monitored host (run on remote host)
sudo ./scripts/setup-monitored-host.sh <OBSERVABILITY_IP>
```

## Essential Commands

### Configuration Management

```bash
# Validate configuration before deployment
./scripts/validate-config.sh

# Validate with strict mode (warnings = errors)
./scripts/validate-config.sh --strict

# Check configuration for specific file
./scripts/validate-config.sh --config /path/to/config.yaml
```

### Module Management

```bash
# List all available modules
./scripts/module-manager.sh list

# Show detailed info about a module
./scripts/module-manager.sh show node_exporter

# Check module status on current host
./scripts/module-manager.sh status

# Install a module
sudo ./scripts/module-manager.sh install node_exporter

# Uninstall a module
sudo ./scripts/module-manager.sh uninstall nginx_exporter

# Auto-detect applicable modules
./scripts/auto-detect.sh

# Generate host config from detection
./scripts/auto-detect.sh --generate --output=config/hosts/myhost.yaml
```

### Host Management

```bash
# Add monitored host to observability server
sudo ./scripts/add-monitored-host.sh \
  --name webserver1 \
  --ip 10.0.0.5 \
  --description "Production web server"

# Setup monitoring agents on remote host
sudo ./scripts/setup-monitored-host.sh <OBSERVABILITY_IP>

# Health check
./scripts/health-check.sh
```

### Service Management

```bash
# Check service status
sudo systemctl status prometheus
sudo systemctl status grafana-server
sudo systemctl status loki
sudo systemctl status alertmanager

# Restart services
sudo systemctl restart prometheus
sudo systemctl restart grafana-server

# View service logs
sudo journalctl -u prometheus -f
sudo journalctl -u grafana-server -f
```

## Important Paths

### Configuration

```
config/global.yaml              Main configuration file
config/hosts/                   Per-host module configurations
```

### Service Configs

```
/etc/prometheus/prometheus.yml  Prometheus configuration
/etc/prometheus/rules/          Alert rules
/etc/alertmanager/alertmanager.yml  Alertmanager configuration
/etc/loki/loki-config.yaml      Loki configuration
/etc/grafana/grafana.ini        Grafana configuration
/etc/nginx/sites-available/observability  Nginx reverse proxy config
```

### Data Directories

```
/var/lib/prometheus/            Metrics data
/var/lib/loki/                  Log data
/var/lib/grafana/               Dashboards and settings
/var/lib/alertmanager/          Alert state
```

### Logs

```
/var/log/grafana/              Grafana logs
/var/log/nginx/                Nginx access/error logs
journalctl -u prometheus       Prometheus logs
journalctl -u loki             Loki logs
journalctl -u alertmanager     Alertmanager logs
```

### Backups

```
/var/backups/observability-stack/  Configuration backups
```

## Access URLs

```
Grafana:        https://YOUR_DOMAIN/
Prometheus:     https://YOUR_DOMAIN/prometheus/
Loki:           https://YOUR_DOMAIN/loki/
Alertmanager:   https://YOUR_DOMAIN/alertmanager/
```

## Default Credentials

### Grafana
```
Username: admin
Password: (set in config/global.yaml)
```

### Prometheus/Loki (Basic Auth)
```
Username: prometheus / loki
Password: (set in config/global.yaml)
```

## Exporter Ports

```
Port 9090  - Prometheus
Port 3000  - Grafana
Port 3100  - Loki
Port 9093  - Alertmanager
Port 9100  - Node Exporter
Port 9113  - Nginx Exporter
Port 9104  - MySQL Exporter
Port 9253  - PHP-FPM Exporter
Port 9191  - Fail2ban Exporter
```

## Common Tasks

### Check Prometheus Targets

```bash
# Via web UI
https://YOUR_DOMAIN/prometheus/targets

# Via CLI
curl -s http://localhost:9090/api/v1/targets | jq .
```

### Reload Prometheus Configuration

```bash
# Graceful reload (no data loss)
sudo systemctl reload prometheus

# Or via API
curl -X POST http://localhost:9090/-/reload
```

### Test Alertmanager Configuration

```bash
# Validate config
sudo /usr/local/bin/alertmanager --config.file=/etc/alertmanager/alertmanager.yml --config.check

# Send test alert
amtool alert add test_alert severity=warning instance=localhost
```

### Query Logs in Loki

```bash
# Via Grafana Explore or LogCLI
logcli query '{job="nginx_access"}' --limit=50 --since=1h

# Or via API
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="nginx_access"}' \
  --data-urlencode 'limit=10' | jq .
```

### Backup Current Configuration

```bash
# Backup is automatic before setup-observability.sh runs
# Manual backup:
sudo tar -czf observability-backup-$(date +%Y%m%d).tar.gz \
  /etc/prometheus \
  /etc/alertmanager \
  /etc/loki \
  /etc/grafana \
  /etc/nginx/sites-available/observability
```

### Restore from Backup

```bash
# List available backups
ls -lh /var/backups/observability-stack/

# Restore specific files
sudo cp /var/backups/observability-stack/YYYYMMDD_HHMMSS/prometheus.yml \
  /etc/prometheus/prometheus.yml

# Restart service after restore
sudo systemctl restart prometheus
```

## Troubleshooting

### Service Won't Start

```bash
# Check service status and logs
sudo systemctl status SERVICE_NAME
sudo journalctl -u SERVICE_NAME -n 50

# Validate configuration
sudo /usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --config.check
sudo /usr/local/bin/alertmanager --config.file=/etc/alertmanager/alertmanager.yml --config.check

# Check file permissions
ls -l /etc/prometheus/
sudo chown -R prometheus:prometheus /etc/prometheus/
```

### Targets Not Appearing in Prometheus

```bash
# Check firewall on monitored host
sudo ufw status

# Test connectivity from observability server
curl http://MONITORED_HOST_IP:9100/metrics

# Check Prometheus config
cat /etc/prometheus/prometheus.yml

# Reload Prometheus
sudo systemctl reload prometheus
```

### No Alerts Received

```bash
# Check Alertmanager status
sudo systemctl status alertmanager

# View Alertmanager logs
sudo journalctl -u alertmanager -f

# Test SMTP connectivity
telnet smtp-relay.brevo.com 587

# Check alert rules
promtool check rules /etc/prometheus/rules/*.yml

# View active alerts in Prometheus
https://YOUR_DOMAIN/prometheus/alerts
```

### Grafana Dashboards Not Loading

```bash
# Check Grafana logs
sudo journalctl -u grafana-server -n 100

# Check datasource connectivity
curl -s http://admin:PASSWORD@localhost:3000/api/datasources | jq .

# Restart Grafana
sudo systemctl restart grafana-server
```

### SSL Certificate Issues

```bash
# Check certificate expiry
sudo certbot certificates

# Renew certificate manually
sudo certbot renew

# Test nginx configuration
sudo nginx -t

# View nginx error logs
sudo tail -f /var/log/nginx/error.log
```

### Disk Space Running Low

```bash
# Check disk usage
df -h
du -sh /var/lib/prometheus
du -sh /var/lib/loki

# Adjust retention in config/global.yaml
# Then rerun setup-observability.sh

# Manually compact Prometheus data
sudo systemctl stop prometheus
sudo /usr/local/bin/promtool tsdb analyze /var/lib/prometheus
sudo systemctl start prometheus
```

## One-Liners

```bash
# Get current metric value for a host
curl -s 'http://localhost:9090/api/v1/query?query=up{instance="webserver1"}' | jq .

# List all active targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].labels.instance'

# Count alerts firing
curl -s http://localhost:9090/api/v1/alerts | jq '[.data.alerts[] | select(.state=="firing")] | length'

# Get recent logs for a host
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={host="webserver1"}' \
  --data-urlencode 'limit=20' | jq -r '.data.result[].values[][1]'

# Check all exporter health
for port in 9100 9113 9104 9253 9191; do
  echo -n "Port $port: "
  curl -s http://localhost:$port/metrics > /dev/null && echo "OK" || echo "FAILED"
done
```

## Getting Help

```bash
# Script help
./scripts/setup-observability.sh --help
./scripts/module-manager.sh help
./scripts/validate-config.sh --help

# Check module details
./scripts/module-manager.sh show MODULE_NAME

# View comprehensive docs
cat observability-stack/README.md

# Health check
./scripts/health-check.sh
```

## Emergency Procedures

### Complete Uninstall

```bash
# On observability server
sudo ./scripts/setup-observability.sh --uninstall --purge

# On monitored hosts
sudo ./scripts/setup-monitored-host.sh --uninstall --purge
```

### Restore from Catastrophic Failure

```bash
# 1. Reinstall from scratch
sudo ./scripts/setup-observability.sh --force

# 2. Restore configs from backup
sudo cp -r /var/backups/observability-stack/LATEST/* /etc/

# 3. Fix permissions
sudo chown -R prometheus:prometheus /etc/prometheus
sudo chown -R grafana:grafana /etc/grafana
sudo chown -R loki:loki /etc/loki
sudo chown -R alertmanager:alertmanager /etc/alertmanager

# 4. Restart all services
sudo systemctl restart prometheus grafana-server loki alertmanager nginx
```

## Performance Tuning

```bash
# Reduce Prometheus memory usage (adjust retention)
# Edit config/global.yaml: retention.metrics_days

# Reduce Loki disk usage (adjust retention)
# Edit config/global.yaml: retention.logs_days

# Optimize Prometheus queries
# Add recording rules in prometheus/rules/

# Limit Grafana concurrent queries
# Edit /etc/grafana/grafana.ini: [database] max_connections

# Enable Prometheus remote write for long-term storage
# Add remote_write section to prometheus.yml
```

## Quick Links

- Prometheus Documentation: https://prometheus.io/docs/
- Grafana Documentation: https://grafana.com/docs/
- Loki Documentation: https://grafana.com/docs/loki/
- Alertmanager Documentation: https://prometheus.io/docs/alerting/
