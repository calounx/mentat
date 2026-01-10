# Skills for CHOM Homelab

This file defines reusable skills (slash commands) for common tasks in the CHOM (Cloud Hosting & Observability Manager) homelab project. Skills are invoked as `/skill-name` and automate repetitive workflows.

## Available Skills

### /deploy-production

**Purpose**: Deploy CHOM to production servers (mentat + landsraad)

**Description**: Executes the full automated deployment workflow including pre-flight checks, secret generation, dependency installation, and application deployment.

**Workflow**:
1. Validate environment and prerequisites
2. Run security audit
3. Execute full test suite
4. Run `deploy/deploy-chom-automated.sh`
5. Validate deployment health
6. Report deployment status

**Usage**:
```
/deploy-production
```

**Options**:
- `--dry-run` - Simulate deployment without making changes
- `--skip-tests` - Skip test execution (not recommended)
- `--phase <phase>` - Run specific deployment phase only

**Example**:
```
/deploy-production --dry-run
```

**Requirements**:
- SSH access to both servers
- Deployment key configured
- `.env` file properly configured

---

### /test-isolation

**Purpose**: Run multi-tenancy isolation test suite

**Description**: Executes comprehensive tests to validate tenant isolation across the application, ensuring no cross-tenant data leaks.

**Workflow**:
1. Run `BackupTenantIsolationTest.php` (7 test cases)
2. Scan code for multi-tenancy violations
3. Validate repository tenant filtering
4. Check form request validation
5. Generate isolation report

**Usage**:
```
/test-isolation
```

**Tests Executed**:
- Backup cross-tenant access prevention
- Site lookup validation
- Repository filtering
- Query tenant isolation
- Policy authorization

**Example Output**:
```
✓ Tenant cannot access another tenant's backups
✓ Form requests validate site ownership
✓ Repository filters by tenant_id
✓ Policies enforce tenant boundaries
```

---

### /setup-observability

**Purpose**: Configure observability stack for a new server or service

**Description**: Sets up Prometheus, Loki, Grafana, and AlertManager with proper exporters and dashboards.

**Workflow**:
1. Install observability components
2. Configure Prometheus scrape targets
3. Set up Loki log collection
4. Configure Grafana data sources
5. Import dashboards
6. Set up alert rules
7. Test metric collection
8. Validate log aggregation

**Usage**:
```
/setup-observability <target-server>
```

**Options**:
- `--metrics-only` - Only set up Prometheus/exporters
- `--logs-only` - Only set up Loki/Promtail
- `--dashboards` - Import Grafana dashboards

**Example**:
```
/setup-observability new-vps.arewel.com --metrics-only
```

**Components Configured**:
- Prometheus (metrics collection)
- Node Exporter (system metrics)
- Nginx Exporter (web server metrics)
- PostgreSQL Exporter (database metrics)
- Redis Exporter (cache metrics)
- PHP-FPM Exporter (application metrics)
- Loki (log aggregation)
- Promtail (log collection)
- Grafana (visualization)
- AlertManager (alerting)

---

### /create-migration

**Purpose**: Create a new database migration with proper structure

**Description**: Generates a migration file following CHOM conventions with tenant isolation, foreign keys, and indexes.

**Workflow**:
1. Run `php artisan make:migration <name>`
2. Add proper foreign key constraints
3. Add tenant_id column if needed
4. Add indexes for performance
5. Add proper rollback logic

**Usage**:
```
/create-migration <migration-name>
```

**Options**:
- `--table=<name>` - Specify table name
- `--tenant-isolated` - Add tenant_id column and foreign key
- `--create` - Create a new table

**Example**:
```
/create-migration create_site_analytics_table --tenant-isolated
```

**Generated Structure**:
```php
public function up(): void
{
    Schema::create('site_analytics', function (Blueprint $table) {
        $table->id();
        $table->foreignId('tenant_id')->constrained()->onDelete('cascade');
        $table->foreignId('site_id')->constrained()->onDelete('cascade');
        $table->integer('visits');
        $table->timestamps();

        $table->index(['tenant_id', 'site_id', 'created_at']);
    });
}

public function down(): void
{
    Schema::dropIfExists('site_analytics');
}
```

---

### /provision-site

**Purpose**: Provision a new site on a VPS server

**Description**: Uses VPSManager to create a new WordPress, Laravel, or HTML site with SSL certificate.

**Workflow**:
1. Validate site domain and type
2. Create site system user
3. Run `create-site.sh <domain> <type>`
4. Set up SSL certificate with Let's Encrypt
5. Configure Nginx virtual host
6. Set up database (if needed)
7. Validate site accessibility
8. Configure monitoring

**Usage**:
```
/provision-site <domain> <type>
```

**Options**:
- `--type=<wordpress|laravel|html>` - Site type (default: wordpress)
- `--no-ssl` - Skip SSL setup
- `--database=<name>` - Create database with name

**Example**:
```
/provision-site myblog.example.com --type=wordpress
```

**Site Types**:
- **wordpress** - WordPress installation
- **laravel** - Laravel application
- **html** - Static HTML site

---

### /backup-site

**Purpose**: Create an encrypted backup of a site

**Description**: Uses VPSManager to create a complete backup of a site including files and database.

**Workflow**:
1. Validate site exists
2. Run `create-backup.sh <domain>`
3. Encrypt backup with OpenSSL
4. Upload to backup storage
5. Record backup in database
6. Validate backup integrity
7. Apply retention policy

**Usage**:
```
/backup-site <domain>
```

**Options**:
- `--no-encrypt` - Skip encryption (not recommended)
- `--retention=<days>` - Override retention policy

**Example**:
```
/backup-site myblog.example.com --retention=30
```

**Backup Contents**:
- Site files (document root)
- Database dump (if applicable)
- Nginx configuration
- SSL certificates
- Site metadata

---

### /restore-site

**Purpose**: Restore a site from backup

**Description**: Restores a site from a previously created backup.

**Workflow**:
1. List available backups for site
2. Select backup to restore
3. Decrypt backup
4. Run `restore-backup.sh <domain> <backup-file>`
5. Restore files and database
6. Validate site functionality
7. Update DNS if needed

**Usage**:
```
/restore-site <domain> [backup-file]
```

**Options**:
- `--latest` - Restore latest backup (default)
- `--date=<YYYY-MM-DD>` - Restore backup from specific date
- `--dry-run` - Show what would be restored

**Example**:
```
/restore-site myblog.example.com --latest
```

---

### /health-check

**Purpose**: Check health of all CHOM services

**Description**: Performs comprehensive health checks across all infrastructure components.

**Workflow**:
1. Check application health (`/health` endpoint)
2. Check database connectivity
3. Check Redis connectivity
4. Check queue workers
5. Check observability services
6. Check VPS servers
7. Generate health report

**Usage**:
```
/health-check
```

**Options**:
- `--service=<name>` - Check specific service only
- `--detailed` - Show detailed diagnostics
- `--json` - Output as JSON

**Example**:
```
/health-check --detailed
```

**Services Checked**:
- Laravel Application
- PostgreSQL Database
- Redis Cache/Queue
- Nginx Web Server
- Prometheus
- Grafana
- Loki
- AlertManager
- VPS Servers

---

### /security-scan

**Purpose**: Run comprehensive security scan

**Description**: Executes security audit across the codebase and infrastructure.

**Workflow**:
1. Run multi-tenancy validation
2. Check authentication/authorization
3. Validate rate limiting
4. Check SSH key management
5. Audit backup encryption
6. Review circuit breaker config
7. Scan for common vulnerabilities
8. Generate security report

**Usage**:
```
/security-scan
```

**Options**:
- `--critical-only` - Only show P0/P1 issues
- `--fix` - Auto-fix known issues (use with caution)
- `--report=<file>` - Save report to file

**Example**:
```
/security-scan --critical-only
```

**Vulnerabilities Checked**:
- SQL Injection
- XSS (Cross-Site Scripting)
- CSRF (Cross-Site Request Forgery)
- Multi-tenancy isolation
- Authentication bypass
- Authorization issues
- Sensitive data exposure
- Insecure configurations

---

### /run-tests

**Purpose**: Execute the complete test suite

**Description**: Runs all PHPUnit tests with coverage analysis.

**Workflow**:
1. Run unit tests
2. Run feature tests
3. Run integration tests
4. Generate coverage report
5. Report test results

**Usage**:
```
/run-tests
```

**Options**:
- `--coverage` - Generate coverage report
- `--filter=<name>` - Run specific test
- `--group=<name>` - Run test group
- `--stop-on-failure` - Stop on first failure

**Example**:
```
/run-tests --coverage --filter=Backup
```

**Test Suites**:
- Unit Tests (`tests/Unit/`)
- Feature Tests (`tests/Feature/`)
- VPSManager Tests (`deploy/vpsmanager/tests/`)

---

### /new-feature

**Purpose**: Scaffold a new feature following CHOM architecture

**Description**: Creates all necessary files for a new feature following DDD bounded contexts.

**Workflow**:
1. Determine bounded context (module)
2. Create migration
3. Create model with relationships
4. Create repository
5. Create service
6. Create controller or Livewire component
7. Create form requests
8. Create policy
9. Add routes
10. Create tests
11. Update documentation

**Usage**:
```
/new-feature <feature-name>
```

**Options**:
- `--module=<name>` - Specify bounded context
- `--api` - Create API controller instead of Livewire
- `--skip-tests` - Skip test creation (not recommended)

**Example**:
```
/new-feature site-analytics --module=SiteHosting
```

**Files Created**:
```
database/migrations/YYYY_MM_DD_HHMMSS_create_site_analytics_table.php
app/Models/SiteAnalytic.php
app/Repositories/SiteAnalyticRepository.php
app/Services/SiteAnalyticService.php
app/Livewire/Analytics/AnalyticsDashboard.php
app/Http/Requests/StoreSiteAnalyticRequest.php
app/Policies/SiteAnalyticPolicy.php
tests/Feature/SiteAnalyticTest.php
```

---

### /stripe-test

**Purpose**: Test Stripe webhook integration

**Description**: Sends test webhooks to validate Stripe integration.

**Workflow**:
1. Configure Stripe test environment
2. Send test webhook events
3. Validate webhook handling
4. Check subscription updates
5. Verify billing logic
6. Generate test report

**Usage**:
```
/stripe-test <event-type>
```

**Options**:
- `--event=<type>` - Specific event type
- `--all` - Test all webhook events

**Example**:
```
/stripe-test --event=customer.subscription.created
```

**Events Tested**:
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `invoice.paid`
- `invoice.payment_failed`
- `charge.refunded`

---

### /logs

**Purpose**: View and analyze application logs

**Description**: Displays logs from various sources with filtering options.

**Workflow**:
1. Determine log source
2. Fetch logs
3. Apply filters
4. Format output
5. Display results

**Usage**:
```
/logs [source]
```

**Options**:
- `--source=<laravel|nginx|php|system>` - Log source
- `--lines=<n>` - Number of lines (default: 100)
- `--follow` - Follow log in real-time
- `--grep=<pattern>` - Filter by pattern
- `--since=<time>` - Show logs since time

**Example**:
```
/logs --source=laravel --grep="ERROR" --lines=50
```

**Log Sources**:
- **laravel** - `storage/logs/laravel.log`
- **nginx** - `/var/log/nginx/error.log`
- **php** - `/var/log/php8.2-fpm.log`
- **system** - `/var/log/syslog`
- **queue** - `storage/logs/worker.log`

---

### /rollback

**Purpose**: Rollback to previous deployment

**Description**: Reverts to the previous stable deployment.

**Workflow**:
1. Confirm rollback target
2. Run database rollback (if needed)
3. Revert code to previous version
4. Clear caches
5. Restart services
6. Validate health
7. Notify team

**Usage**:
```
/rollback [version]
```

**Options**:
- `--version=<tag>` - Rollback to specific version
- `--skip-db` - Don't rollback database
- `--dry-run` - Simulate rollback

**Example**:
```
/rollback --version=v2.2.11
```

**Warning**: Database rollbacks may cause data loss. Always backup first.

---

### /generate-report

**Purpose**: Generate various operational reports

**Description**: Creates reports for deployment, security, performance, or billing.

**Workflow**:
1. Select report type
2. Gather data from relevant sources
3. Analyze and format data
4. Generate report
5. Save or display report

**Usage**:
```
/generate-report <type>
```

**Options**:
- `--type=<deployment|security|performance|billing>` - Report type
- `--format=<md|json|html>` - Output format
- `--output=<file>` - Save to file

**Example**:
```
/generate-report --type=security --format=md --output=security-audit.md
```

**Report Types**:
- **deployment** - Deployment history and status
- **security** - Security audit findings
- **performance** - Performance metrics and bottlenecks
- **billing** - Subscription and revenue metrics
- **usage** - Resource usage by tenant

---

### /cache-clear

**Purpose**: Clear all application caches

**Description**: Clears Laravel caches including config, route, view, and application cache.

**Workflow**:
1. Clear config cache
2. Clear route cache
3. Clear view cache
4. Clear application cache
5. Clear Redis cache (optional)
6. Restart queue workers
7. Validate application

**Usage**:
```
/cache-clear
```

**Options**:
- `--redis` - Also clear Redis cache
- `--queue-restart` - Restart queue workers

**Example**:
```
/cache-clear --redis --queue-restart
```

**Commands Executed**:
```bash
php artisan config:clear
php artisan route:clear
php artisan view:clear
php artisan cache:clear
php artisan queue:restart
```

---

### /db-migrate

**Purpose**: Run database migrations

**Description**: Executes pending database migrations with validation.

**Workflow**:
1. Backup database
2. Check pending migrations
3. Run migrations
4. Validate schema
5. Run seeders (optional)
6. Update documentation

**Usage**:
```
/db-migrate
```

**Options**:
- `--fresh` - Drop all tables and re-run (DESTRUCTIVE)
- `--seed` - Run seeders after migration
- `--rollback` - Rollback last migration batch
- `--force` - Force in production

**Example**:
```
/db-migrate --seed
```

**Warning**: Use `--fresh` only in development. It destroys all data.

---

### /optimize-performance

**Purpose**: Analyze and optimize application performance

**Description**: Identifies performance bottlenecks and applies optimizations.

**Workflow**:
1. Run performance profiling
2. Analyze database queries
3. Check cache hit rates
4. Review N+1 queries
5. Optimize database indexes
6. Enable opcode caching
7. Optimize Composer autoload
8. Generate optimization report

**Usage**:
```
/optimize-performance
```

**Options**:
- `--analyze-only` - Only analyze, don't optimize
- `--database` - Focus on database optimization
- `--cache` - Focus on caching optimization

**Example**:
```
/optimize-performance --analyze-only
```

**Optimizations Applied**:
- Config cache
- Route cache
- View cache
- Composer autoload optimization
- Database query optimization
- Redis cache tuning

---

### /monitor-alerts

**Purpose**: View and manage monitoring alerts

**Description**: Displays active alerts from AlertManager and provides remediation.

**Workflow**:
1. Fetch alerts from AlertManager
2. Categorize by severity
3. Display active alerts
4. Suggest remediation steps
5. Silence alerts (optional)

**Usage**:
```
/monitor-alerts
```

**Options**:
- `--active` - Show only active alerts
- `--critical` - Show only critical alerts
- `--silence=<alert>` - Silence specific alert

**Example**:
```
/monitor-alerts --critical
```

**Alert Sources**:
- Prometheus (via AlertManager)
- Application health checks
- Observability stack monitoring
- VPS health monitoring

---

## Skill Composition

Some skills can be combined in workflows:

**Complete Deployment Workflow**:
```
/security-scan → /run-tests → /deploy-production → /health-check → /monitor-alerts
```

**New Site Provisioning**:
```
/provision-site → /setup-observability → /backup-site → /health-check
```

**Incident Response**:
```
/health-check → /logs → /monitor-alerts → /rollback (if needed)
```

---

## Creating Custom Skills

To add a new skill:

1. Define the skill purpose and workflow
2. Document required parameters and options
3. Specify the commands/tools to execute
4. Add error handling and validation
5. Document in this file
6. Test thoroughly before production use

---

## Skill Best Practices

1. **Always validate inputs** before executing
2. **Provide dry-run options** for destructive operations
3. **Generate reports** for audit trails
4. **Handle errors gracefully** with clear messages
5. **Document all actions** taken by the skill
6. **Test in development** before using in production
7. **Use idempotent operations** when possible

---

## Environment-Specific Skills

Some skills behave differently based on environment:

**Development**:
- Database migrations use SQLite
- Stripe uses test mode
- Email goes to log
- Debug mode enabled

**Production**:
- Database migrations require confirmation
- Stripe uses live mode
- Email goes to SMTP
- Debug mode disabled
- Requires `--force` flag for risky operations

---

**Last Updated**: 2025-01-10
**Version**: 1.0.0
