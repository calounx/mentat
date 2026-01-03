# Native Observability Stack Deployment Guide

Complete step-by-step deployment guide for replacing Docker-based observability with native Debian 13 services.

## Pre-Deployment Checklist

### System Requirements

- Operating System: Debian 11+ (Tested on Debian 13)
- CPU: 2+ cores recommended
- RAM: 4GB minimum, 8GB recommended
- Disk: 20GB+ free space for data storage
- Network: Ports 9090, 3000, 3100, 9093, 9100 available

### Server Information

- Monitoring Server: mentat.arewel.com
- Application Server: landsraad.arewel.com
- Deployment User: stilgar (with sudo access)

### Pre-Deployment Steps

1. Backup existing observability configurations (if any)
2. Document current monitoring setup
3. Plan maintenance window (30-60 minutes)
4. Notify team of deployment

## Deployment Steps

### Step 1: Remove Docker-Based Stack (If Exists)

```bash
# Stop Docker containers
docker-compose -f /path/to/docker-compose.yml down

# Remove Docker volumes (if safe to do so)
docker volume ls | grep -E 'prometheus|grafana|loki' | awk '{print $2}' | xargs docker volume rm

# Backup any important dashboards or configurations first!
```

### Step 2: Deploy to Monitoring Server (mentat.arewel.com)

```bash
# SSH to monitoring server
ssh stilgar@mentat.arewel.com

# Navigate to deployment directory
cd /home/calounx/repositories/mentat/chom/deploy/observability-native

# Review installation scripts
ls -la *.sh

# Run master installation (installs all components)
sudo bash install-all.sh

# This will install:
# - Prometheus (metrics)
# - Grafana (dashboards)
# - Loki (log aggregation)
# - Promtail (log shipping)
# - AlertManager (alerts)
# - Node Exporter (system metrics)
```

### Step 3: Verify Installation

```bash
# Check all services are running
sudo bash manage-services.sh status

# Expected output: All services should show "running"

# Check health endpoints
sudo bash manage-services.sh health

# Verify ports are listening
sudo bash manage-services.sh ports
```

### Step 4: Configure Grafana

```bash
# Access Grafana web interface
# URL: http://mentat.arewel.com:3000
# Default credentials: admin / changeme

# IMPORTANT: Change password immediately!
sudo grafana-cli admin reset-admin-password <NEW_SECURE_PASSWORD>

# Verify Prometheus datasource is connected
# Go to: Configuration > Data Sources > Prometheus
# Test connection should show "Data source is working"
```

### Step 5: Deploy Promtail to Application Server (landsraad.arewel.com)

```bash
# SSH to application server
ssh stilgar@landsraad.arewel.com

# Copy installation script
scp mentat.arewel.com:/home/calounx/repositories/mentat/chom/deploy/observability-native/install-promtail.sh .

# Install Promtail
sudo bash install-promtail.sh

# Install Node Exporter for system metrics
scp mentat.arewel.com:/home/calounx/repositories/mentat/chom/deploy/observability-native/install-node-exporter.sh .
sudo bash install-node-exporter.sh

# Verify services
systemctl status promtail
systemctl status node_exporter
```

### Step 6: Configure Alert Notifications

```bash
# On monitoring server, edit AlertManager config
sudo nano /etc/alertmanager/alertmanager.yml

# Update email settings:
global:
  smtp_smarthost: 'smtp.example.com:587'
  smtp_from: 'alertmanager@chom.arewel.com'
  smtp_auth_username: 'your-username'
  smtp_auth_password: 'your-password'

receivers:
  - name: 'critical'
    email_configs:
      - to: 'ops@arewel.com'
        headers:
          Subject: '[CRITICAL] {{ .GroupLabels.alertname }}'

# Validate and reload
sudo amtool check-config /etc/alertmanager/alertmanager.yml
sudo systemctl reload alertmanager
```

### Step 7: Import Grafana Dashboards

```bash
# Copy pre-built dashboards to Grafana
sudo cp /path/to/dashboards/*.json /var/lib/grafana/dashboards/

# Or import via UI:
# 1. Go to Dashboards > Import
# 2. Upload JSON or use dashboard ID from grafana.com
# 3. Recommended dashboards:
#    - Node Exporter Full: 1860
#    - Prometheus: 3662
#    - Loki Dashboard: 13639
```

### Step 8: Configure Prometheus Scrape Targets

```bash
# Edit Prometheus configuration
sudo nano /etc/prometheus/prometheus.yml

# Verify scrape targets include:
scrape_configs:
  - job_name: 'chom_app'
    static_configs:
      - targets: ['landsraad.arewel.com:9100']

  - job_name: 'chom'
    metrics_path: '/metrics'
    static_configs:
      - targets: ['landsraad.arewel.com']

# Validate and reload
sudo promtool check config /etc/prometheus/prometheus.yml
sudo systemctl reload prometheus
```

### Step 9: Test Alert Rules

```bash
# Send test alert
curl -X POST http://localhost:9093/api/v2/alerts -H "Content-Type: application/json" -d '[{
  "labels": {"alertname": "TestAlert", "severity": "info"},
  "annotations": {"summary": "Test alert", "description": "Testing alert routing"}
}]'

# Check alert appears in AlertManager
curl http://localhost:9093/api/v2/alerts | jq

# Check Grafana alerts panel
```

### Step 10: Configure Log Collection

```bash
# On application server, verify Promtail is collecting logs
sudo journalctl -u promtail -f

# Should see log collection activity

# On monitoring server, verify logs are in Loki
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="chom"}' \
  --data-urlencode 'limit=10' | jq

# Or query in Grafana: Explore > Loki datasource > {job="chom"}
```

## Post-Deployment Validation

### Comprehensive Health Check

```bash
# Run on monitoring server
cd /home/calounx/repositories/mentat/chom/deploy/observability-native

# Check all services
sudo bash manage-services.sh status
sudo bash manage-services.sh health

# Run observability validation script
cd /home/calounx/repositories/mentat/chom/deploy/validation
sudo bash observability-check.sh
```

### Verify Metrics Collection

```bash
# Check Prometheus targets are up
curl http://mentat.arewel.com:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# All targets should show health: "up"
```

### Verify Log Aggregation

```bash
# Check Loki is receiving logs
curl http://mentat.arewel.com:3100/loki/api/v1/labels | jq

# Should return list of log labels including {job="chom"}
```

### Performance Baseline

```bash
# Check resource usage
top -bn1 | grep -E 'prometheus|grafana|loki|promtail|alertmanager'

# Check disk usage
sudo bash manage-services.sh disk

# Recommended: < 1GB for initial setup
```

## Troubleshooting

### Service Won't Start

```bash
# Check service status
sudo systemctl status <service-name>

# View recent logs
sudo journalctl -u <service-name> -n 50

# Common issues:
# 1. Port already in use: ss -tlnp | grep <port>
# 2. Configuration error: Check validation commands
# 3. Permission issues: Check file ownership
```

### No Metrics in Prometheus

```bash
# Check targets in Prometheus
curl http://localhost:9090/api/v1/targets

# Verify network connectivity
curl http://landsraad.arewel.com:9100/metrics

# Check firewall rules
sudo ufw status
sudo ss -tlnp | grep 9100
```

### No Logs in Loki

```bash
# Check Promtail is running
sudo systemctl status promtail

# Check Promtail can reach Loki
curl http://mentat.arewel.com:3100/ready

# Check Promtail logs
sudo journalctl -u promtail -f

# Verify log file permissions
ls -la /var/www/chom/current/storage/logs/
```

### Grafana Can't Connect to Datasources

```bash
# Check Grafana logs
sudo journalctl -u grafana-server -n 100

# Verify datasource configuration
sudo cat /etc/grafana/provisioning/datasources/prometheus.yml

# Test connectivity from Grafana server
curl http://localhost:9090/api/v1/query?query=up
curl http://localhost:3100/ready
```

## Rollback Procedure

If deployment fails and you need to rollback:

```bash
# Stop all new services
sudo bash manage-services.sh stop

# Uninstall observability stack
sudo bash uninstall-all.sh

# Restore Docker-based stack (if applicable)
docker-compose -f /path/to/old/docker-compose.yml up -d

# Restore configurations from backup
# Backup location: /root/observability-backup-<timestamp>
```

## Security Hardening (Production)

### Firewall Configuration

```bash
# Restrict Prometheus to internal network only
sudo ufw delete allow 9090
sudo ufw allow from 192.168.0.0/16 to any port 9090

# Restrict other services similarly
sudo ufw allow from 192.168.0.0/16 to any port 9100  # Node Exporter
sudo ufw allow from 192.168.0.0/16 to any port 9093  # AlertManager

# Grafana can be public (but use reverse proxy with SSL)
sudo ufw allow 3000
```

### Enable HTTPS

```bash
# Use Nginx/Apache reverse proxy with Let's Encrypt
# Example Nginx config:

server {
    listen 443 ssl http2;
    server_name grafana.arewel.com;

    ssl_certificate /etc/letsencrypt/live/grafana.arewel.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/grafana.arewel.com/privkey.pem;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### Authentication

```bash
# Grafana: Already has authentication
# Prometheus/AlertManager: Add basic auth via reverse proxy or use native auth

# Example: Add basic auth to Prometheus systemd service
sudo nano /etc/systemd/system/prometheus.service

# Add to ExecStart:
--web.enable-admin-api \
--web.config.file=/etc/prometheus/web-config.yml

# Create web-config.yml with basic auth
```

## Backup Strategy

### Daily Backup Script

```bash
# Create backup script
cat > /usr/local/bin/backup-observability.sh <<'EOF'
#!/bin/bash
BACKUP_DIR=/backup/observability
DATE=$(date +%Y%m%d)

mkdir -p $BACKUP_DIR

# Backup configurations
tar czf $BACKUP_DIR/config-$DATE.tar.gz \
  /etc/prometheus \
  /etc/grafana \
  /etc/loki \
  /etc/promtail \
  /etc/alertmanager

# Backup Grafana database (SQLite)
cp /var/lib/grafana/grafana.db $BACKUP_DIR/grafana-$DATE.db

# Keep last 7 days
find $BACKUP_DIR -mtime +7 -delete
EOF

chmod +x /usr/local/bin/backup-observability.sh

# Add to cron
echo "0 2 * * * /usr/local/bin/backup-observability.sh" | sudo crontab -
```

## Maintenance

### Weekly Tasks

- Review disk usage: `sudo bash manage-services.sh disk`
- Check for service errors: `sudo journalctl -p err -since "1 week ago"`
- Review firing alerts
- Update dashboards as needed

### Monthly Tasks

- Review retention policies
- Clean old data if disk is filling up
- Update components to latest stable versions
- Review and optimize alert rules
- Test backup restore procedure

### Component Updates

```bash
# Stop service
sudo systemctl stop prometheus

# Download new version
wget https://github.com/prometheus/prometheus/releases/download/v<VERSION>/prometheus-<VERSION>.linux-amd64.tar.gz

# Extract and replace binary
tar xzf prometheus-<VERSION>.linux-amd64.tar.gz
sudo cp prometheus-<VERSION>.linux-amd64/prometheus /usr/local/bin/

# Start service
sudo systemctl start prometheus

# Verify
sudo systemctl status prometheus
```

## Monitoring the Monitoring

Set up meta-monitoring:

1. Create alerts for observability stack health
2. Monitor disk usage of data directories
3. Set up external uptime monitoring for Grafana
4. Configure dead man's switch alert to ensure alerting is working

## Support

For issues or questions:

1. Check logs: `sudo journalctl -u <service> -f`
2. Review configuration validation
3. Check official documentation links in README.md
4. Review deployment guide troubleshooting section

## Deployment Checklist

- [ ] Pre-deployment backup completed
- [ ] System requirements verified
- [ ] All components installed successfully
- [ ] All services running (manage-services.sh status)
- [ ] Health checks passing (manage-services.sh health)
- [ ] Grafana password changed
- [ ] Prometheus collecting metrics from all targets
- [ ] Loki receiving logs from Promtail
- [ ] AlertManager configured and tested
- [ ] Dashboards imported and functional
- [ ] Alert rules configured
- [ ] Email notifications working
- [ ] Firewall rules configured
- [ ] Backup script configured
- [ ] Documentation updated
- [ ] Team notified of new URLs
- [ ] Post-deployment validation completed

## Success Criteria

Deployment is successful when:

1. All services show "running" status
2. All health endpoints return OK
3. Prometheus shows all targets "up"
4. Grafana displays metrics from Prometheus
5. Loki shows logs from application
6. Test alert successfully delivered
7. No errors in service logs
8. Disk usage is reasonable (< 2GB initial)
9. All ports properly secured
10. Backup procedure tested

## Next Steps After Deployment

1. Create custom dashboards for CHOM application
2. Set up additional alert rules specific to your application
3. Configure log-based alerts in Loki
4. Set up notification channels (Slack, PagerDuty, etc.)
5. Implement retention policies based on storage capacity
6. Document runbook procedures for common incidents
7. Train team on using Grafana and querying metrics/logs
