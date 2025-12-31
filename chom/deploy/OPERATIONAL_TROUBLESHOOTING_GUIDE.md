# CHOM Deployment - Operational Troubleshooting Guide

Quick reference for diagnosing and fixing common deployment and runtime issues.

---

## DEPLOYMENT FAILURES

### Deployment Fails with "No space left on device"

**Symptoms:**
- wget fails mid-download
- Service crashes on startup
- Errors like "cannot create directory: No space left on device"

**Diagnosis:**
```bash
# Check disk usage
df -h
du -sh /var/lib/observability/* 2>/dev/null
du -sh /tmp/* 2>/dev/null

# Check inode usage (sometimes the issue)
df -i
```

**Fix:**
```bash
# Free up space
sudo apt-get clean
sudo journalctl --vacuum-time=7d
rm -rf /tmp/prometheus-* /tmp/loki-* /tmp/node_exporter-*

# Reduce Prometheus retention
sudo sed -i 's/retention.time=15d/retention.time=7d/' /etc/systemd/system/prometheus.service
sudo systemctl daemon-reload && sudo systemctl restart prometheus

# Reduce Loki retention
sudo sed -i 's/retention_period: 720h/retention_period: 168h/' /etc/observability/loki/loki.yml
sudo systemctl restart loki
```

**Prevention:**
Add to script before downloads:
```bash
check_disk_space() {
    local required_mb="$1"
    local available_mb=$(df -m / | awk 'NR==2 {print $4}')
    if [[ $available_mb -lt $required_mb ]]; then
        echo "ERROR: Need ${required_mb}MB, only ${available_mb}MB available"
        exit 1
    fi
}
check_disk_space 2000
```

---

### Deployment Fails with "Out of memory"

**Symptoms:**
- Services crash immediately after starting
- journalctl shows "killed" or "signal 9"
- System becomes unresponsive
- OOM killer messages in kernel log

**Diagnosis:**
```bash
# Check available memory
free -h

# Check OOM killer activity
journalctl -k | grep -i "out of memory\|killed process"
sudo dmesg | grep -i "oom"

# Check which process was killed
journalctl -xe | grep -i "killed process" | tail -10
```

**Fix:**
```bash
# Reduce memory footprint immediately
# 1. Stop non-essential services
sudo systemctl stop grafana-server alertmanager

# 2. Reduce Prometheus memory
sudo systemctl stop prometheus
sudo sed -i 's/retention.time=15d/retention.time=5d/' /etc/systemd/system/prometheus.service
sudo systemctl start prometheus

# 3. Reduce MariaDB buffer pool
sudo sed -i 's/innodb_buffer_pool_size = 256M/innodb_buffer_pool_size = 64M/' \
    /etc/mysql/mariadb.conf.d/99-optimization.cnf
sudo systemctl restart mariadb

# 4. Reduce Redis memory
sudo sed -i 's/maxmemory 128mb/maxmemory 64mb/' /etc/redis/redis.conf
sudo systemctl restart redis-server

# 5. Restart other services
sudo systemctl start grafana-server alertmanager
```

**Prevention:**
Add memory check to deployment:
```bash
check_memory() {
    local total_mb=$(free -m | awk 'NR==2 {print $2}')
    if [[ $total_mb -lt 1024 ]]; then
        echo "WARNING: Only ${total_mb}MB RAM available"
        echo "Adjusting service configuration for low memory..."
        export PROMETHEUS_RETENTION="5d"
        export MARIADB_BUFFER="64M"
        export REDIS_MAXMEMORY="64mb"
    fi
}
```

---

### Services Show "Active" But Not Working

**Symptoms:**
- `systemctl status prometheus` shows "active (running)"
- But curl http://localhost:9090 times out
- Grafana shows "Error" for datasources
- No metrics being collected

**Diagnosis:**
```bash
# Check if process is actually running
ps aux | grep prometheus

# Check if port is listening
sudo lsof -i :9090
sudo netstat -tlnp | grep 9090

# Check service logs
journalctl -xeu prometheus -n 100

# Test health endpoint
curl -v http://localhost:9090/-/healthy
```

**Common Causes & Fixes:**

1. **Config file syntax error**
```bash
# Test Prometheus config
/opt/observability/bin/promtool check config /etc/observability/prometheus/prometheus.yml

# Test Loki config
/opt/observability/bin/loki -config.file=/etc/observability/loki/loki.yml -verify-config
```

2. **Permission issues**
```bash
# Check file ownership
ls -la /var/lib/observability/prometheus
ls -la /etc/observability/prometheus

# Fix ownership
sudo chown -R observability:observability /var/lib/observability
sudo chown -R observability:observability /etc/observability
```

3. **Port already in use**
```bash
# Find what's using the port
sudo lsof -i :9090

# Kill the conflicting process
sudo kill $(sudo lsof -ti :9090)

# Or change port in service file
sudo systemctl stop prometheus
sudo sed -i 's/:9090/:9091/' /etc/systemd/system/prometheus.service
sudo systemctl daemon-reload && sudo systemctl start prometheus
```

---

### Port Conflict During Deployment

**Symptoms:**
- Error: "address already in use"
- Service fails to start
- Port 9090/3100/3000 already occupied

**Diagnosis:**
```bash
# Check all required ports
for port in 80 443 3000 9090 9100 3100 9093 3306 6379; do
    echo "=== Port $port ==="
    sudo lsof -i :$port -P -n
done
```

**Fix:**
```bash
# Safe cleanup - identify process first
PORT=9090
PID=$(sudo lsof -ti :$PORT)
if [[ -n "$PID" ]]; then
    echo "Process on port $PORT:"
    ps -p $PID -o comm=,user=,pid=

    # If it's a CHOM service, restart it
    PROCESS=$(ps -p $PID -o comm= | head -n1)
    if [[ "$PROCESS" =~ (prometheus|loki|grafana) ]]; then
        sudo systemctl restart $PROCESS
    else
        # Unknown process - manual decision
        sudo kill $PID
    fi
fi
```

---

### DNS Resolution Failure

**Symptoms:**
- SSL setup fails with "connection timeout"
- certbot can't verify domain ownership
- Domain resolves to wrong IP

**Diagnosis:**
```bash
# Check if domain resolves
host mentat.arewel.com
dig mentat.arewel.com +short
nslookup mentat.arewel.com

# Check if domain points to THIS server
SERVER_IP=$(hostname -I | awk '{print $1}')
RESOLVED_IP=$(host mentat.arewel.com | awk '/address/ {print $4}' | head -n1)
echo "Server IP:   $SERVER_IP"
echo "Resolved IP: $RESOLVED_IP"

# Check from outside (Google DNS)
curl -s "https://dns.google/resolve?name=mentat.arewel.com&type=A" | jq -r '.Answer[].data'

# Check DNS propagation
dig mentat.arewel.com @8.8.8.8 +short
dig mentat.arewel.com @1.1.1.1 +short
```

**Fix:**
```bash
# 1. Update DNS A record to point to your server IP
SERVER_IP=$(hostname -I | awk '{print $1}')
echo "Set DNS A record for mentat.arewel.com to: $SERVER_IP"

# 2. Wait for DNS propagation (can take up to 48 hours)
# Check every few minutes:
watch -n60 "dig mentat.arewel.com +short"

# 3. Once DNS propagates, run SSL setup manually
sudo certbot --nginx -d mentat.arewel.com --email admin@arewel.com \
    --non-interactive --agree-tos --redirect

# 4. Test SSL
curl -I https://mentat.arewel.com
```

---

### SSL Certificate Setup Fails

**Symptoms:**
- certbot errors: "Connection refused", "timeout", "too many requests"
- Certificate not issued
- HTTPS not working

**Diagnosis:**
```bash
# Check certbot logs
sudo tail -100 /var/log/letsencrypt/letsencrypt.log

# Check if port 80 accessible from outside
curl -I http://mentat.arewel.com

# Check nginx config
sudo nginx -t

# Check firewall
sudo ufw status
```

**Common Issues & Fixes:**

1. **Port 80 blocked by firewall**
```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

2. **Nginx not running**
```bash
sudo systemctl status nginx
sudo systemctl start nginx
```

3. **Rate limit hit (too many attempts)**
```bash
# Check rate limit status
sudo certbot certificates

# Wait 1 hour, then try staging first
sudo certbot --nginx -d mentat.arewel.com --staging --non-interactive

# If staging works, try production
sudo certbot --nginx -d mentat.arewel.com --force-renewal
```

4. **Domain not accessible from internet**
```bash
# Test from external service
curl -I http://mentat.arewel.com

# Check if server is behind NAT/firewall
# May need to configure port forwarding on router
```

---

## RUNTIME ISSUES

### Prometheus Not Collecting Metrics

**Symptoms:**
- Grafana dashboards show "No data"
- Prometheus UI shows targets as "DOWN"
- Scrape errors in logs

**Diagnosis:**
```bash
# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job, health, lastError}'

# Check if node_exporter is running and accessible
curl -s http://localhost:9100/metrics | head -20

# Check Prometheus config
/opt/observability/bin/promtool check config /etc/observability/prometheus/prometheus.yml

# Check Prometheus logs
journalctl -xeu prometheus -n 100
```

**Fix:**
```bash
# Reload Prometheus config
curl -XPOST http://localhost:9090/-/reload

# Or restart Prometheus
sudo systemctl restart prometheus

# If node_exporter down
sudo systemctl restart node_exporter

# Verify targets now UP
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job, health}'
```

---

### Grafana Datasources Showing Error

**Symptoms:**
- Grafana datasources have red "Error" badge
- Dashboards show "Data source connected, but no labels received"
- Can't query Prometheus/Loki from Grafana

**Diagnosis:**
```bash
# Check datasources status
curl -s http://admin:PASSWORD@localhost:3000/api/datasources | jq '.[] | {name, type, url, isDefault}'

# Test Prometheus connection from Grafana host
curl -s http://localhost:9090/-/healthy
curl -s http://localhost:9090/api/v1/query?query=up

# Test Loki connection
curl -s http://localhost:3100/ready
curl -s http://localhost:3100/loki/api/v1/labels

# Check Grafana logs
journalctl -xeu grafana-server -n 100
```

**Fix:**
```bash
# 1. Ensure Prometheus and Loki are running
sudo systemctl restart prometheus loki

# 2. Wait for services to be ready (30s)
sleep 30

# 3. Restart Grafana to reconnect
sudo systemctl restart grafana-server

# 4. Verify datasources (wait 30s for Grafana to start)
sleep 30
curl -s http://admin:PASSWORD@localhost:3000/api/datasources | jq '.[] | {name, url}'

# 5. If still broken, recreate datasources
# Delete existing
curl -X DELETE http://admin:PASSWORD@localhost:3000/api/datasources/1
curl -X DELETE http://admin:PASSWORD@localhost:3000/api/datasources/2

# Recreate (script should do this automatically on next run)
```

---

### Loki Not Receiving Logs

**Symptoms:**
- Loki running but no logs in Grafana
- "No logs found" in Explore view
- Ingestion rate is 0

**Diagnosis:**
```bash
# Check Loki health
curl -s http://localhost:3100/ready

# Check Loki metrics
curl -s http://localhost:3100/metrics | grep loki_distributor_lines_received_total

# Check Loki config
cat /etc/observability/loki/loki.yml

# Check Loki logs
journalctl -xeu loki -n 100
```

**Common Issues:**

1. **Auth enabled but no X-Loki-Org-Id header**
```bash
# Check config
grep auth_enabled /etc/observability/loki/loki.yml

# If "true", either disable it or configure client with tenant ID
sudo sed -i 's/auth_enabled: true/auth_enabled: false/' /etc/observability/loki/loki.yml
sudo systemctl restart loki
```

2. **No log shippers configured**
```bash
# Loki doesn't collect logs automatically
# Need to configure Promtail or other shipper
# For now, test with manual log push:
curl -H "Content-Type: application/json" -XPOST \
    -s "http://localhost:3100/loki/api/v1/push" \
    --data-raw '{"streams": [{"stream": {"job": "test"}, "values": [["'"$(date +%s)000000000"'", "test log message"]]}]}'
```

---

### MariaDB Won't Start

**Symptoms:**
- `systemctl start mariadb` fails
- Error: "Can't connect to local MySQL server"
- Socket file missing

**Diagnosis:**
```bash
# Check status
systemctl status mariadb

# Check error log
sudo tail -50 /var/log/mysql/error.log

# Check if socket exists
ls -la /run/mysqld/mysqld.sock

# Check permissions
ls -la /var/lib/mysql
```

**Common Issues & Fixes:**

1. **InnoDB corruption (unclean shutdown)**
```bash
# Check error log for InnoDB errors
sudo grep -i innodb /var/log/mysql/error.log

# Force InnoDB recovery
sudo systemctl stop mariadb
echo -e "[mysqld]\ninnodb_force_recovery = 1" | sudo tee -a /etc/mysql/mariadb.conf.d/99-recovery.cnf
sudo systemctl start mariadb

# If starts, dump databases
mysqldump -u root -p --all-databases > /tmp/mysql-backup.sql

# Remove recovery mode
sudo rm /etc/mysql/mariadb.conf.d/99-recovery.cnf
sudo systemctl restart mariadb
```

2. **Disk full**
```bash
df -h
sudo du -sh /var/lib/mysql/*

# Free up space, then:
sudo systemctl start mariadb
```

3. **Wrong permissions**
```bash
sudo chown -R mysql:mysql /var/lib/mysql
sudo chmod 750 /var/lib/mysql
sudo systemctl start mariadb
```

---

### Nginx Configuration Errors

**Symptoms:**
- nginx fails to reload
- "nginx: configuration file test failed"
- Site inaccessible

**Diagnosis:**
```bash
# Test configuration
sudo nginx -t

# Check error log
sudo tail -50 /var/log/nginx/error.log

# Check if config files exist
ls -la /etc/nginx/sites-available/
ls -la /etc/nginx/sites-enabled/
```

**Fix:**
```bash
# Backup current config
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup

# Find syntax error
sudo nginx -t 2>&1 | head -20

# Common fixes:
# 1. Missing semicolon - add ; at end of directive
# 2. Unclosed block - check { } matching
# 3. Invalid directive - check spelling

# If can't fix, restore backup
sudo cp /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf

# Or use default config
sudo cp /etc/nginx/nginx.conf.default /etc/nginx/nginx.conf

# Test and reload
sudo nginx -t && sudo systemctl reload nginx
```

---

### SSL Certificate Expired

**Symptoms:**
- Browser shows "Your connection is not private"
- Error: "NET::ERR_CERT_DATE_INVALID"
- HTTPS not working

**Diagnosis:**
```bash
# Check certificate expiry
echo | openssl s_client -servername mentat.arewel.com -connect mentat.arewel.com:443 2>/dev/null | \
    openssl x509 -noout -dates

# Check certbot status
sudo certbot certificates

# Check renewal timer
systemctl status certbot.timer
systemctl list-timers certbot.timer
```

**Fix:**
```bash
# Manual renewal
sudo certbot renew --force-renewal

# Check if renewal worked
sudo certbot certificates

# If renewal fails, check logs
sudo tail -100 /var/log/letsencrypt/letsencrypt.log

# Common issues:
# 1. Port 80 blocked - sudo ufw allow 80/tcp
# 2. Domain DNS changed - update DNS A record
# 3. Rate limit - wait 1 hour

# After fixing issue, try renewal again
sudo certbot renew
sudo systemctl reload nginx
```

---

### Service Restart Loop

**Symptoms:**
- Service continuously restarting
- High CPU usage
- systemctl shows "activating (auto-restart)"

**Diagnosis:**
```bash
# Check service status
systemctl status prometheus
systemctl status loki

# Check restart count
systemctl show prometheus -p NRestarts

# Check logs for error
journalctl -xeu prometheus -n 200 | less

# Monitor restarts in real-time
watch -n1 'systemctl status prometheus | head -20'
```

**Fix:**
```bash
# Stop the restart loop
sudo systemctl stop prometheus
sudo systemctl disable prometheus

# Fix the underlying issue (check logs for cause)
# Common causes:
# 1. Config syntax error - run promtool check config
# 2. Disk full - free up space
# 3. Permission denied - fix file ownership
# 4. Port in use - kill conflicting process

# After fixing, re-enable and start
sudo systemctl enable prometheus
sudo systemctl start prometheus
```

---

## MONITORING & ALERTS

### Check System Health

```bash
#!/bin/bash
# Quick health check script

echo "===== DISK USAGE ====="
df -h | grep -E "Filesystem|/$"

echo -e "\n===== MEMORY USAGE ====="
free -h

echo -e "\n===== LOAD AVERAGE ====="
uptime

echo -e "\n===== SERVICE STATUS ====="
for svc in prometheus loki grafana-server alertmanager nginx mariadb redis-server; do
    printf "%-20s " "$svc:"
    systemctl is-active $svc
done

echo -e "\n===== HEALTH ENDPOINTS ====="
curl -sf http://localhost:9090/-/healthy && echo "Prometheus: HEALTHY" || echo "Prometheus: UNHEALTHY"
curl -sf http://localhost:3100/ready && echo "Loki: READY" || echo "Loki: NOT READY"
curl -sf http://localhost:3000/api/health && echo "Grafana: HEALTHY" || echo "Grafana: UNHEALTHY"

echo -e "\n===== PROMETHEUS TARGETS ====="
curl -s http://localhost:9090/api/v1/targets 2>/dev/null | \
    jq -r '.data.activeTargets[] | "\(.job): \(.health)"' | \
    column -t

echo -e "\n===== SSL CERTIFICATE ====="
if [[ -f /etc/letsencrypt/live/*/fullchain.pem ]]; then
    openssl x509 -in /etc/letsencrypt/live/*/fullchain.pem -noout -enddate
fi
```

Save as `/usr/local/bin/check-chom-health` and run:
```bash
sudo chmod +x /usr/local/bin/check-chom-health
/usr/local/bin/check-chom-health
```

---

## RECOVERY PROCEDURES

### Emergency: All Services Down

```bash
# 1. Check system basics
free -h
df -h
uptime

# 2. Check for OOM kills
journalctl -k | grep -i "out of memory"

# 3. Start services in order
sudo systemctl start prometheus
sleep 10
sudo systemctl start loki
sleep 10
sudo systemctl start node_exporter alertmanager
sleep 5
sudo systemctl start grafana-server
sudo systemctl start nginx

# 4. Verify
systemctl status prometheus loki grafana-server nginx
```

### Emergency: Disk Full

```bash
# 1. Free immediate space
sudo journalctl --vacuum-time=1d
sudo apt-get clean
rm -rf /tmp/*

# 2. Reduce retention
sudo systemctl stop prometheus
sudo sed -i 's/retention.time=15d/retention.time=5d/' /etc/systemd/system/prometheus.service
sudo systemctl daemon-reload
sudo systemctl start prometheus

# 3. Clean old Prometheus data
du -sh /var/lib/observability/prometheus
# Consider moving old data to backup storage
```

### Emergency: SSL Expired

```bash
# 1. Quick renewal
sudo certbot renew --force-renewal

# 2. If fails, get new cert
sudo certbot --nginx -d mentat.arewel.com --force-renewal

# 3. If still fails, temporarily disable HTTPS
sudo sed -i 's/listen 443/listen 8443/' /etc/nginx/sites-available/observability
sudo systemctl reload nginx
# Site accessible on HTTP:80, fix SSL separately
```

---

## USEFUL COMMANDS CHEAT SHEET

### Service Management
```bash
# Restart all CHOM services
sudo systemctl restart prometheus loki grafana-server alertmanager node_exporter nginx

# View logs for service
journalctl -xeu prometheus -f

# Check service startup time
systemctl show prometheus --property=ExecMainStartTimestamp
```

### Health Checks
```bash
# All health endpoints
curl -sf http://localhost:9090/-/healthy && echo "Prometheus: OK"
curl -sf http://localhost:3100/ready && echo "Loki: OK"
curl -sf http://localhost:3000/api/health && echo "Grafana: OK"
curl -sf http://localhost:9093/-/healthy && echo "Alertmanager: OK"
```

### Configuration Validation
```bash
# Prometheus
/opt/observability/bin/promtool check config /etc/observability/prometheus/prometheus.yml

# Nginx
sudo nginx -t

# Loki (if promtool available)
/opt/observability/bin/loki -config.file=/etc/observability/loki/loki.yml -verify-config
```

### Resource Monitoring
```bash
# Real-time resource usage
htop

# Disk I/O
iotop

# Network connections
sudo netstat -tlnp | grep -E '(9090|3100|3000|9093)'
```

---

## PREVENTIVE MAINTENANCE

### Daily Checks
```bash
# Run health check
/usr/local/bin/check-chom-health

# Check disk space
df -h

# Check for errors in logs
journalctl -p err -b | tail -20
```

### Weekly Tasks
```bash
# Check SSL expiry
sudo certbot certificates

# Review log sizes
du -sh /var/log/*

# Check for updates
apt list --upgradable
```

### Monthly Tasks
```bash
# Backup Prometheus data
curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot

# Backup MariaDB
mysqldump -u root -p --all-databases > /tmp/mysql-backup-$(date +%Y%m%d).sql

# Review Grafana dashboards
curl -s http://admin:PASSWORD@localhost:3000/api/dashboards/home
```

---

**End of Troubleshooting Guide**
