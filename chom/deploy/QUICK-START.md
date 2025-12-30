# CHOM Quick Start Guide - Deploy in 30 Minutes

Get your CHOM infrastructure deployed and running in 30 minutes with this streamlined guide.

## Overview

You'll deploy a complete monitoring and management infrastructure:
- **Observability Stack** - Prometheus, Grafana, Loki for monitoring
- **VPSManager** - Laravel application with LEMP stack (Nginx, PHP, MariaDB)

**Total time:** 30 minutes
**Difficulty:** Beginner-friendly
**VPS required:** 2 servers with Debian 13

---

## Prerequisites Checklist

Before you start, make sure you have:

- [ ] 2 VPS servers with Debian 13 (fresh install)
- [ ] Control machine with Linux or macOS
- [ ] SSH access to both VPS servers
- [ ] 30 minutes of uninterrupted time

### VPS Requirements

| Component | Min Specs | Recommended |
|-----------|-----------|-------------|
| **Observability VPS** | 1 vCPU, 2GB RAM, 20GB disk | 2 vCPU, 4GB RAM, 40GB SSD |
| **VPSManager VPS** | 1 vCPU, 2GB RAM, 20GB disk | 2 vCPU, 4GB RAM, 60GB SSD |

> **INFO:** You can provision VPS from any provider (DigitalOcean, Vultr, Hetzner, Linode, etc.)

---

## Step 1: Prepare Your VPS Servers (10 minutes)

### 1.1 Provision VPS Servers

1. Log in to your VPS provider
2. Create **2 new servers** with these settings:
   - Operating System: **Debian 13** (bookworm)
   - SSH keys: Add your SSH key during provisioning (optional)
   - Network: Enable public IPv4

3. Record your VPS details:

```
Observability VPS:
IP Address: ________________
Root Password: ________________

VPSManager VPS:
IP Address: ________________
Root Password: ________________
```

### 1.2 Create Sudo User (IMPORTANT - Security)

> **WARNING:** Do NOT use the root user for deployment! Create a dedicated sudo user.

On **each VPS**, run these commands:

```bash
# SSH into VPS as root
ssh root@YOUR_VPS_IP

# Download user creation script
wget https://raw.githubusercontent.com/calounx/mentat/master/chom/deploy/scripts/create-deploy-user.sh
chmod +x create-deploy-user.sh

# Create deployment user (replace 'deploy' with your preferred username)
./create-deploy-user.sh deploy

# Follow prompts:
# - Set a PASSWORD when prompted (required for ssh-copy-id later)
# - Copy the ssh-copy-id command shown
# - Exit the VPS
exit
```

**What this does:**
- Creates user `deploy` (or whatever name you chose)
- Grants passwordless sudo access
- Sets up SSH directory with proper permissions
- Shows you the command to copy your SSH key

### 1.3 Copy SSH Keys to VPS

On your **local machine**, run the command provided by the script:

```bash
# Example (use YOUR actual IP and username):
ssh-copy-id deploy@203.0.113.10

# Enter the password you set in step 1.2
# Repeat for second VPS:
ssh-copy-id deploy@203.0.113.20
```

### 1.4 Verify Access

Test passwordless SSH to both VPS:

```bash
# Test Observability VPS (replace with your IP and username)
ssh deploy@203.0.113.10
sudo whoami
# Should print: root (without asking for password)
exit

# Test VPSManager VPS
ssh deploy@203.0.113.20
sudo whoami
exit
```

> **SUCCESS:** If both tests work, you're ready to proceed!

> **HELP NEEDED:** If SSH or sudo doesn't work, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md#ssh-connection-issues)

---

## Step 2: Prepare Control Machine (5 minutes)

### 2.1 Clone Repository

On your **local machine**:

```bash
# Clone the repository
git clone https://github.com/calounx/mentat.git
cd mentat/chom/deploy

# Make deployment script executable
chmod +x deploy-enhanced.sh
```

### 2.2 Configure Inventory

Create your inventory configuration:

```bash
# Copy example configuration
cp configs/inventory.yaml.example configs/inventory.yaml

# Edit with your details
nano configs/inventory.yaml
```

**Update these values** (replace with YOUR actual IPs and username):

```yaml
observability:
  ip: "203.0.113.10"              # YOUR Observability VPS IP
  ssh_user: "deploy"              # Username you created in Step 1.2
  ssh_port: 22
  hostname: "monitoring.example.com"

vpsmanager:
  ip: "203.0.113.20"              # YOUR VPSManager VPS IP
  ssh_user: "deploy"              # Username you created in Step 1.2
  ssh_port: 22
  hostname: "manager.example.com"
```

Save the file (`Ctrl+X`, then `Y`, then `Enter` in nano).

### 2.3 Validate Configuration

Run pre-flight checks:

```bash
./deploy-enhanced.sh --validate
```

**Expected output:**
```
✓ All dependencies installed
✓ Inventory configuration valid
✓ SSH key found
✓ SSH connection to Observability successful
✓ SSH connection to VPSManager successful
✓ OS: Debian 13 (correct)
✓ Disk space: 40GB available
✓ RAM: 2048MB
✓ All pre-flight checks passed!
```

> **SUCCESS:** All checks passed? Continue to deployment!

> **FAILED CHECK:** See specific error message and fix before proceeding. Common issues in [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

---

## Step 3: Deploy Infrastructure (15 minutes)

### 3.1 Start Deployment

Run the automated deployment:

```bash
./deploy-enhanced.sh all
```

**What happens:**
1. **Pre-flight validation** (2 min) - Verifies everything is ready
2. **Observability Stack** (5-8 min) - Installs Prometheus, Grafana, Loki
3. **VPSManager Stack** (8-12 min) - Installs LEMP stack + Laravel
4. **Verification** (1 min) - Tests all services

### 3.2 Monitor Progress

You'll see output like this:

```
   ____ _   _  ___  __  __
  / ___| | | |/ _ \|  \/  |
 | |   | |_| | | | | |\/| |
 | |___|  _  | |_| | |  | |
  \____|_| |_|\___/|_|  |_|

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Deploying Observability
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[STEP] Installing Prometheus 2.54.1...
[STEP] Installing Grafana 11.3.0...
[STEP] Installing Loki 3.2.1...
[✓] Observability Stack deployed successfully!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Deploying VPSManager
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[STEP] Installing Nginx, PHP 8.4, MariaDB...
[STEP] Deploying Laravel application...
[✓] VPSManager deployed successfully!
```

> **TIP:** Grab a coffee! The script runs unattended and auto-fixes most issues.

### 3.3 Deployment Complete

When finished, you'll see:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Deployment Complete!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ All components deployed successfully!

Access URLs:
  Grafana:     http://203.0.113.10:3000
  Prometheus:  http://203.0.113.10:9090
  VPSManager:  http://203.0.113.20:8080

Next Steps:
  1. Access Grafana and change default password
  2. Import monitoring dashboards
  3. Configure Laravel application
```

> **SUCCESS:** Copy your access URLs - you'll need them in the next step!

---

## Step 4: Verify Deployment (5 minutes)

### 4.1 Check Grafana

1. Open in browser: `http://YOUR_OBSERVABILITY_IP:3000`
2. Login with default credentials:
   - Username: `admin`
   - Password: `admin`
3. You'll be prompted to change password - **DO THIS NOW**

> **SUCCESS:** Grafana login page appears

> **FAILED:** See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md#grafana-not-accessible)

### 4.2 Check Prometheus

1. Open: `http://YOUR_OBSERVABILITY_IP:9090`
2. Click "Status" → "Targets"
3. Verify all targets show **"UP"** status

**Expected targets:**
- `prometheus` (self-monitoring)
- `node_exporter` (both VPS)
- `nginx_exporter` (VPSManager)
- `mysqld_exporter` (VPSManager)
- `phpfpm_exporter` (VPSManager)

> **SUCCESS:** All targets show green "UP" status

> **FAILED:** Some targets "DOWN"? See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md#prometheus-targets-down)

### 4.3 Check VPSManager

1. Open: `http://YOUR_VPSMANAGER_IP:8080`
2. You should see the Laravel welcome page or configured application

> **SUCCESS:** Web page loads

> **FAILED:** See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md#vpsmanager-not-accessible)

### 4.4 Check Services

SSH into each VPS and verify services:

```bash
# Check Observability VPS
ssh deploy@YOUR_OBSERVABILITY_IP
systemctl status prometheus grafana-server loki
# All should show: active (running)
exit

# Check VPSManager VPS
ssh deploy@YOUR_VPSMANAGER_IP
systemctl status nginx php8.4-fpm mariadb redis-server
# All should show: active (running)
exit
```

> **SUCCESS:** All services show "active (running)"

---

## Next Steps

Your infrastructure is now running! Here's what to do next:

### 1. Secure Your Installation

Follow [SECURITY-SETUP.md](./SECURITY-SETUP.md) to:
- [ ] Enable SSL/TLS with Let's Encrypt
- [ ] Configure firewall rules
- [ ] Set up 2FA for admin access
- [ ] Configure secrets management

### 2. Configure Monitoring

In Grafana:
- [ ] Import dashboards (recommended IDs: 1860, 12708, 7362)
- [ ] Set up alert notification channels (email, Slack, etc.)
- [ ] Configure alert rules
- [ ] Test alerting with a test alert

### 3. Configure Laravel Application

SSH into VPSManager and configure:

```bash
ssh deploy@YOUR_VPSMANAGER_IP
cd /var/www/vpsmanager

# Edit environment file
sudo nano .env

# Run migrations
php artisan migrate

# Create admin user (if applicable)
php artisan make:user

# Optimize application
php artisan config:cache
php artisan route:cache
php artisan view:cache
```

### 4. Set Up DNS (Optional)

Point your domains to VPS IPs:
- `monitoring.example.com` → Observability IP
- `manager.example.com` → VPSManager IP

Then configure SSL certificates (see SECURITY-SETUP.md).

---

## Quick Reference

### Access URLs

Replace with YOUR IPs:

```bash
# Monitoring
Grafana:    http://YOUR_OBSERVABILITY_IP:3000
Prometheus: http://YOUR_OBSERVABILITY_IP:9090

# Application
VPSManager: http://YOUR_VPSMANAGER_IP:8080

# Metrics Exporters (internal only)
Node Exporter:   http://YOUR_VPS_IP:9100/metrics
Nginx Exporter:  http://YOUR_VPSMANAGER_IP:9113/metrics
MySQL Exporter:  http://YOUR_VPSMANAGER_IP:9104/metrics
PHP-FPM Exporter: http://YOUR_VPSMANAGER_IP:9253/metrics
```

### Useful Commands

```bash
# Check deployment status
./deploy-enhanced.sh --validate

# View deployment logs
cat .deploy-state/deployment.state | jq

# Re-deploy component
./deploy-enhanced.sh observability
./deploy-enhanced.sh vpsmanager

# Check service status
ssh deploy@YOUR_VPS_IP "systemctl status SERVICE_NAME"

# View service logs
ssh deploy@YOUR_VPS_IP "journalctl -u SERVICE_NAME -n 50"

# Restart service
ssh deploy@YOUR_VPS_IP "sudo systemctl restart SERVICE_NAME"
```

### Common Services

**Observability VPS:**
- `prometheus` - Metrics collection
- `grafana-server` - Dashboards
- `loki` - Log aggregation
- `alertmanager` - Alert management
- `promtail` - Log shipping

**VPSManager VPS:**
- `nginx` - Web server
- `php8.4-fpm` - PHP processor
- `mariadb` - Database
- `redis-server` - Cache
- `node_exporter` - System metrics
- `nginx_exporter` - Nginx metrics
- `mysqld_exporter` - Database metrics
- `phpfpm_exporter` - PHP metrics

---

## Troubleshooting

### Deployment Failed?

```bash
# Resume from where it stopped
./deploy-enhanced.sh --resume

# Or with debug output
./deploy-enhanced.sh --debug --resume
```

### SSH Connection Issues?

1. Verify you can SSH manually:
   ```bash
   ssh deploy@YOUR_VPS_IP
   ```

2. Verify passwordless sudo works:
   ```bash
   ssh deploy@YOUR_VPS_IP "sudo whoami"
   # Should print: root
   ```

3. Check inventory.yaml has correct IP and username

4. See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md#ssh-connection-issues) for detailed fixes

### Service Won't Start?

```bash
# SSH into VPS
ssh deploy@YOUR_VPS_IP

# Check service status
sudo systemctl status SERVICE_NAME

# View recent logs
sudo journalctl -u SERVICE_NAME -n 100

# Check for port conflicts
sudo netstat -tulpn | grep PORT_NUMBER
```

### More Help

For detailed troubleshooting, see:
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Common issues and fixes
- [README.md](./README.md) - Comprehensive deployment guide
- [SECURITY-SETUP.md](./SECURITY-SETUP.md) - Security configuration

---

## Success Checklist

You're done when:

- [x] Deployment completed without errors
- [x] Grafana accessible and password changed
- [x] Prometheus shows all targets "UP"
- [x] VPSManager web page loads
- [x] All systemd services show "active (running)"
- [ ] SSL certificates configured (optional but recommended)
- [ ] Firewall rules configured
- [ ] Monitoring alerts configured
- [ ] Application configured and tested

---

## What You've Deployed

### Observability Stack (Monitoring VPS)

| Service | Version | Purpose | Port |
|---------|---------|---------|------|
| Prometheus | 2.54.1 | Metrics collection & storage | 9090 |
| Grafana | 11.3.0 | Visualization dashboards | 3000 |
| Loki | 3.2.1 | Log aggregation | 3100 |
| Alertmanager | 0.27.0 | Alert management | 9093 |
| Nginx | Latest | Reverse proxy | 80/443 |

### VPSManager Stack (Application VPS)

| Service | Version | Purpose | Port |
|---------|---------|---------|------|
| Nginx | Latest | Web server | 80/443 |
| PHP-FPM | 8.4 | Application runtime | 9000 |
| MariaDB | 11.4 | Database | 3306 |
| Redis | Latest | Cache & sessions | 6379 |
| Laravel | Latest | Application framework | - |
| Node Exporter | Latest | System metrics | 9100 |
| Nginx Exporter | Latest | Web server metrics | 9113 |
| MySQL Exporter | Latest | Database metrics | 9104 |
| PHP-FPM Exporter | Latest | PHP metrics | 9253 |

---

## Congratulations!

You've successfully deployed CHOM infrastructure! Your monitoring and management platform is now running.

**What's next?**
1. Secure your installation (see SECURITY-SETUP.md)
2. Configure monitoring alerts
3. Deploy your applications
4. Enjoy automated infrastructure management!

Need help? Check:
- [README.md](./README.md) - Full documentation
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Problem solving
- [SECURITY-SETUP.md](./SECURITY-SETUP.md) - Security hardening

---

**Deployment Time:** ___________
**Your IPs:**
- Observability: ___________
- VPSManager: ___________

**Notes:**
_______________________________________
_______________________________________
