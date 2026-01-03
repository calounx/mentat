# CHOM Deployment Runbook

Step-by-step guide for deploying and managing the CHOM application.

## Pre-Deployment Checklist

- [ ] SSH access to both mentat and landsraad servers
- [ ] SSH keys configured for stilgar user
- [ ] Repository URL and access token (if private repo)
- [ ] Database credentials configured in /var/www/chom/shared/.env
- [ ] SSL certificates installed and valid
- [ ] Firewall rules configured
- [ ] Monitoring stack running on mentat
- [ ] All services running on landsraad
- [ ] Recent backup exists (or will be created automatically)

## Standard Deployment Procedure

### 1. Connect to Deployment Server

```bash
ssh stilgar@mentat.arewel.com
cd /path/to/deployment
```

### 2. Set Environment Variables

```bash
export REPO_URL="https://github.com/your-org/chom.git"
export GITHUB_TOKEN="your_github_token"  # For private repos
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."  # Optional
```

### 3. Run Pre-Deployment Checks

```bash
# Verify SSH connectivity
ssh stilgar@landsraad.arewel.com "hostname && date"

# Check current application status
ssh stilgar@landsraad.arewel.com "cd /var/www/chom/current && php artisan --version"

# Check disk space
ssh stilgar@landsraad.arewel.com "df -h /"

# Verify services are running
ssh stilgar@landsraad.arewel.com "sudo systemctl status nginx php8.2-fpm postgresql redis-server | grep Active"
```

### 4. Execute Deployment

```bash
./deploy-chom.sh --environment=production --branch=main
```

Expected duration: 3-5 minutes

### 5. Monitor Deployment Progress

Watch for:
- Pre-deployment backup completion
- Repository clone success
- Composer install completion
- Asset build completion
- Migration execution (if any)
- Health checks passing
- Service reload confirmation

### 6. Post-Deployment Verification

```bash
# Test application endpoint
curl -I https://chom.arewel.com

# Check application version
ssh stilgar@landsraad.arewel.com "cd /var/www/chom/current && git log -1 --oneline"

# Verify queue workers
ssh stilgar@landsraad.arewel.com "sudo supervisorctl status chom-worker:*"

# Check for errors in logs
ssh stilgar@landsraad.arewel.com "tail -50 /var/www/chom/shared/storage/logs/laravel.log"
```

### 7. Monitor Application

```bash
# Open Grafana
open http://mentat.arewel.com:3000

# Check Prometheus targets
open http://mentat.arewel.com:9090/targets

# Monitor application metrics
open http://mentat.arewel.com:9090/graph
```

## Emergency Rollback Procedure

### When to Rollback

- Health checks fail after deployment
- Critical errors in application logs
- Database migration failures
- Significant performance degradation
- User-reported critical bugs

### Rollback Steps

```bash
# 1. SSH to deployment server
ssh stilgar@mentat.arewel.com

# 2. Execute rollback to previous release
ssh stilgar@landsraad.arewel.com "/var/www/chom/deploy/scripts/rollback.sh"

# 3. If database was migrated, restore database
ssh stilgar@landsraad.arewel.com "/var/www/chom/deploy/scripts/rollback.sh --restore-database"

# 4. Verify rollback success
ssh stilgar@landsraad.arewel.com "/var/www/chom/deploy/scripts/health-check.sh"

# 5. Test application
curl -I https://chom.arewel.com
```

Expected duration: 1-2 minutes

### Post-Rollback Actions

1. Notify team of rollback
2. Document the issue
3. Review logs to identify root cause
4. Create ticket for issue resolution
5. Test fix in staging before next deployment

## Common Operations

### View Current Release

```bash
ssh stilgar@landsraad.arewel.com "readlink -f /var/www/chom/current"
```

### List Available Releases

```bash
ssh stilgar@landsraad.arewel.com "ls -lt /var/www/chom/releases/"
```

### View Deployment History

```bash
ssh stilgar@landsraad.arewel.com "ls -lt /var/www/chom/backups/*.manifest | head -10"
```

### Manual Backup

```bash
ssh stilgar@landsraad.arewel.com "/var/www/chom/deploy/scripts/backup-before-deploy.sh"
```

### Restart Services

```bash
# Restart PHP-FPM
ssh stilgar@landsraad.arewel.com "sudo systemctl restart php8.2-fpm"

# Restart queue workers
ssh stilgar@landsraad.arewel.com "sudo supervisorctl restart chom-worker:*"

# Restart Nginx
ssh stilgar@landsraad.arewel.com "sudo systemctl restart nginx"
```

### Clear Application Cache

```bash
ssh stilgar@landsraad.arewel.com "cd /var/www/chom/current && php artisan cache:clear && php artisan config:clear && php artisan view:clear"
```

### Run Artisan Commands

```bash
ssh stilgar@landsraad.arewel.com "cd /var/www/chom/current && php artisan <command>"
```

### Check Queue Status

```bash
ssh stilgar@landsraad.arewel.com "cd /var/www/chom/current && php artisan queue:monitor"
```

### Database Operations

```bash
# Run migrations
ssh stilgar@landsraad.arewel.com "cd /var/www/chom/current && php artisan migrate --force"

# Check migration status
ssh stilgar@landsraad.arewel.com "cd /var/www/chom/current && php artisan migrate:status"

# Rollback last migration
ssh stilgar@landsraad.arewel.com "cd /var/www/chom/current && php artisan migrate:rollback --step=1 --force"

# Access database
ssh stilgar@landsraad.arewel.com "cd /var/www/chom/current && php artisan tinker"
```

## Troubleshooting Scenarios

### Scenario 1: Deployment Hangs During Composer Install

**Symptoms:**
- Deployment stuck at "Installing Composer dependencies"
- No progress for > 5 minutes

**Resolution:**
```bash
# 1. Cancel deployment (Ctrl+C)

# 2. SSH to landsraad and check Composer cache
ssh stilgar@landsraad.arewel.com "composer clear-cache"

# 3. Retry deployment with verbose output
./deploy-chom.sh --environment=production --branch=main
```

### Scenario 2: Health Checks Fail After Deployment

**Symptoms:**
- Health check script reports failures
- Application not responding

**Resolution:**
```bash
# 1. Check which health check failed
ssh stilgar@landsraad.arewel.com "/var/www/chom/deploy/scripts/health-check.sh"

# 2. Check service status
ssh stilgar@landsraad.arewel.com "sudo systemctl status nginx php8.2-fpm postgresql redis-server"

# 3. Check application logs
ssh stilgar@landsraad.arewel.com "tail -100 /var/www/chom/shared/storage/logs/laravel.log"

# 4. If issue persists, rollback
ssh stilgar@landsraad.arewel.com "/var/www/chom/deploy/scripts/rollback.sh"
```

### Scenario 3: Database Migration Fails

**Symptoms:**
- Migration errors during deployment
- Database in inconsistent state

**Resolution:**
```bash
# 1. Automatic rollback should trigger

# 2. If not, manually rollback
ssh stilgar@landsraad.arewel.com "/var/www/chom/deploy/scripts/rollback.sh --restore-database"

# 3. Check migration status
ssh stilgar@landsraad.arewel.com "cd /var/www/chom/current && php artisan migrate:status"

# 4. Review and fix migration files

# 5. Redeploy with fix
```

### Scenario 4: Queue Workers Not Processing Jobs

**Symptoms:**
- Jobs piling up in queue
- No worker activity in logs

**Resolution:**
```bash
# 1. Check worker status
ssh stilgar@landsraad.arewel.com "sudo supervisorctl status chom-worker:*"

# 2. Check worker logs
ssh stilgar@landsraad.arewel.com "tail -100 /var/www/chom/shared/storage/logs/worker.log"

# 3. Restart workers
ssh stilgar@landsraad.arewel.com "sudo supervisorctl restart chom-worker:*"

# 4. Monitor queue
ssh stilgar@landsraad.arewel.com "cd /var/www/chom/current && php artisan queue:monitor redis:default"
```

### Scenario 5: High Memory Usage

**Symptoms:**
- Server slow to respond
- OOM errors in logs

**Resolution:**
```bash
# 1. Check memory usage
ssh stilgar@landsraad.arewel.com "free -h"

# 2. Check top processes
ssh stilgar@landsraad.arewel.com "top -bn1 | head -20"

# 3. Restart PHP-FPM to free memory
ssh stilgar@landsraad.arewel.com "sudo systemctl restart php8.2-fpm"

# 4. Clear application cache
ssh stilgar@landsraad.arewel.com "cd /var/www/chom/current && php artisan cache:clear"

# 5. Monitor in Grafana
```

### Scenario 6: SSL Certificate Expired

**Symptoms:**
- Browser shows certificate error
- HTTPS not working

**Resolution:**
```bash
# 1. Check certificate status
ssh stilgar@landsraad.arewel.com "sudo certbot certificates"

# 2. Renew certificate
ssh stilgar@landsraad.arewel.com "sudo certbot renew"

# 3. Reload Nginx
ssh stilgar@landsraad.arewel.com "sudo systemctl reload nginx"

# 4. Verify
curl -I https://chom.arewel.com
```

## Maintenance Windows

### Weekly Maintenance (Sundays 02:00 UTC)

```bash
# 1. Update system packages
ssh stilgar@landsraad.arewel.com "sudo apt-get update && sudo apt-get upgrade -y"

# 2. Restart services
ssh stilgar@landsraad.arewel.com "sudo systemctl restart nginx php8.2-fpm"

# 3. Cleanup old logs
ssh stilgar@landsraad.arewel.com "sudo find /var/log -name '*.log.*' -mtime +30 -delete"

# 4. Check disk space
ssh stilgar@landsraad.arewel.com "df -h"
```

### Monthly Maintenance (First Sunday 02:00 UTC)

```bash
# All weekly tasks plus:

# 1. Database optimization
ssh stilgar@landsraad.arewel.com "cd /var/www/chom/current && php artisan db:optimize"

# 2. Cleanup old releases (keep last 5)
ssh stilgar@landsraad.arewel.com "cd /var/www/chom/releases && ls -t | tail -n +6 | xargs rm -rf"

# 3. Cleanup old backups (keep last 10)
ssh stilgar@landsraad.arewel.com "cd /var/www/chom/backups && ls -t database_*.sql.gz | tail -n +11 | xargs rm -f"

# 4. Review monitoring alerts
```

## Contact Information

### Escalation Path

1. **Level 1:** DevOps Team - ops@example.com
2. **Level 2:** Senior DevOps Engineer - senior-ops@example.com
3. **Level 3:** CTO - cto@example.com

### On-Call Schedule

- Check PagerDuty for current on-call engineer
- Slack: #ops-oncall channel

## Appendix

### Service Port Reference

**Landsraad:**
- HTTP: 80
- HTTPS: 443
- PostgreSQL: 5432 (localhost only)
- Redis: 6379 (localhost only)
- Node Exporter: 9100
- Laravel Metrics: 9200

**Mentat:**
- Prometheus: 9090
- Grafana: 3000
- AlertManager: 9093
- Loki: 3100
- Node Exporter: 9100

### Important File Locations

**Application:**
- Current release: `/var/www/chom/current`
- Releases: `/var/www/chom/releases/`
- Shared: `/var/www/chom/shared/`
- Backups: `/var/www/chom/backups/`

**Logs:**
- Deployment: `/var/log/chom-deploy/`
- Application: `/var/www/chom/shared/storage/logs/`
- Nginx: `/var/log/nginx/`
- PHP-FPM: `/var/log/php8.2-fpm-chom.log`

**Configuration:**
- Nginx: `/etc/nginx/sites-available/chom`
- PHP-FPM: `/etc/php/8.2/fpm/pool.d/chom.conf`
- Supervisor: `/etc/supervisor/conf.d/chom-worker.conf`
- Environment: `/var/www/chom/shared/.env`
