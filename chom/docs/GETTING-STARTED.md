# Getting Started with CHOM

Welcome to CHOM! This guide will walk you through setting up CHOM from scratch and creating your first site in about 20 minutes.

## Table of Contents

1. [Before You Begin](#before-you-begin)
2. [Installation](#installation)
3. [Initial Configuration](#initial-configuration)
4. [First Login](#first-login)
5. [Adding a VPS Server](#adding-a-vps-server)
6. [Creating Your First Site](#creating-your-first-site)
7. [Setting Up Backups](#setting-up-backups)
8. [Monitoring Your Site](#monitoring-your-site)
9. [Common Tasks](#common-tasks)
10. [Next Steps](#next-steps)
11. [Troubleshooting](#troubleshooting)

---

## Before You Begin

### What You'll Need

**For Local Development:**
- Computer with Linux or macOS (Windows via WSL2)
- 4GB RAM minimum (8GB recommended)
- 10GB free disk space
- Internet connection

**Software Requirements:**
- PHP 8.2 or higher
- Composer 2.x
- Node.js 18+ and npm
- Git
- A text editor (VS Code, PHPStorm, etc.)

**For Production Deployment:**
- 1-2 VPS servers (see [Operator Guide](OPERATOR-GUIDE.md))
- Domain name (optional but recommended)
- Stripe account (for billing features)

### Time Required

| Task | Time |
|------|------|
| Installation | 5-10 minutes |
| Configuration | 5 minutes |
| First site setup | 5 minutes |
| **Total** | **15-20 minutes** |

---

## Installation

### Step 1: Clone the Repository

```bash
# Clone the Mentat repository
git clone https://github.com/calounx/mentat.git
cd mentat/chom
```

### Step 2: Install PHP Dependencies

```bash
# Install backend dependencies
composer install

# This will download Laravel and all required packages
# Expected time: 2-3 minutes
```

**Troubleshooting:**
- If you see "composer: command not found", install Composer from [getcomposer.org](https://getcomposer.org)
- If you get PHP extension errors, see [Prerequisites](#prerequisites-check) below

### Step 3: Install JavaScript Dependencies

```bash
# Install frontend dependencies
npm install

# This will download Vue, Tailwind, and build tools
# Expected time: 1-2 minutes
```

### Step 4: Create Environment File

```bash
# Copy the example environment file
cp .env.example .env

# Generate application key
php artisan key:generate
```

You should see: `Application key set successfully.`

### Step 5: Setup Database

For local development, we'll use SQLite (zero configuration needed):

```bash
# Create SQLite database file
touch database/database.sqlite

# Run database migrations
php artisan migrate
```

You should see a list of migrations running successfully.

**Alternative: Using MySQL/PostgreSQL**

If you prefer MySQL or PostgreSQL, edit `.env`:

```bash
# For MySQL
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=chom
DB_USERNAME=your_username
DB_PASSWORD=your_password

# Then run migrations
php artisan migrate
```

### Step 6: Build Frontend Assets

```bash
# Build for development
npm run build

# This compiles Tailwind CSS and JavaScript
# Expected time: 30 seconds
```

### Step 7: Start the Development Server

```bash
# Start Laravel development server
php artisan serve
```

You should see:
```
INFO  Server running on [http://127.0.0.1:8000]
```

**Success!** CHOM is now running at [http://localhost:8000](http://localhost:8000)

---

## Initial Configuration

### Understanding the .env File

The `.env` file contains all configuration. Here are the key settings:

```bash
# Application
APP_NAME=CHOM                    # Your app name
APP_ENV=local                    # Environment (local, staging, production)
APP_URL=http://localhost:8000    # Your app URL

# Database (SQLite by default)
DB_CONNECTION=sqlite

# Cache and Queue (optional for development)
CACHE_STORE=file
QUEUE_CONNECTION=sync

# Stripe (required for billing)
STRIPE_KEY=pk_test_xxxxx
STRIPE_SECRET=sk_test_xxxxx
STRIPE_WEBHOOK_SECRET=whsec_xxxxx
```

### Optional: Setup Redis (Recommended)

Redis improves performance for caching and queues:

```bash
# Install Redis (Ubuntu/Debian)
sudo apt-get install redis-server

# Or macOS
brew install redis
brew services start redis

# Update .env
CACHE_STORE=redis
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis
```

### Optional: Setup Email

For development, we'll use log driver (emails written to `storage/logs`):

```bash
MAIL_MAILER=log
```

For production, configure SMTP:

```bash
MAIL_MAILER=smtp
MAIL_HOST=smtp.mailtrap.io
MAIL_PORT=2525
MAIL_USERNAME=your_username
MAIL_PASSWORD=your_password
MAIL_FROM_ADDRESS=hello@example.com
```

---

## First Login

### Create Your Admin Account

1. **Open CHOM** in your browser: [http://localhost:8000](http://localhost:8000)

2. **Click "Register"** or navigate to `/register`

3. **Fill in the registration form:**
   ```
   Organization Name: Acme Hosting
   Email: admin@example.com
   Password: (choose a strong password)
   ```

4. **Click "Create Account"**

5. **You're logged in!** You'll see the CHOM dashboard.

### Dashboard Overview

After login, you'll see:

```
┌─────────────────────────────────────────────┐
│  CHOM Dashboard                        [👤] │
├─────────────────────────────────────────────┤
│  Sites (0)  |  VPS Servers (0)  |  Backups  │
├─────────────────────────────────────────────┤
│                                              │
│  [+] Create Your First Site                 │
│                                              │
│  [+] Add VPS Server                         │
│                                              │
│  📊 View Metrics                            │
│                                              │
└─────────────────────────────────────────────┘
```

---

## Adding a VPS Server

Before creating sites, you need to add a VPS server that will host them.

### Prerequisites for VPS

Your VPS server needs:
- Debian 13 or Ubuntu 22.04+
- SSH access (root or sudo user)
- Public IP address
- At least 2GB RAM (recommended 4GB+)

### Step-by-Step: Add VPS Server

1. **Navigate to VPS Servers**
   - Click "VPS Servers" in the sidebar
   - Click "+ Add VPS Server"

2. **Fill in Server Details:**

   ```
   Name: Production Server 1
   IP Address: 192.168.1.100
   SSH Port: 22
   SSH Username: root (or your sudo user)
   ```

3. **Setup SSH Key Authentication**

   CHOM will generate an SSH key pair automatically. You need to add the public key to your VPS:

   ```bash
   # On your VPS, run:
   echo "ssh-rsa AAAAB3NzaC1yc2E... chom@deploy" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

   The public key is displayed in the CHOM UI during setup.

4. **Test Connection**
   - Click "Test Connection"
   - You should see: "Connection successful!"

5. **Click "Add Server"**

### Verify Server Status

After adding, the server should show:
```
✓ Status: Online
✓ Disk: 20GB / 80GB (25% used)
✓ Memory: 1.2GB / 4GB (30% used)
✓ Sites: 0 / 50
```

---

## Creating Your First Site

Now let's create your first WordPress site!

### Step-by-Step: Create WordPress Site

1. **Navigate to Sites**
   - Click "Sites" in the sidebar
   - Click "+ Create Site"

2. **Fill in Site Details:**

   ```
   Domain: mysite.example.com
   Site Type: WordPress
   PHP Version: 8.2
   VPS Server: Production Server 1
   ```

3. **WordPress Configuration (optional):**

   ```
   Site Title: My Awesome Site
   Admin Username: admin
   Admin Email: admin@example.com
   ```

   Leave blank to use WordPress defaults.

4. **Click "Create Site"**

   You'll see the deployment progress:
   ```
   ⏳ Creating site structure...
   ⏳ Installing WordPress...
   ⏳ Configuring Nginx...
   ⏳ Setting up PHP-FPM...
   ✓ Site created successfully!
   ```

   **Time:** 2-3 minutes

### Access Your Site

Once deployment completes:

1. **Add hosts entry** (for local testing):
   ```bash
   # Edit /etc/hosts
   sudo nano /etc/hosts

   # Add line:
   192.168.1.100  mysite.example.com
   ```

2. **Visit your site:**
   - Frontend: http://mysite.example.com
   - Admin: http://mysite.example.com/wp-admin

3. **Login credentials:**
   - Username: (as configured)
   - Password: (check email or CHOM dashboard)

### Issue SSL Certificate

To enable HTTPS:

1. **Navigate to your site** in CHOM dashboard
2. **Click "SSL" tab**
3. **Click "Issue Certificate"**
4. **Wait for Let's Encrypt** (30-60 seconds)
5. **Done!** Your site now has HTTPS

**Note:** This requires a real domain pointing to your VPS IP.

---

## Setting Up Backups

Protect your site with automated backups.

### Enable Automatic Backups

1. **Navigate to site** in CHOM dashboard
2. **Click "Backups" tab**
3. **Toggle "Automatic Backups"** to ON
4. **Configure schedule:**
   ```
   Frequency: Daily
   Time: 02:00 AM
   Retention: 7 days
   ```
5. **Click "Save"**

### Create Manual Backup

Create an immediate backup:

1. **Click "Create Backup" button**
2. **Add description:** "Initial backup"
3. **Click "Create"**
4. **Wait for completion** (1-5 minutes depending on site size)

You'll see:
```
✓ Backup completed successfully!
   Size: 125 MB
   Files: 12,453
   Database: 2.3 MB
```

### Restore from Backup

To restore a backup:

1. **Navigate to Backups** tab
2. **Find the backup** you want to restore
3. **Click "Restore"**
4. **Confirm** the restoration
5. **Wait for completion** (1-5 minutes)

**Warning:** This will overwrite current site data!

---

## Monitoring Your Site

CHOM integrates with the Mentat Observability Stack for monitoring.

### View Site Metrics

1. **Navigate to your site** in CHOM dashboard
2. **Click "Metrics" tab**

You'll see:
```
📊 Site Metrics (Last 24h)

⏱️  Response Time: 245ms avg
📈 Requests: 1,234 total
💾 Bandwidth: 2.3 GB
⚠️  Errors: 3 (0.2%)

[View in Grafana →]
```

### Setup Alerts (Optional)

To get notified of issues:

1. **Click "Alerts" tab**
2. **Click "+ Add Alert"**
3. **Configure alert:**
   ```
   Name: High Response Time
   Condition: Response time > 1000ms
   Notification: Email
   ```
4. **Click "Save"**

### View Logs

To debug issues:

1. **Navigate to site** → **Logs** tab
2. **Select log type:**
   - Application (Laravel/WordPress logs)
   - Access (Nginx access logs)
   - Error (Nginx error logs)
3. **Filter by date/severity**
4. **Search logs** with query

---

## Common Tasks

### Adding Team Members

Share access with your team:

1. **Navigate to** Settings → **Team**
2. **Click "Invite Member"**
3. **Enter email:** teammate@example.com
4. **Select role:** Admin, Member, or Viewer
5. **Click "Send Invitation"**

They'll receive an email with setup instructions.

### Changing PHP Version

To change PHP version for a site:

1. **Navigate to site** → **Settings** tab
2. **Find "PHP Version"** dropdown
3. **Select version:** 8.2, 8.4
4. **Click "Update"**
5. **Wait for reconfiguration** (30 seconds)

### Viewing Invoices

To view billing history:

1. **Navigate to** Settings → **Billing**
2. **Click "Invoices" tab**
3. **View/Download** past invoices

### Updating Subscription

To change your plan:

1. **Navigate to** Settings → **Billing**
2. **Click "Change Plan"**
3. **Select new tier:** Starter, Pro, or Enterprise
4. **Confirm change**
5. **Billing updates immediately** (prorated)

---

## Next Steps

Congratulations! You've completed the basics. Here's what to explore next:

### For Users
- 👥 **[User Guide](USER-GUIDE.md)** - Complete guide for daily operations
- 🎨 **Customize site** - Install WordPress themes and plugins
- 📊 **Setup monitoring** - Configure custom dashboards
- 🔐 **Enable 2FA** - Secure your account

### For Developers
- 💻 **[Developer Guide](DEVELOPER-GUIDE.md)** - Contribute to CHOM
- 🔧 **[API Documentation](API-README.md)** - Integrate with CHOM API
- 🧪 **Write tests** - Add test coverage
- 🎨 **Customize UI** - Modify Livewire components

### For Operators
- 🚀 **[Operator Guide](OPERATOR-GUIDE.md)** - Deploy to production
- 📊 **Setup observability** - Integrate Prometheus + Grafana
- 🔐 **Harden security** - Follow security best practices
- 📈 **Scale infrastructure** - Add more VPS servers

---

## Troubleshooting

### Common Issues

#### "500 Internal Server Error"

**Cause:** Missing environment key or permissions issue

**Solution:**
```bash
# Regenerate app key
php artisan key:generate

# Fix permissions
chmod -R 775 storage bootstrap/cache
chown -R www-data:www-data storage bootstrap/cache
```

#### "Connection refused" when adding VPS

**Causes:**
- SSH port is closed
- Wrong IP address
- Firewall blocking connection
- SSH key not authorized

**Solution:**
```bash
# Test SSH connection manually
ssh -p 22 root@192.168.1.100

# Check firewall (on VPS)
sudo ufw status
sudo ufw allow 22/tcp

# Verify SSH key is added
cat ~/.ssh/authorized_keys
```

#### "Site creation failed"

**Causes:**
- VPS server out of disk space
- PHP version not installed
- Nginx not installed

**Solution:**
1. **Check VPS logs** in CHOM dashboard
2. **View operation details** for error messages
3. **SSH into VPS** and check `/var/log/chom/`
4. **Run VPS setup script** again if needed

#### "npm install" fails

**Cause:** Node.js version too old

**Solution:**
```bash
# Install Node.js 18+ (Ubuntu/Debian)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify version
node --version  # Should be v18.x or higher

# Try again
npm install
```

#### "composer install" fails

**Cause:** Missing PHP extensions

**Solution:**
```bash
# Install required extensions (Ubuntu/Debian)
sudo apt-get install -y php8.2-cli php8.2-mbstring php8.2-xml \
  php8.2-mysql php8.2-curl php8.2-zip php8.2-gd

# Try again
composer install
```

### Prerequisites Check

Run this script to verify all prerequisites:

```bash
#!/bin/bash

echo "CHOM Prerequisites Check"
echo "========================"

# Check PHP
if command -v php &> /dev/null; then
    PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1,2)
    echo "✓ PHP $PHP_VERSION installed"

    if (( $(echo "$PHP_VERSION >= 8.2" | bc -l) )); then
        echo "  ✓ Version requirement met (>= 8.2)"
    else
        echo "  ✗ Version too old (need >= 8.2)"
    fi
else
    echo "✗ PHP not found"
fi

# Check Composer
if command -v composer &> /dev/null; then
    COMPOSER_VERSION=$(composer --version | cut -d " " -f 3 | cut -d "." -f 1)
    echo "✓ Composer $COMPOSER_VERSION installed"
else
    echo "✗ Composer not found"
fi

# Check Node.js
if command -v node &> /dev/null; then
    NODE_VERSION=$(node -v | cut -d "v" -f 2 | cut -d "." -f 1)
    echo "✓ Node.js v$NODE_VERSION installed"

    if [ "$NODE_VERSION" -ge 18 ]; then
        echo "  ✓ Version requirement met (>= 18)"
    else
        echo "  ✗ Version too old (need >= 18)"
    fi
else
    echo "✗ Node.js not found"
fi

# Check npm
if command -v npm &> /dev/null; then
    echo "✓ npm installed"
else
    echo "✗ npm not found"
fi

# Check Git
if command -v git &> /dev/null; then
    echo "✓ Git installed"
else
    echo "✗ Git not found"
fi

echo ""
echo "Check PHP extensions:"
for ext in mbstring xml mysql curl zip gd; do
    if php -m | grep -q "^$ext$"; then
        echo "  ✓ $ext"
    else
        echo "  ✗ $ext (missing)"
    fi
done
```

Save as `check-prerequisites.sh` and run:
```bash
chmod +x check-prerequisites.sh
./check-prerequisites.sh
```

### Getting Help

If you're still stuck:

1. 📖 **Check documentation** - [docs/](.)
2. 🔍 **Search existing issues** - [GitHub Issues](https://github.com/calounx/mentat/issues)
3. 💬 **Ask in discussions** - [GitHub Discussions](https://github.com/calounx/mentat/discussions)
4. 📧 **Email support** - support@chom.io

When asking for help, include:
- CHOM version (`php artisan --version`)
- PHP version (`php -v`)
- Error messages (from logs or screen)
- Steps to reproduce

---

## Summary

You've learned:

- ✅ How to install CHOM
- ✅ How to configure the environment
- ✅ How to add VPS servers
- ✅ How to create sites
- ✅ How to setup backups
- ✅ How to monitor sites
- ✅ Common troubleshooting steps

**Ready for more?** Check out:
- 👥 [User Guide](USER-GUIDE.md) - Complete feature guide
- 💻 [Developer Guide](DEVELOPER-GUIDE.md) - Development workflows
- 🚀 [Operator Guide](OPERATOR-GUIDE.md) - Production deployment

**Happy hosting!** 🚀
