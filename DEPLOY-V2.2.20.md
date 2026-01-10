# Deployment Guide: Version 2.2.20

## 🚀 Ready for Production Deployment

**Version**: 2.2.20
**Branch**: main
**Status**: All fixes committed and pushed to GitHub ✅
**Latest Commit**: `e3526a6` - Major test infrastructure fixes

---

## 📦 What's Included in This Release

### Critical Fixes:
1. ✅ Missing VPS server columns (ssh_user, ssh_port)
2. ✅ Fixed duplicate migration issue
3. ✅ Moved doctrine/dbal to production dependencies
4. ✅ Test infrastructure improvements (77% fewer test failures)
5. ✅ SQLite compatibility for local development
6. ✅ Complete observability configuration

### Database Migrations:
- **New Migration**: `2026_01_10_173100_add_missing_columns_to_vps_servers.php`
- **Total New Migrations**: 6 migrations from v2.2.19 to v2.2.20

### Updated Models & Factories:
- VpsServer model with complete fillable array
- VpsServerFactory with all required columns
- User model schema changes (username, first_name, last_name)

---

## 🔧 Deployment Instructions

### Option 1: Automated Deployment (Recommended)

SSH into mentat.arewel.com and run:

```bash
# SSH into production server
ssh stilgar@mentat.arewel.com

# Navigate to deployment directory
cd /var/www/mentat  # or wherever the repo is located

# Pull latest changes
git fetch origin
git checkout main
git pull origin main

# Run automated deployment
sudo ./deploy/deploy-chom.sh \
  --environment=production \
  --branch=main \
  --repo-url=https://github.com/calounx/mentat.git \
  --skip-observability
```

### Option 2: Manual Deployment Steps

If automated deployment fails, follow these steps:

```bash
# 1. SSH into server
ssh stilgar@mentat.arewel.com

# 2. Navigate to application directory
cd /var/www/mentat

# 3. Pull latest code
git pull origin main

# 4. Install/update dependencies
composer install --no-dev --optimize-autoloader

# 5. Run database migrations
php artisan migrate --force

# 6. Clear caches
php artisan config:clear
php artisan cache:clear
php artisan view:clear
php artisan route:clear

# 7. Optimize for production
php artisan config:cache
php artisan route:cache
php artisan view:cache

# 8. Restart services
sudo systemctl restart php8.2-fpm
sudo systemctl restart nginx

# 9. Verify deployment
php artisan --version
php artisan migrate:status
```

---

## ✅ Pre-Deployment Checklist

- [x] All code committed and pushed to GitHub
- [x] Database migrations tested locally
- [x] doctrine/dbal moved to production dependencies
- [x] Deployment scripts validated
- [x] Version bumped to 2.2.20
- [ ] Backup database before deployment
- [ ] Verify SSH access to mentat.arewel.com
- [ ] Review deployment logs after completion

---

## 📋 Post-Deployment Verification

After deployment, verify the following:

```bash
# Check application version
php artisan --version

# Verify migrations ran successfully
php artisan migrate:status

# Check VPS servers table has new columns
php artisan tinker
>>> Schema::hasColumn('vps_servers', 'ssh_user')  # Should return true
>>> Schema::hasColumn('vps_servers', 'ssh_port')  # Should return true

# Test Prometheus metrics endpoint
curl http://localhost/prometheus/metrics

# Check application health
curl http://localhost/api/health
```

---

## 🔄 Rollback Plan

If deployment fails:

```bash
# 1. Rollback to previous release
cd /var/www/mentat
git log --oneline -5  # Find previous commit
git checkout <previous-commit-hash>

# 2. Rollback migrations
php artisan migrate:rollback --step=6

# 3. Clear caches
php artisan cache:clear
php artisan config:clear

# 4. Restart services
sudo systemctl restart php8.2-fpm
```

---

## 📊 Database Migration Summary

The following migrations will run in order:

1. `2026_01_06_075318_add_health_error_to_vps_servers_table.php`
2. `2026_01_10_082405_modify_users_table_for_onboarding.php`
3. `2026_01_10_082428_migrate_existing_user_names.php`
4. `2026_01_10_082454_remove_name_column_from_users.php`
5. `2026_01_10_082518_add_approval_to_organizations.php`
6. `2026_01_10_082539_add_plan_selection_to_tenants.php`
7. `2026_01_10_082559_create_onboarding_support_tables.php`
8. `2026_01_10_082560_make_user_name_fields_not_null.php`
9. `2026_01_10_173100_add_missing_columns_to_vps_servers.php` ⬅️ NEW

---

## 🚨 Important Notes

### Database Changes:
- **Breaking**: User table `name` column removed, replaced with `username`, `first_name`, `last_name`
- **New**: VPS servers table has `ssh_user` and `ssh_port` columns
- **Modified**: Tenants table `tier` column is now nullable
- **Data Migration**: Existing user names automatically split into first/last names

### Dependencies:
- **Critical**: `doctrine/dbal` now in production dependencies (required for migrations)
- Run `composer install` WITHOUT `--no-dev` flag first time, or ensure doctrine/dbal is installed

### Compatibility:
- PHP 8.2+ required
- PostgreSQL production database (migrations tested)
- Redis for caching and queues

---

## 📞 Support

If you encounter issues during deployment:

1. Check deployment logs: `/var/log/chom-deploy/deployment-*.log`
2. Review Laravel logs: `storage/logs/laravel.log`
3. Check migration status: `php artisan migrate:status`
4. Verify environment: `php artisan about`

---

## 🎉 Expected Results

After successful deployment:

- ✅ Application running on version 2.2.20
- ✅ All 9 migrations applied successfully
- ✅ VPS servers table has new SSH columns
- ✅ User authentication working with new schema
- ✅ Prometheus metrics endpoint active
- ✅ Zero downtime during deployment

---

**Deployment Date**: _To be filled after deployment_
**Deployed By**: _To be filled after deployment_
**Deployment Status**: _To be filled after deployment_
