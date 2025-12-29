# CHOM Infrastructure Deployment Guide

Complete end-to-end deployment procedure for CHOM infrastructure using the auto-healing orchestrator.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Pre-Deployment Preparation](#pre-deployment-preparation)
3. [VPS Provisioning](#vps-provisioning)
4. [Configuration Setup](#configuration-setup)
5. [Deployment Execution](#deployment-execution)
6. [Post-Deployment Verification](#post-deployment-verification)
7. [Access and Initial Configuration](#access-and-initial-configuration)
8. [Troubleshooting](#troubleshooting)
9. [Rollback Procedures](#rollback-procedures)

---

## Prerequisites

### Control Machine Requirements

Your local machine (where you run the deployment from) needs:

- **Operating System**: Linux or macOS
- **Shell**: Bash 4.0+
- **Network**: Internet connectivity
- **Disk Space**: At least 500MB free

### Required Tools (Auto-installed if missing)

The deployment script will auto-install these if not present:

- `git`
- `ssh` / `scp` (openssh-client)
- `yq` (YAML processor)
- `jq` (JSON processor)
- `wget` or `curl`

### VPS Requirements

You need **2 VPS servers** with:

- **Operating System**: Debian 13 (vanilla/fresh install)
- **Disk Space**: Minimum 20GB (recommended 40GB+)
- **RAM**: Minimum 1GB (recommended 2GB+ for Observability, 4GB+ for VPSManager)
- **CPU**: Minimum 1 vCPU (recommended 2+)
- **Network**: Public IP address, internet connectivity
- **SSH Access**: Root or sudo user access

### Network Requirements

- **SSH Port**: Port 22 accessible (or custom port)
- **HTTP/HTTPS**: Ports 80, 443 open for web access
- **Monitoring Ports**:
  - Observability VPS: 9090 (Prometheus), 3000 (Grafana), 3100 (Loki)
  - VPSManager VPS: 9100-9253 (exporters)

---

## Pre-Deployment Preparation

### Step 1: Clone the Repository

```bash
# Clone the Mentat repository
git clone https://github.com/calounx/mentat.git
cd mentat/chom/deploy
```

### Step 2: Verify Script Permissions

```bash
# Ensure the deployment script is executable
chmod +x deploy-enhanced.sh

# Verify
ls -la deploy-enhanced.sh
# Should show: -rwxr-xr-x ... deploy-enhanced.sh
```

### Step 3: Review the Inventory Template

```bash
# View the example inventory
cat configs/inventory.yaml.example
```

---

## VPS Provisioning

### Step 1: Provision VPS Servers

Choose your VPS provider (DigitalOcean, Vultr, Hetzner, Linode, etc.) and provision **2 servers**:

#### Observability VPS
- **Purpose**: Monitoring infrastructure (Prometheus, Grafana, Loki, Alertmanager)
- **Recommended Specs**:
  - CPU: 2 vCPUs
  - RAM: 2GB
  - Disk: 40GB SSD
  - OS: Debian 13

#### VPSManager VPS
- **Purpose**: Laravel application with LEMP stack
- **Recommended Specs**:
  - CPU: 2 vCPUs
  - RAM: 4GB
  - Disk: 60GB SSD
  - OS: Debian 13

### Step 2: Record VPS Details

After provisioning, note down:

| VPS | Detail | Example |
|-----|--------|---------|
| **Observability** | IP Address | 203.0.113.10 |
| | SSH Port | 22 |
| | SSH User | deploy (sudo user) |
| | Hostname | monitoring.example.com |
| **VPSManager** | IP Address | 203.0.113.20 |
| | SSH Port | 22 |
| | SSH User | deploy (sudo user) |
| | Hostname | manager.example.com |

### Step 3: Create Deployment User (IMPORTANT - Security Best Practice)

**Do NOT use root for deployment!** Create a dedicated sudo user on each VPS:

#### Option A: Automated Setup (Recommended)

```bash
# SSH into each VPS as root
ssh root@203.0.113.10

# Download and run the setup script
wget https://raw.githubusercontent.com/calounx/mentat/master/chom/deploy/scripts/create-deploy-user.sh
chmod +x create-deploy-user.sh
sudo ./create-deploy-user.sh deploy

# The script will:
# ✓ Create user 'deploy'
# ✓ Configure passwordless sudo
# ✓ Setup SSH directory
# ✓ Prompt to add your SSH public key

# Repeat for VPSManager VPS
ssh root@203.0.113.20
# ... same steps ...
```

#### Option B: Manual Setup

```bash
# SSH into VPS as root
ssh root@203.0.113.10

# Create deployment user
useradd -m -s /bin/bash deploy
usermod -aG sudo deploy

# Configure passwordless sudo
echo "deploy ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/deploy
chmod 0440 /etc/sudoers.d/deploy

# Setup SSH keys (much easier with ssh-copy-id)
# From your control machine, run:
# ssh-copy-id -i ~/.ssh/id_rsa.pub deploy@203.0.113.10

# Or if you prefer to set it up manually on the VPS:
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
touch /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh

# Then from control machine, copy your key:
# ssh-copy-id deploy@203.0.113.10

# Repeat for VPSManager VPS
```

### Step 4: Verify Sudo User Access

Test the deployment user on both servers:

```bash
# Test Observability VPS
ssh deploy@203.0.113.10

# Test passwordless sudo
sudo whoami
# Should output: root (without asking for password)

# Exit
exit

# Test VPSManager VPS
ssh deploy@203.0.113.20
sudo whoami
exit
```

**If you can't SSH or sudo fails, see SUDO-USER-SETUP.md for troubleshooting.**

---

## Configuration Setup

### Step 1: Create Inventory Configuration

```bash
# Navigate to deployment directory
cd /home/calounx/repositories/mentat/chom/deploy

# Create inventory from template (or create new file)
cp configs/inventory.yaml.example configs/inventory.yaml

# Edit with your VPS details
nano configs/inventory.yaml
```

### Step 2: Configure VPS Details

Edit `configs/inventory.yaml` with your actual VPS information:

```yaml
# Observability Stack VPS
observability:
  ip: "203.0.113.10"                    # Replace with your Observability VPS IP
  ssh_user: "deploy"                    # SSH user with passwordless sudo (NOT root!)
  ssh_port: 22                          # SSH port
  hostname: "monitoring.example.com"    # Your monitoring domain (optional)

# VPSManager VPS
vpsmanager:
  ip: "203.0.113.20"                    # Replace with your VPSManager VPS IP
  ssh_user: "deploy"                    # SSH user with passwordless sudo (NOT root!)
  ssh_port: 22                          # SSH port
  hostname: "manager.example.com"       # Your manager domain (optional)
```

**Important**: Replace the example IPs with your actual VPS IP addresses!

### Step 3: Validate Configuration

```bash
# Run validation only (no deployment)
./deploy-enhanced.sh --validate
```

This will:
- ✅ Check local dependencies (auto-install if missing)
- ✅ Validate inventory.yaml syntax
- ✅ Test SSH connectivity to both VPS servers
- ✅ Verify Debian 13 OS on remote servers
- ✅ Check disk space and RAM
- ✅ Verify network connectivity

**Expected output**:
```
✓ All dependencies installed
✓ Inventory configuration valid
✓ SSH key found
✓ SSH connection to Observability successful
✓ SSH connection to VPSManager successful
✓ OS: Debian 13 (correct)
✓ Disk space: 40GB available
✓ RAM: 2048MB
✓ Network connectivity OK
✓ All pre-flight checks passed!
```

---

## Deployment Execution

### Option 1: Automatic Deployment (Recommended)

The simplest way - fully automated with auto-healing:

```bash
# Deploy everything with auto-healing
./deploy-enhanced.sh all
```

**What happens**:
1. Pre-flight validation (auto-fixes issues)
2. Displays deployment plan
3. Deploys Observability Stack (5-10 minutes)
4. Deploys VPSManager (10-15 minutes)
5. Shows access URLs and next steps

**Total time**: ~15-25 minutes

### Option 2: Interactive Deployment

If you want confirmation prompts:

```bash
# Deploy with interactive confirmations
./deploy-enhanced.sh --interactive all
```

You'll be prompted:
- Before starting deployment
- Before each major step
- To continue after each component

### Option 3: Step-by-Step Deployment

Deploy components separately:

```bash
# Step 1: Deploy Observability Stack only
./deploy-enhanced.sh observability

# Wait for completion, then...

# Step 2: Deploy VPSManager only
./deploy-enhanced.sh vpsmanager
```

### Option 4: Preview Before Deploying

See what will be deployed without executing:

```bash
# Dry-run mode - shows plan only
./deploy-enhanced.sh --plan
```

### Expected Deployment Output

```
   ____ _   _  ___  __  __
  / ___| | | |/ _ \|  \/  |
 | |   | |_| | | | | |\/| |
 | |___|  _  | |_| | |  | |
  \____|_| |_|\___/|_|  |_|

  Infrastructure Deployment Orchestrator

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Pre-flight Validation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[✓] Checking local dependencies...
[✓] All dependencies installed
[✓] Validating inventory configuration...
[✓] Inventory configuration valid
[✓] Checking SSH key...
[✓] SSH key found
[INFO] Testing SSH connection to Observability (root@203.0.113.10:22)...
[✓] SSH connection to Observability successful
[INFO] Testing SSH connection to VPSManager (root@203.0.113.20:22)...
[✓] SSH connection to VPSManager successful
...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Deployment Plan
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Target Infrastructure:

  ┌─ Observability Stack
  │  IP:       203.0.113.10
  │  Hostname: monitoring.example.com
  │  Services: Prometheus, Loki, Grafana, Alertmanager, Tempo, Alloy
  │  Ports:    9090 (Prometheus), 3000 (Grafana), 3100 (Loki)
  └─

  ┌─ VPSManager
  │  IP:       203.0.113.20
  │  Hostname: manager.example.com
  │  Services: Nginx, PHP-FPM, MariaDB, Redis, Laravel, Exporters
  │  Ports:    80/443 (Web), 3306 (MySQL), 6379 (Redis)
  └─

Deployment Steps:

  1. Deploy Observability Stack to 203.0.113.10
     - Install Prometheus 2.54.1
     - Install Loki 3.2.1
     - Install Grafana 11.3.0
     - Install Alertmanager 0.27.0
     - Configure Nginx reverse proxy
     - Setup Let's Encrypt SSL

  2. Deploy VPSManager to 203.0.113.20
     - Install LEMP stack (Nginx, PHP 8.2/8.4, MariaDB 11.4)
     - Deploy Laravel application
     - Install monitoring exporters
     - Configure Promtail log shipping to 203.0.113.10
     - Setup application monitoring

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Deploying Observability
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[STEP] Deploying Observability Stack...
[INFO] Target: root@203.0.113.10:22
[INFO] Copying setup script...
[INFO] Executing setup (this may take 5-10 minutes)...

... (installation output) ...

[✓] Observability Stack deployed successfully!
[INFO] Grafana: http://203.0.113.10:3000
[INFO] Prometheus: http://203.0.113.10:9090

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Deploying VPSManager
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[STEP] Deploying VPSManager...
[INFO] Target: root@203.0.113.20:22
[INFO] Copying setup script...
[INFO] Executing setup (this may take 10-15 minutes)...

... (installation output) ...

[✓] VPSManager deployed successfully!
[INFO] Dashboard: http://203.0.113.20:8080

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Deployment Complete!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ All components deployed successfully!

Access URLs:
  Grafana:     http://203.0.113.10:3000
  Prometheus:  http://203.0.113.10:9090
  VPSManager:  http://203.0.113.20:8080

Next Steps:
  1. Access Grafana and configure dashboards
  2. Set up alert notification channels
  3. Configure VPSManager Laravel application
  4. Verify monitoring data is flowing
```

---

## Post-Deployment Verification

### Step 1: Verify Service Status

#### Check Observability Stack

```bash
# SSH into Observability VPS
ssh root@203.0.113.10

# Check all services
systemctl status prometheus
systemctl status grafana-server
systemctl status loki
systemctl status alertmanager
systemctl status promtail

# All should show "active (running)"

# Exit
exit
```

#### Check VPSManager

```bash
# SSH into VPSManager VPS
ssh root@203.0.113.20

# Check LEMP stack
systemctl status nginx
systemctl status php8.4-fpm
systemctl status mariadb
systemctl status redis-server

# Check exporters
systemctl status node_exporter
systemctl status nginx_exporter
systemctl status mysqld_exporter
systemctl status phpfpm_exporter

# Exit
exit
```

### Step 2: Test Web Access

Open your browser and verify access to:

#### Observability Stack

| Service | URL | Expected |
|---------|-----|----------|
| **Grafana** | http://203.0.113.10:3000 | Grafana login page |
| **Prometheus** | http://203.0.113.10:9090 | Prometheus web UI |
| **Prometheus Targets** | http://203.0.113.10:9090/targets | All targets should be "UP" |

#### VPSManager

| Service | URL | Expected |
|---------|-----|----------|
| **Web Dashboard** | http://203.0.113.20:8080 | Laravel welcome or configured app |
| **Node Exporter** | http://203.0.113.20:9100/metrics | Metrics output |

### Step 3: Verify Monitoring Integration

#### Check Prometheus Targets

1. Open: http://203.0.113.10:9090/targets
2. Verify all targets show status "UP":
   - prometheus (self)
   - node_exporter (both VPS)
   - nginx_exporter (VPSManager)
   - mysqld_exporter (VPSManager)
   - phpfpm_exporter (VPSManager)

#### Check Grafana Datasources

1. Open: http://203.0.113.10:3000
2. Login with default credentials:
   - Username: `admin`
   - Password: `admin` (you'll be prompted to change)
3. Navigate to: Configuration → Data Sources
4. Verify datasources are configured:
   - Prometheus
   - Loki
   - Tempo

#### Check Log Collection

1. In Grafana, go to Explore
2. Select "Loki" datasource
3. Query: `{job="varlogs"}`
4. Should show logs from VPSManager

### Step 4: Test Alerting (Optional)

#### Trigger a Test Alert

```bash
# SSH into VPSManager VPS
ssh root@203.0.113.20

# Temporarily stop a service to trigger an alert
systemctl stop nginx

# Wait 1-2 minutes, then check Prometheus alerts
# http://203.0.113.10:9090/alerts

# Restart the service
systemctl start nginx

# Exit
exit
```

---

## Access and Initial Configuration

### Grafana Initial Setup

1. **Access Grafana**: http://203.0.113.10:3000

2. **First Login**:
   - Username: `admin`
   - Password: `admin`
   - You'll be prompted to change the password

3. **Import Dashboards**:
   - Go to: Dashboards → Import
   - Recommended dashboards:
     - Node Exporter Full (Dashboard ID: 1860)
     - Nginx Overview (Dashboard ID: 12708)
     - MySQL Overview (Dashboard ID: 7362)
     - PHP-FPM (Dashboard ID: 11331)

4. **Configure Alerts**:
   - Go to: Alerting → Contact points
   - Add email, Slack, or other notification channels

### VPSManager Laravel Configuration

1. **SSH into VPSManager**:
   ```bash
   ssh root@203.0.113.20
   cd /var/www/vpsmanager
   ```

2. **Configure Environment**:
   ```bash
   # Edit .env file
   nano .env

   # Set your configuration:
   APP_NAME="CHOM VPSManager"
   APP_ENV=production
   APP_DEBUG=false
   APP_URL=http://manager.example.com

   DB_DATABASE=vpsmanager
   DB_USERNAME=vpsmanager
   DB_PASSWORD=<your-secure-password>
   ```

3. **Run Migrations**:
   ```bash
   php artisan migrate
   php artisan db:seed  # If you have seeders
   ```

4. **Create Admin User** (if applicable):
   ```bash
   php artisan make:user
   # Or use tinker
   php artisan tinker
   ```

5. **Optimize Application**:
   ```bash
   php artisan config:cache
   php artisan route:cache
   php artisan view:cache
   ```

### SSL Certificate Setup (Optional but Recommended)

#### For Observability Stack

```bash
ssh root@203.0.113.10

# Install Certbot
apt-get update
apt-get install -y certbot python3-certbot-nginx

# Get certificate (replace with your domain)
certbot --nginx -d monitoring.example.com

# Test auto-renewal
certbot renew --dry-run
```

#### For VPSManager

```bash
ssh root@203.0.113.20

# Get certificate
certbot --nginx -d manager.example.com
```

---

## Troubleshooting

### Deployment Failures

#### Issue: SSH Connection Failed

**Symptoms**:
```
[✗] Cannot connect to Observability via SSH
```

**Auto-Recovery**:
The script automatically attempts:
- Clear known_hosts
- Verify host reachability (ping)
- Check SSH port accessibility
- Retry with exponential backoff

**Manual Fix**:
```bash
# Verify VPS is reachable
ping 203.0.113.10

# Test SSH manually
ssh -v root@203.0.113.10

# Check firewall on VPS (from VPS console)
ufw status
ufw allow 22/tcp
```

#### Issue: Pre-flight Validation Failed

**Symptoms**:
```
[✗] Pre-flight checks failed after 3 attempts
```

**Solutions**:

1. **Missing Dependencies**:
   ```bash
   # Auto-installed, but manual installation:
   sudo apt-get update
   sudo apt-get install -y jq
   sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
   sudo chmod +x /usr/local/bin/yq
   ```

2. **Insufficient Disk Space**:
   ```bash
   # Check disk space
   ssh root@203.0.113.10 "df -h"

   # Clean up if needed
   ssh root@203.0.113.10 "apt-get clean && apt-get autoclean"
   ```

3. **Wrong OS Version**:
   ```bash
   # Verify OS version
   ssh root@203.0.113.10 "cat /etc/os-release"

   # Should show: Debian 13
   # If not, provision a new VPS with Debian 13
   ```

#### Issue: Deployment Interrupted

**Symptoms**:
Deployment stopped mid-way due to network issue or ctrl+c.

**Solution**:
```bash
# Resume from last successful checkpoint
./deploy-enhanced.sh --resume
```

The script automatically:
- Skips completed components
- Continues from where it stopped
- Maintains deployment state

#### Issue: Service Won't Start

**Symptoms**:
```
[✗] Deploy observability failed after 3 attempts
```

**Debug**:
```bash
# SSH into the VPS
ssh root@203.0.113.10

# Check service status
systemctl status prometheus
systemctl status grafana-server

# View service logs
journalctl -u prometheus -n 50
journalctl -u grafana-server -n 50

# Check for port conflicts
netstat -tulpn | grep :9090
netstat -tulpn | grep :3000
```

**Common Fixes**:

1. **Port Already in Use**:
   ```bash
   # Find and stop conflicting service
   lsof -i :9090
   systemctl stop <conflicting-service>

   # Re-run deployment
   ./deploy-enhanced.sh --resume
   ```

2. **Configuration Error**:
   ```bash
   # Check configuration files
   cat /etc/prometheus/prometheus.yml

   # Validate syntax
   promtool check config /etc/prometheus/prometheus.yml
   ```

### Post-Deployment Issues

#### Issue: Prometheus Targets Down

**Check**:
```bash
# Access Prometheus UI
# http://203.0.113.10:9090/targets
# If targets show "DOWN"
```

**Fix**:
```bash
# SSH into VPSManager
ssh root@203.0.113.20

# Check exporters are running
systemctl status node_exporter
systemctl status nginx_exporter

# Restart if needed
systemctl restart node_exporter

# Check firewall
ufw status
ufw allow from 203.0.113.10 to any port 9100
```

#### Issue: No Logs in Loki

**Check**:
```bash
# SSH into VPSManager
ssh root@203.0.113.20

# Verify Promtail is running
systemctl status promtail

# Check Promtail logs
journalctl -u promtail -n 50

# Test connectivity to Loki
curl http://203.0.113.10:3100/ready
```

**Fix**:
```bash
# Restart Promtail
systemctl restart promtail

# Check configuration
cat /etc/promtail/config.yml
```

#### Issue: Grafana Can't Connect to Datasources

**Fix**:
```bash
# SSH into Observability VPS
ssh root@203.0.113.10

# Verify Prometheus is accessible locally
curl http://localhost:9090/-/healthy

# Verify Loki is accessible
curl http://localhost:3100/ready

# Restart Grafana
systemctl restart grafana-server
```

### Performance Issues

#### High CPU Usage

```bash
# Check processes
top

# If Prometheus is using too much CPU:
# Check for expensive queries in Prometheus UI
# Adjust scrape_interval in /etc/prometheus/prometheus.yml
# Default is 15s, can increase to 30s or 60s
```

#### High Memory Usage

```bash
# Check memory
free -h

# If Prometheus is using too much memory:
# Reduce retention period in /etc/prometheus/prometheus.yml
# Default is 30d, can reduce to 15d or 7d

# Restart Prometheus
systemctl restart prometheus
```

---

## Rollback Procedures

### Full Rollback (Remove Everything)

If you need to start over:

```bash
# SSH into Observability VPS
ssh root@203.0.113.10

# Stop all services
systemctl stop prometheus grafana-server loki alertmanager promtail

# Remove installations
rm -rf /etc/prometheus /var/lib/prometheus
rm -rf /etc/grafana /var/lib/grafana
rm -rf /etc/loki /var/lib/loki
apt-get remove --purge grafana

# Exit
exit

# SSH into VPSManager VPS
ssh root@203.0.113.20

# Stop services
systemctl stop nginx php8.4-fpm mariadb redis-server

# Remove installations
rm -rf /var/www/vpsmanager
apt-get remove --purge nginx php8.4-fpm mariadb-server redis-server

# Exit
exit

# Remove deployment state on control machine
cd /home/calounx/repositories/mentat/chom/deploy
rm -rf .deploy-state/
```

### Partial Rollback (Single Component)

#### Remove Only Observability Stack

```bash
ssh root@203.0.113.10
systemctl stop prometheus grafana-server loki alertmanager
systemctl disable prometheus grafana-server loki alertmanager
rm -rf /etc/prometheus /var/lib/prometheus
rm -rf /etc/grafana /var/lib/grafana
rm -rf /etc/loki /var/lib/loki
```

#### Remove Only VPSManager

```bash
ssh root@203.0.113.20
systemctl stop nginx php8.4-fpm mariadb
rm -rf /var/www/vpsmanager
# Optionally remove LEMP stack
apt-get remove --purge nginx php8.4-fpm mariadb-server
```

### Re-deployment After Rollback

```bash
# Clear deployment state
rm -rf .deploy-state/

# Run fresh deployment
./deploy-enhanced.sh all
```

---

## Quick Reference Commands

### Deployment Commands

```bash
# Full deployment (recommended)
./deploy-enhanced.sh all

# Interactive deployment
./deploy-enhanced.sh --interactive all

# Preview only (dry-run)
./deploy-enhanced.sh --plan

# Pre-flight checks only
./deploy-enhanced.sh --validate

# Resume interrupted deployment
./deploy-enhanced.sh --resume

# Deploy with verbose logging
./deploy-enhanced.sh --verbose all

# Debug mode
./deploy-enhanced.sh --debug all
```

### Service Management

```bash
# Check service status
systemctl status <service-name>

# Start/stop/restart service
systemctl start <service-name>
systemctl stop <service-name>
systemctl restart <service-name>

# Enable/disable autostart
systemctl enable <service-name>
systemctl disable <service-name>

# View service logs
journalctl -u <service-name> -f
journalctl -u <service-name> -n 100
```

### Monitoring Access

```bash
# Prometheus
http://<observability-ip>:9090

# Grafana
http://<observability-ip>:3000

# Prometheus Targets
http://<observability-ip>:9090/targets

# Prometheus Alerts
http://<observability-ip>:9090/alerts
```

---

## Deployment Checklist

Print this checklist and check off items as you complete them:

### Pre-Deployment
- [ ] VPS servers provisioned (2 servers with Debian 13)
- [ ] VPS IP addresses and SSH credentials recorded
- [ ] Repository cloned to control machine
- [ ] `configs/inventory.yaml` created and configured with actual IPs
- [ ] SSH access to both VPS servers verified
- [ ] `deploy-enhanced.sh` is executable

### Deployment
- [ ] Pre-flight validation passed (`./deploy-enhanced.sh --validate`)
- [ ] Deployment plan reviewed (`./deploy-enhanced.sh --plan`)
- [ ] Deployment executed (`./deploy-enhanced.sh all`)
- [ ] Observability Stack deployment completed successfully
- [ ] VPSManager deployment completed successfully

### Post-Deployment Verification
- [ ] Prometheus is accessible (http://observability-ip:9090)
- [ ] Grafana is accessible (http://observability-ip:3000)
- [ ] VPSManager is accessible (http://vpsmanager-ip:8080)
- [ ] All Prometheus targets are "UP" (/targets)
- [ ] Grafana datasources configured (Prometheus, Loki, Tempo)
- [ ] Logs appearing in Loki (verify in Grafana Explore)

### Configuration
- [ ] Grafana admin password changed
- [ ] Grafana dashboards imported
- [ ] Alert notification channels configured
- [ ] Laravel `.env` configured
- [ ] Database migrations run
- [ ] SSL certificates installed (optional)

### Final Verification
- [ ] All services running and healthy
- [ ] Monitoring data flowing correctly
- [ ] Alerts configured and tested
- [ ] Backup procedures documented

---

## Support and Resources

### Documentation
- **Deployment Script**: `README-ENHANCED.md`
- **Observability Stack**: `/observability-stack/README.md`
- **CHOM Platform**: `/chom/README.md`

### Helpful Commands
```bash
# View deployment script help
./deploy-enhanced.sh --help

# Check deployment state
cat .deploy-state/deployment.state | jq

# View script version
./deploy-enhanced.sh --version
```

### Common Files Locations

**On Observability VPS**:
- Prometheus config: `/etc/prometheus/prometheus.yml`
- Grafana config: `/etc/grafana/grafana.ini`
- Loki config: `/etc/loki/local-config.yaml`
- Service logs: `/var/log/` and `journalctl`

**On VPSManager VPS**:
- Nginx config: `/etc/nginx/sites-available/vpsmanager`
- Laravel app: `/var/www/vpsmanager`
- PHP-FPM config: `/etc/php/8.4/fpm/`
- MariaDB config: `/etc/mysql/`

---

## Appendix

### A. Example inventory.yaml

```yaml
observability:
  ip: "203.0.113.10"
  ssh_user: "deploy"  # Use sudo user with passwordless sudo
  ssh_port: 22
  hostname: "monitoring.example.com"

vpsmanager:
  ip: "203.0.113.20"
  ssh_user: "deploy"  # Use sudo user with passwordless sudo
  ssh_port: 22
  hostname: "manager.example.com"
```

### B. Deployment Timeline

| Phase | Duration | Description |
|-------|----------|-------------|
| Pre-flight checks | 1-2 min | Validation and SSH connectivity |
| Observability deployment | 5-10 min | Install Prometheus, Grafana, Loki, etc. |
| VPSManager deployment | 10-15 min | Install LEMP stack, Laravel, exporters |
| **Total** | **15-25 min** | Complete deployment |

### C. Port Reference

| Service | Port | Access |
|---------|------|--------|
| Prometheus | 9090 | Public (with auth) |
| Grafana | 3000 | Public |
| Loki | 3100 | Internal only |
| Alertmanager | 9093 | Internal only |
| Node Exporter | 9100 | Internal only |
| Nginx Exporter | 9113 | Internal only |
| MySQL Exporter | 9104 | Internal only |
| PHP-FPM Exporter | 9253 | Internal only |
| HTTP | 80 | Public |
| HTTPS | 443 | Public |
| SSH | 22 | Restricted |

---

## End of Guide

**Deployment Date**: _______________
**Deployed By**: _______________
**Observability VPS IP**: _______________
**VPSManager VPS IP**: _______________
**Notes**:
_______________________________________________
_______________________________________________
_______________________________________________
