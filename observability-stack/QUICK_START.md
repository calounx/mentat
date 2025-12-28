# Quick Start Guide

Get your observability stack running in 10 minutes.

## What You'll Get

- **Grafana** dashboards showing all your server metrics
- **Prometheus** collecting CPU, memory, disk, network data
- **Loki** aggregating all your logs in one place
- **Email alerts** when things go wrong

## Prerequisites

- Fresh Debian 13 VPS (Ubuntu 22.04+ also works)
- Root access
- Domain name (optional, for SSL)

## Understanding the Roles

This installation system supports three different deployment scenarios. Choose the one that matches your needs:

### 1. Observability VPS (Central Monitoring Server)

**What it is:** A dedicated server that runs Prometheus, Loki, and Grafana to collect and visualize metrics and logs from all your other servers.

**When to use it:**
- You want a centralized monitoring solution for multiple servers
- This is typically the first thing you install
- One Observability VPS can monitor dozens of other servers

**What gets installed:**
- Prometheus (metrics database)
- Loki (log aggregation)
- Grafana (visualization dashboards)
- Alertmanager (alert routing and notifications)
- Node Exporter (to monitor the observability server itself)

**Resource requirements:**

| CPU | RAM | Disk |
|-----|-----|------|
| 1-2 vCPU | 2GB | 20GB |

**Installation time:** 15-20 minutes (including configuration)

### 2. VPSManager (Full-Stack Laravel Application)

**What it is:** A complete LEMP stack (Linux, Nginx, MySQL, PHP) configured for Laravel applications, plus monitoring exporters.

**When to use it:**
- You're deploying a Laravel application
- You want a pre-configured production environment
- You want your application server to be monitored by your Observability VPS

**What gets installed:**
- Full LEMP stack (Nginx, MySQL 8.0, PHP 8.3)
- Laravel deployment scripts
- Node Exporter (system metrics)
- MySQL Exporter (database metrics)
- Promtail (log shipping to Loki)

**Resource requirements:**

| CPU | RAM | Disk |
|-----|-----|------|
| 2+ vCPU | 4GB | 40GB |

**Installation time:** 25-35 minutes (including LEMP stack setup and Laravel deployment)

### 3. Monitored Host (Add Monitoring to Existing Server)

**What it is:** Lightweight monitoring agents that send metrics and logs from an existing server to your Observability VPS.

**When to use it:**
- You have an existing server you want to monitor
- You don't want to install the full observability stack
- You already have an Observability VPS set up

**What gets installed:**
- Node Exporter (system metrics: CPU, memory, disk, network)
- Promtail (ships logs to your Loki server)

**Resource requirements:**

| CPU | RAM | Disk |
|-----|-----|------|
| any | 512MB | 5GB |

**Installation time:** 3-5 minutes (lightweight exporter installation only)

**Note:** The exporters use minimal resources (typically <50MB RAM, <1% CPU).

## Step 1: Run the Installer (~1-2 minutes)

**Option A: One-command install (recommended)**

```bash
curl -sSL https://raw.githubusercontent.com/calounx/mentat/master/observability-stack/deploy/bootstrap.sh | sudo bash
```

**Option B: Manual clone**

```bash
git clone https://github.com/calounx/mentat.git
cd mentat/observability-stack
sudo ./deploy/install.sh
```

**Time estimate:** 1-2 minutes for download and initial setup

## Step 2: Choose Your Role (~30 seconds)

The installer will ask which role to install:

1. **Observability VPS** — Central monitoring server (Prometheus, Loki, Grafana)
2. **VPSManager** — Laravel application with full LEMP stack + monitoring
3. **Monitored Host** — Just exporters for existing servers

Refer to "Understanding the Roles" section above to determine which role fits your needs.

**Time estimate:** 30 seconds to select your role

## Step 3: Answer the Prompts (~2-5 minutes)

The installer will ask different questions based on the role you selected. Here's what to expect:

### For Observability VPS

The installer will prompt you for:

1. **Domain name (optional)**
   - **Prompt:** "Enter domain name for Grafana (leave empty for IP access):"
   - **What it means:** If you have a domain (like `monitoring.example.com`), enter it here. The installer will configure SSL automatically with Let's Encrypt.
   - **Example answer:** `monitoring.example.com` or leave empty to access via IP
   - **Note:** If using a domain, make sure DNS is already pointing to this server's IP

2. **Grafana admin password**
   - **Prompt:** "Set Grafana admin password:"
   - **What it means:** This is the password you'll use to login to Grafana web interface
   - **Example answer:** A strong password (minimum 8 characters recommended)
   - **Important:** Save this password securely - you'll need it to access Grafana

3. **Metrics retention period**
   - **Prompt:** "Metrics retention in days (default: 30):"
   - **What it means:** How long to keep historical metrics data
   - **Example answer:** `30` for 30 days, `90` for 3 months, `365` for 1 year
   - **Note:** Longer retention requires more disk space (roughly 1-2GB per monitored server per month)

4. **Logs retention period**
   - **Prompt:** "Logs retention in days (default: 14):"
   - **What it means:** How long to keep log data
   - **Example answer:** `14` for 2 weeks, `30` for 1 month
   - **Note:** Logs consume more space than metrics - start conservative

5. **Email for alerts (optional)**
   - **Prompt:** "SMTP email for alerts (leave empty to skip):"
   - **What it means:** Email address to receive alert notifications
   - **Example answer:** `alerts@example.com` or leave empty
   - **Note:** If you enter an email, you'll be prompted for SMTP settings next

6. **SMTP settings (if email provided)**
   - **SMTP server:** `smtp.gmail.com:587` for Gmail, `smtp.mailgun.org:587` for Mailgun
   - **SMTP username:** Your email or SMTP username
   - **SMTP password:** App-specific password (not your regular email password)

### For VPSManager

The installer will prompt you for:

1. **Laravel repository URL**
   - **Prompt:** "Enter your Laravel repository URL (https://...):"
   - **What it means:** The Git repository URL of your Laravel application
   - **Example answer:** `https://github.com/username/my-laravel-app.git`
   - **Note:** Repository must be accessible (public or SSH key configured)

2. **Domain name**
   - **Prompt:** "Enter domain name for your application:"
   - **What it means:** The domain where your Laravel app will be accessible
   - **Example answer:** `app.example.com`
   - **Important:** DNS must point to this server before requesting SSL

3. **MySQL root password**
   - **Prompt:** "Set MySQL root password:"
   - **What it means:** Password for MySQL database root user
   - **Example answer:** A strong password (save it securely)

4. **Laravel database name**
   - **Prompt:** "Laravel database name (default: laravel):"
   - **What it means:** Name of the MySQL database for your application
   - **Example answer:** `laravel` or your preferred database name

5. **Laravel database user**
   - **Prompt:** "Laravel database username (default: laravel):"
   - **What it means:** MySQL user that Laravel will use to connect
   - **Example answer:** `laravel` or your preferred username

6. **Laravel database password**
   - **Prompt:** "Laravel database password:"
   - **What it means:** Password for the Laravel database user
   - **Example answer:** A strong password (will be added to .env file)

7. **Observability VPS IP address**
   - **Prompt:** "Enter Observability VPS IP address:"
   - **What it means:** IP address of your central monitoring server
   - **Example answer:** `192.168.1.100` or your Observability VPS IP
   - **Note:** This must be the IP of a server where you've already installed the Observability VPS role

### For Monitored Host

The installer will prompt you for:

1. **Observability VPS IP address**
   - **Prompt:** "Enter Observability VPS IP address:"
   - **What it means:** IP address of your central monitoring server where Prometheus is running
   - **Example answer:** `192.168.1.100`
   - **Important:** This server must be reachable on the network

2. **Hostname for this server**
   - **Prompt:** "Enter a name for this host (used in Grafana):"
   - **What it means:** A friendly name to identify this server in Grafana dashboards
   - **Example answer:** `web-server-01`, `database-prod`, `api-server`
   - **Note:** Use descriptive names - you'll see this in dashboards

3. **Job name (optional)**
   - **Prompt:** "Enter job name (default: node_exporter):"
   - **What it means:** Prometheus job label for grouping metrics
   - **Example answer:** Usually just press Enter for default, or use `webservers`, `databases`, etc. to group similar hosts
   - **Note:** Job names help organize servers in Grafana queries

## Step 4: Verify Installation (~3-5 minutes)

After installation completes, verify everything is working correctly.

**Time estimate:** 3-5 minutes to run verification commands and check service status

### For Observability VPS

**1. Check that all services are running:**

```bash
sudo systemctl status prometheus grafana-server loki
```

**Expected output:** All services should show `active (running)` in green.

Example:
```
● prometheus.service - Prometheus
     Loaded: loaded (/etc/systemd/system/prometheus.service; enabled)
     Active: active (running) since...
```

**2. Test Prometheus is responding:**

```bash
curl -s http://localhost:9090/-/healthy
```

**Expected output:** `Prometheus is Healthy.`

**3. Test Grafana is responding:**

```bash
curl -s http://localhost:3000/api/health
```

**Expected output:** JSON response with `"database": "ok"`

**4. Verify Prometheus is collecting metrics:**

```bash
curl -s http://localhost:9090/api/v1/targets | grep -o '"health":"up"' | wc -l
```

**Expected output:** A number greater than 0 (at least 1 for node_exporter on the local server)

**5. Check Loki is receiving logs:**

```bash
sudo journalctl -u loki -n 20 --no-pager
```

**Expected output:** Log entries showing Loki starting successfully, no ERROR lines

### For VPSManager

**1. Check all services are running:**

```bash
sudo systemctl status nginx mysql php8.3-fpm node_exporter
```

**Expected output:** All services `active (running)`

**2. Test web server is responding:**

```bash
curl -I http://localhost
```

**Expected output:** `HTTP/1.1 200 OK` (or a redirect to HTTPS)

**3. Test MySQL is accessible:**

```bash
mysql -u root -p -e "SELECT VERSION();"
```

**Expected output:** MySQL version number (e.g., `8.0.35`)

**4. Verify Laravel is deployed:**

```bash
ls -la /var/www/laravel
```

**Expected output:** Laravel directory structure with `artisan`, `composer.json`, etc.

**5. Test Node Exporter is working:**

```bash
curl -s http://localhost:9100/metrics | head -n 5
```

**Expected output:** Metrics in Prometheus format starting with `# HELP` and `# TYPE`

### For Monitored Host

**1. Check Node Exporter is running:**

```bash
sudo systemctl status node_exporter
```

**Expected output:** `active (running)`

**2. Test Node Exporter metrics endpoint:**

```bash
curl -s http://localhost:9100/metrics | grep "node_cpu_seconds_total"
```

**Expected output:** Multiple lines showing CPU metrics

**3. Check Promtail is running:**

```bash
sudo systemctl status promtail
```

**Expected output:** `active (running)`

**4. Verify connectivity to Observability VPS:**

```bash
# Replace OBSERVABILITY_IP with your actual IP
ping -c 3 OBSERVABILITY_IP
```

**Expected output:** 3 successful ping responses with 0% packet loss

**5. Confirm target file was created:**

```bash
ls -lh /tmp/*-targets.yaml
```

**Expected output:** A YAML file with your hostname

## Step 5: Access Grafana (~5 minutes)

**For Observability VPS installations:**

1. **Open Grafana in your browser:**
   - With domain: `https://monitoring.example.com`
   - Without domain: `http://YOUR_VPS_IP:3000`

2. **Login with default credentials:**
   - **Username:** `admin`
   - **Password:** The password you set during installation

3. **Change the admin password:**
   - After first login, Grafana will prompt you to change the password
   - If not prompted, go to: Profile (click your name) > Change Password

4. **Verify data sources are configured:**
   - Navigate to: Configuration (gear icon) > Data Sources
   - You should see:
     - **Prometheus** (should show green "Data source is working")
     - **Loki** (should show green "Data source is working")

5. **Check that local metrics are being collected:**
   - Navigate to: Explore (compass icon)
   - Select "Prometheus" as the data source
   - In the query field, enter: `up`
   - Click "Run query"
   - **Expected result:** You should see at least one entry with `value=1` (the Observability VPS itself)

**Time estimate:** 5 minutes to access Grafana and verify data sources

## Step 6: Connect Monitored Hosts (~2-3 minutes per host)

If you installed the "Monitored Host" role on other servers, you need to register them with Prometheus.

**1. Copy the target file from the monitored host to Observability VPS:**

```bash
# On the monitored host, copy the file to Observability VPS
scp /tmp/HOSTNAME-targets.yaml root@OBSERVABILITY_IP:/etc/prometheus/targets/
```

Replace:
- `HOSTNAME` with the actual hostname you set during installation
- `OBSERVABILITY_IP` with your Observability VPS IP address

**2. On the Observability VPS, reload Prometheus to pick up the new target:**

```bash
sudo systemctl reload prometheus
```

**3. Verify the connection in Grafana:**
   - Navigate to: Configuration > Targets (or Status > Targets in older versions)
   - Look for your new host in the list
   - Status should show "UP" in green within 1-2 minutes

**Alternative method using SSH:**

If SCP is not available, you can manually create the target file:

```bash
# On Observability VPS, create the target file
sudo nano /etc/prometheus/targets/HOSTNAME-targets.yaml
```

Paste this content (replace values):
```yaml
- targets:
    - 'MONITORED_HOST_IP:9100'
  labels:
    job: 'node_exporter'
    instance: 'HOSTNAME'
```

Then reload Prometheus:
```bash
sudo systemctl reload prometheus
```

## First Steps After Installation

Once installation is verified, here's how to start using your observability stack:

### 1. Import Pre-built Dashboards

The stack includes several pre-configured dashboards.

**In Grafana:**

1. Click the **+** icon in the left sidebar
2. Select **Import**
3. Upload dashboard JSON files from your local clone:
   - Node Exporter: `grafana/dashboards/library/node-exporter-full.json`
   - System Overview: `grafana/dashboards/library/system-overview.json`
   - MySQL (if VPSManager): `grafana/dashboards/library/mysql-overview.json`

4. Select "Prometheus" as the data source
5. Click **Import**

**What you'll see:**
- CPU, Memory, Disk, Network graphs
- System load and process statistics
- Disk I/O and filesystem usage

### 2. Explore Your First Metrics

**Navigate to:** Explore (compass icon on left sidebar)

**Try these queries:**

```promql
# CPU usage percentage
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage percentage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Disk space used percentage
(1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100

# Network traffic (bytes per second)
rate(node_network_receive_bytes_total[5m])
```

Click **Run query** to see real-time data.

### 3. View Logs in Grafana

**Navigate to:** Explore

**Select data source:** Loki

**Try these queries:**

```logql
# All logs from a specific host
{job="varlogs"} |= "hostname"

# Only ERROR level logs
{job="varlogs"} |= "ERROR"

# Nginx access logs
{job="varlogs"} |= "nginx"
```

### 4. Configure Your First Alert

Alerts notify you when metrics cross thresholds (high CPU, low disk space, etc.).

**In Grafana:**

1. Navigate to: **Alerting** (bell icon) > **Alert rules**
2. Click **New alert rule**
3. Configure a simple disk space alert:

   **Query:**
   ```promql
   (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100
   ```

   **Condition:** `IS ABOVE 80`

   **For:** `5m` (alert if condition persists for 5 minutes)

   **Alert name:** "High Disk Usage"

   **Folder:** Create new folder "Infrastructure Alerts"

4. Click **Save rule and exit**

**Configure notification channels:**

1. Navigate to: **Alerting** > **Contact points**
2. Click **New contact point**
3. Choose integration:
   - **Email:** Enter email address (requires SMTP configured during install)
   - **Slack:** Enter webhook URL
   - **Discord:** Enter webhook URL
   - **PagerDuty:** Enter integration key

4. Click **Test** to verify, then **Save**

### 5. Add Your First Monitored Host

To monitor additional servers:

**On the new server:**

1. Run the installer:
   ```bash
   curl -sSL https://raw.githubusercontent.com/calounx/mentat/master/observability-stack/deploy/bootstrap.sh | sudo bash
   ```

2. Select role: **3. Monitored Host**

3. Enter your Observability VPS IP address

4. Give the host a descriptive name (e.g., `web-server-02`)

**On the Observability VPS:**

1. Copy the target file:
   ```bash
   scp root@NEW_SERVER_IP:/tmp/HOSTNAME-targets.yaml /etc/prometheus/targets/
   ```

2. Reload Prometheus:
   ```bash
   sudo systemctl reload prometheus
   ```

3. Verify in Grafana: Status > Targets (should show "UP" within 2 minutes)

### 6. Customize Retention Policies

If you need to adjust how long data is kept:

**Edit Prometheus retention:**
```bash
sudo nano /etc/systemd/system/prometheus.service
```

Look for the line with `--storage.tsdb.retention.time=` and modify (e.g., `90d` for 90 days).

Reload:
```bash
sudo systemctl daemon-reload
sudo systemctl restart prometheus
```

**Edit Loki retention:**
```bash
sudo nano /etc/loki/config.yml
```

Under `table_manager` section, modify `retention_period` (e.g., `720h` for 30 days).

Reload:
```bash
sudo systemctl restart loki
```

## Troubleshooting

### Services Not Starting

**Issue:** One or more services fail to start after installation.

**Diagnosis:**

```bash
# Check service status
sudo systemctl status prometheus
sudo systemctl status grafana-server
sudo systemctl status loki

# View detailed logs
sudo journalctl -u prometheus -n 50 --no-pager
sudo journalctl -u grafana-server -n 50 --no-pager
sudo journalctl -u loki -n 50 --no-pager
```

**Common causes:**

1. **Port already in use:**
   ```bash
   # Check what's using the ports
   sudo netstat -tlnp | grep -E ':(3000|9090|3100)'
   ```
   **Fix:** Stop the conflicting service or change the port in the service config

2. **Permission issues:**
   ```bash
   # Check file ownership
   ls -la /etc/prometheus/
   ls -la /var/lib/prometheus/
   ```
   **Fix:** Ensure files are owned by the correct user:
   ```bash
   sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
   ```

3. **Configuration syntax error:**
   ```bash
   # Validate Prometheus config
   promtool check config /etc/prometheus/prometheus.yml
   ```
   **Fix:** Correct syntax errors in the config file

### Metrics Not Appearing in Grafana

**Issue:** Grafana shows "No data" or monitored hosts don't appear.

**Diagnosis:**

```bash
# From Observability VPS, test connectivity to monitored host
curl -m 5 http://MONITORED_HOST_IP:9100/metrics

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job, instance, health}'
```

**Common causes:**

1. **Firewall blocking connections:**
   ```bash
   # On monitored host, check firewall status
   sudo ufw status
   ```
   **Fix:** Allow port 9100:
   ```bash
   sudo ufw allow from OBSERVABILITY_IP to any port 9100
   ```

2. **Target file not loaded:**
   ```bash
   # Check target files exist
   ls -la /etc/prometheus/targets/

   # Check Prometheus config includes target directory
   grep file_sd_configs /etc/prometheus/prometheus.yml
   ```
   **Fix:** Ensure target files are in `/etc/prometheus/targets/` and Prometheus has been reloaded

3. **DNS/network issues:**
   ```bash
   # Test network connectivity
   ping -c 3 MONITORED_HOST_IP

   # Test from Observability VPS
   telnet MONITORED_HOST_IP 9100
   ```
   **Fix:** Ensure servers can communicate over the network

### Grafana Login Issues

**Issue:** Cannot login to Grafana or forgot password.

**Reset admin password:**

```bash
sudo grafana-cli admin reset-admin-password NEW_PASSWORD
sudo systemctl restart grafana-server
```

**Check Grafana is listening:**

```bash
sudo netstat -tlnp | grep 3000
```

**Expected:** Should show grafana-server listening on port 3000

### SSL Certificate Failed

**Issue:** Let's Encrypt SSL certificate installation fails.

**Diagnosis:**

```bash
# Check DNS is pointing to this server
dig your-domain.com +short

# Check Certbot logs
sudo tail -50 /var/log/letsencrypt/letsencrypt.log
```

**Common causes:**

1. **DNS not propagated:**
   - Wait 10-60 minutes for DNS to propagate
   - Verify with: `nslookup your-domain.com`

2. **Port 80/443 blocked:**
   ```bash
   # Check firewall
   sudo ufw status | grep -E '80|443'
   ```
   **Fix:**
   ```bash
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```

3. **Retry certificate manually:**
   ```bash
   sudo certbot --nginx -d your-domain.com
   ```

### High Memory Usage

**Issue:** Prometheus or Loki consuming too much memory.

**Check memory usage:**

```bash
# Overall system memory
free -h

# Per-service memory usage
systemctl status prometheus | grep Memory
systemctl status loki | grep Memory
```

**Solutions:**

1. **Reduce retention period** (see "Customize Retention Policies" above)

2. **Reduce scrape frequency in Prometheus:**
   ```bash
   sudo nano /etc/prometheus/prometheus.yml
   ```
   Change `scrape_interval` from `15s` to `30s` or `60s`

3. **Limit query memory:**
   ```bash
   sudo nano /etc/systemd/system/prometheus.service
   ```
   Add `--query.max-samples=50000000` to ExecStart line

### Logs Not Showing in Loki

**Issue:** Logs not appearing in Grafana when querying Loki.

**Diagnosis:**

```bash
# Check Promtail is running on monitored hosts
sudo systemctl status promtail

# Check Promtail logs for errors
sudo journalctl -u promtail -n 50 --no-pager

# Test Loki endpoint
curl http://localhost:3100/ready
```

**Common causes:**

1. **Promtail not configured correctly:**
   ```bash
   # Check Promtail config
   sudo nano /etc/promtail/config.yml
   ```
   Verify the `clients` section points to your Loki server

2. **Network connectivity:**
   ```bash
   # From monitored host, test Loki endpoint
   curl -I http://OBSERVABILITY_IP:3100/ready
   ```

3. **Firewall blocking port 3100:**
   ```bash
   # On Observability VPS
   sudo ufw allow from MONITORED_IP to any port 3100
   ```

### Where to Get Help

If you're still stuck after trying the troubleshooting steps:

1. **Check the logs:** Most issues leave clues in systemd journals
   ```bash
   sudo journalctl -xe
   ```

2. **Detailed deployment documentation:** See [deploy/README.md](deploy/README.md)

3. **Security guide:** For firewall and SSL issues, see [SECURITY.md](SECURITY.md)

4. **GitHub Issues:** Search existing issues or create a new one at the repository

5. **Component documentation:**
   - [Prometheus Troubleshooting](https://prometheus.io/docs/prometheus/latest/troubleshooting/)
   - [Grafana Troubleshooting](https://grafana.com/docs/grafana/latest/troubleshooting/)
   - [Loki Troubleshooting](https://grafana.com/docs/loki/latest/operations/troubleshooting/)

## Next Steps

Now that your observability stack is running, consider these next steps:

- **Explore more dashboards:** Import additional dashboards from [Grafana's dashboard library](https://grafana.com/grafana/dashboards/)
- **Set up more alerts:** Create alerts for CPU, memory, disk, and application-specific metrics
- **Monitor more hosts:** Add monitoring to all your servers using the "Monitored Host" role
- **Customize retention:** Adjust data retention based on your storage capacity and compliance needs
- **Secure your setup:** Review [SECURITY.md](SECURITY.md) for hardening recommendations
- **Learn PromQL:** Practice writing queries at [PromQL basics](https://prometheus.io/docs/prometheus/latest/querying/basics/)

## Full Documentation

- [Deployment Guide](deploy/README.md) — Detailed installation instructions and architecture
- [Main README](README.md) — Full feature list and module documentation
- [Security Guide](SECURITY.md) — Security best practices and hardening
- [Architecture Overview](ARCHITECTURE.md) — System design and component interactions
