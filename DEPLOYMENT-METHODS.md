# Alternative Deployment Methods for Mentat v2.2.20

This guide provides multiple deployment strategies for deploying Mentat to production.

---

## Table of Contents

1. [Method 1: Local SSH Deployment Script (Recommended)](#method-1-local-ssh-deployment-script)
2. [Method 2: GitHub Actions CI/CD](#method-2-github-actions-cicd)
3. [Method 3: Direct SSH Manual Deployment](#method-3-direct-ssh-manual-deployment)
4. [Method 4: Git Pull + Artisan Deploy](#method-4-git-pull--artisan-deploy)
5. [Method 5: Deployment via Jump Server](#method-5-deployment-via-jump-server)
6. [Method 6: Docker-based Deployment](#method-6-docker-based-deployment)

---

## Method 1: Local SSH Deployment Script

**✅ Recommended** - Automated deployment from your local machine via SSH.

### Prerequisites:
- SSH access to mentat.arewel.com
- SSH key configured and authorized

### Usage:

```bash
# Basic deployment
./deploy-from-local.sh

# With custom options
./deploy-from-local.sh \
  --host=mentat.arewel.com \
  --user=stilgar \
  --key=~/.ssh/calounx_arewel \
  --repo-path=/var/www/mentat

# Dry run (show what would be executed)
./deploy-from-local.sh --dry-run

# Skip backup (faster, use for non-critical deployments)
./deploy-from-local.sh --skip-backup
```

### What it does:
1. Tests SSH connection
2. Creates backup (optional)
3. Pulls latest code from GitHub
4. Installs dependencies
5. Runs migrations
6. Clears and rebuilds caches
7. Restarts services
8. Verifies deployment

### Troubleshooting:

**SSH Connection Failed:**
```bash
# Test SSH manually
ssh -i ~/.ssh/calounx_arewel stilgar@mentat.arewel.com "hostname"

# Check SSH key permissions
chmod 600 ~/.ssh/calounx_arewel

# Add SSH key to ssh-agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/calounx_arewel
```

---

## Method 2: GitHub Actions CI/CD

**✅ Best for Teams** - Automated deployment on git push.

### Setup GitHub Actions Deployment:

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to Production

on:
  push:
    branches:
      - main
  workflow_dispatch:

jobs:
  deploy:
    name: Deploy to mentat.arewel.com
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup SSH
        env:
          SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
          SSH_KNOWN_HOSTS: ${{ secrets.SSH_KNOWN_HOSTS }}
        run: |
          mkdir -p ~/.ssh
          echo "$SSH_PRIVATE_KEY" > ~/.ssh/deploy_key
          chmod 600 ~/.ssh/deploy_key
          echo "$SSH_KNOWN_HOSTS" > ~/.ssh/known_hosts

      - name: Deploy to Production
        run: |
          ssh -i ~/.ssh/deploy_key stilgar@mentat.arewel.com << 'ENDSSH'
            cd /var/www/mentat
            git pull origin main
            composer install --no-dev --optimize-autoloader
            php artisan migrate --force
            php artisan config:cache
            php artisan route:cache
            php artisan view:cache
            sudo systemctl restart php8.2-fpm
            sudo systemctl restart nginx
          ENDSSH

      - name: Verify Deployment
        run: |
          ssh -i ~/.ssh/deploy_key stilgar@mentat.arewel.com \
            "cd /var/www/mentat && php artisan --version"
```

### Setup GitHub Secrets:

```bash
# 1. Add SSH private key to GitHub Secrets
# Settings > Secrets and variables > Actions > New repository secret
# Name: SSH_PRIVATE_KEY
# Value: Contents of ~/.ssh/calounx_arewel

# 2. Add known hosts
ssh-keyscan mentat.arewel.com > known_hosts
# Add as SSH_KNOWN_HOSTS secret
```

### Trigger Deployment:

```bash
# Automatic: Push to main branch
git push origin main

# Manual: Via GitHub Actions UI
# Go to Actions > Deploy to Production > Run workflow
```

---

## Method 3: Direct SSH Manual Deployment

**✅ Simplest** - Direct commands via SSH.

### One-Liner Deployment:

```bash
ssh stilgar@mentat.arewel.com "cd /var/www/mentat && \
  git pull origin main && \
  composer install --no-dev --optimize-autoloader && \
  php artisan migrate --force && \
  php artisan config:cache && \
  php artisan route:cache && \
  php artisan view:cache && \
  sudo systemctl restart php8.2-fpm && \
  sudo systemctl restart nginx && \
  php artisan --version"
```

### Step-by-Step Deployment:

```bash
# 1. SSH into server
ssh stilgar@mentat.arewel.com

# 2. Navigate to repository
cd /var/www/mentat

# 3. Pull latest code
git pull origin main

# 4. Install dependencies
composer install --no-dev --optimize-autoloader

# 5. Run migrations
php artisan migrate --force

# 6. Clear caches
php artisan config:clear
php artisan cache:clear
php artisan view:clear
php artisan route:clear

# 7. Optimize
php artisan config:cache
php artisan route:cache
php artisan view:cache

# 8. Restart services
sudo systemctl restart php8.2-fpm
sudo systemctl restart nginx

# 9. Verify
php artisan --version
php artisan migrate:status
```

---

## Method 4: Git Pull + Artisan Deploy

**✅ Zero-Downtime** - Uses automated deployment script on server.

### Create Deployment Command:

```bash
# On server, create: app/Console/Commands/DeployCommand.php
php artisan make:command DeployCommand
```

```php
<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Artisan;

class DeployCommand extends Command
{
    protected $signature = 'app:deploy';
    protected $description = 'Deploy application updates';

    public function handle()
    {
        $this->info('Starting deployment...');

        // Clear caches
        $this->info('Clearing caches...');
        Artisan::call('config:clear');
        Artisan::call('cache:clear');
        Artisan::call('view:clear');
        Artisan::call('route:clear');

        // Run migrations
        $this->info('Running migrations...');
        Artisan::call('migrate', ['--force' => true]);

        // Optimize
        $this->info('Optimizing...');
        Artisan::call('config:cache');
        Artisan::call('route:cache');
        Artisan::call('view:cache');

        $this->info('✅ Deployment completed!');
    }
}
```

### Deploy:

```bash
ssh stilgar@mentat.arewel.com "cd /var/www/mentat && \
  git pull origin main && \
  composer install --no-dev --optimize-autoloader && \
  php artisan app:deploy && \
  sudo systemctl restart php8.2-fpm nginx"
```

---

## Method 5: Deployment via Jump Server

**✅ High Security** - Deploy through bastion/jump host.

### Setup SSH Config:

Create `~/.ssh/config`:

```
# Bastion/Jump Server
Host bastion
    HostName bastion.arewel.com
    User jumpuser
    IdentityFile ~/.ssh/jump_key

# Production Server via Bastion
Host mentat
    HostName mentat.arewel.com
    User stilgar
    IdentityFile ~/.ssh/calounx_arewel
    ProxyJump bastion
```

### Deploy:

```bash
# Direct command through jump server
ssh mentat "cd /var/www/mentat && git pull origin main && ..."

# Or use the deployment script
./deploy-from-local.sh --host=mentat
```

---

## Method 6: Docker-based Deployment

**✅ Containerized** - If using Docker for deployment.

### Build and Deploy:

```bash
# 1. Build new image locally
docker build -t mentat:2.2.20 .

# 2. Tag for registry
docker tag mentat:2.2.20 registry.arewel.com/mentat:2.2.20

# 3. Push to registry
docker push registry.arewel.com/mentat:2.2.20

# 4. Deploy on server
ssh stilgar@mentat.arewel.com << 'EOF'
  cd /var/www/mentat
  docker pull registry.arewel.com/mentat:2.2.20
  docker-compose down
  docker-compose up -d
  docker exec mentat php artisan migrate --force
EOF
```

---

## Comparison Matrix

| Method | Complexity | Automation | Zero-Downtime | Best For |
|--------|-----------|------------|---------------|----------|
| Local SSH Script | ⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | Quick deployments |
| GitHub Actions | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | Team collaboration |
| Direct SSH | ⭐ | ⭐ | ⭐⭐ | Emergency fixes |
| Artisan Deploy | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | Structured deploys |
| Jump Server | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | High security envs |
| Docker | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Containerized apps |

---

## Pre-Deployment Checklist

Before using any method:

- [ ] Backup database
- [ ] Verify SSH access
- [ ] Check disk space on server
- [ ] Review pending migrations
- [ ] Test migrations locally
- [ ] Notify team of deployment
- [ ] Have rollback plan ready

---

## Post-Deployment Verification

After deployment with any method:

```bash
# 1. Check version
ssh stilgar@mentat.arewel.com "cd /var/www/mentat && php artisan --version"

# 2. Verify migrations
ssh stilgar@mentat.arewel.com "cd /var/www/mentat && php artisan migrate:status"

# 3. Test health endpoint
curl https://mentat.arewel.com/api/health

# 4. Check logs
ssh stilgar@mentat.arewel.com "tail -50 /var/www/mentat/storage/logs/laravel.log"

# 5. Monitor for errors
ssh stilgar@mentat.arewel.com "tail -f /var/www/mentat/storage/logs/laravel.log"
```

---

## Rollback Procedures

### Quick Rollback:

```bash
ssh stilgar@mentat.arewel.com << 'EOF'
  cd /var/www/mentat
  git log --oneline -5
  git checkout <previous-commit-hash>
  php artisan migrate:rollback --step=6
  composer install --no-dev --optimize-autoloader
  php artisan config:cache
  sudo systemctl restart php8.2-fpm nginx
EOF
```

### Using Deployment Script:

```bash
# The automated deployment script creates backups
ssh stilgar@mentat.arewel.com "cd /var/www/mentat && ls -la backups/"
# Restore from backup if needed
```

---

## Troubleshooting Common Issues

### Issue 1: SSH Permission Denied

```bash
# Fix SSH key permissions
chmod 600 ~/.ssh/calounx_arewel

# Add to SSH agent
ssh-add ~/.ssh/calounx_arewel

# Test connection
ssh -v stilgar@mentat.arewel.com
```

### Issue 2: Migration Failed

```bash
# Check migration status
php artisan migrate:status

# Rollback last batch
php artisan migrate:rollback

# Re-run migrations
php artisan migrate --force
```

### Issue 3: Composer Dependencies

```bash
# Clear composer cache
composer clear-cache

# Reinstall dependencies
rm -rf vendor
composer install --no-dev --optimize-autoloader
```

### Issue 4: Permission Errors

```bash
# Fix storage permissions
sudo chown -R www-data:www-data storage bootstrap/cache
sudo chmod -R 775 storage bootstrap/cache
```

---

## Emergency Deployment

For critical hotfixes:

```bash
# 1. Create hotfix branch
git checkout -b hotfix/critical-fix

# 2. Make fix and commit
git add .
git commit -m "fix: Critical security patch"

# 3. Push to GitHub
git push origin hotfix/critical-fix

# 4. Deploy directly to production
./deploy-from-local.sh --skip-backup

# 5. Merge to main after verification
git checkout main
git merge hotfix/critical-fix
git push origin main
```

---

## Monitoring Post-Deployment

```bash
# Real-time error monitoring
ssh stilgar@mentat.arewel.com "tail -f /var/www/mentat/storage/logs/laravel.log | grep ERROR"

# Performance monitoring
ssh stilgar@mentat.arewel.com "top -bn1 | grep php"

# Disk space
ssh stilgar@mentat.arewel.com "df -h"

# Service status
ssh stilgar@mentat.arewel.com "systemctl status php8.2-fpm nginx"
```

---

## Support & Resources

- **Deployment Logs**: `/var/log/chom-deploy/`
- **Application Logs**: `/var/www/mentat/storage/logs/`
- **Deployment Guide**: `DEPLOY-V2.2.20.md`
- **GitHub Repository**: https://github.com/calounx/mentat

---

**Choose the method that best fits your workflow and security requirements!**
