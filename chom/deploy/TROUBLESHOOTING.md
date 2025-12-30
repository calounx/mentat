# CHOM Deployment Troubleshooting Guide

Quick diagnosis and fixes for common deployment issues.

## How to Use This Guide

1. Find your symptom in the table of contents
2. Follow the diagnosis steps
3. Apply the recommended fix
4. Verify the solution worked

**Not finding your issue?** Jump to [When to Seek Help](#when-to-seek-help)

---

## Table of Contents

**Pre-Deployment Issues**
- [SSH Connection Issues](#ssh-connection-issues)
- [Validation Failures](#validation-failures)
- [Wrong OS Version](#wrong-os-version)
- [Insufficient Disk Space](#insufficient-disk-space)

**Deployment Issues**
- [Deployment Failed Mid-Way](#deployment-failed-mid-way)
- [Services Won't Start](#services-wont-start)
- [Port Conflicts](#port-conflicts)
- [Network Timeouts](#network-timeouts)

**Post-Deployment Issues**
- [Grafana Not Accessible](#grafana-not-accessible)
- [Prometheus Targets Down](#prometheus-targets-down)
- [VPSManager Not Accessible](#vpsmanager-not-accessible)
- [No Logs in Loki](#no-logs-in-loki)
- [SSL Certificate Issues](#ssl-certificate-issues)

**Performance Issues**
- [High CPU Usage](#high-cpu-usage)
- [High Memory Usage](#high-memory-usage)
- [Slow Web Interface](#slow-web-interface)

---

## Pre-Deployment Issues

### SSH Connection Issues

#### Symptom
```
[✗] Cannot connect to Observability via SSH
Connection timed out
```

#### Diagnosis

**Step 1:** Verify VPS is reachable
```bash
ping YOUR_VPS_IP
# Should get responses
```

**Step 2:** Test SSH manually
```bash
ssh -v deploy@YOUR_VPS_IP
# Look for error messages in verbose output
```

**Step 3:** Check SSH key
```bash
ls -la ~/.ssh/id_rsa
# Should exist with permissions 600
```

#### Fixes

**Fix 1: VPS unreachable**
```bash
# Check VPS provider dashboard
# Verify VPS is running
# Check firewall rules allow SSH (port 22)
```

**Fix 2: SSH key not found**
```bash
# Generate SSH key if missing
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa

# Copy to VPS
ssh-copy-id deploy@YOUR_VPS_IP
```

**Fix 3: Wrong username in inventory.yaml**
```bash
# Edit inventory.yaml
nano configs/inventory.yaml

# Verify ssh_user matches the user you created
# Save and retry
./deploy-enhanced.sh --validate
```

**Fix 4: Firewall blocking SSH**
```bash
# On VPS (via provider console/VNC):
sudo ufw status
sudo ufw allow 22/tcp
sudo ufw reload
```

**Fix 5: SSH port changed**
```bash
# If SSH runs on different port (e.g., 2222)
# Update inventory.yaml:
ssh_port: 2222

# Test manually:
ssh -p 2222 deploy@YOUR_VPS_IP
```

#### Verification
```bash
./deploy-enhanced.sh --validate
# Should show: ✓ SSH connection to ... successful
```

---

### Validation Failures

#### Symptom
```
[✗] Pre-flight checks failed after 3 attempts
Missing required tools: yq
```

#### Diagnosis

**Step 1:** Check what's missing
```bash
./deploy-enhanced.sh --validate
# Read error messages carefully
```

**Step 2:** Verify manual installation
```bash
# Check if tools exist
which yq jq ssh scp
```

#### Fixes

**Fix 1: Missing dependencies (auto-install should handle this)**
```bash
# Manual installation on Ubuntu/Debian:
sudo apt-get update
sudo apt-get install -y jq curl wget

# Install yq
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# Verify
yq --version
jq --version
```

**Fix 2: Missing dependencies on macOS**
```bash
# Install Homebrew if not present
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install tools
brew install yq jq
```

**Fix 3: Permission issues**
```bash
# If installation fails due to permissions
sudo chown -R $USER:$USER /usr/local/bin
```

#### Verification
```bash
./deploy-enhanced.sh --validate
# Should show: ✓ All dependencies installed
```

---

### Wrong OS Version

#### Symptom
```
[✗] OS version check failed
Expected: Debian 13
Found: Ubuntu 22.04
```

#### Diagnosis
```bash
# SSH into VPS
ssh deploy@YOUR_VPS_IP

# Check OS version
cat /etc/os-release
```

#### Fix

**Unfortunately, you cannot change OS without reprovisioning.**

**Solution:**
1. Backup any data (if applicable)
2. Destroy current VPS
3. Provision new VPS with **Debian 13 (bookworm)**
4. Update `inventory.yaml` with new IP
5. Restart deployment

#### Prevention
- Always select **Debian 13** when provisioning VPS
- Double-check OS version in provider dashboard before deployment

---

### Insufficient Disk Space

#### Symptom
```
[✗] Disk space check failed
Available: 15GB
Required: 20GB minimum
```

#### Diagnosis
```bash
# SSH into VPS
ssh deploy@YOUR_VPS_IP

# Check disk usage
df -h
```

#### Fixes

**Fix 1: Clean up existing data**
```bash
# Remove old packages
sudo apt-get clean
sudo apt-get autoclean
sudo apt-get autoremove

# Check again
df -h
```

**Fix 2: Resize VPS disk**
```bash
# Use VPS provider dashboard to:
# 1. Increase disk size (may cost more)
# 2. Reboot VPS
# 3. Expand filesystem

# After resizing, verify:
df -h
```

**Fix 3: Use different VPS**
- Provision new VPS with larger disk (40GB+ recommended)
- Update inventory.yaml with new IP
- Restart deployment

---

## Deployment Issues

### Deployment Failed Mid-Way

#### Symptom
```
[✗] Deploy observability failed after 3 attempts
Error: Connection reset by peer
```

#### Diagnosis

**Step 1:** Check deployment state
```bash
cat .deploy-state/deployment.state | jq
# Shows which components succeeded/failed
```

**Step 2:** Check network connectivity
```bash
ping YOUR_VPS_IP
ssh deploy@YOUR_VPS_IP
```

#### Fixes

**Fix 1: Resume deployment**
```bash
# Resume from last successful checkpoint
./deploy-enhanced.sh --resume
```

**Fix 2: Network issue - retry with backoff**
```bash
# Deployment script auto-retries, but you can force retry
./deploy-enhanced.sh --resume --verbose
```

**Fix 3: Check VPS hasn't run out of resources**
```bash
ssh deploy@YOUR_VPS_IP

# Check memory
free -h

# Check disk
df -h

# Check if any process is hung
top
```

**Fix 4: Clear state and start fresh**
```bash
# Only if resume doesn't work
rm -rf .deploy-state/
./deploy-enhanced.sh all
```

#### Verification
```bash
# Check deployment completed
cat .deploy-state/deployment.state | jq '.status'
# Should show: "completed"
```

---

### Services Won't Start

#### Symptom
```
[✗] Service prometheus failed to start
Job for prometheus.service failed
```

#### Diagnosis

**Step 1:** SSH into VPS and check service
```bash
ssh deploy@YOUR_VPS_IP
sudo systemctl status prometheus
```

**Step 2:** Check service logs
```bash
sudo journalctl -u prometheus -n 50 --no-pager
```

**Step 3:** Check configuration
```bash
# For Prometheus
sudo promtool check config /etc/prometheus/prometheus.yml

# For Nginx
sudo nginx -t

# For PHP-FPM
sudo php-fpm8.4 -t
```

#### Fixes

**Fix 1: Port already in use**
```bash
# Find what's using the port
sudo lsof -i :9090
# or
sudo netstat -tulpn | grep :9090

# Stop conflicting service
sudo systemctl stop CONFLICTING_SERVICE

# Restart Prometheus
sudo systemctl restart prometheus
```

**Fix 2: Configuration error**
```bash
# Edit configuration
sudo nano /etc/prometheus/prometheus.yml

# Fix syntax errors
# Validate again
sudo promtool check config /etc/prometheus/prometheus.yml

# Restart
sudo systemctl restart prometheus
```

**Fix 3: Binary permissions**
```bash
# Check binary exists and is executable
ls -la /opt/observability/bin/prometheus

# Fix if needed
sudo chmod +x /opt/observability/bin/prometheus
sudo systemctl restart prometheus
```

**Fix 4: Missing directories**
```bash
# Create required directories
sudo mkdir -p /var/lib/prometheus
sudo chown -R prometheus:prometheus /var/lib/prometheus

sudo mkdir -p /etc/prometheus
sudo chown -R prometheus:prometheus /etc/prometheus

# Restart
sudo systemctl restart prometheus
```

#### Verification
```bash
sudo systemctl status prometheus
# Should show: active (running)

# Test endpoint
curl http://localhost:9090/-/healthy
# Should return: Prometheus is Healthy
```

---

### Port Conflicts

#### Symptom
```
bind: address already in use
Cannot start service on port 3000
```

#### Diagnosis
```bash
ssh deploy@YOUR_VPS_IP

# Check what's using the port
sudo lsof -i :3000
# or
sudo netstat -tulpn | grep :3000
```

#### Fix

**Option 1: Stop conflicting service**
```bash
# Identify the service
sudo lsof -i :3000
# Shows: COMMAND PID USER

# Stop it
sudo systemctl stop SERVICE_NAME
# or
sudo kill PID

# Start your service
sudo systemctl start grafana-server
```

**Option 2: Change port**
```bash
# Edit service configuration
sudo nano /etc/grafana/grafana.ini

# Change port (example):
[server]
http_port = 3001

# Restart
sudo systemctl restart grafana-server

# Update firewall
sudo ufw allow 3001/tcp
```

#### Verification
```bash
sudo systemctl status grafana-server
# Should show: active (running)

# Test new port
curl http://localhost:3001
```

---

### Network Timeouts

#### Symptom
```
Connection timeout during download
Failed to download Prometheus binary
```

#### Diagnosis
```bash
ssh deploy@YOUR_VPS_IP

# Test internet connectivity
ping -c 4 8.8.8.8

# Test DNS
ping -c 4 github.com

# Test HTTPS
curl -I https://github.com
```

#### Fixes

**Fix 1: DNS issues**
```bash
# Check DNS configuration
cat /etc/resolv.conf

# Add Google DNS
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf

# Test again
ping github.com
```

**Fix 2: Firewall blocking outbound**
```bash
# Check firewall
sudo ufw status

# Allow outbound HTTPS
sudo ufw allow out 443/tcp

# Allow outbound HTTP
sudo ufw allow out 80/tcp
```

**Fix 3: Provider network issues**
- Check VPS provider status page
- Contact provider support
- Try again later

**Fix 4: Use deployment with longer timeout**
```bash
# Edit deploy-enhanced.sh temporarily
# Find: ConnectTimeout=10
# Change to: ConnectTimeout=60

# Or wait and retry
./deploy-enhanced.sh --resume
```

---

## Post-Deployment Issues

### Grafana Not Accessible

#### Symptom
- Browser shows "Connection refused" or "Timeout"
- Cannot access http://YOUR_IP:3000

#### Diagnosis

**Step 1:** Check if Grafana is running
```bash
ssh deploy@YOUR_VPS_IP
sudo systemctl status grafana-server
```

**Step 2:** Check if port is listening
```bash
sudo netstat -tulpn | grep :3000
# Should show Grafana listening on 3000
```

**Step 3:** Check firewall
```bash
sudo ufw status
# Should allow port 3000
```

**Step 4:** Test locally on VPS
```bash
curl http://localhost:3000
# Should return HTML
```

#### Fixes

**Fix 1: Grafana not running**
```bash
# Start Grafana
sudo systemctl start grafana-server

# Enable on boot
sudo systemctl enable grafana-server

# Check status
sudo systemctl status grafana-server
```

**Fix 2: Firewall blocking**
```bash
# Allow port 3000
sudo ufw allow 3000/tcp
sudo ufw reload

# Verify
sudo ufw status | grep 3000
```

**Fix 3: Grafana bound to localhost only**
```bash
# Edit configuration
sudo nano /etc/grafana/grafana.ini

# Find and update:
[server]
http_addr = 0.0.0.0
http_port = 3000

# Restart
sudo systemctl restart grafana-server
```

**Fix 4: Provider firewall**
- Check VPS provider dashboard
- Ensure port 3000 is allowed in provider firewall/security group
- Add inbound rule: TCP port 3000 from anywhere (0.0.0.0/0)

#### Verification
```bash
# From your local machine:
curl -I http://YOUR_VPS_IP:3000
# Should return HTTP 302 or 200

# In browser:
http://YOUR_VPS_IP:3000
# Should show Grafana login page
```

---

### Prometheus Targets Down

#### Symptom
- Prometheus UI shows targets with status "DOWN"
- Red indicators in Status → Targets page

#### Diagnosis

**Step 1:** Check which targets are down
```bash
# Open in browser
http://YOUR_OBSERVABILITY_IP:9090/targets

# Look for red/down targets
```

**Step 2:** SSH into target VPS
```bash
# If node_exporter is down on VPSManager:
ssh deploy@YOUR_VPSMANAGER_IP

# Check if exporter is running
sudo systemctl status node_exporter
```

**Step 3:** Check if port is accessible
```bash
# From Observability VPS:
ssh deploy@YOUR_OBSERVABILITY_IP
curl http://YOUR_VPSMANAGER_IP:9100/metrics
# Should return metrics
```

#### Fixes

**Fix 1: Exporter not running**
```bash
# SSH to VPS where exporter is down
ssh deploy@YOUR_VPS_IP

# Start the exporter
sudo systemctl start node_exporter

# Enable on boot
sudo systemctl enable node_exporter

# Check status
sudo systemctl status node_exporter
```

**Fix 2: Firewall blocking**
```bash
# On target VPS (e.g., VPSManager)
ssh deploy@YOUR_VPSMANAGER_IP

# Allow Observability VPS to scrape metrics
sudo ufw allow from YOUR_OBSERVABILITY_IP to any port 9100
sudo ufw allow from YOUR_OBSERVABILITY_IP to any port 9113
sudo ufw allow from YOUR_OBSERVABILITY_IP to any port 9104
sudo ufw allow from YOUR_OBSERVABILITY_IP to any port 9253
sudo ufw reload
```

**Fix 3: Wrong IP in Prometheus config**
```bash
# On Observability VPS
ssh deploy@YOUR_OBSERVABILITY_IP

# Edit Prometheus config
sudo nano /etc/prometheus/prometheus.yml

# Verify targets have correct IPs
# Look for scrape_configs section

# Reload Prometheus
sudo systemctl reload prometheus
```

**Fix 4: Exporter crashed - check logs**
```bash
# View exporter logs
sudo journalctl -u node_exporter -n 100

# Common issues:
# - Port conflict (another process using port)
# - Permission issues
# - Missing dependencies

# Restart exporter
sudo systemctl restart node_exporter
```

#### Verification
```bash
# Check Prometheus targets page
http://YOUR_OBSERVABILITY_IP:9090/targets

# All should show: UP (green)

# Test metric scraping
curl http://TARGET_VPS_IP:EXPORTER_PORT/metrics
# Should return metrics
```

---

### VPSManager Not Accessible

#### Symptom
- Cannot access http://YOUR_VPSMANAGER_IP:8080
- 502 Bad Gateway error
- 504 Gateway Timeout

#### Diagnosis

**Step 1:** Check Nginx status
```bash
ssh deploy@YOUR_VPSMANAGER_IP
sudo systemctl status nginx
```

**Step 2:** Check PHP-FPM status
```bash
sudo systemctl status php8.4-fpm
```

**Step 3:** Check Nginx configuration
```bash
sudo nginx -t
```

**Step 4:** Check error logs
```bash
sudo tail -f /var/log/nginx/error.log
```

#### Fixes

**Fix 1: Nginx not running**
```bash
sudo systemctl start nginx
sudo systemctl enable nginx
sudo systemctl status nginx
```

**Fix 2: PHP-FPM not running**
```bash
sudo systemctl start php8.4-fpm
sudo systemctl enable php8.4-fpm
sudo systemctl status php8.4-fpm
```

**Fix 3: Nginx configuration error**
```bash
# Test configuration
sudo nginx -t

# If errors, edit config
sudo nano /etc/nginx/sites-available/vpsmanager

# Fix errors and test again
sudo nginx -t

# Reload if valid
sudo systemctl reload nginx
```

**Fix 4: PHP-FPM socket not found**
```bash
# Check PHP-FPM socket exists
ls -la /var/run/php/php8.4-fpm.sock

# If missing, check PHP-FPM config
sudo nano /etc/php/8.4/fpm/pool.d/www.conf

# Ensure listen = /var/run/php/php8.4-fpm.sock

# Restart PHP-FPM
sudo systemctl restart php8.4-fpm
```

**Fix 5: File permissions**
```bash
# Fix Laravel directory permissions
sudo chown -R www-data:www-data /var/www/vpsmanager
sudo chmod -R 755 /var/www/vpsmanager
sudo chmod -R 775 /var/www/vpsmanager/storage
sudo chmod -R 775 /var/www/vpsmanager/bootstrap/cache
```

**Fix 6: Firewall**
```bash
sudo ufw allow 8080/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

#### Verification
```bash
# Test Nginx
curl -I http://localhost:8080

# Test from browser
http://YOUR_VPSMANAGER_IP:8080
```

---

### No Logs in Loki

#### Symptom
- Grafana Explore shows no logs when querying Loki
- Empty result for query: `{job="varlogs"}`

#### Diagnosis

**Step 1:** Check Promtail status
```bash
ssh deploy@YOUR_VPSMANAGER_IP
sudo systemctl status promtail
```

**Step 2:** Check Promtail logs
```bash
sudo journalctl -u promtail -n 100
```

**Step 3:** Test Loki connectivity
```bash
curl http://YOUR_OBSERVABILITY_IP:3100/ready
# Should return: ready
```

**Step 4:** Check Promtail config
```bash
cat /etc/promtail/config.yml
```

#### Fixes

**Fix 1: Promtail not running**
```bash
sudo systemctl start promtail
sudo systemctl enable promtail
sudo systemctl status promtail
```

**Fix 2: Cannot reach Loki**
```bash
# Check network connectivity from VPSManager to Observability
ssh deploy@YOUR_VPSMANAGER_IP
ping YOUR_OBSERVABILITY_IP

# Test Loki endpoint
curl http://YOUR_OBSERVABILITY_IP:3100/ready

# If fails, check firewall on Observability VPS:
ssh deploy@YOUR_OBSERVABILITY_IP
sudo ufw allow from YOUR_VPSMANAGER_IP to any port 3100
sudo ufw reload
```

**Fix 3: Wrong Loki URL in Promtail config**
```bash
# Edit Promtail config
sudo nano /etc/promtail/config.yml

# Verify clients section:
clients:
  - url: http://YOUR_OBSERVABILITY_IP:3100/loki/api/v1/push

# Update with correct IP
# Restart Promtail
sudo systemctl restart promtail
```

**Fix 4: No log files to read**
```bash
# Check if log files exist
ls -la /var/log/nginx/
ls -la /var/log/mysql/

# Verify Promtail config points to correct paths
sudo nano /etc/promtail/config.yml

# Look for scrape_configs with correct paths
```

**Fix 5: Permission issues**
```bash
# Add promtail user to log groups
sudo usermod -a -G adm promtail
sudo usermod -a -G systemd-journal promtail

# Restart Promtail
sudo systemctl restart promtail
```

#### Verification
```bash
# In Grafana Explore:
# 1. Select "Loki" datasource
# 2. Query: {job="varlogs"}
# 3. Should see log entries

# Or test with logcli:
ssh deploy@YOUR_OBSERVABILITY_IP
curl -G -s "http://localhost:3100/loki/api/v1/query" --data-urlencode 'query={job="varlogs"}' | jq
```

---

### SSL Certificate Issues

#### Symptom
- Certificate expired
- Browser shows "Not Secure"
- Certbot failed to renew

#### Diagnosis

**Step 1:** Check certificate status
```bash
ssh deploy@YOUR_VPS_IP
sudo certbot certificates
```

**Step 2:** Test certificate renewal
```bash
sudo certbot renew --dry-run
```

#### Fixes

**Fix 1: Manual renewal**
```bash
# Renew all certificates
sudo certbot renew

# Renew specific domain
sudo certbot renew --cert-name YOUR_DOMAIN
```

**Fix 2: Certbot renewal failed - HTTP challenge**
```bash
# Ensure port 80 is accessible
sudo ufw allow 80/tcp
sudo ufw reload

# Ensure Nginx serves .well-known
sudo nginx -t
sudo systemctl reload nginx

# Try renewal again
sudo certbot renew --force-renewal
```

**Fix 3: Setup auto-renewal**
```bash
# Check if certbot timer is active
sudo systemctl status certbot.timer

# Enable if not active
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer

# Test renewal
sudo certbot renew --dry-run
```

**Fix 4: Get new certificate**
```bash
# Delete old certificate
sudo certbot delete --cert-name YOUR_DOMAIN

# Get new one
sudo certbot --nginx -d YOUR_DOMAIN

# Follow prompts
```

#### Verification
```bash
# Check certificate expiry
sudo certbot certificates

# Test in browser
https://YOUR_DOMAIN
# Should show valid certificate (green lock)
```

---

## Performance Issues

### High CPU Usage

#### Symptom
- VPS slow to respond
- High load average
- Services timing out

#### Diagnosis

**Step 1:** Check current CPU usage
```bash
ssh deploy@YOUR_VPS_IP
top
# Press 'P' to sort by CPU
```

**Step 2:** Check load average
```bash
uptime
# Load should be < number of CPUs
```

**Step 3:** Identify the culprit
```bash
# Top processes
ps aux --sort=-%cpu | head -10
```

#### Fixes

**Fix 1: Prometheus using too much CPU**
```bash
# Increase scrape interval to reduce load
sudo nano /etc/prometheus/prometheus.yml

# Find global section:
global:
  scrape_interval: 60s  # Increase from 15s to 60s

# Reload
sudo systemctl reload prometheus
```

**Fix 2: Too many scrape targets**
```bash
# Edit Prometheus config
sudo nano /etc/prometheus/prometheus.yml

# Disable non-essential targets
# Comment out targets you don't need

# Reload
sudo systemctl reload prometheus
```

**Fix 3: Reduce Prometheus retention**
```bash
# Edit systemd service
sudo nano /etc/systemd/system/prometheus.service

# Find --storage.tsdb.retention.time
# Change from 30d to 15d or 7d

# Reload systemd and restart
sudo systemctl daemon-reload
sudo systemctl restart prometheus
```

**Fix 4: Upgrade VPS**
- Increase CPU cores in provider dashboard
- 2 vCPUs recommended for Observability
- 2-4 vCPUs recommended for VPSManager

#### Verification
```bash
# Check load average
uptime
# Should be reasonable (< 2x number of CPUs)

# Monitor with htop
sudo apt-get install htop
htop
```

---

### High Memory Usage

#### Symptom
- Out of memory errors
- OOM killer terminating processes
- Services crashing

#### Diagnosis

**Step 1:** Check memory usage
```bash
ssh deploy@YOUR_VPS_IP
free -h
```

**Step 2:** Identify memory hogs
```bash
ps aux --sort=-%mem | head -10
```

**Step 3:** Check if swap is being used
```bash
swapon --show
```

#### Fixes

**Fix 1: Prometheus using too much memory**
```bash
# Reduce retention period
sudo nano /etc/systemd/system/prometheus.service

# Change:
--storage.tsdb.retention.time=15d
--storage.tsdb.retention.size=5GB

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart prometheus
```

**Fix 2: MariaDB using too much memory**
```bash
# Edit MariaDB config
sudo nano /etc/mysql/mariadb.conf.d/50-server.cnf

# Adjust these values (for 2GB RAM VPS):
[mysqld]
innodb_buffer_pool_size = 512M
key_buffer_size = 32M
max_connections = 50

# Restart MariaDB
sudo systemctl restart mariadb
```

**Fix 3: Enable swap**
```bash
# Create 2GB swap file
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Verify
free -h
```

**Fix 4: Restart memory-heavy services**
```bash
# Restart to clear memory leaks
sudo systemctl restart prometheus
sudo systemctl restart grafana-server
sudo systemctl restart php8.4-fpm
```

**Fix 5: Upgrade VPS RAM**
- Increase RAM in provider dashboard
- Minimum 2GB for Observability
- Minimum 4GB for VPSManager

#### Verification
```bash
free -h
# Ensure available memory > 200MB

# Monitor
watch -n 1 free -h
```

---

### Slow Web Interface

#### Symptom
- Grafana takes long to load
- VPSManager slow to respond
- Timeouts in browser

#### Diagnosis

**Step 1:** Check server resources
```bash
ssh deploy@YOUR_VPS_IP
top
free -h
df -h
```

**Step 2:** Check service status
```bash
sudo systemctl status nginx php8.4-fpm mariadb redis-server
```

**Step 3:** Check error logs
```bash
sudo tail -f /var/log/nginx/error.log
sudo journalctl -u php8.4-fpm -n 100
```

#### Fixes

**Fix 1: Enable Laravel caching**
```bash
ssh deploy@YOUR_VPSMANAGER_IP
cd /var/www/vpsmanager

# Cache configuration
php artisan config:cache

# Cache routes
php artisan route:cache

# Cache views
php artisan view:cache

# Optimize autoloader
composer install --optimize-autoloader --no-dev
```

**Fix 2: Optimize PHP-FPM**
```bash
sudo nano /etc/php/8.4/fpm/pool.d/www.conf

# Increase process manager settings:
pm = dynamic
pm.max_children = 50
pm.start_servers = 10
pm.min_spare_servers = 5
pm.max_spare_servers = 20

# Restart
sudo systemctl restart php8.4-fpm
```

**Fix 3: Enable Redis caching**
```bash
# Edit Laravel .env
cd /var/www/vpsmanager
sudo nano .env

# Set:
CACHE_DRIVER=redis
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis

# Clear cache
php artisan cache:clear
php artisan config:cache
```

**Fix 4: Optimize database**
```bash
# Optimize MariaDB tables
sudo mysqlcheck -u root -p --optimize --all-databases

# Add indexes if needed (check slow query log)
```

**Fix 5: Enable Nginx caching**
```bash
sudo nano /etc/nginx/sites-available/vpsmanager

# Add caching for static assets:
location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
}

# Reload
sudo systemctl reload nginx
```

#### Verification
```bash
# Test page load time
time curl http://YOUR_VPS_IP:8080

# Should be < 2 seconds

# Test in browser with developer tools
# Network tab should show < 3s load time
```

---

## Decision Tree for Common Problems

### Can't access Grafana?

```
Can you ping the VPS?
├─ No → Check VPS provider, ensure VPS is running
└─ Yes → Is Grafana running?
    ├─ No → sudo systemctl start grafana-server
    └─ Yes → Is port 3000 open?
        ├─ No → sudo ufw allow 3000/tcp
        └─ Yes → Test locally: curl localhost:3000
            ├─ Works → Provider firewall blocking
            └─ Fails → Check Grafana config
```

### Deployment keeps failing?

```
Does validation pass?
├─ No → Fix validation errors first
└─ Yes → Resume deployment
    ├─ ./deploy-enhanced.sh --resume
    └─ Still failing? → Check VPS resources
        ├─ Out of disk? → Clean up or upgrade
        ├─ Out of memory? → Add swap or upgrade
        └─ Network timeout? → Check connectivity
```

### Prometheus targets down?

```
Is exporter service running?
├─ No → sudo systemctl start EXPORTER_NAME
└─ Yes → Can Prometheus reach it?
    ├─ No → Check firewall rules
    └─ Yes → Check Prometheus config
        └─ Verify correct IP and port
```

---

## When to Seek Help

### You should investigate further if:

- Deployment fails repeatedly even after following fixes
- Services crash immediately after starting
- Error messages don't match any troubleshooting guide
- VPS provider-specific networking issues
- Custom configuration conflicts

### How to gather information for help:

**Collect logs:**
```bash
# Deployment logs
cat .deploy-state/deployment.state | jq > deployment.log

# Service logs
ssh deploy@YOUR_VPS_IP
sudo journalctl -u SERVICE_NAME -n 500 > service.log

# System info
uname -a > sysinfo.txt
df -h >> sysinfo.txt
free -h >> sysinfo.txt
```

**Include in your help request:**
1. Deployment command you ran
2. Exact error message (copy/paste, not screenshot)
3. Output of `./deploy-enhanced.sh --validate`
4. Relevant service logs
5. VPS specifications (CPU, RAM, disk)
6. What you've already tried

### Where to get help:

- GitHub Issues: https://github.com/calounx/mentat/issues
- Documentation: Check README.md and other guides
- Community forums (if available)

---

## Quick Command Reference

### Diagnosis Commands

```bash
# Check service status
sudo systemctl status SERVICE_NAME

# View logs
sudo journalctl -u SERVICE_NAME -n 100

# Check ports
sudo netstat -tulpn | grep PORT
sudo lsof -i :PORT

# Check resources
top
free -h
df -h

# Test connectivity
ping IP_ADDRESS
curl http://IP:PORT

# Check firewall
sudo ufw status verbose
```

### Recovery Commands

```bash
# Restart service
sudo systemctl restart SERVICE_NAME

# Reload configuration
sudo systemctl reload SERVICE_NAME

# Resume deployment
./deploy-enhanced.sh --resume

# Clear and redeploy
rm -rf .deploy-state/
./deploy-enhanced.sh all

# Fix permissions
sudo chown -R USER:GROUP /path
sudo chmod -R 755 /path
```

---

## Prevention Tips

### Before Deployment
- [ ] Use Debian 13 (not Ubuntu or other OS)
- [ ] Ensure VPS has adequate resources (2GB+ RAM, 40GB+ disk)
- [ ] Create sudo user (don't use root)
- [ ] Test SSH connection before deploying
- [ ] Run validation: `./deploy-enhanced.sh --validate`

### During Deployment
- [ ] Don't interrupt deployment (let it complete)
- [ ] Monitor for errors in output
- [ ] If deployment fails, use `--resume` not re-run from scratch

### After Deployment
- [ ] Change default passwords immediately
- [ ] Configure firewall rules
- [ ] Set up SSL certificates
- [ ] Enable automatic updates
- [ ] Configure monitoring alerts
- [ ] Schedule secrets rotation

---

## Troubleshooting Checklist

When something goes wrong, check these in order:

1. [ ] Is the VPS running and accessible?
2. [ ] Can you SSH into the VPS?
3. [ ] Is the service running? (`systemctl status`)
4. [ ] Are there errors in logs? (`journalctl -u SERVICE`)
5. [ ] Is the port open? (`netstat -tulpn | grep PORT`)
6. [ ] Is firewall allowing traffic? (`ufw status`)
7. [ ] Is configuration valid? (service-specific validation)
8. [ ] Are file permissions correct? (`ls -la`)
9. [ ] Is there enough disk space? (`df -h`)
10. [ ] Is there enough memory? (`free -h`)

---

**Last Updated:** 2025-12-30
**For more help:** See [README.md](./README.md) and [QUICK-START.md](./QUICK-START.md)
