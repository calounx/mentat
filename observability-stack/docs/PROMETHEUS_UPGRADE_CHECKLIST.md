# Prometheus Two-Stage Upgrade - Quick Reference Checklist

**CRITICAL UPGRADE**: Prometheus 2.48.1 → 2.55.1 → 3.8.1

**WARNING**: This is a one-way migration. Read full documentation before proceeding.

Full documentation: [PROMETHEUS_TWO_STAGE_UPGRADE.md](PROMETHEUS_TWO_STAGE_UPGRADE.md)

---

## Pre-Upgrade Preparation

### One Week Before Stage 1

- [ ] Read complete upgrade documentation
- [ ] Review Prometheus 2.55.1 changelog
- [ ] Verify 15+ GB free disk space: `df -h /var/lib/prometheus`
- [ ] Schedule downtime window (15 minutes)
- [ ] Notify team of upgrade plan
- [ ] Export Grafana dashboards as backup

### One Day Before Stage 1

- [ ] Verify all targets healthy
- [ ] Confirm backup storage available
- [ ] Review rollback plan
- [ ] Ensure on-call engineer available

---

## STAGE 1: Prometheus 2.48.1 → 2.55.1

### Stage 1 Pre-Flight (1 hour before)

```bash
# Verify current state
prometheus --version  # Should show 2.48.1
promtool check config /etc/prometheus/prometheus.yml
curl -s http://localhost:9090/api/v1/targets | jq '[.data.activeTargets[] | select(.health != "up")] | length'  # Should be 0

# Create backup
BACKUP_DIR="/var/backups/prometheus-upgrade-stage1/backup-$(date +%Y%m%d-%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"
curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot
SNAPSHOT_DIR=$(ls -t /var/lib/prometheus/snapshots/ | head -1)
sudo cp -a "/var/lib/prometheus/snapshots/$SNAPSHOT_DIR" "$BACKUP_DIR/tsdb-snapshot"
sudo cp -a /etc/prometheus "$BACKUP_DIR/config"
sudo cp -a /etc/systemd/system/prometheus.service "$BACKUP_DIR/"
sudo cp /usr/local/bin/prometheus "$BACKUP_DIR/prometheus-binary-2.48.1"
sudo cp /usr/local/bin/promtool "$BACKUP_DIR/promtool-binary-2.48.1"
echo "2.48.1" > "$BACKUP_DIR/VERSION"

# SAVE THIS PATH FOR ROLLBACK
echo "Backup location: $BACKUP_DIR"

# Download Prometheus 2.55.1
cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v2.55.1/prometheus-2.55.1.linux-amd64.tar.gz
wget https://github.com/prometheus/prometheus/releases/download/v2.55.1/sha256sums.txt
sha256sum -c sha256sums.txt 2>&1 | grep "prometheus-2.55.1.linux-amd64.tar.gz"  # Verify: OK
tar -xzf prometheus-2.55.1.linux-amd64.tar.gz
cd prometheus-2.55.1.linux-amd64
```

### Stage 1 Execution (15 minutes downtime)

```bash
# Stop Prometheus 2.48.1
sudo systemctl stop prometheus
sudo systemctl status prometheus  # Verify: inactive (dead)

# Install Prometheus 2.55.1
cd /tmp/prometheus-2.55.1.linux-amd64
sudo cp prometheus promtool /usr/local/bin/
sudo chown root:root /usr/local/bin/prometheus /usr/local/bin/promtool
sudo chmod 755 /usr/local/bin/prometheus /usr/local/bin/promtool
prometheus --version  # Verify: 2.55.1

# Start Prometheus 2.55.1 (TSDB migration will occur automatically)
sudo systemctl start prometheus

# Monitor TSDB migration (10-15 minutes)
sudo journalctl -u prometheus -f
# Wait for: "TSDB migration completed successfully" and "Server is ready to receive web requests"
```

### Stage 1 Validation (Immediate)

```bash
# Service health
sudo systemctl status prometheus  # Verify: active (running)
prometheus --version  # Verify: 2.55.1
curl -s http://localhost:9090/-/healthy  # Verify: "Prometheus is Healthy."
curl -s http://localhost:9090/-/ready  # Verify: "Prometheus is Ready."

# Targets
sleep 60  # Wait for first scrape
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {instance: .labels.instance, health: .health}'
# Verify: All targets show "health": "up"

# Alert rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].name'  # Verify: All groups listed
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.health != "ok")'  # Verify: Empty

# Data continuity
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.status'  # Verify: "success"
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.data.result | length'  # Verify: Non-zero

# Grafana
# Access http://your-domain:3000
# Configuration → Data Sources → Prometheus → Test
# Verify: "Data source is working"
# Check all dashboards display data

# Logs
sudo journalctl -u prometheus -n 200 --no-pager | grep -Ei "error|fatal"
# Verify: No critical errors
```

### Stage 1 Daily Checks (1-2 weeks)

```bash
# Daily health check script
curl -s http://localhost:9090/-/healthy && echo "HEALTHY" || echo "UNHEALTHY"
curl -s http://localhost:9090/api/v1/targets | jq '[.data.activeTargets[] | select(.health != "up")] | length'  # Should be 0
sudo journalctl -u prometheus --since "1 day ago" | grep -Ei "error|fatal" | wc -l  # Should be 0 or minimal
```

### Stage 1 Sign-Off Criteria (Before Stage 2)

- [ ] Prometheus 2.55.1 stable for 1-2 weeks
- [ ] All daily checks passed
- [ ] No TSDB compaction errors
- [ ] All targets scraped successfully
- [ ] Alert rules evaluating correctly
- [ ] Grafana dashboards operational
- [ ] No performance degradation
- [ ] Team approval to proceed

---

## STAGE 2: Prometheus 2.55.1 → 3.8.1

### Stage 2 Preparation (One week before)

```bash
# Review breaking changes
cat docs/PROMETHEUS_TWO_STAGE_UPGRADE.md | grep -A50 "Breaking Changes in Prometheus 3.x"

# Download Prometheus 3.8.1 for testing
cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v3.8.1/prometheus-3.8.1.linux-amd64.tar.gz
wget https://github.com/prometheus/prometheus/releases/download/v3.8.1/sha256sums.txt
sha256sum -c sha256sums.txt 2>&1 | grep "prometheus-3.8.1.linux-amd64.tar.gz"  # Verify: OK
tar -xzf prometheus-3.8.1.linux-amd64.tar.gz

# Test configuration with Prometheus 3.x promtool
cd /tmp/prometheus-3.8.1.linux-amd64
./promtool check config /etc/prometheus/prometheus.yml  # Verify: SUCCESS
./promtool check rules /etc/prometheus/rules/*.yml  # Verify: SUCCESS
```

### Stage 2 Configuration Updates

#### Update 1: prometheus.yml

```bash
# Backup current config
sudo cp /etc/prometheus/prometheus.yml /etc/prometheus/prometheus.yml.pre-v3

# Edit configuration
sudo nano /etc/prometheus/prometheus.yml
```

Add to `global` section:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'observability-stack'

  # NEW: Native histogram configuration
  scrape_protocols:
    - PrometheusProto
    - OpenMetricsText1.0.0
    - OpenMetricsText0.0.1
    - PrometheusText0.0.4
```

```bash
# Validate new config
cd /tmp/prometheus-3.8.1.linux-amd64
./promtool check config /etc/prometheus/prometheus.yml  # Verify: SUCCESS
```

#### Update 2: systemd Service File

```bash
# Backup current service file
sudo cp /etc/systemd/system/prometheus.service /etc/systemd/system/prometheus.service.pre-v3

# Edit service file
sudo nano /etc/systemd/system/prometheus.service
```

**Remove these deprecated flags**:
- `--storage.tsdb.allow-overlapping-blocks`
- `--storage.tsdb.wal-compression`

**Add these new flags**:
- `--enable-feature=native-histograms`
- `--enable-feature=exemplar-storage`

**Updated ExecStart** (example):

```ini
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --storage.tsdb.retention.time=15d \
  --web.enable-lifecycle \
  --enable-feature=exemplar-storage \
  --enable-feature=native-histograms
```

```bash
# Validate systemd syntax
systemd-analyze verify prometheus.service  # Verify: No errors
```

### Stage 2 Pre-Flight (1 hour before)

```bash
# Create Stage 2 backup
BACKUP_DIR="/var/backups/prometheus-upgrade-stage2/backup-$(date +%Y%m%d-%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"
curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot
SNAPSHOT_DIR=$(ls -t /var/lib/prometheus/snapshots/ | head -1)
sudo cp -a "/var/lib/prometheus/snapshots/$SNAPSHOT_DIR" "$BACKUP_DIR/tsdb-snapshot"
sudo cp -a /etc/prometheus "$BACKUP_DIR/config"
sudo cp -a /etc/systemd/system/prometheus.service "$BACKUP_DIR/"
sudo cp /usr/local/bin/prometheus "$BACKUP_DIR/prometheus-binary-2.55.1"
sudo cp /usr/local/bin/promtool "$BACKUP_DIR/promtool-binary-2.55.1"
echo "2.55.1" > "$BACKUP_DIR/VERSION"

# SAVE THIS PATH FOR ROLLBACK
echo "Stage 2 backup location: $BACKUP_DIR"

# Final pre-validation
cd /tmp/prometheus-3.8.1.linux-amd64
./promtool check config /etc/prometheus/prometheus.yml  # Verify: SUCCESS
./promtool check rules /etc/prometheus/rules/*.yml  # Verify: SUCCESS
```

### Stage 2 Execution (20 minutes downtime)

```bash
# Stop Prometheus 2.55.1
sudo systemctl stop prometheus
sudo systemctl status prometheus  # Verify: inactive (dead)

# Install Prometheus 3.8.1
cd /tmp/prometheus-3.8.1.linux-amd64
sudo cp prometheus promtool /usr/local/bin/
sudo chown root:root /usr/local/bin/prometheus /usr/local/bin/promtool
sudo chmod 755 /usr/local/bin/prometheus /usr/local/bin/promtool
prometheus --version  # Verify: 3.8.1

# Reload systemd and start Prometheus 3.8.1
sudo systemctl daemon-reload
sudo systemctl start prometheus

# Monitor TSDB v2 → v3 migration (15-20 minutes)
sudo journalctl -u prometheus -f
# Wait for: "TSDB migration completed successfully" and "Server is ready to receive web requests"
```

### Stage 2 Validation (Immediate)

```bash
# Service health
sudo systemctl status prometheus  # Verify: active (running)
prometheus --version  # Verify: 3.8.1
curl -s http://localhost:9090/api/v1/status/buildinfo | jq .data.version  # Verify: "3.8.1"
curl -s http://localhost:9090/-/healthy  # Verify: "Prometheus is Healthy."
curl -s http://localhost:9090/-/ready  # Verify: "Prometheus is Ready."

# Native histograms enabled
curl -s http://localhost:9090/api/v1/status/flags | jq '.data | ."enable-feature"'
# Verify: Contains "native-histograms"

# Targets
sleep 30
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {instance: .labels.instance, health: .health}'
# Verify: All targets show "health": "up"

curl -s http://localhost:9090/api/v1/targets | jq '[.data.activeTargets[] | select(.health != "up")] | length'
# Verify: 0

# Alert rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].name'  # Verify: All groups listed
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.type == "alerting") | {alert: .name, state: .state, health: .health}'
# Verify: All rules show "health": "ok"

# Data continuity (test across upgrade time)
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.status'  # Verify: "success"
curl -s 'http://localhost:9090/api/v1/query?query=up&time='$(($(date +%s) - 86400)) | jq '.status'  # Verify: "success"

# Range query across upgrade
UPGRADE_TIME=$(($(date +%s) - 1800))  # Adjust to actual upgrade time
curl -s 'http://localhost:9090/api/v1/query_range?query=up{instance="observability-vps"}&start='$((UPGRADE_TIME - 3600))'&end='$((UPGRADE_TIME + 3600))'&step=60s' | jq '.status'
# Verify: "success"

# Grafana validation
# 1. Configuration → Data Sources → Prometheus → Test
#    Verify: "Data source is working"
# 2. Check all dashboards:
#    - Overview Dashboard
#    - Node Exporter Dashboard
#    - Nginx/MySQL/PHP-FPM Dashboards (if enabled)
#    - Logs Explorer
# 3. Verify all panels show data
# 4. Test queries in Explore view

# Performance test
time curl -s 'http://localhost:9090/api/v1/query?query=up' > /dev/null
# Verify: <1 second

time curl -s 'http://localhost:9090/api/v1/query_range?query=rate(node_cpu_seconds_total[5m])&start='$(($(date +%s) - 3600))'&end='$(date +%s)'&step=15s' > /dev/null
# Verify: 2-5 seconds

# Check for errors
sudo journalctl -u prometheus -n 500 --no-pager | grep -Ei "error|fatal"
# Verify: No critical errors

# TSDB status
curl -s http://localhost:9090/api/v1/status/tsdb | jq .
# Review for warnings
```

### Stage 2 Monitoring (First 24 hours)

**Every 2 hours**:

```bash
curl -s http://localhost:9090/-/healthy && echo "HEALTHY" || echo "UNHEALTHY"
curl -s http://localhost:9090/api/v1/targets | jq '[.data.activeTargets[] | select(.health != "up")] | length'
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.health != "ok") | .name'
sudo journalctl -u prometheus --since "2 hours ago" | grep -Ei "error|fatal" | wc -l
```

**Twice daily (first 48 hours)**:

- [ ] Review all Grafana dashboards
- [ ] Check alert firing patterns
- [ ] Verify TSDB compaction success
- [ ] Monitor disk usage growth
- [ ] Test query performance

### Stage 2 Sign-Off (After 48 hours)

- [ ] All validation checks passed
- [ ] No regressions detected
- [ ] Performance acceptable
- [ ] All features working
- [ ] Team sign-off obtained

---

## Emergency Rollback Procedures

### Rollback Stage 1 (2.55.1 → 2.48.1)

**WARNING: Data loss - only use if Stage 1 completely failed**

```bash
# Stop failed Prometheus
sudo systemctl stop prometheus

# Restore from backup
BACKUP_DIR="/var/backups/prometheus-upgrade-stage1/backup-YYYYMMDD-HHMMSS"
sudo cp "$BACKUP_DIR/prometheus-binary-2.48.1" /usr/local/bin/prometheus
sudo cp "$BACKUP_DIR/promtool-binary-2.48.1" /usr/local/bin/promtool
sudo chown root:root /usr/local/bin/prometheus /usr/local/bin/promtool
sudo chmod 755 /usr/local/bin/prometheus /usr/local/bin/promtool

# Restore TSDB
sudo rm -rf /var/lib/prometheus/*
sudo cp -a "$BACKUP_DIR/tsdb-snapshot/"* /var/lib/prometheus/
sudo chown -R prometheus:prometheus /var/lib/prometheus

# Restore config
sudo cp -a "$BACKUP_DIR/config/"* /etc/prometheus/
sudo cp "$BACKUP_DIR/prometheus.service" /etc/systemd/system/
sudo systemctl daemon-reload

# Start
sudo systemctl start prometheus
sudo journalctl -u prometheus -f

# Validate
prometheus --version  # Should be 2.48.1
curl -s http://localhost:9090/-/healthy
```

### Rollback Stage 2 (3.8.1 → 2.55.1)

```bash
# Stop Prometheus 3.8.1
sudo systemctl stop prometheus

# Restore from backup
BACKUP_DIR="/var/backups/prometheus-upgrade-stage2/backup-YYYYMMDD-HHMMSS"
sudo cp "$BACKUP_DIR/prometheus-binary-2.55.1" /usr/local/bin/prometheus
sudo cp "$BACKUP_DIR/promtool-binary-2.55.1" /usr/local/bin/promtool
sudo chown root:root /usr/local/bin/prometheus /usr/local/bin/promtool
sudo chmod 755 /usr/local/bin/prometheus /usr/local/bin/promtool

# Restore config
sudo cp -a "$BACKUP_DIR/config/"* /etc/prometheus/
sudo cp "$BACKUP_DIR/prometheus.service" /etc/systemd/system/
sudo systemctl daemon-reload

# Restore TSDB if needed
# sudo rm -rf /var/lib/prometheus/*
# sudo cp -a "$BACKUP_DIR/tsdb-snapshot/"* /var/lib/prometheus/
# sudo chown -R prometheus:prometheus /var/lib/prometheus

# Start
sudo systemctl start prometheus
sudo journalctl -u prometheus -f

# Validate
prometheus --version  # Should be 2.55.1
curl -s http://localhost:9090/-/healthy
```

---

## Quick Status Commands

```bash
# Overall health
curl -s http://localhost:9090/-/healthy && echo "HEALTHY" || echo "UNHEALTHY"

# Version
prometheus --version

# Service status
sudo systemctl status prometheus

# Recent errors
sudo journalctl -u prometheus -n 100 --no-pager | grep -Ei "error|fatal"

# Target health summary
curl -s http://localhost:9090/api/v1/targets | jq '{total: (.data.activeTargets | length), up: ([.data.activeTargets[] | select(.health == "up")] | length), down: ([.data.activeTargets[] | select(.health != "up")] | length)}'

# Alert rule health
curl -s http://localhost:9090/api/v1/rules | jq '{total_rules: [.data.groups[].rules[] | select(.type == "alerting")] | length, unhealthy: [.data.groups[].rules[] | select(.type == "alerting" and .health != "ok")] | length}'

# TSDB size
sudo du -sh /var/lib/prometheus

# Disk space
df -h /var/lib/prometheus
```

---

## Timeline Summary

```
Week 0: Preparation
  Day 1-2: Review docs, plan
  Day 3-4: Create backups
  Day 5: STAGE 1 EXECUTION (15 min)
  Day 6-7: Initial validation

Week 1-2: Monitoring Stage 1
  Daily: Health checks
  Weekly: Dashboard review
  End: Stage 1 sign-off

Week 3: Stage 2 Preparation
  Day 1-2: Review breaking changes
  Day 3-4: Update configs, backups
  Day 5: STAGE 2 EXECUTION (20 min)
  Day 6-7: Intensive monitoring

Week 4: Final Sign-Off
  Complete validation
  Team approval
  Upgrade complete
```

---

**CRITICAL REMINDERS**:

1. This is a ONE-WAY migration after Stage 1
2. Backup before EACH stage
3. Wait 1-2 weeks between stages
4. Validate EVERY step
5. Read full documentation: `docs/PROMETHEUS_TWO_STAGE_UPGRADE.md`

**Support**: If issues arise, consult full documentation for troubleshooting and detailed rollback procedures.
