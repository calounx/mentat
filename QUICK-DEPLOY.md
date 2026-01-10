# Quick Deployment Reference - Mentat v2.2.20

## 🚀 Ready to Deploy!

Version 2.2.20 is ready for production deployment. All code has been committed and pushed to GitHub.

---

## Option 1: Local Deployment Script ⭐ RECOMMENDED

**From your current machine:**

```bash
# Simple deployment
./deploy-from-local.sh

# See what it will do first (dry run)
./deploy-from-local.sh --dry-run

# With custom SSH key
./deploy-from-local.sh --key=~/.ssh/calounx_arewel

# Skip backup (faster)
./deploy-from-local.sh --skip-backup
```

**If SSH connection fails, try:**

```bash
# Test SSH manually
ssh stilgar@mentat.arewel.com "hostname"

# Or try with specific key
ssh -i ~/.ssh/calounx_arewel stilgar@mentat.arewel.com "hostname"
```

---

## Option 2: One-Line SSH Deployment

**Copy and paste this command:**

```bash
ssh stilgar@mentat.arewel.com "cd /var/www/mentat && git pull origin main && composer install --no-dev --optimize-autoloader && php artisan migrate --force && php artisan config:cache && php artisan route:cache && php artisan view:cache && sudo systemctl restart php8.2-fpm nginx && echo '✅ Deployment Complete!' && php artisan --version"
```

---

## Option 3: Step-by-Step Manual Deployment

**SSH into server and run:**

```bash
# 1. Connect
ssh stilgar@mentat.arewel.com

# 2. Go to app directory
cd /var/www/mentat

# 3. Pull latest
git pull origin main

# 4. Install dependencies
composer install --no-dev --optimize-autoloader

# 5. Migrate database
php artisan migrate --force

# 6. Clear and rebuild caches
php artisan config:clear && php artisan cache:clear
php artisan config:cache && php artisan route:cache && php artisan view:cache

# 7. Restart services
sudo systemctl restart php8.2-fpm nginx

# 8. Verify
php artisan --version
```

---

## Option 4: Use Server's Built-in Deployment Script

**If the server has the deployment script:**

```bash
ssh stilgar@mentat.arewel.com
cd /var/www/mentat
sudo ./deploy/deploy-chom.sh --environment=production --branch=main --skip-observability
```

---

## ✅ Verify Deployment

**After deployment, check:**

```bash
# Check version
ssh stilgar@mentat.arewel.com "cd /var/www/mentat && php artisan --version"

# Check migrations ran
ssh stilgar@mentat.arewel.com "cd /var/www/mentat && php artisan migrate:status | head -20"

# Test health endpoint
curl https://mentat.arewel.com/api/health

# Check logs for errors
ssh stilgar@mentat.arewel.com "tail -20 /var/www/mentat/storage/logs/laravel.log"
```

---

## 🆘 If Something Goes Wrong

**Rollback to previous version:**

```bash
ssh stilgar@mentat.arewel.com "cd /var/www/mentat && git log --oneline -5"
# Note the previous commit hash, then:
ssh stilgar@mentat.arewel.com "cd /var/www/mentat && git checkout <previous-hash> && php artisan migrate:rollback --step=6 && composer install --no-dev && php artisan config:cache && sudo systemctl restart php8.2-fpm nginx"
```

---

## 📚 More Information

- **Full Deployment Guide**: `DEPLOY-V2.2.20.md`
- **Alternative Methods**: `DEPLOYMENT-METHODS.md`
- **Latest Commits**:
  ```
  2f963fb - feat(deploy): Add local deployment script and alternative methods
  2c4e95b - docs: Add comprehensive deployment guide for v2.2.20
  e3526a6 - fix(tests): Major test infrastructure fixes
  6b84444 - chore(tests): Add doctrine/dbal and improve test configuration
  4ac09cc - fix(database): Fix SQLite compatibility for migrations
  032370d - chore: Bump version to 2.2.20
  ```

---

## 🎯 What Gets Deployed

- ✅ Version 2.2.20
- ✅ 9 new database migrations
- ✅ VPS server SSH columns (ssh_user, ssh_port)
- ✅ User model changes (username, first_name, last_name)
- ✅ doctrine/dbal in production
- ✅ Complete observability configuration
- ✅ All test fixes and improvements

---

**Pick the method that works for you and deploy!** 🚀
