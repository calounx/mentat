# DevOps & Operations Guide

This guide covers all deployment, monitoring, and operational tooling for the application.

## Table of Contents

1. [Deployment](#deployment)
2. [Health Checks](#health-checks)
3. [Monitoring](#monitoring)
4. [Alerting](#alerting)
5. [Logging](#logging)
6. [Backups](#backups)
7. [Security](#security)
8. [Configuration Validation](#configuration-validation)

---

## Deployment

### Production Deployment

Deploy to production with zero-downtime:

```bash
./scripts/deploy-production.sh
```

**Features:**
- Pre-deployment validation checks
- Automatic database backup
- Zero-downtime deployment (maintenance mode)
- Database migrations with rollback on failure
- Cache optimization
- Queue worker restart
- Post-deployment health checks
- Slack/email notifications

**Environment Variables:**
```bash
DEPLOY_BRANCH=main                    # Branch to deploy
BACKUP_RETENTION_DAYS=7               # How long to keep backups
MAINTENANCE_RETRY_SECONDS=60          # Retry after seconds during maintenance
SLACK_WEBHOOK_URL=https://...         # Slack notifications
EMAIL_NOTIFICATION=ops@example.com    # Email notifications
```

### Staging Deployment

Deploy to staging environment:

```bash
./scripts/deploy-staging.sh
```

**Additional Features:**
- Runs test suite before deployment
- Optional database seeding
- Keeps dev dependencies for testing

**Environment Variables:**
```bash
DEPLOY_BRANCH=develop                 # Branch to deploy
RUN_TESTS=true                        # Run tests before deploying
SEED_DATABASE=false                   # Seed database after migration
```

### Rollback

Rollback to previous version:

```bash
# Rollback 1 commit
./scripts/rollback.sh

# Rollback 3 commits
./scripts/rollback.sh --steps 3

# Rollback to specific commit
./scripts/rollback.sh --commit abc123

# Skip migrations rollback
./scripts/rollback.sh --skip-migrations

# Skip backup before rollback
./scripts/rollback.sh --skip-backup
```

**Features:**
- Automatic migration rollback
- Code rollback via git
- Dependency reinstallation
- Cache rebuild
- Health checks after rollback

---

## Health Checks

### Available Endpoints

```bash
# Basic health (200 OK if up)
GET /health

# Readiness check (database, Redis, queue)
GET /health/ready

# Liveness check (application responsive)
GET /health/live

# Security posture
GET /health/security

# External dependencies
GET /health/dependencies

# Detailed health report
GET /health/detailed
```

### Integration with Load Balancers

**Kubernetes:**
```yaml
livenessProbe:
  httpGet:
    path: /health/live
    port: 80
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /health/ready
    port: 80
  initialDelaySeconds: 5
  periodSeconds: 5
```

**AWS ALB Target Groups:**
- Health check path: `/health/ready`
- Success codes: `200`
- Interval: 30 seconds
- Timeout: 5 seconds
- Healthy threshold: 2
- Unhealthy threshold: 3

### Post-Deployment Health Check

```bash
./scripts/health-check.sh
```

This runs comprehensive health checks after deployment.

---

## Monitoring

### Configuration

Edit `config/monitoring.php` to configure monitoring:

```php
'prometheus' => [
    'enabled' => true,
    'pushgateway_url' => 'http://prometheus:9091',
],

'performance' => [
    'slow_request_threshold' => 1000,  // ms
    'slow_query_threshold' => 1000,    // ms
],
```

### Metrics Collected

**Request Metrics:**
- HTTP requests total
- Request duration (histogram)
- Memory usage per request
- Query count per request
- Error rate (4xx, 5xx)

**System Metrics:**
- Memory usage (current, peak, percentage)
- CPU usage
- Disk usage
- PHP configuration

**Application Metrics:**
- Cache hit/miss ratio
- Queue depth
- Queue job processing time
- Active users
- Error count

**Business Metrics:**
- Sites created
- Backups completed
- Deployments
- API calls

### Using MetricsCollector

```php
use App\Services\Monitoring\MetricsCollector;

// Increment counter
$metrics->increment('user_signups', ['plan' => 'pro']);

// Set gauge value
$metrics->gauge('active_users', 150);

// Record histogram (response time, query duration)
$metrics->histogram('api_response_time', 245.5, ['endpoint' => '/api/sites']);

// Record business event
$metrics->recordSiteCreated('enterprise');
$metrics->recordBackupCompleted('database', true);
```

### Performance Dashboard

Access the real-time performance dashboard:

```
/admin/performance
```

Shows:
- System resource usage (memory, disk)
- Database status and metrics
- Cache hit rates
- Queue status
- Average response times

---

## Alerting

### Configuration

Edit `config/alerting.php` to configure alerts:

```php
'channels' => [
    'critical' => ['slack', 'pagerduty', 'email'],
    'warning' => ['slack', 'email'],
    'info' => ['slack'],
],

'slack' => [
    'enabled' => true,
    'webhook_url' => env('SLACK_WEBHOOK_URL'),
],
```

### Alert Rules

Pre-configured alert rules:

| Rule | Threshold | Severity | Description |
|------|-----------|----------|-------------|
| high_error_rate | 5% | Critical | Error rate exceeds 5% |
| slow_response_time | 1000ms | Warning | Avg response time > 1s |
| database_connection_failure | 1 | Critical | Cannot connect to database |
| high_memory_usage | 90% | Warning | Memory usage above 90% |
| low_disk_space | 20% free | Critical | Disk space below 20% |
| high_queue_depth | 1000 jobs | Warning | Queue depth exceeds 1000 |
| high_failed_jobs | 10/min | Critical | More than 10 failed jobs/min |
| high_failed_login_attempts | 10/min | Critical | Possible brute force attack |
| ssl_certificate_expiring | 30 days | Warning | SSL cert expires soon |

### Using AlertManager

```php
use App\Services\Alerting\AlertManager;

// Send critical alert
$alertManager->critical(
    'database_connection_failure',
    'Cannot connect to database',
    ['error' => $exception->getMessage()]
);

// Send warning alert
$alertManager->warning(
    'slow_response_time',
    'Average response time is 1.5s',
    ['threshold' => '1000ms', 'actual' => '1500ms']
);

// Check if condition triggers alert
if ($alertManager->checkCondition('high_error_rate', $errorRate)) {
    $alertManager->critical('high_error_rate', "Error rate is {$errorRate}%");
}
```

### Alert Throttling

Alerts are automatically throttled to prevent spam:
- Maximum 3 alerts per rule per hour
- Similar alerts grouped within 5-minute window
- Quiet hours suppression (non-critical alerts)

### Environment Variables

```bash
# Slack
SLACK_ALERTS_ENABLED=true
SLACK_WEBHOOK_URL=https://hooks.slack.com/...
SLACK_ALERT_CHANNEL=#alerts

# Email
EMAIL_ALERTS_ENABLED=true
ALERT_EMAIL_RECIPIENTS=ops@example.com,dev@example.com
ALERT_EMAIL_FROM=alerts@example.com

# PagerDuty
PAGERDUTY_ENABLED=true
PAGERDUTY_INTEGRATION_KEY=your-key

# Quiet Hours
QUIET_HOURS_ENABLED=true
QUIET_HOURS_START=22:00
QUIET_HOURS_END=08:00
```

---

## Logging

### Log Channels

Multiple specialized log channels:

| Channel | Path | Retention | Purpose |
|---------|------|-----------|---------|
| stack | logs/laravel.log | 14 days | Default application logs |
| performance | logs/performance.log | 14 days | Performance metrics |
| security | logs/security.log | 90 days | Security events |
| audit | logs/audit.log | 90 days | Audit trail |
| slow_queries | logs/slow-queries.log | 7 days | Slow database queries |
| api | logs/api.log | 14 days | API requests |
| deployment | logs/deployment.log | 30 days | Deployment logs |
| json | logs/json.log | 14 days | Structured JSON logs |

### Usage

```php
// Standard logging
Log::info('User action', ['user_id' => $userId]);

// Performance logging
Log::channel('performance')->info('Slow request', [
    'duration_ms' => 1500,
    'url' => $request->url(),
]);

// Security logging
Log::channel('security')->warning('Failed login', [
    'email' => $email,
    'ip' => $request->ip(),
]);

// Audit logging
Log::channel('audit')->info('User created', [
    'admin_id' => $adminId,
    'new_user_id' => $userId,
]);
```

### Structured Logging

For machine-readable logs, use the JSON channel:

```php
Log::channel('json')->info('event_name', [
    'user_id' => 123,
    'action' => 'site_created',
    'site_id' => 456,
    'timestamp' => now()->toIso8601String(),
]);
```

### ELK Stack Integration

JSON logs are ready for Elasticsearch/Logstash:

```bash
# Filebeat configuration
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /path/to/storage/logs/json.log
    json.keys_under_root: true
```

---

## Backups

### Automated Database Backups

Backups run automatically via scheduled task:

```php
// In app/Console/Kernel.php
$schedule->command('backup:database --encrypt --upload')
    ->daily()
    ->at('02:00')
    ->onSuccess(fn() => Notification::send('Backup completed'))
    ->onFailure(fn() => Alert::critical('Backup failed'));
```

### Manual Backup

```bash
# Basic backup
php artisan backup:database

# Encrypted backup
php artisan backup:database --encrypt

# Upload to remote storage (S3)
php artisan backup:database --encrypt --upload

# Test backup integrity
php artisan backup:database --encrypt --test
```

### Backup Configuration

Edit `config/backup.php`:

```php
'retention' => [
    'daily' => 7,      // Keep 7 daily backups
    'weekly' => 4,     // Keep 4 weekly backups
    'monthly' => 12,   // Keep 12 monthly backups
],

'encryption' => [
    'enabled' => true,
    'algorithm' => 'aes-256-cbc',
],

'remote_storage' => [
    'enabled' => true,
    'disk' => 's3',
    'path' => 'backups',
],
```

### Cleanup Old Backups

```bash
# Preview what will be deleted
php artisan backup:clean --dry-run

# Delete old backups
php artisan backup:clean --force
```

### Environment Variables

```bash
BACKUP_ENABLED=true
BACKUP_FREQUENCY=daily
BACKUP_TIME=02:00
BACKUP_ENCRYPTION_ENABLED=true
BACKUP_REMOTE_ENABLED=true
BACKUP_REMOTE_DISK=s3
```

---

## Security

### Security Monitoring

The SecurityMonitor service tracks:
- Failed login attempts
- Authorization failures
- SQL injection attempts
- XSS attempts
- Rate limit violations
- Suspicious file uploads
- Cross-tenant access attempts
- API abuse
- SSH key age

### Security Scan

Run comprehensive security scan:

```bash
# Scan for security issues
php artisan security:scan

# Auto-fix issues where possible
php artisan security:scan --fix
```

Checks:
- Debug mode configuration
- .env file permissions
- Storage permissions
- SSH key security
- SSL certificate status
- Known dependency vulnerabilities
- Exposed sensitive files
- Security headers

### Automated Scanning

GitHub Actions runs security scans automatically:
- On every push/PR
- Daily scheduled scan
- Composer dependency audit
- NPM dependency audit
- CodeQL static analysis
- Secrets detection (TruffleHog)

### Manual Dependency Audit

```bash
# Composer packages
./scripts/composer-audit.sh

# NPM packages
npm audit

# Both with fix
composer audit && npm audit fix
```

---

## Configuration Validation

### Pre-Flight Checks

Validate configuration before deployment:

```bash
# Run validation
php artisan config:validate

# Strict mode (warnings fail)
php artisan config:validate --strict

# Auto-fix issues
php artisan config:validate --fix
```

**Checks:**
- PHP version and extensions
- Environment variables
- Database connectivity
- Redis connectivity
- File permissions
- Storage directories
- Cache functionality
- Queue configuration
- Security settings
- SSL certificates

### Pre-Deployment Script

The deployment scripts automatically run validation:

```bash
./scripts/pre-deployment-check.sh
```

---

## Monitoring & Alerting Integrations

### Prometheus

Export metrics for Prometheus:

```bash
# Enable Prometheus in .env
PROMETHEUS_ENABLED=true
PROMETHEUS_PUSHGATEWAY_URL=http://prometheus:9091
```

Metrics endpoint: `/metrics` (implement via Prometheus exporter)

### Sentry

Error tracking with Sentry:

```bash
# Enable Sentry in .env
SENTRY_ENABLED=true
SENTRY_LARAVEL_DSN=https://...@sentry.io/...
SENTRY_TRACES_SAMPLE_RATE=0.1
```

### New Relic

```bash
NEW_RELIC_ENABLED=true
NEW_RELIC_APP_NAME=MyApp
NEW_RELIC_LICENSE_KEY=your-key
```

### DataDog

```bash
DATADOG_ENABLED=true
DATADOG_API_KEY=your-key
DATADOG_APP_KEY=your-app-key
```

---

## Best Practices

### Deployment

1. Always test in staging first
2. Run `config:validate` before deploying
3. Monitor health checks after deployment
4. Keep deployment logs for troubleshooting
5. Have rollback plan ready

### Monitoring

1. Set appropriate alert thresholds
2. Avoid alert fatigue (use throttling)
3. Review metrics regularly
4. Tune slow query threshold
5. Monitor business metrics

### Backups

1. Test restore procedures regularly
2. Store backups off-site
3. Encrypt sensitive backups
4. Verify backup integrity
5. Document restore process

### Security

1. Run security scans regularly
2. Keep dependencies updated
3. Review security logs
4. Rotate SSH keys annually
5. Monitor failed login attempts

---

## Troubleshooting

### Deployment Failed

```bash
# Check deployment logs
tail -f storage/logs/deployment_*.log

# Verify health
./scripts/health-check.sh

# Rollback if needed
./scripts/rollback.sh
```

### High Memory Usage

```bash
# Check current usage
php artisan config:validate

# Clear caches
php artisan cache:clear
php artisan config:clear
php artisan route:clear
php artisan view:clear

# Restart queue workers
php artisan queue:restart
```

### Database Connection Issues

```bash
# Test connection
php artisan db:show

# Check configuration
php artisan config:validate

# View logs
tail -f storage/logs/laravel.log
```

### High Error Rate

```bash
# Check error logs
tail -f storage/logs/laravel.log

# Check slow queries
tail -f storage/logs/slow-queries.log

# Review performance
less storage/logs/performance.log
```

---

## Support

For issues or questions:
- Check logs in `storage/logs/`
- Review health endpoints: `/health/detailed`
- Check Slack alerts channel
- Run diagnostics: `php artisan config:validate`
