# CHOM/Mentat Troubleshooting Guide

This guide covers common issues, diagnostic commands, and recovery procedures for the CHOM test environment.

## Table of Contents

1. [Common Issues](#common-issues)
2. [Diagnostic Commands](#diagnostic-commands)
3. [Recovery Procedures](#recovery-procedures)

---

## Common Issues

### Container Won't Start

#### Symptom: Container exits immediately or fails to start

**Check 1: Systemd/cgroups configuration**

```bash
# Check if cgroups v2 is properly mounted
mount | grep cgroup

# Verify container logs for systemd errors
docker logs mentat_tst 2>&1 | head -50

# Common error: "Failed to mount cgroup"
# Solution: Ensure Docker is configured for cgroups v2
```

**Fix: Update Docker daemon configuration**

```bash
# Edit /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "features": {
    "buildkit": true
  }
}

# Restart Docker
sudo systemctl restart docker
```

**Check 2: Privileged mode and capabilities**

The containers require privileged mode for systemd:

```bash
# Verify container is running in privileged mode
docker inspect mentat_tst | jq '.[0].HostConfig.Privileged'
# Should return: true

# Check capabilities
docker inspect mentat_tst | jq '.[0].HostConfig.CapAdd'
# Should include: SYS_ADMIN
```

**Check 3: Volume permissions**

```bash
# Check if volumes are accessible
docker volume ls | grep mentat

# Inspect volume
docker volume inspect docker_mentat-prometheus-data

# Fix permissions inside container
docker exec mentat_tst chown -R prometheus:prometheus /var/lib/prometheus
```

#### Symptom: Systemd stuck in "starting" state

```bash
# Check systemd status inside container
docker exec mentat_tst systemctl is-system-running

# Expected output: "running" or "degraded"
# If "starting", check what's blocking:
docker exec mentat_tst systemctl list-jobs

# Cancel stuck jobs
docker exec mentat_tst systemctl cancel
```

**Fix: Mask problematic services**

```bash
docker exec mentat_tst systemctl mask \
  systemd-logind.service \
  getty.target \
  console-getty.service
```

---

### Services Not Responding

#### Symptom: Cannot connect to Prometheus/Grafana/Loki

**Check 1: Service is running**

```bash
# Check service status
docker exec mentat_tst systemctl status prometheus
docker exec mentat_tst systemctl status grafana-server
docker exec mentat_tst systemctl status loki

# Check if process is running
docker exec mentat_tst pgrep -a prometheus
```

**Check 2: Port binding**

```bash
# Check listening ports inside container
docker exec mentat_tst ss -tlnp | grep -E "(9090|3000|3100)"

# Check port mapping from host
docker port mentat_tst
```

**Check 3: Firewall issues**

```bash
# Check UFW status inside container
docker exec mentat_tst ufw status verbose

# Disable UFW temporarily for testing
docker exec mentat_tst ufw disable
```

**Fix: Restart services**

```bash
# Restart specific service
docker exec mentat_tst systemctl restart prometheus

# Restart all observability services
docker exec mentat_tst systemctl restart prometheus grafana-server loki alertmanager
```

#### Symptom: Health check returns error

```bash
# Test endpoints directly
curl -v http://localhost:9090/-/healthy
curl -v http://localhost:3000/api/health
curl -v http://localhost:3100/ready

# Check for error messages in service logs
docker exec mentat_tst journalctl -u prometheus --no-pager -n 50
docker exec mentat_tst journalctl -u grafana-server --no-pager -n 50
docker exec mentat_tst journalctl -u loki --no-pager -n 50
```

---

### Deployment Failures

#### Symptom: Deployment script fails

**Check 1: Missing dependencies**

```bash
# Check if required packages are installed
docker exec landsraad_tst dpkg -l | grep -E "(nginx|php|mariadb)"

# Check for failed package installations
docker exec landsraad_tst apt-get check
```

**Check 2: Configuration errors**

```bash
# Validate Nginx configuration
docker exec landsraad_tst nginx -t

# Validate PHP-FPM configuration
docker exec landsraad_tst php-fpm8.4 -t

# Validate Prometheus configuration
docker exec mentat_tst promtool check config /etc/prometheus/prometheus.yml
```

**Check 3: Disk space**

```bash
# Check disk usage inside container
docker exec landsraad_tst df -h

# Check Docker disk usage on host
docker system df
```

**Fix: Clear failed state and retry**

```bash
# Reset failed services
docker exec landsraad_tst systemctl reset-failed

# Run deployment again
./scripts/test-env.sh deploy vpsmanager
```

#### Symptom: Laravel application not working

**Check 1: Composer dependencies**

```bash
docker exec landsraad_tst bash -c "cd /var/www/vpsmanager && composer check-platform-reqs"
docker exec landsraad_tst bash -c "cd /var/www/vpsmanager && composer diagnose"
```

**Check 2: Laravel configuration**

```bash
# Check .env file exists
docker exec landsraad_tst cat /var/www/vpsmanager/.env

# Test artisan
docker exec landsraad_tst bash -c "cd /var/www/vpsmanager && php artisan --version"

# Clear all caches
docker exec landsraad_tst bash -c "cd /var/www/vpsmanager && php artisan cache:clear"
docker exec landsraad_tst bash -c "cd /var/www/vpsmanager && php artisan config:clear"
docker exec landsraad_tst bash -c "cd /var/www/vpsmanager && php artisan route:clear"
docker exec landsraad_tst bash -c "cd /var/www/vpsmanager && php artisan view:clear"
```

**Check 3: Permissions**

```bash
# Fix storage permissions
docker exec landsraad_tst chown -R www-data:www-data /var/www/vpsmanager/storage
docker exec landsraad_tst chmod -R 775 /var/www/vpsmanager/storage
docker exec landsraad_tst chmod -R 775 /var/www/vpsmanager/bootstrap/cache
```

---

### Database Connection Issues

#### Symptom: Cannot connect to MySQL

**Check 1: MariaDB service status**

```bash
# Check if MariaDB is running
docker exec landsraad_tst systemctl status mariadb

# Check MariaDB logs
docker exec landsraad_tst journalctl -u mariadb --no-pager -n 50
```

**Check 2: Socket and port**

```bash
# Check if MySQL is listening
docker exec landsraad_tst ss -tlnp | grep 3306

# Test connection inside container
docker exec landsraad_tst mysql -u root -proot -e "SELECT 1;"
```

**Check 3: User permissions**

```bash
# Check users
docker exec landsraad_tst mysql -u root -proot -e "SELECT user, host FROM mysql.user;"

# Check grants
docker exec landsraad_tst mysql -u root -proot -e "SHOW GRANTS FOR 'chom'@'localhost';"
```

**Fix: Reset database user**

```bash
docker exec landsraad_tst mysql -u root -proot << 'EOF'
DROP USER IF EXISTS 'chom'@'localhost';
CREATE USER 'chom'@'localhost' IDENTIFIED BY 'secret';
GRANT ALL PRIVILEGES ON chom.* TO 'chom'@'localhost';
FLUSH PRIVILEGES;
EOF
```

#### Symptom: Redis connection refused

```bash
# Check Redis service
docker exec landsraad_tst systemctl status redis-server

# Test Redis connection
docker exec landsraad_tst redis-cli ping

# If password protected, find password
docker exec landsraad_tst cat /root/.credentials/redis
```

---

### Observability Stack Issues

#### Symptom: Prometheus scrape failures

**Check 1: Target status**

```bash
# View all targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health, lastError: .lastError}'

# Check specific target
curl -s "http://localhost:9090/api/v1/query?query=up{job='vpsmanager-node'}" | jq '.data.result'
```

**Check 2: Network connectivity**

```bash
# Test from mentat_tst to landsraad_tst
docker exec mentat_tst curl -s http://10.10.100.20:9100/metrics | head -5

# Ping test
docker exec mentat_tst ping -c 3 10.10.100.20
```

**Check 3: Exporter status**

```bash
# Check if exporter is running on target
docker exec landsraad_tst systemctl status node_exporter
docker exec landsraad_tst systemctl status nginx_exporter
docker exec landsraad_tst systemctl status mysqld_exporter
docker exec landsraad_tst systemctl status phpfpm_exporter

# Test exporter endpoint directly
docker exec landsraad_tst curl -s http://localhost:9100/metrics | head -10
```

**Fix: Restart exporters**

```bash
docker exec landsraad_tst systemctl restart node_exporter nginx_exporter mysqld_exporter phpfpm_exporter
```

#### Symptom: Loki not ingesting logs

**Check 1: Loki status**

```bash
# Check Loki ready
curl -s http://localhost:3100/ready

# Check Loki config
curl -s http://localhost:3100/config

# Test push manually
curl -X POST http://localhost:3100/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -d '{"streams":[{"stream":{"job":"test"},"values":[["'"$(date +%s)000000000"'","test message"]]}]}'
```

**Check 2: Promtail/Alloy status**

```bash
# Check telemetry collector on target host
docker exec landsraad_tst systemctl status promtail
# or
docker exec landsraad_tst systemctl status alloy

# View Promtail logs
docker exec landsraad_tst journalctl -u promtail --no-pager -n 50

# Check Promtail targets
docker exec landsraad_tst curl -s http://localhost:9080/targets
```

**Check 3: Labels query**

```bash
# Check if any labels exist
curl -s http://localhost:3100/loki/api/v1/labels | jq '.data'

# Query recent logs
curl -sG http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={job=~".+"}' \
  --data-urlencode 'limit=5' | jq '.data.result | length'
```

**Fix: Restart telemetry pipeline**

```bash
# On landsraad_tst
docker exec landsraad_tst systemctl restart promtail

# On mentat_tst
docker exec mentat_tst systemctl restart loki
```

#### Symptom: Grafana dashboards empty

**Check 1: Data source configuration**

```bash
# List data sources
curl -s -u admin:admin http://localhost:3000/api/datasources | jq '.[].name'

# Test Prometheus data source
curl -s -u admin:admin http://localhost:3000/api/datasources/proxy/1/api/v1/query?query=up | jq '.data.result | length'
```

**Check 2: Dashboard provisioning**

```bash
# Check provisioned dashboards
docker exec mentat_tst ls -la /etc/grafana/provisioning/dashboards/

# Check Grafana logs
docker exec mentat_tst journalctl -u grafana-server --no-pager -n 50 | grep -i error
```

**Fix: Reload Grafana provisioning**

```bash
docker exec mentat_tst systemctl restart grafana-server
```

---

## Diagnostic Commands

### Container Diagnostics

```bash
# Container status overview
docker ps -a --filter "name=_tst"

# Container resource usage
docker stats --no-stream mentat_tst landsraad_tst richese_tst

# Container logs (last 100 lines)
docker logs --tail 100 mentat_tst
docker logs --tail 100 landsraad_tst

# Inspect container configuration
docker inspect mentat_tst | jq '.[0].State'
docker inspect mentat_tst | jq '.[0].NetworkSettings.Networks'
```

### Service Health Checks

```bash
# Comprehensive health check script
check_all_services() {
    echo "=== Prometheus ==="
    curl -s http://localhost:9090/-/healthy && echo "OK" || echo "FAIL"

    echo "=== Grafana ==="
    curl -s http://localhost:3000/api/health | jq -r '.database'

    echo "=== Loki ==="
    curl -s http://localhost:3100/ready

    echo "=== Alertmanager ==="
    curl -s http://localhost:9093/-/healthy && echo "OK" || echo "FAIL"

    echo "=== CHOM Application ==="
    curl -s http://localhost:8000/api/v1/health | jq -r '.status'
}
check_all_services
```

### Network Connectivity Tests

```bash
# Test inter-container connectivity
docker exec mentat_tst ping -c 1 10.10.100.20
docker exec mentat_tst ping -c 1 10.10.100.30
docker exec landsraad_tst ping -c 1 10.10.100.10

# Test port connectivity
docker exec mentat_tst nc -zv 10.10.100.20 80
docker exec mentat_tst nc -zv 10.10.100.20 9100

# DNS resolution
docker exec landsraad_tst nslookup landsraad-tst
```

### Resource Usage Monitoring

```bash
# Check memory usage inside container
docker exec landsraad_tst free -h

# Check disk usage
docker exec landsraad_tst df -h

# Check process memory
docker exec landsraad_tst ps aux --sort=-%mem | head -10

# Check open file descriptors
docker exec landsraad_tst cat /proc/sys/fs/file-nr
```

### Log Analysis

```bash
# Systemd journal for specific service
docker exec landsraad_tst journalctl -u nginx --since "1 hour ago" --no-pager

# Laravel logs
docker exec landsraad_tst tail -100 /var/www/vpsmanager/storage/logs/laravel.log

# Nginx error log
docker exec landsraad_tst tail -100 /var/log/nginx/error.log

# MySQL error log
docker exec landsraad_tst tail -100 /var/log/mysql/error.log

# PHP-FPM log
docker exec landsraad_tst tail -100 /var/log/php8.4-fpm.log
```

### Quick Diagnostic Script

```bash
#!/bin/bash
# Save as diagnose.sh

echo "=== Container Status ==="
docker ps --filter "name=_tst" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "=== Systemd Status ==="
for host in mentat_tst landsraad_tst richese_tst; do
    status=$(docker exec $host systemctl is-system-running 2>/dev/null || echo "not running")
    echo "$host: $status"
done

echo ""
echo "=== Service Health ==="
echo -n "Prometheus: "; curl -sf http://localhost:9090/-/healthy && echo "OK" || echo "FAIL"
echo -n "Grafana: "; curl -sf http://localhost:3000/api/health >/dev/null && echo "OK" || echo "FAIL"
echo -n "Loki: "; curl -sf http://localhost:3100/ready && echo "" || echo "FAIL"
echo -n "CHOM: "; curl -sf http://localhost:8000/api/v1/health >/dev/null && echo "OK" || echo "FAIL"

echo ""
echo "=== Prometheus Targets ==="
curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | "\(.labels.job): \(.health)"' 2>/dev/null || echo "Cannot reach Prometheus"
```

---

## Recovery Procedures

### Reset Test Environment

Complete reset (destroys all data):

```bash
cd docker

# Stop and remove all containers and volumes
./scripts/test-env.sh reset

# Confirm with 'y' when prompted

# Start fresh
./scripts/test-env.sh up

# Wait for containers to be healthy (2-3 minutes)
sleep 120

# Deploy all stacks
./scripts/test-env.sh deploy
```

### Restore from Backup

```bash
# List available backups
ls -la docker/backups/

# Restore specific backup
./scripts/restore.sh docker/backups/chom_backup_20240101_120000.tar.gz

# Start containers after restore
./scripts/test-env.sh up
```

### Create Backup Before Changes

```bash
# Create backup of current state
./docker/scripts/backup.sh

# Backup will be saved to docker/backups/chom_backup_YYYYMMDD_HHMMSS.tar.gz
```

### Manual Service Restart

**Restart individual services:**

```bash
# Observability services (mentat_tst)
docker exec mentat_tst systemctl restart prometheus
docker exec mentat_tst systemctl restart grafana-server
docker exec mentat_tst systemctl restart loki
docker exec mentat_tst systemctl restart alertmanager
docker exec mentat_tst systemctl restart tempo

# Application services (landsraad_tst)
docker exec landsraad_tst systemctl restart nginx
docker exec landsraad_tst systemctl restart php8.4-fpm
docker exec landsraad_tst systemctl restart mariadb
docker exec landsraad_tst systemctl restart redis-server
docker exec landsraad_tst systemctl restart supervisor
```

**Restart all services in container:**

```bash
# Restart all observability services
docker exec mentat_tst bash -c "systemctl restart prometheus grafana-server loki alertmanager tempo node_exporter"

# Restart all application services
docker exec landsraad_tst bash -c "systemctl restart nginx php8.4-fpm mariadb redis-server node_exporter nginx_exporter mysqld_exporter phpfpm_exporter promtail"
```

### Rebuild Single Container

```bash
cd docker

# Stop specific container
docker stop landsraad_tst
docker rm landsraad_tst

# Rebuild and start
docker compose -f docker-compose.vps.yml up -d --build landsraad_tst

# Wait for systemd
sleep 30

# Redeploy
docker exec landsraad_tst bash /opt/scripts/deploy-vpsmanager.sh
```

### Database Recovery

**Reset database:**

```bash
# Drop and recreate database
docker exec landsraad_tst mysql -u root -proot << 'EOF'
DROP DATABASE IF EXISTS chom;
CREATE DATABASE chom CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON chom.* TO 'chom'@'localhost';
FLUSH PRIVILEGES;
EOF

# Run migrations
docker exec landsraad_tst bash -c "cd /var/www/vpsmanager && php artisan migrate --force"
```

**Fix corrupted database:**

```bash
# Check tables
docker exec landsraad_tst mysqlcheck -u root -proot --check chom

# Repair tables
docker exec landsraad_tst mysqlcheck -u root -proot --repair chom
```

### Emergency Access

**If container shell doesn't work:**

```bash
# Try nsenter instead of docker exec
CONTAINER_PID=$(docker inspect --format '{{.State.Pid}}' landsraad_tst)
sudo nsenter -t $CONTAINER_PID -m -u -i -n -p /bin/bash
```

**If network is broken:**

```bash
# Recreate network
docker network rm docker_vps-network
docker network create --driver bridge --subnet 10.10.100.0/24 docker_vps-network

# Restart containers
./scripts/test-env.sh down
./scripts/test-env.sh up
```

---

## Quick Fixes Reference

| Problem | Quick Fix |
|---------|-----------|
| Container won't start | `docker rm -f container_name && ./scripts/test-env.sh up` |
| Service not responding | `docker exec container systemctl restart service` |
| Port conflict | Check `docker ps` and stop conflicting containers |
| Disk full | `docker system prune -a` (removes unused images) |
| Permission denied | `docker exec container chown -R www-data:www-data /path` |
| Config invalid | Check with `-t` flag: `nginx -t`, `php-fpm8.4 -t` |
| Database locked | `docker exec container systemctl restart mariadb` |
| Tests failing | Run `./scripts/test-env.sh status` first |
| Logs not appearing | `docker exec container systemctl restart promtail` |
| Metrics missing | Check target status in Prometheus UI |

---

## Getting Help

If issues persist after trying these troubleshooting steps:

1. Collect diagnostic information:
   ```bash
   ./diagnose.sh > diagnostic_output.txt 2>&1
   docker logs mentat_tst >> diagnostic_output.txt 2>&1
   docker logs landsraad_tst >> diagnostic_output.txt 2>&1
   ```

2. Check recent changes in git:
   ```bash
   git log --oneline -10
   git diff HEAD~1
   ```

3. Review deployment scripts for recent modifications:
   ```bash
   ls -lt docker/vps-base/scripts/
   ```
