# Quick & Dirty Deployment - Debian 13

> **Target:** Fresh Debian 13 server
> **Time:** ~30 minutes
> **User:** Root or sudo user

---

## Prerequisites

- Fresh Debian 13 server
- Root access or sudo privileges
- Domain name pointing to server IP (optional, can use IP)
- SSH access

---

## Step 1: System Update & Dependencies (5 min)

```bash
# Update system
apt update && apt upgrade -y

# Install essential packages
apt install -y \
    curl \
    git \
    unzip \
    ca-certificates \
    lsb-release \
    gnupg2 \
    supervisor \
    nginx

# Install PHP 8.2 and extensions
apt install -y \
    php8.2 \
    php8.2-fpm \
    php8.2-cli \
    php8.2-common \
    php8.2-mysql \
    php8.2-pgsql \
    php8.2-zip \
    php8.2-gd \
    php8.2-mbstring \
    php8.2-curl \
    php8.2-xml \
    php8.2-bcmath \
    php8.2-redis \
    php8.2-intl
```

---

## Step 2: Install Composer (2 min)

```bash
# Download and install Composer
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
chmod +x /usr/local/bin/composer

# Verify
composer --version
```

---

## Step 3: Install Node.js & NPM (3 min)

```bash
# Install Node.js 20.x (LTS)
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Verify
node --version
npm --version
```

---

## Step 4: Install MySQL/MariaDB (5 min)

```bash
# Install MariaDB
apt install -y mariadb-server mariadb-client

# Secure installation
mysql_secure_installation
# Answer prompts:
# - Set root password: YES (use strong password)
# - Remove anonymous users: YES
# - Disallow root login remotely: YES
# - Remove test database: YES
# - Reload privilege tables: YES

# Create database and user
mysql -u root -p << 'EOF'
CREATE DATABASE chom CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'chom_user'@'localhost' IDENTIFIED BY 'CHANGE_THIS_PASSWORD';
GRANT ALL PRIVILEGES ON chom.* TO 'chom_user'@'localhost';
FLUSH PRIVILEGES;
EXIT;
EOF
```

---

## Step 5: Install Redis (2 min)

```bash
# Install Redis
apt install -y redis-server

# Enable and start Redis
systemctl enable redis-server
systemctl start redis-server

# Verify
redis-cli ping
# Should return: PONG
```

---

## Step 6: Clone & Setup Application (10 min)

```bash
# Create app directory
mkdir -p /var/www/chom
cd /var/www/chom

# Clone repository
git clone https://github.com/calounx/mentat.git .
cd chom

# Install PHP dependencies
composer install --no-dev --optimize-autoloader --no-interaction

# Install Node dependencies
npm install

# Build frontend assets
npm run build

# Set permissions
chown -R www-data:www-data /var/www/chom
chmod -R 755 /var/www/chom
chmod -R 775 /var/www/chom/storage /var/www/chom/bootstrap/cache
```

---

## Step 7: Configure Environment (3 min)

```bash
# Copy environment file
cp .env.example .env

# Generate application key
php artisan key:generate

# Edit .env file
nano .env
```

**Update these values in .env:**

```env
APP_NAME=CHOM
APP_ENV=production
APP_DEBUG=false
APP_URL=http://your-domain.com

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=chom
DB_USERNAME=chom_user
DB_PASSWORD=CHANGE_THIS_PASSWORD

CACHE_DRIVER=redis
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

# Event system (enabled by default)
EVENTS_ENABLED=true
```

Save and exit (Ctrl+X, Y, Enter)

---

## Step 8: Run Migrations & Seed (2 min)

```bash
# Run database migrations
php artisan migrate --force

# (Optional) Seed test data for development
php artisan db:seed --class=TestUserSeeder
# Creates test user: admin@chom.local / password
```

---

## Step 9: Configure Nginx (5 min)

```bash
# Create Nginx config
cat > /etc/nginx/sites-available/chom << 'EOF'
server {
    listen 80;
    server_name your-domain.com www.your-domain.com;
    root /var/www/chom/chom/public;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    index index.php;

    charset utf-8;

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
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

# Enable site
ln -s /etc/nginx/sites-available/chom /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default

# Test configuration
nginx -t

# Restart Nginx
systemctl restart nginx
systemctl enable nginx
```

---

## Step 10: Setup Queue Workers (5 min)

```bash
# Create Supervisor config for queue workers
cat > /etc/supervisor/conf.d/chom-worker.conf << 'EOF'
[program:chom-worker]
process_name=%(program_name)s_%(process_num)02d
command=php /var/www/chom/chom/artisan queue:work redis --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=www-data
numprocs=2
redirect_stderr=true
stdout_logfile=/var/www/chom/chom/storage/logs/worker.log
stopwaitsecs=3600
EOF

# Reload Supervisor
supervisorctl reread
supervisorctl update
supervisorctl start chom-worker:*

# Verify workers are running
supervisorctl status
```

---

## Step 11: Setup Scheduler (2 min)

```bash
# Add Laravel scheduler to crontab
(crontab -l 2>/dev/null; echo "* * * * * cd /var/www/chom/chom && php artisan schedule:run >> /dev/null 2>&1") | crontab -

# Verify crontab
crontab -l
```

---

## Step 12: Cache Configuration (1 min)

```bash
cd /var/www/chom/chom

# Cache config, routes, views, events
php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan event:cache

# Clear application cache
php artisan cache:clear
```

---

## Step 13: Verify Installation

```bash
# Check queue workers
supervisorctl status

# Check Redis
redis-cli ping

# Check database connection
php artisan tinker
# Inside tinker, run:
DB::connection()->getPdo();
exit

# Check logs
tail -f /var/www/chom/chom/storage/logs/laravel.log

# Check web server
curl -I http://localhost
# Should return: HTTP/1.1 200 OK
```

---

## Step 14: Access Application

Open browser and navigate to:
```
http://your-server-ip
```

Or if you configured a domain:
```
http://your-domain.com
```

**Default test credentials (if seeded):**
- Email: `admin@chom.local`
- Password: `password`

---

## Post-Deployment: SSL/TLS (Optional, 5 min)

```bash
# Install Certbot
apt install -y certbot python3-certbot-nginx

# Obtain SSL certificate
certbot --nginx -d your-domain.com -d www.your-domain.com

# Follow prompts:
# - Enter email address
# - Agree to Terms of Service
# - Redirect HTTP to HTTPS: YES (recommended)

# Auto-renewal is set up automatically
# Test renewal:
certbot renew --dry-run
```

---

## Monitoring & Maintenance

### Check Queue Workers
```bash
supervisorctl status chom-worker:*
```

### Restart Queue Workers
```bash
supervisorctl restart chom-worker:*
```

### View Logs
```bash
# Application logs
tail -f /var/www/chom/chom/storage/logs/laravel.log

# Queue worker logs
tail -f /var/www/chom/chom/storage/logs/worker.log

# Nginx logs
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
```

### Check Failed Jobs
```bash
cd /var/www/chom/chom
php artisan queue:failed
```

### Retry Failed Jobs
```bash
php artisan queue:retry all
```

### Monitor Queue
```bash
php artisan queue:monitor default,notifications --max=1000
```

---

## Troubleshooting

### Permission Issues
```bash
chown -R www-data:www-data /var/www/chom
chmod -R 755 /var/www/chom
chmod -R 775 /var/www/chom/chom/storage /var/www/chom/chom/bootstrap/cache
```

### Clear All Caches
```bash
cd /var/www/chom/chom
php artisan cache:clear
php artisan config:clear
php artisan route:clear
php artisan view:clear
php artisan event:clear
```

### Reset Application
```bash
cd /var/www/chom/chom
php artisan migrate:fresh --seed --force
php artisan config:cache
php artisan route:cache
supervisorctl restart chom-worker:*
```

### Check PHP-FPM Status
```bash
systemctl status php8.2-fpm
```

### Restart Services
```bash
systemctl restart nginx
systemctl restart php8.2-fpm
systemctl restart redis-server
supervisorctl restart all
```

---

## Security Hardening (Production)

### 1. Firewall
```bash
# Install UFW
apt install -y ufw

# Allow SSH, HTTP, HTTPS
ufw allow 22
ufw allow 80
ufw allow 443

# Enable firewall
ufw enable

# Check status
ufw status
```

### 2. Fail2Ban
```bash
# Install Fail2Ban
apt install -y fail2ban

# Enable and start
systemctl enable fail2ban
systemctl start fail2ban
```

### 3. Secure Redis
```bash
# Edit Redis config
nano /etc/redis/redis.conf

# Find and uncomment:
# requirepass YOUR_STRONG_PASSWORD

# Restart Redis
systemctl restart redis-server

# Update .env
nano /var/www/chom/chom/.env
# Set: REDIS_PASSWORD=YOUR_STRONG_PASSWORD

# Clear config cache
php artisan config:cache
```

### 4. Disable Root SSH Login
```bash
nano /etc/ssh/sshd_config
# Set: PermitRootLogin no

systemctl restart sshd
```

---

## Performance Optimization

### 1. Enable OPcache
```bash
# Edit PHP-FPM config
nano /etc/php/8.2/fpm/php.ini

# Find and set:
opcache.enable=1
opcache.memory_consumption=128
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
opcache.revalidate_freq=2

# Restart PHP-FPM
systemctl restart php8.2-fpm
```

### 2. Increase PHP Limits
```bash
nano /etc/php/8.2/fpm/php.ini

# Set:
memory_limit = 512M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 300

systemctl restart php8.2-fpm
```

### 3. Optimize Nginx
```bash
nano /etc/nginx/nginx.conf

# In http block:
client_max_body_size 64M;
gzip on;
gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

systemctl restart nginx
```

---

## Quick Deployment Checklist

- [ ] System updated
- [ ] PHP 8.2 installed
- [ ] Composer installed
- [ ] Node.js installed
- [ ] MySQL/MariaDB installed and configured
- [ ] Redis installed and running
- [ ] Repository cloned
- [ ] Dependencies installed (composer + npm)
- [ ] .env configured
- [ ] Database migrated
- [ ] Nginx configured
- [ ] Queue workers running (Supervisor)
- [ ] Scheduler configured (crontab)
- [ ] Caches optimized
- [ ] SSL certificate installed (optional)
- [ ] Firewall configured
- [ ] Application accessible

---

## One-Line Quick Deploy (Advanced)

**WARNING:** This runs all commands automatically. Review each command first!

```bash
# Save as deploy.sh and run: bash deploy.sh
cat > /tmp/chom-deploy.sh << 'SCRIPT'
#!/bin/bash
set -e

echo "==> Installing system dependencies..."
apt update && apt upgrade -y
apt install -y curl git unzip ca-certificates lsb-release gnupg2 supervisor nginx
apt install -y php8.2 php8.2-fpm php8.2-cli php8.2-common php8.2-mysql php8.2-zip php8.2-gd php8.2-mbstring php8.2-curl php8.2-xml php8.2-bcmath php8.2-redis php8.2-intl

echo "==> Installing Composer..."
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
chmod +x /usr/local/bin/composer

echo "==> Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

echo "==> Installing MariaDB..."
apt install -y mariadb-server mariadb-client

echo "==> Installing Redis..."
apt install -y redis-server
systemctl enable redis-server
systemctl start redis-server

echo "==> Cloning application..."
mkdir -p /var/www/chom
cd /var/www/chom
git clone https://github.com/calounx/mentat.git .
cd chom

echo "==> Installing dependencies..."
composer install --no-dev --optimize-autoloader --no-interaction
npm install
npm run build

echo "==> Setting up environment..."
cp .env.example .env
php artisan key:generate

echo "==> Setting permissions..."
chown -R www-data:www-data /var/www/chom
chmod -R 755 /var/www/chom
chmod -R 775 /var/www/chom/chom/storage /var/www/chom/chom/bootstrap/cache

echo "==> Done! Edit /var/www/chom/chom/.env and configure database, then run migrations."
SCRIPT

chmod +x /tmp/chom-deploy.sh
/tmp/chom-deploy.sh
```

---

**Total Time:** ~30 minutes
**Ready for Production:** Configure SSL, firewall, and security hardening first!
