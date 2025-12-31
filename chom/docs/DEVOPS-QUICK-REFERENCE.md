# DevOps Quick Reference

Quick commands and workflows for common operational tasks.

## 🚀 Deployment

```bash
# Production deployment
./scripts/deploy-production.sh

# Staging deployment
./scripts/deploy-staging.sh

# Rollback to previous version
./scripts/rollback.sh

# Rollback to specific commit
./scripts/rollback.sh --commit abc123
```

## 🏥 Health Checks

```bash
# Post-deployment health check
./scripts/health-check.sh

# Health endpoints
curl https://app.example.com/health
curl https://app.example.com/health/ready
curl https://app.example.com/health/detailed
```

## 📊 Monitoring

```bash
# View performance dashboard
open https://app.example.com/admin/performance

# Check metrics
php artisan tinker
>>> app(MetricsCollector::class)->getAll()
```

## 🔔 Alerts

```bash
# Test alert
php artisan tinker
>>> app(AlertManager::class)->info('test', 'Test alert')

# Check alert history
tail -f storage/logs/audit.log | grep Alert
```

## 📝 Logs

```bash
# View logs by channel
tail -f storage/logs/laravel.log         # Application
tail -f storage/logs/performance.log     # Performance
tail -f storage/logs/security.log        # Security
tail -f storage/logs/audit.log          # Audit
tail -f storage/logs/slow-queries.log   # Slow queries
tail -f storage/logs/deployment.log     # Deployments

# Follow all logs
tail -f storage/logs/*.log
```

## 💾 Backups

```bash
# Create backup
php artisan backup:database --encrypt --upload

# Test backup
php artisan backup:database --encrypt --test

# Clean old backups
php artisan backup:clean --dry-run
php artisan backup:clean --force

# List backups
ls -lh storage/app/backups/
```

## 🔒 Security

```bash
# Security scan
php artisan security:scan

# Security scan with auto-fix
php artisan security:scan --fix

# Dependency audit
./scripts/composer-audit.sh
composer audit
npm audit

# Check failed logins
grep "Failed login" storage/logs/security.log | tail -20
```

## ⚙️ Configuration

```bash
# Validate configuration
php artisan config:validate

# Validate with strict mode
php artisan config:validate --strict

# Auto-fix issues
php artisan config:validate --fix

# Pre-deployment checks
./scripts/pre-deployment-check.sh
```

## 🔍 Diagnostics

```bash
# Check database
php artisan db:show

# Check Redis
php artisan tinker
>>> Redis::ping()

# Check queue
php artisan queue:monitor

# Check cache
php artisan tinker
>>> Cache::get('test')

# System resources
df -h                    # Disk usage
free -h                  # Memory usage
ps aux | grep php        # PHP processes
ps aux | grep queue      # Queue workers
```

## 🧹 Maintenance

```bash
# Clear all caches
php artisan cache:clear
php artisan config:clear
php artisan route:clear
php artisan view:clear
php artisan event:clear

# Optimize caches
php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan event:cache

# Restart queue workers
php artisan queue:restart

# Run migrations
php artisan migrate --force

# Rollback migrations
php artisan migrate:rollback --step=1
```

## 📈 Performance

```bash
# Check slow queries
tail -f storage/logs/slow-queries.log

# Monitor queue
watch -n 5 'php artisan queue:monitor'

# Check memory usage
php -i | grep memory_limit

# Profile request
# Add ?XDEBUG_PROFILE=1 to URL
```

## 🔧 Troubleshooting

```bash
# Application not responding
php artisan config:clear
php artisan cache:clear
php artisan queue:restart
systemctl restart php-fpm  # or your PHP service

# High memory usage
php artisan cache:clear
php artisan queue:restart

# Database connection errors
php artisan config:validate
php artisan db:show

# Redis connection errors
redis-cli ping
php artisan config:validate

# Queue not processing
ps aux | grep queue
php artisan queue:work &

# Disk space issues
df -h
du -sh storage/logs/*
php artisan backup:clean --force

# Check for errors
tail -100 storage/logs/laravel.log
grep ERROR storage/logs/laravel.log | tail -20
```

## 📋 Pre-Deployment Checklist

```bash
# 1. Run tests
php artisan test

# 2. Validate configuration
php artisan config:validate

# 3. Check dependencies
composer audit
npm audit

# 4. Security scan
php artisan security:scan

# 5. Backup database
php artisan backup:database --encrypt --upload

# 6. Review changes
git log --oneline -10

# 7. Deploy
./scripts/deploy-production.sh

# 8. Verify health
./scripts/health-check.sh

# 9. Monitor logs
tail -f storage/logs/deployment_*.log
```

## 🆘 Emergency Procedures

### Rollback Deployment

```bash
# Quick rollback
./scripts/rollback.sh --steps 1

# Rollback with specific commit
./scripts/rollback.sh --commit previous_stable_commit
```

### Enable Maintenance Mode

```bash
# Enable
php artisan down --retry=60 --secret=bypass-token

# Disable
php artisan up

# Access during maintenance
https://app.example.com?secret=bypass-token
```

### Stop All Processing

```bash
# Stop queue workers
php artisan queue:restart

# Kill all queue workers
pkill -f "artisan queue:work"

# Enable maintenance mode
php artisan down
```

### Database Emergency

```bash
# Backup immediately
php artisan backup:database --encrypt --upload

# Rollback last migration
php artisan migrate:rollback --step=1

# Restore from backup (manual)
mysql -u user -p database < backup_file.sql
```

## 📱 Monitoring URLs

```bash
# Health checks
https://app.example.com/health
https://app.example.com/health/ready
https://app.example.com/health/live
https://app.example.com/health/detailed

# Performance dashboard
https://app.example.com/admin/performance

# Metrics (if Prometheus enabled)
https://app.example.com/metrics
```

## 🔐 Security Contacts

| Severity | Channel | Response Time |
|----------|---------|---------------|
| Critical | PagerDuty + Slack | Immediate |
| Warning | Slack + Email | 1 hour |
| Info | Slack | Next day |

## 📞 Escalation

1. Check logs and metrics
2. Run diagnostics commands
3. Review recent deployments
4. Check external service status
5. Rollback if needed
6. Contact on-call engineer
7. Document incident

## 🔗 Useful Links

- [Full DevOps Guide](DEVOPS-GUIDE.md)
- [GitHub Actions](https://github.com/org/repo/actions)
- [Slack Alerts Channel](#slack-channel)
- [Status Page](#status-page)
- [Runbook](#runbook)
