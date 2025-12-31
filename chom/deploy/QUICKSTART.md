# CHOM Deployment Quick Start Guide

**Goal:** Deploy CHOM infrastructure in 30 minutes or less.

This guide is for first-time users who want the fastest path from zero to deployed.

## Prerequisites Check

Before starting, make sure you have:

- [ ] **2 VPS servers** with Debian 13 installed
- [ ] **SSH access** to both servers
- [ ] **Control machine** running Linux or macOS
- [ ] **15-30 minutes** of uninterrupted time

## 5-Step Deployment

### Step 1: Get the Code (2 minutes)

```bash
# Clone repository
git clone https://github.com/calounx/mentat.git
cd mentat/chom/deploy

# Make script executable
chmod +x deploy-enhanced.sh
```

### Step 2: Create Sudo Users on VPS (5 minutes)

**Do this on BOTH VPS servers:**

```bash
# SSH into your VPS as root
ssh root@YOUR_VPS_IP

# Download and run user setup script
wget https://raw.githubusercontent.com/calounx/mentat/master/chom/deploy/scripts/create-deploy-user.sh
chmod +x create-deploy-user.sh
sudo ./create-deploy-user.sh deploy

# Follow prompts to set a password (needed for ssh-copy-id)
```

This creates a user called `deploy` with passwordless sudo.

**Repeat for both VPS servers.**

### Step 3: Configure Inventory (3 minutes)

```bash
# Copy example config
cp configs/inventory.yaml.example configs/inventory.yaml

# Edit with your details
nano configs/inventory.yaml
```

Update with your VPS information:

```yaml
observability:
  ip: "YOUR_OBSERVABILITY_IP"        # Replace with actual IP
  ssh_user: "deploy"                  # User you created in Step 2
  ssh_port: 22
  hostname: "monitoring.example.com"  # Optional

vpsmanager:
  ip: "YOUR_VPSMANAGER_IP"            # Replace with actual IP
  ssh_user: "deploy"                  # User you created in Step 2
  ssh_port: 22
  hostname: "manager.example.com"     # Optional
```

**Save and exit** (Ctrl+X, then Y, then Enter in nano)

### Step 4: Validate Setup (2 minutes)

```bash
# Run pre-flight checks
./deploy-enhanced.sh --validate
```

**What happens:**
- Checks SSH connectivity
- Verifies Debian 13 OS
- Checks disk space and RAM
- Tests sudo access
- Auto-installs missing tools (yq, jq)

**If validation fails:**
- Read the error messages carefully
- Follow the troubleshooting steps shown
- Fix the issue and run `--validate` again

**Expected output when successful:**
```
✓ All dependencies installed
✓ Inventory configuration valid
✓ SSH connection to Observability successful
✓ SSH connection to VPSManager successful
✓ OS: Debian 13 (correct)
✓ Disk space: 40GB available
✓ All pre-flight checks passed!
```

### Step 5: Deploy (15-25 minutes)

```bash
# Deploy everything
./deploy-enhanced.sh all
```

**What happens:**
1. Shows deployment plan
2. Deploys Observability Stack (5-10 min)
   - Prometheus, Grafana, Loki, Alertmanager
3. Deploys VPSManager (10-15 min)
   - Nginx, PHP, MariaDB, Laravel

**Grab a coffee - this takes 15-25 minutes.**

The script will show progress and automatically:
- Retry on network failures
- Fix common errors
- Show status for each component

**When complete, you'll see:**
```
✓ All components deployed successfully!

Access URLs:
  Grafana:     http://YOUR_OBS_IP:3000
  Prometheus:  http://YOUR_OBS_IP:9090
  VPSManager:  http://YOUR_VPS_IP:8080
```

## First Login

### Grafana

1. Open: `http://YOUR_OBSERVABILITY_IP:3000`
2. Login:
   - Username: `admin`
   - Password: `admin`
3. Change password when prompted

### VPSManager

1. Open: `http://YOUR_VPSMANAGER_IP:8080`
2. You'll see the Laravel welcome page
3. Configure your application as needed

## Verification

Check everything is working:

```bash
# SSH into Observability VPS
ssh deploy@YOUR_OBSERVABILITY_IP

# Check services
systemctl status prometheus
systemctl status grafana-server
systemctl status loki

# All should show "active (running)"
exit

# SSH into VPSManager VPS
ssh deploy@YOUR_VPSMANAGER_IP

# Check services
systemctl status nginx
systemctl status php8.4-fpm
systemctl status mariadb

# All should show "active (running)"
exit
```

In Grafana:
1. Go to http://YOUR_OBS_IP:9090/targets
2. All targets should show "UP"

## Troubleshooting

### Deployment Failed?

```bash
# Resume from where it stopped
./deploy-enhanced.sh --resume
```

### SSH Connection Issues?

```bash
# Test SSH manually
ssh deploy@YOUR_VPS_IP

# If that fails, verify:
# 1. User 'deploy' exists on VPS
# 2. SSH key was copied (ssh-copy-id)
# 3. Firewall allows port 22
```

### Validation Errors?

Read the error messages - they include specific commands to fix the issue.

Common fixes:
- **Wrong OS:** Provision new VPS with Debian 13
- **Low disk:** Clean up or use larger VPS
- **Sudo fails:** Run user setup script again
- **No internet:** Check VPS network settings

### Need Help?

1. Run validation: `./deploy-enhanced.sh --validate`
2. Check the error messages (they're detailed!)
3. See full documentation: `DEPLOYMENT-GUIDE.md`
4. Review SSH setup: `SUDO-USER-SETUP.md`

## What's Next?

After successful deployment:

1. **Configure Grafana Dashboards**
   - Import pre-built dashboards (IDs: 1860, 12708, 7362)
   - Set up alert notification channels

2. **Configure VPSManager**
   - Edit Laravel .env file
   - Run database migrations
   - Set up admin user

3. **SSL Certificates** (Optional but recommended)
   ```bash
   ssh deploy@YOUR_VPS_IP
   sudo apt install certbot python3-certbot-nginx
   sudo certbot --nginx -d your-domain.com
   ```

4. **Backups**
   - Set up automated backups
   - Document recovery procedures

## Command Reference

```bash
# Validation
./deploy-enhanced.sh --validate        # Check setup before deploying

# Deployment
./deploy-enhanced.sh all               # Deploy everything (auto)
./deploy-enhanced.sh --interactive all # Deploy with confirmations
./deploy-enhanced.sh --plan            # Preview without executing

# Recovery
./deploy-enhanced.sh --resume          # Continue failed deployment

# Troubleshooting
./deploy-enhanced.sh --debug all       # Verbose logging
./deploy-enhanced.sh --help            # Full help text
```

## Quick Checklist

Use this to track your progress:

- [ ] Cloned repository
- [ ] Created sudo users on both VPS servers
- [ ] Configured inventory.yaml with VPS IPs
- [ ] Ran validation successfully
- [ ] Deployed successfully
- [ ] Can access Grafana
- [ ] Can access VPSManager
- [ ] All services running
- [ ] Prometheus targets are UP

## Time Breakdown

| Task | Time |
|------|------|
| Clone repo | 1 min |
| Create VPS users | 5 min |
| Configure inventory | 3 min |
| Validation | 2 min |
| Deployment | 15-25 min |
| **Total** | **26-36 min** |

## Common Mistakes to Avoid

1. **Using root instead of sudo user**
   - Always create a dedicated `deploy` user
   - See SUDO-USER-SETUP.md

2. **Skipping validation**
   - Always run `--validate` before deploying
   - Catches issues early

3. **Wrong IP addresses**
   - Double-check inventory.yaml
   - Use actual IPs, not 0.0.0.0

4. **Not setting user password**
   - ssh-copy-id requires a password
   - Set it when creating the user

5. **Firewall blocking SSH**
   - Ensure port 22 is open
   - Test with: `nc -zv YOUR_IP 22`

## Success Indicators

You're done when:

- ✓ Validation passes with no errors
- ✓ Deployment completes without failures
- ✓ You can login to Grafana
- ✓ You can access VPSManager
- ✓ All systemd services show "active (running)"
- ✓ Prometheus shows all targets as "UP"

Congratulations! Your CHOM infrastructure is deployed.
