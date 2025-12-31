# CHOM Operator Guide

Complete guide for deploying, configuring, and operating CHOM in production environments. This guide is for system administrators, DevOps engineers, and infrastructure operators.

## Table of Contents

1. [Production Deployment](#production-deployment)
2. [Configuration Reference](#configuration-reference)
3. [Infrastructure Setup](#infrastructure-setup)
4. [Monitoring and Observability](#monitoring-and-observability)
5. [Security Hardening](#security-hardening)
6. [Backup and Disaster Recovery](#backup-and-disaster-recovery)
7. [Performance Optimization](#performance-optimization)
8. [Maintenance Tasks](#maintenance-tasks)
9. [Troubleshooting](#troubleshooting)
10. [Scaling Guide](#scaling-guide)

---

## Production Deployment

### Quick Deploy (30 minutes)

For the fastest path to production, use the automated deployment script:

```bash
# Clone repository
git clone https://github.com/calounx/mentat.git
cd mentat/chom/deploy

# See deploy/QUICKSTART.md for detailed instructions
./deploy-enhanced.sh all
```

This will deploy:
- CHOM control plane
- Observability stack (Prometheus, Loki, Grafana)
- VPS manager infrastructure
- SSL certificates
- Firewall rules

### Manual Production Deployment

For more control over the deployment process:

#### Step 1: Server Requirements

**Control Plane Server:**
- **OS**: Ubuntu 22.04 LTS or Debian 13
- **CPU**: 2 cores minimum, 4+ recommended
- **RAM**: 4GB minimum, 8GB+ recommended
- **Disk**: 40GB SSD minimum, 100GB+ recommended
- **Network**: Public IP, 1Gbps connection

**Managed VPS Servers:**
- **OS**: Ubuntu 22.04 LTS or Debian 13
- **CPU**: 2+ cores per server
- **RAM**: 4GB+ per server
- **Disk**: 40GB+ per server
- **Network**: Public IP

#### Step 2: Install Dependencies

```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install PHP 8.2
sudo apt-get install -y software-properties-common
sudo add-apt-repository ppa:ondrej/php -y
sudo apt-get update
sudo apt-get install -y php8.2 php8.2-cli php8.2-fpm php8.2-mysql \
  php8.2-xml php8.2-mbstring php8.2-curl php8.2-zip php8.2-gd \
  php8.2-redis php8.2-bcmath

# Install Composer
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer

# Install Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install Nginx
sudo apt-get install -y nginx

# Install MySQL (or PostgreSQL)
sudo apt-get install -y mysql-server

# Install Redis
sudo apt-get install -y redis-server
sudo systemctl enable redis-server
sudo systemctl start redis-server

# Install Supervisor (for queue workers)
sudo apt-get install -y supervisor

# Install Certbot (for SSL)
sudo apt-get install -y certbot python3-certbot-nginx
```

#### Step 3: Setup Application

```bash
# Create application directory
sudo mkdir -p /var/www/chom
sudo chown -R $USER:$USER /var/www/chom
cd /var/www/chom

# Clone repository
git clone https://github.com/calounx/mentat.git .
cd chom

# Install dependencies
composer install --no-dev --optimize-autoloader
npm install
npm run build

# Set permissions
sudo chown -R www-data:www-data storage bootstrap/cache
sudo chmod -R 775 storage bootstrap/cache
```

#### Step 4: Configure Environment

```bash
# Create production environment file
cp .env.example .env
nano .env
```

**Production Environment Configuration:**

```bash
# Application
APP_NAME=CHOM
APP_ENV=production
APP_DEBUG=false
APP_URL=https://chom.yourdomain.com

# Generate secure key
php artisan key:generate

# Database (MySQL)
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=chom_production
DB_USERNAME=chom_user
DB_PASSWORD=SECURE_RANDOM_PASSWORD

# Redis
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

# Cache & Sessions
CACHE_STORE=redis
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis

# Mail (Production SMTP)
MAIL_MAILER=smtp
MAIL_HOST=smtp.yourprovider.com
MAIL_PORT=587
MAIL_USERNAME=your_smtp_username
MAIL_PASSWORD=your_smtp_password
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=noreply@yourdomain.com

# Stripe (Production Keys)
STRIPE_KEY=pk_live_xxxxx
STRIPE_SECRET=sk_live_xxxxx
STRIPE_WEBHOOK_SECRET=whsec_xxxxx

# Observability Stack
CHOM_PROMETHEUS_URL=http://your-prometheus-server:9090
CHOM_LOKI_URL=http://your-loki-server:3100
CHOM_GRAFANA_URL=https://grafana.yourdomain.com
CHOM_GRAFANA_API_KEY=your_grafana_api_key

# Security
SESSION_SECURE_COOKIE=true
SESSION_SAME_SITE=strict
AUTH_2FA_ENABLED=true
```

#### Step 5: Setup Database

```bash
# Create database
mysql -u root -p <<EOF
CREATE DATABASE chom_production CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'chom_user'@'localhost' IDENTIFIED BY 'SECURE_RANDOM_PASSWORD';
GRANT ALL PRIVILEGES ON chom_production.* TO 'chom_user'@'localhost';
FLUSH PRIVILEGES;
EOF

# Run migrations
php artisan migrate --force

# (Optional) Seed initial data
php artisan db:seed --class=ProductionSeeder
```

#### Step 6: Configure Nginx

```bash
sudo nano /etc/nginx/sites-available/chom
```

**Nginx Configuration:**

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name chom.yourdomain.com;

    # Redirect to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name chom.yourdomain.com;

    root /var/www/chom/chom/public;
    index index.php;

    # SSL Configuration (Certbot will populate these)
    ssl_certificate /etc/letsencrypt/live/chom.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/chom.yourdomain.com/privkey.pem;

    # SSL Security
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' https:; script-src 'self' 'unsafe-inline' 'unsafe-eval' https:; style-src 'self' 'unsafe-inline' https:;" always;

    # Max upload size
    client_max_body_size 100M;

    # Logging
    access_log /var/log/nginx/chom-access.log;
    error_log /var/log/nginx/chom-error.log;

    # Laravel specific
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
```

```bash
# Enable site
sudo ln -s /etc/nginx/sites-available/chom /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# Get SSL certificate
sudo certbot --nginx -d chom.yourdomain.com
```

#### Step 7: Configure Queue Workers

```bash
sudo nano /etc/supervisor/conf.d/chom-worker.conf
```

**Supervisor Configuration:**

```ini
[program:chom-worker]
process_name=%(program_name)s_%(process_num)02d
command=php /var/www/chom/chom/artisan queue:work redis --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=www-data
numprocs=4
redirect_stderr=true
stdout_logfile=/var/www/chom/chom/storage/logs/worker.log
stopwaitsecs=3600
```

```bash
# Start workers
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start chom-worker:*
```

#### Step 8: Configure Scheduler

```bash
# Add to crontab
sudo crontab -e -u www-data
```

Add line:
```
* * * * * cd /var/www/chom/chom && php artisan schedule:run >> /dev/null 2>&1
```

#### Step 9: Verify Deployment

```bash
# Check application
curl -I https://chom.yourdomain.com

# Check queue workers
sudo supervisorctl status chom-worker:*

# Check logs
tail -f /var/www/chom/chom/storage/logs/laravel.log

# Test database connection
php artisan tinker
>>> DB::connection()->getPdo();
```

---

## Configuration Reference

### Core Environment Variables

#### Application Settings

```bash
# Basic
APP_NAME=CHOM                      # Application name
APP_ENV=production                 # Environment: local, staging, production
APP_DEBUG=false                    # NEVER true in production
APP_URL=https://chom.example.com   # Full application URL

# Timezone & Locale
APP_TIMEZONE=UTC                   # Server timezone
APP_LOCALE=en                      # Default language
```

#### Database Configuration

```bash
# MySQL
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=chom_production
DB_USERNAME=chom_user
DB_PASSWORD=secure_password

# PostgreSQL (alternative)
DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432

# Connection Pool
DB_POOL_SIZE=10
DB_POOL_MAX_IDLE_TIME=60
```

#### Cache & Queue

```bash
# Redis Configuration
REDIS_CLIENT=phpredis              # phpredis (faster) or predis
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

# Database Separation
REDIS_DB=0                         # Default
REDIS_CACHE_DB=1                   # Cache
REDIS_QUEUE_DB=2                   # Queues
REDIS_SESSION_DB=3                 # Sessions

# Cache Settings
CACHE_STORE=redis
CACHE_PREFIX=chom_cache

# Queue Settings
QUEUE_CONNECTION=redis
QUEUE_RETRY_AFTER=90               # Seconds
```

#### Security Settings

```bash
# Session Security
SESSION_DRIVER=redis
SESSION_LIFETIME=120               # Minutes
SESSION_EXPIRE_ON_CLOSE=true
SESSION_SECURE_COOKIE=true         # Requires HTTPS
SESSION_SAME_SITE=strict           # strict, lax, none

# Two-Factor Authentication
AUTH_2FA_ENABLED=true
AUTH_2FA_REQUIRED_ROLES=owner,admin
AUTH_2FA_GRACE_PERIOD_DAYS=7
AUTH_2FA_SESSION_TIMEOUT_HOURS=24

# API Token Settings
SANCTUM_TOKEN_EXPIRATION=60        # Minutes
SANCTUM_TOKEN_ROTATION_ENABLED=true
SANCTUM_TOKEN_ROTATION_THRESHOLD=15
SANCTUM_TOKEN_GRACE_PERIOD=5
```

#### CHOM Platform Settings

```bash
# SSH Configuration
CHOM_SSH_KEY_PATH=/path/to/ssh/key
CHOM_DEFAULT_VPS_USER=chom
CHOM_DEFAULT_VPS_PORT=22

# Backup Settings
CHOM_BACKUP_RETENTION_DAYS=30
CHOM_BACKUP_MAX_SIZE_GB=10

# Rate Limiting
CHOM_API_RATE_LIMIT=60             # Requests per minute
CHOM_API_RATE_LIMIT_BURST=100
```

#### Observability Stack

```bash
# Prometheus
CHOM_PROMETHEUS_URL=http://prometheus:9090
CHOM_PROMETHEUS_ENABLED=true

# Loki
CHOM_LOKI_URL=http://loki:3100
CHOM_LOKI_ENABLED=true

# Grafana
CHOM_GRAFANA_URL=https://grafana.example.com
CHOM_GRAFANA_API_KEY=your_api_key
CHOM_GRAFANA_ENABLED=true
```

### Performance Tuning

#### PHP-FPM Configuration

```bash
sudo nano /etc/php/8.2/fpm/pool.d/www.conf
```

**Recommended Settings:**

```ini
[www]
user = www-data
group = www-data

listen = /var/run/php/php8.2-fpm.sock
listen.owner = www-data
listen.group = www-data

# Process Management
pm = dynamic
pm.max_children = 50
pm.start_servers = 10
pm.min_spare_servers = 5
pm.max_spare_servers = 20
pm.max_requests = 500

# Resource Limits
php_admin_value[memory_limit] = 256M
php_admin_value[upload_max_filesize] = 100M
php_admin_value[post_max_size] = 100M
php_admin_value[max_execution_time] = 300

# Logging
php_admin_value[error_log] = /var/log/php8.2-fpm.log
php_admin_flag[log_errors] = on
```

#### Redis Configuration

```bash
sudo nano /etc/redis/redis.conf
```

**Recommended Settings:**

```conf
# Memory
maxmemory 2gb
maxmemory-policy allkeys-lru

# Persistence
save 900 1
save 300 10
save 60 10000

# Performance
tcp-backlog 511
timeout 300
tcp-keepalive 60

# Security
requirepass your_redis_password
```

#### MySQL Optimization

```bash
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
```

**Recommended Settings:**

```ini
[mysqld]
# Memory
innodb_buffer_pool_size = 2G
innodb_log_file_size = 256M

# Performance
max_connections = 200
thread_cache_size = 16
query_cache_size = 0
query_cache_type = 0

# Logging
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2
```

---

## Infrastructure Setup

### VPS Server Preparation

Before adding VPS servers to CHOM, prepare them:

#### 1. Install Required Software

```bash
# On each VPS server
sudo apt-get update
sudo apt-get install -y nginx mysql-server php8.2-fpm \
  php8.2-mysql php8.2-xml php8.2-mbstring php8.2-curl \
  certbot python3-certbot-nginx

# Install Node Exporter (for Prometheus)
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xvfz node_exporter-1.7.0.linux-amd64.tar.gz
sudo mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-1.7.0.linux-amd64*

# Create systemd service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
User=node_exporter
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

sudo useradd -rs /bin/false node_exporter
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
```

#### 2. Configure Firewall

```bash
# Allow necessary ports
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw allow 9100/tcp    # Node Exporter (from Prometheus only)

# Enable firewall
sudo ufw enable
```

#### 3. Create CHOM User

```bash
# Create dedicated user for CHOM
sudo useradd -m -s /bin/bash chom
sudo usermod -aG www-data chom

# Setup SSH key authentication
sudo mkdir -p /home/chom/.ssh
sudo chmod 700 /home/chom/.ssh

# Copy public key from CHOM control plane
echo "ssh-rsa AAAAB3NzaC1yc2E... chom@deploy" | sudo tee /home/chom/.ssh/authorized_keys
sudo chmod 600 /home/chom/.ssh/authorized_keys
sudo chown -R chom:chom /home/chom/.ssh

# Add sudo privileges (for site management)
echo "chom ALL=(ALL) NOPASSWD: /usr/sbin/nginx, /usr/bin/systemctl, /usr/bin/certbot" | sudo tee /etc/sudoers.d/chom
```

#### 4. Verify Setup

```bash
# From CHOM control plane, test connection
ssh chom@vps-server-ip "whoami && sudo nginx -v"
```

### Load Balancer Setup (Optional)

For high availability, setup a load balancer:

#### Using Nginx as Load Balancer

```nginx
upstream chom_backend {
    least_conn;
    server chom1.example.com:443 max_fails=3 fail_timeout=30s;
    server chom2.example.com:443 max_fails=3 fail_timeout=30s;
    server chom3.example.com:443 max_fails=3 fail_timeout=30s;
}

server {
    listen 443 ssl http2;
    server_name chom.example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass https://chom_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Sticky sessions (important for Livewire)
        ip_hash;
    }
}
```

---

## Monitoring and Observability

### Prometheus Setup

#### Configure Prometheus Scraping

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # CHOM Application Metrics
  - job_name: 'chom'
    static_configs:
      - targets: ['chom.example.com:9090']

  # VPS Server Metrics
  - job_name: 'vps-servers'
    static_configs:
      - targets:
          - 'vps1.example.com:9100'
          - 'vps2.example.com:9100'
          - 'vps3.example.com:9100'

  # MySQL Metrics
  - job_name: 'mysql'
    static_configs:
      - targets: ['localhost:9104']

  # Redis Metrics
  - job_name: 'redis'
    static_configs:
      - targets: ['localhost:9121']

  # Nginx Metrics
  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:9113']
```

### Grafana Dashboards

Import these dashboard IDs:

- **Node Exporter Full** - 1860
- **MySQL Overview** - 7362
- **Redis Dashboard** - 11835
- **Nginx Overview** - 12708

### Custom CHOM Metrics

CHOM exposes custom metrics at `/metrics`:

```
# Site Metrics
chom_sites_total{status="active"} 42
chom_sites_total{status="suspended"} 3
chom_sites_created_total 127

# Backup Metrics
chom_backups_total{status="completed"} 834
chom_backups_total{status="failed"} 12
chom_backup_size_bytes 1.2e+10

# VPS Metrics
chom_vps_servers_total{status="online"} 5
chom_vps_cpu_usage_percent{server="vps1"} 45.2
chom_vps_memory_usage_bytes{server="vps1"} 3.2e+9
chom_vps_disk_usage_bytes{server="vps1"} 2.1e+10
```

### Alert Rules

```yaml
# /etc/prometheus/alerts/chom.yml
groups:
  - name: chom
    interval: 30s
    rules:
      # High Error Rate
      - alert: HighErrorRate
        expr: rate(chom_errors_total[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value }} errors/sec"

      # Site Down
      - alert: SiteDown
        expr: up{job="chom"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "CHOM site is down"
          description: "CHOM has been down for 2 minutes"

      # Disk Space Low
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space on {{ $labels.instance }}"
          description: "Only {{ $value | humanizePercentage }} space remaining"

      # High Memory Usage
      - alert: HighMemoryUsage
        expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Only {{ $value | humanizePercentage }} memory available"
```

---

## Security Hardening

### Application Security

#### 1. Environment Security

```bash
# Secure .env file
chmod 600 /var/www/chom/chom/.env
chown www-data:www-data /var/www/chom/chom/.env
```

#### 2. Disable Debug Mode

```bash
# In .env
APP_DEBUG=false
APP_ENV=production
```

#### 3. Configure CORS

```bash
# In .env
CORS_ALLOWED_ORIGINS=https://yourdomain.com
# Never use * in production!
```

#### 4. Enable Rate Limiting

Already configured in `app/Http/Kernel.php`:

```php
'api' => [
    'throttle:60,1',  // 60 requests per minute
    'auth:sanctum',
],
```

### Server Security

#### 1. SSH Hardening

```bash
sudo nano /etc/ssh/sshd_config
```

**Recommended Settings:**

```conf
# Disable root login
PermitRootLogin no

# Disable password authentication
PasswordAuthentication no
PubkeyAuthentication yes

# Allow specific users only
AllowUsers your-admin-user chom

# Change default port (optional)
Port 2222

# Disable X11 forwarding
X11Forwarding no
```

```bash
sudo systemctl reload sshd
```

#### 2. Firewall Configuration

```bash
# Reset firewall
sudo ufw --force reset

# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (adjust port if changed)
sudo ufw allow 22/tcp

# Allow HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow Prometheus (from monitoring server only)
sudo ufw allow from MONITORING_SERVER_IP to any port 9090

# Enable firewall
sudo ufw enable

# Verify rules
sudo ufw status verbose
```

#### 3. Fail2Ban Configuration

```bash
# Install
sudo apt-get install -y fail2ban

# Configure
sudo nano /etc/fail2ban/jail.local
```

```ini
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/*error.log

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/*error.log
```

```bash
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

### SSL/TLS Security

#### 1. Strong SSL Configuration

```nginx
# In Nginx configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
ssl_prefer_server_ciphers off;

# HSTS
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

# OCSP Stapling
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /etc/letsencrypt/live/example.com/chain.pem;
resolver 8.8.8.8 8.8.4.4 valid=300s;
```

#### 2. Auto-Renew Certificates

```bash
# Test renewal
sudo certbot renew --dry-run

# Cron job (already created by certbot)
sudo crontab -l
# Should show:
# 0 0,12 * * * certbot renew --quiet
```

---

## Backup and Disaster Recovery

### Database Backups

#### Automated Daily Backups

```bash
# Create backup script
sudo nano /usr/local/bin/chom-db-backup.sh
```

```bash
#!/bin/bash

BACKUP_DIR="/var/backups/chom/database"
DATE=$(date +%Y%m%d_%H%M%S)
DB_NAME="chom_production"
DB_USER="chom_user"
DB_PASS="your_password"

# Create backup directory
mkdir -p $BACKUP_DIR

# Dump database
mysqldump -u $DB_USER -p$DB_PASS $DB_NAME | gzip > $BACKUP_DIR/chom_db_$DATE.sql.gz

# Keep only last 7 days
find $BACKUP_DIR -name "chom_db_*.sql.gz" -mtime +7 -delete

# Upload to S3 (optional)
# aws s3 cp $BACKUP_DIR/chom_db_$DATE.sql.gz s3://your-bucket/backups/
```

```bash
# Make executable
sudo chmod +x /usr/local/bin/chom-db-backup.sh

# Add to crontab
sudo crontab -e
# Add line:
0 2 * * * /usr/local/bin/chom-db-backup.sh
```

### Application Backups

```bash
# Create backup script
sudo nano /usr/local/bin/chom-app-backup.sh
```

```bash
#!/bin/bash

BACKUP_DIR="/var/backups/chom/application"
DATE=$(date +%Y%m%d_%H%M%S)
APP_DIR="/var/www/chom/chom"

mkdir -p $BACKUP_DIR

# Backup storage and uploads
tar -czf $BACKUP_DIR/chom_storage_$DATE.tar.gz -C $APP_DIR storage

# Backup .env
cp $APP_DIR/.env $BACKUP_DIR/chom_env_$DATE

# Keep only last 7 days
find $BACKUP_DIR -name "chom_*" -mtime +7 -delete
```

### Disaster Recovery Plan

#### 1. Regular Backups Checklist

- ✅ Database backups (daily, automated)
- ✅ Application storage (daily, automated)
- ✅ Configuration files (.env, nginx configs)
- ✅ Off-site backup storage (S3, another server)
- ✅ Test restoration monthly

#### 2. Recovery Procedure

**Scenario: Complete server failure**

1. **Provision new server** (same specs)

2. **Restore application:**
   ```bash
   # Install dependencies (as in deployment section)
   # ...

   # Restore application files
   tar -xzf chom_storage_YYYYMMDD.tar.gz -C /var/www/chom/chom/
   ```

3. **Restore database:**
   ```bash
   # Create database
   mysql -u root -p -e "CREATE DATABASE chom_production;"

   # Restore from backup
   gunzip < chom_db_YYYYMMDD.sql.gz | mysql -u root -p chom_production
   ```

4. **Restore configuration:**
   ```bash
   cp chom_env_YYYYMMDD /var/www/chom/chom/.env
   ```

5. **Verify and restart services:**
   ```bash
   sudo systemctl restart nginx
   sudo systemctl restart php8.2-fpm
   sudo supervisorctl restart chom-worker:*
   ```

**Expected Recovery Time:** 30-60 minutes

---

## Performance Optimization

### Laravel Optimization

```bash
# Cache configuration
php artisan config:cache

# Cache routes
php artisan route:cache

# Cache views
php artisan view:cache

# Optimize autoloader
composer dump-autoload --optimize --classmap-authoritative

# Cache events
php artisan event:cache
```

### Database Optimization

```bash
# Analyze and optimize tables
php artisan tinker
>>> DB::statement('ANALYZE TABLE sites, backups, vps_servers');
>>> DB::statement('OPTIMIZE TABLE sites, backups, vps_servers');
```

### Redis Optimization

```bash
# Monitor Redis
redis-cli INFO stats

# Check slow queries
redis-cli SLOWLOG GET 10

# Flush cache if needed (careful in production!)
# redis-cli FLUSHDB
```

---

## Maintenance Tasks

### Daily Tasks (Automated)

- ✅ Database backups (cron)
- ✅ Storage backups (cron)
- ✅ Log rotation (logrotate)
- ✅ Queue processing (supervisor)

### Weekly Tasks

```bash
# Update packages
sudo apt-get update
sudo apt-get upgrade -y

# Clear old logs
php artisan telescope:prune
find /var/log -name "*.log" -mtime +30 -delete

# Check disk space
df -h

# Review metrics
# (Check Grafana dashboards)
```

### Monthly Tasks

```bash
# Test disaster recovery
# (Restore from backup to test server)

# Review security
sudo lynis audit system

# Update SSL certificates (auto-renewed by certbot)

# Review and optimize database
php artisan telescope:prune
ANALYZE TABLE sites, backups;
OPTIMIZE TABLE sites, backups;
```

---

## Troubleshooting

### Common Issues

#### Issue: High Memory Usage

**Symptoms:**
- Slow response times
- 502 Bad Gateway errors
- PHP-FPM crashes

**Diagnosis:**
```bash
# Check PHP-FPM processes
ps aux | grep php-fpm | wc -l

# Check memory usage
free -h

# Check PHP-FPM logs
tail -f /var/log/php8.2-fpm.log
```

**Solution:**
```bash
# Adjust PHP-FPM pool settings
sudo nano /etc/php/8.2/fpm/pool.d/www.conf

# Reduce max_children
pm.max_children = 30  # From 50
pm.start_servers = 5  # From 10

sudo systemctl restart php8.2-fpm
```

#### Issue: Queue Jobs Failing

**Symptoms:**
- Sites not deploying
- Backups not completing
- Error in supervisor logs

**Diagnosis:**
```bash
# Check queue workers
sudo supervisorctl status chom-worker:*

# Check worker logs
tail -f /var/www/chom/chom/storage/logs/worker.log

# Check failed jobs table
php artisan queue:failed
```

**Solution:**
```bash
# Restart workers
sudo supervisorctl restart chom-worker:*

# Retry failed jobs
php artisan queue:retry all

# Clear stuck jobs
php artisan queue:flush
```

#### Issue: Database Connection Errors

**Symptoms:**
- "SQLSTATE[HY000] [2002] Connection refused"
- Site returns 500 error

**Diagnosis:**
```bash
# Check MySQL status
sudo systemctl status mysql

# Check connections
mysql -u chom_user -p -e "SHOW PROCESSLIST;"

# Check max connections
mysql -u chom_user -p -e "SHOW VARIABLES LIKE 'max_connections';"
```

**Solution:**
```bash
# Increase max connections
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf

# Add/modify:
max_connections = 200

sudo systemctl restart mysql
```

---

## Scaling Guide

### Vertical Scaling (More Resources)

1. **Upgrade VPS Plan**
   - Increase CPU cores
   - Increase RAM
   - Increase disk space

2. **Adjust PHP-FPM Pool**
   ```bash
   # Increase workers proportionally
   pm.max_children = 100  # From 50
   pm.start_servers = 20  # From 10
   ```

3. **Increase Database Resources**
   ```bash
   # Increase buffer pool
   innodb_buffer_pool_size = 4G  # From 2G
   ```

### Horizontal Scaling (More Servers)

1. **Add More VPS Servers**
   - Deploy CHOM to multiple servers
   - Use load balancer (Nginx, HAProxy)
   - Shared Redis and MySQL

2. **Separate Services**
   ```
   Server 1: CHOM Application
   Server 2: MySQL Database
   Server 3: Redis Cache/Queue
   Server 4: Managed VPS 1
   Server 5: Managed VPS 2
   ...
   ```

3. **Database Replication**
   - Master-slave replication
   - Read replicas for queries
   - Write to master only

---

## Summary

You now know how to:

- ✅ Deploy CHOM to production
- ✅ Configure all environment variables
- ✅ Setup and prepare VPS servers
- ✅ Configure monitoring and observability
- ✅ Harden security
- ✅ Setup backups and disaster recovery
- ✅ Optimize performance
- ✅ Perform maintenance tasks
- ✅ Troubleshoot common issues
- ✅ Scale infrastructure

**Need more help?**
- 📖 [Getting Started](GETTING-STARTED.md)
- 💻 [Developer Guide](DEVELOPER-GUIDE.md)
- 👥 [User Guide](USER-GUIDE.md)
- 📧 support@chom.io

**Production ready!** 🚀
