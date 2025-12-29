# Observability Stack Credentials Guide

## Overview

The observability stack has multiple authentication layers for security:

1. **Grafana Admin Account** - Access Grafana web interface
2. **HTTP Basic Auth** - Access Prometheus/Alertmanager via nginx
3. **SSH Keys** - Secure communication between monitored nodes
4. **Database Credentials** - For VPSManager installations (if applicable)

---

## 1. Grafana Admin Credentials

### Default Credentials
- **Username**: `admin`
- **Password**: Set during installation (displayed at end of install)

### Where Stored
- Configuration: `/etc/grafana/grafana.ini`
- Database: `/var/lib/grafana/grafana.db` (SQLite)

### How to Change Password

#### Option A: Via Web Interface (Recommended)
1. Login to https://your-domain.com
2. Click your profile icon (bottom left)
3. Go to **Profile** → **Change Password**
4. Enter current password and new password
5. Click **Change Password**

#### Option B: Via Command Line
```bash
# Reset to a new password
sudo grafana-cli admin reset-admin-password "YourNewPassword123"

# Restart Grafana
sudo systemctl restart grafana-server
```

#### Option C: Edit Configuration File
```bash
# Edit grafana.ini
sudo nano /etc/grafana/grafana.ini

# Find and update the line:
admin_password = YourNewPassword

# Restart Grafana
sudo systemctl restart grafana-server
```

**Important**: Password stored in `grafana.ini` is only used on first start. After that, it's stored in the database.

---

## 2. Prometheus/Alertmanager HTTP Basic Auth

### Purpose
Protects Prometheus and Alertmanager web interfaces when accessed via nginx reverse proxy.

### URLs Protected
- `https://your-domain.com/prometheus/`
- `https://your-domain.com/alertmanager/`

### Check if Configured

```bash
# Check if htpasswd file exists
sudo ls -la /etc/nginx/.htpasswd

# View current users (passwords are hashed)
sudo cat /etc/nginx/.htpasswd
```

### Create/Update Credentials

#### First User (Creates File)
```bash
# Install apache2-utils if not present
sudo apt-get install -y apache2-utils

# Create htpasswd file with first user
sudo htpasswd -c /etc/nginx/.htpasswd admin

# You'll be prompted to enter password twice
```

**Warning**: `-c` flag overwrites the file. Only use it for the FIRST user.

#### Add Additional Users
```bash
# Add more users (without -c flag)
sudo htpasswd /etc/nginx/.htpasswd username2
sudo htpasswd /etc/nginx/.htpasswd monitoring_user
```

#### Change Existing User Password
```bash
# Update password for existing user
sudo htpasswd /etc/nginx/.htpasswd admin
# Enter new password when prompted
```

#### Delete User
```bash
# Remove user from htpasswd file
sudo htpasswd -D /etc/nginx/.htpasswd username
```

#### Reload Nginx
```bash
# After any changes, reload nginx
sudo systemctl reload nginx
```

---

## 3. SSH Keys for Monitored Nodes

### Purpose
Secure communication between observability VPS and monitored nodes for metrics/logs collection.

### Location
- Private key: `/root/.ssh/observability_key`
- Public key: `/root/.ssh/observability_key.pub`

### View Current Keys
```bash
# On observability VPS
sudo cat /root/.ssh/observability_key.pub
```

### Regenerate SSH Keys

**Warning**: This will break connections to all monitored nodes.

```bash
# Generate new key pair
sudo ssh-keygen -t ed25519 -f /root/.ssh/observability_key -N "" -C "observability@mentat"

# Copy public key to monitored nodes
sudo ssh-copy-id -i /root/.ssh/observability_key.pub user@monitored-vps-ip
```

### Add Key to Monitored Node Manually
```bash
# On monitored node, add to authorized_keys
mkdir -p ~/.ssh
echo "PUBLIC_KEY_CONTENT_HERE" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
```

---

## 4. Database Credentials (VPSManager Only)

### For Laravel VPSManager Installation

#### MySQL/MariaDB Root Password
**Location**: `/root/.credentials/mysql`

```bash
# View credentials
sudo cat /root/.credentials/mysql
```

#### Laravel Database User
**Location**: `/var/www/vpsmanager/.env`

```bash
# View database configuration
sudo grep "DB_" /var/www/vpsmanager/.env
```

#### Change Database Password

```bash
# 1. Login to MySQL
sudo mysql

# 2. Change password
ALTER USER 'vpsmanager'@'localhost' IDENTIFIED BY 'NewPassword123';
FLUSH PRIVILEGES;
EXIT;

# 3. Update .env file
sudo nano /var/www/vpsmanager/.env
# Update: DB_PASSWORD=NewPassword123

# 4. Clear Laravel cache
cd /var/www/vpsmanager
sudo -u www-data php artisan config:clear
sudo -u www-data php artisan cache:clear

# 5. Update credentials file
echo "root:NewRootPassword" | sudo tee /root/.credentials/mysql
echo "vpsmanager:NewPassword123" | sudo tee -a /root/.credentials/mysql
sudo chmod 600 /root/.credentials/mysql
```

---

## 5. SMTP Credentials (If Configured)

### For Email Alerts

#### Grafana SMTP Settings
**Location**: `/etc/grafana/grafana.ini`

```bash
# View SMTP configuration
sudo grep -A 10 "\[smtp\]" /etc/grafana/grafana.ini
```

#### Update SMTP Credentials
```bash
# Edit grafana.ini
sudo nano /etc/grafana/grafana.ini

# Update these lines under [smtp]:
user = your-email@example.com
password = your-smtp-password

# Restart Grafana
sudo systemctl restart grafana-server
```

#### Alertmanager SMTP Settings
**Location**: `/etc/alertmanager/alertmanager.yml`

```bash
# Edit alertmanager config
sudo nano /etc/alertmanager/alertmanager.yml

# Update email_configs section:
global:
  smtp_smarthost: 'smtp.example.com:587'
  smtp_from: 'alerts@example.com'
  smtp_auth_username: 'your-email@example.com'
  smtp_auth_password: 'your-password'

# Restart alertmanager
sudo systemctl restart alertmanager
```

---

## Best Practices

### Password Security
1. **Use Strong Passwords**: Minimum 16 characters, mixed case, numbers, symbols
2. **Unique Passwords**: Different password for each service
3. **Password Manager**: Use a password manager to store credentials
4. **Change Defaults**: Always change default passwords immediately after installation

### Credential Storage
1. **Restrict Permissions**:
   ```bash
   sudo chmod 600 /etc/nginx/.htpasswd
   sudo chmod 600 /root/.credentials/*
   ```

2. **Encrypt Backups**: If backing up, encrypt files containing credentials

3. **Avoid Git**: Never commit credentials to version control

### Regular Rotation
```bash
# Recommended rotation schedule:
# - Grafana admin: Every 90 days
# - HTTP Basic Auth: Every 180 days
# - SSH keys: Every year
# - Database passwords: Every 180 days
```

---

## Quick Reference Card

| Service | Username | Password Location | Change Method |
|---------|----------|-------------------|---------------|
| Grafana UI | `admin` | `/etc/grafana/grafana.ini` | Web UI or `grafana-cli admin reset-admin-password` |
| Prometheus/Alertmanager | `admin` (or custom) | `/etc/nginx/.htpasswd` | `sudo htpasswd /etc/nginx/.htpasswd admin` |
| SSH Access | - | `/root/.ssh/observability_key` | `sudo ssh-keygen -t ed25519 ...` |
| MySQL (VPSManager) | `root` / `vpsmanager` | `/root/.credentials/mysql` | MySQL `ALTER USER` command |

---

## Troubleshooting

### Locked Out of Grafana
```bash
# Reset admin password
sudo grafana-cli admin reset-admin-password "NewPassword123"
sudo systemctl restart grafana-server
```

### Forgot HTTP Basic Auth Password
```bash
# Recreate htpasswd file
sudo htpasswd -c /etc/nginx/.htpasswd admin
# Enter new password
sudo systemctl reload nginx
```

### SSH Key Not Working
```bash
# Check key permissions
sudo ls -la /root/.ssh/observability_key
# Should be 600 (rw-------)

# Fix permissions
sudo chmod 600 /root/.ssh/observability_key
sudo chmod 644 /root/.ssh/observability_key.pub
```

### Can't Connect to Database
```bash
# Check if MySQL is running
sudo systemctl status mariadb

# Test connection
sudo mysql -u root -p

# Check Laravel database config
sudo grep "DB_" /var/www/vpsmanager/.env
```

---

## Security Checklist

- [ ] Changed default Grafana admin password
- [ ] Configured HTTP Basic Auth for Prometheus/Alertmanager
- [ ] SSH keys generated and deployed to monitored nodes
- [ ] Database passwords changed from defaults
- [ ] SMTP credentials configured (if using alerts)
- [ ] All credential files have restrictive permissions (600)
- [ ] Credentials documented in secure password manager
- [ ] Regular password rotation schedule established
- [ ] Backup strategy includes encrypted credential backups

---

## Additional Resources

- [Grafana Security Documentation](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/)
- [Nginx HTTP Basic Auth](https://docs.nginx.com/nginx/admin-guide/security-controls/configuring-http-basic-authentication/)
- [SSH Key Management](https://www.ssh.com/academy/ssh/key)
