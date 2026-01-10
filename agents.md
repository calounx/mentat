# Custom Agents for CHOM Homelab

This file defines specialized agents for working with the CHOM (Cloud Hosting & Observability Manager) homelab project. These agents provide domain-specific expertise and automated workflows.

## Agent Definitions

### 1. deployment-orchestrator

**Purpose**: Automates deployment of CHOM across the two-server infrastructure (mentat + landsraad)

**Capabilities**:
- Executes the automated deployment script (`deploy/deploy-chom-automated.sh`)
- Validates deployment prerequisites and environment
- Manages deployment phases with skip/retry options
- Handles secret generation and SSH key management
- Monitors deployment progress and reports failures
- Performs post-deployment validation
- Supports dry-run mode for testing

**When to Use**:
- Full production deployment
- Infrastructure updates
- Version upgrades
- Configuration changes requiring redeployment

**Tools Available**:
- Bash (for running deployment scripts)
- Read (for validating configuration files)
- Grep/Glob (for finding deployment artifacts)
- Write (for generating deployment configs)

**Usage Example**:
```
User: "Deploy CHOM to production"
→ Invoke deployment-orchestrator agent
→ Agent validates environment, runs deploy-chom-automated.sh, reports results
```

**Key Files**:
- `deploy/deploy-chom-automated.sh` (main deployment script)
- `deploy/QUICK-START-AUTOMATED.md` (deployment guide)
- `.env.example` (environment template)

---

### 2. multi-tenancy-validator

**Purpose**: Validates multi-tenant isolation and security across the codebase

**Capabilities**:
- Scans code for multi-tenancy violations
- Validates tenant filtering in repositories
- Checks for cross-tenant data leaks
- Reviews query patterns for isolation
- Runs isolation test suite
- Generates security audit reports
- Identifies P0/P1 security issues

**When to Use**:
- Before deploying new features
- After modifying data access code
- During security audits
- When adding new models or repositories
- Before production releases

**Tools Available**:
- Grep (for finding query patterns)
- Glob (for finding relevant files)
- Read (for code analysis)
- Bash (for running tests)

**Usage Example**:
```
User: "Validate multi-tenancy in the new feature"
→ Invoke multi-tenancy-validator agent
→ Agent scans code, runs tests, reports issues
```

**Key Files**:
- `tests/Feature/BackupTenantIsolationTest.php`
- `app/Repositories/BackupRepository.php`
- `docs/architecture/multi-tenancy.md`
- `app/Models/` (all models with tenant_id)

**Validation Patterns**:
```php
// GOOD: Tenant-filtered query
$sites = Site::where('tenant_id', $tenantId)->get();

// BAD: Unfiltered query in multi-tenant context
$sites = Site::all();

// GOOD: Repository with tenant isolation
public function getBackupsForTenant(int $tenantId): Collection
{
    return SiteBackup::whereHas('site', function ($query) use ($tenantId) {
        $query->where('tenant_id', $tenantId);
    })->get();
}
```

---

### 3. observability-configurator

**Purpose**: Manages observability stack configuration and deployment

**Capabilities**:
- Configures Prometheus, Loki, Grafana, AlertManager
- Sets up metric exporters (node, nginx, postgres, redis, php-fpm)
- Configures alert rules and notification channels
- Validates observability endpoints
- Tests metric collection and log aggregation
- Creates Grafana dashboards
- Configures multi-tenant log isolation in Loki

**When to Use**:
- Initial observability stack setup
- Adding new monitoring targets
- Configuring alerts
- Creating custom dashboards
- Troubleshooting monitoring issues
- Updating observability configurations

**Tools Available**:
- Read/Write (for configuration files)
- Bash (for testing endpoints, restarting services)
- Grep/Glob (for finding config templates)

**Usage Example**:
```
User: "Set up monitoring for a new VPS server"
→ Invoke observability-configurator agent
→ Agent updates Prometheus config, adds exporters, validates
```

**Key Files**:
- `deploy/config/prometheus.yml`
- `deploy/config/loki-config.yml`
- `deploy/config/grafana.ini`
- `deploy/config/alertmanager.yml`
- `docs/operations/observability.md`

**Configuration Locations**:
```
Prometheus: http://mentat.arewel.com:9090
Grafana: http://mentat.arewel.com:3000
Loki: http://mentat.arewel.com:3100
AlertManager: http://mentat.arewel.com:9093
```

---

### 4. security-auditor

**Purpose**: Performs comprehensive security audits of the CHOM platform

**Capabilities**:
- Reviews authentication and authorization code
- Validates rate limiting configuration
- Checks SSH key management
- Audits backup encryption
- Reviews circuit breaker configurations
- Validates input sanitization
- Checks for common vulnerabilities (SQL injection, XSS, CSRF)
- Generates security compliance reports
- Validates firewall rules (UFW)

**When to Use**:
- Before production releases
- After security-related changes
- Periodic security audits
- Compliance reporting
- Post-incident analysis

**Tools Available**:
- Grep (for finding security patterns)
- Read (for code review)
- Bash (for running security tests)
- Glob (for finding vulnerable files)

**Usage Example**:
```
User: "Audit security before v2.3 release"
→ Invoke security-auditor agent
→ Agent scans for vulnerabilities, runs tests, generates report
```

**Key Files**:
- `deploy/security/` (30 security scripts)
- `config/circuit-breaker.php`
- `config/degradation.php`
- `app/Http/Middleware/`
- `DEPLOYMENT_SECURITY_AUDIT_REPORT.md`

**Security Checklist**:
- [ ] Multi-tenant isolation enforced
- [ ] Rate limiting configured
- [ ] SSH key-based authentication only
- [ ] Backup encryption enabled
- [ ] Circuit breakers configured
- [ ] Input validation on all forms
- [ ] CSRF protection enabled
- [ ] API authentication (Sanctum)
- [ ] Firewall rules (UFW) active

---

### 5. vpsmanager-operator

**Purpose**: Manages VPSManager operations for site provisioning and management

**Capabilities**:
- Provisions new sites (WordPress, Laravel, HTML)
- Manages SSL certificates (Let's Encrypt)
- Creates and restores backups
- Manages per-site system users
- Configures site isolation
- Handles database and cache operations
- Monitors site health
- Runs VPSManager test suite

**When to Use**:
- Creating new sites
- Managing existing sites
- SSL certificate operations
- Backup operations
- Site troubleshooting
- Testing VPSManager functionality

**Tools Available**:
- Bash (for running VPSManager scripts)
- Read (for reading VPSManager configs)
- Grep/Glob (for finding VPSManager files)

**Usage Example**:
```
User: "Provision a new WordPress site with SSL"
→ Invoke vpsmanager-operator agent
→ Agent runs create-site.sh, setup-ssl.sh, validates
```

**Key Files**:
- `deploy/vpsmanager/` (VPSManager CLI)
- `deploy/vpsmanager/tests/` (test suite)
- `app/Services/Integration/VPSManagerBridge.php`

**VPSManager Commands**:
```bash
# Site management
./create-site.sh <domain> <type>
./delete-site.sh <domain>
./setup-ssl.sh <domain>

# Backup operations
./create-backup.sh <domain>
./restore-backup.sh <domain> <backup-file>

# User management
./create-site-user.sh <domain>
./delete-site-user.sh <domain>
```

---

### 6. laravel-architect

**Purpose**: Guides Laravel-specific architecture and development patterns

**Capabilities**:
- Designs new features following DDD bounded contexts
- Creates migrations with proper foreign keys
- Generates models with relationships
- Creates Livewire components following project patterns
- Sets up service layer and repositories
- Configures routes (web, API)
- Creates form request validation
- Writes feature tests
- Ensures compliance with Laravel best practices

**When to Use**:
- Adding new features
- Refactoring existing code
- Creating new modules
- Database schema changes
- Building new APIs
- Creating Livewire components

**Tools Available**:
- Read/Write/Edit (for code files)
- Bash (for artisan commands)
- Grep/Glob (for finding patterns)

**Usage Example**:
```
User: "Add a new feature for site analytics"
→ Invoke laravel-architect agent
→ Agent designs feature, creates migration, model, service, controller, tests
```

**Key Files**:
- `chom/MODULAR-ARCHITECTURE.md`
- `app/Models/`
- `app/Services/`
- `app/Repositories/`
- `app/Livewire/`
- `database/migrations/`

**Architecture Patterns**:
```
1. Create migration (schema)
2. Create model (Eloquent)
3. Create repository (data access)
4. Create service (business logic)
5. Create controller/Livewire (presentation)
6. Create form requests (validation)
7. Create policies (authorization)
8. Add routes
9. Create tests
```

---

### 7. test-automation-specialist

**Purpose**: Manages testing strategy and execution

**Capabilities**:
- Runs PHPUnit test suite
- Executes VPSManager integration tests
- Performs multi-tenancy isolation tests
- Runs deployment validation tests
- Generates test coverage reports
- Identifies test gaps
- Creates new test cases
- Performs regression testing
- Validates idempotent deployment

**When to Use**:
- Before deployments
- After code changes
- During CI/CD pipeline
- Regression testing
- Coverage analysis

**Tools Available**:
- Bash (for running tests)
- Read (for analyzing test files)
- Write (for creating new tests)
- Grep/Glob (for finding test files)

**Usage Example**:
```
User: "Run all tests and generate coverage report"
→ Invoke test-automation-specialist agent
→ Agent runs tests, analyzes results, generates report
```

**Key Files**:
- `tests/Feature/`
- `tests/Unit/`
- `deploy/vpsmanager/tests/`
- `phpunit.xml`
- `INTEGRATION_TEST_REPORT.md`

**Test Commands**:
```bash
# Run all tests
composer test

# Run with coverage
composer test --coverage

# Run specific test
php artisan test --filter=BackupTenantIsolation

# VPSManager tests
cd deploy/vpsmanager/tests && ./run-all-tests.sh
```

---

### 8. stripe-integration-manager

**Purpose**: Manages Stripe billing integration and subscription workflows

**Capabilities**:
- Configures Stripe API keys and webhooks
- Manages pricing tiers (Starter/Pro/Enterprise)
- Handles subscription lifecycle events
- Tests webhook handlers
- Validates billing logic
- Manages plan change requests
- Handles payment failures and retries
- Generates billing reports

**When to Use**:
- Setting up Stripe integration
- Changing pricing tiers
- Debugging billing issues
- Testing subscription workflows
- Handling payment failures

**Tools Available**:
- Read (for Stripe configuration)
- Bash (for testing webhooks)
- Grep/Glob (for finding billing code)

**Usage Example**:
```
User: "Test Stripe webhook for subscription cancellation"
→ Invoke stripe-integration-manager agent
→ Agent sends test webhook, validates handler, reports results
```

**Key Files**:
- `app/Http/Controllers/Webhooks/StripeWebhookController.php`
- `config/chom.php` (billing tiers)
- `app/Models/Subscription.php`
- `app/Models/TierLimit.php`

**Webhook Events**:
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `invoice.paid`
- `invoice.payment_failed`
- `charge.refunded`

---

### 9. database-migration-expert

**Purpose**: Manages database schema evolution and migrations

**Capabilities**:
- Creates new migrations following project conventions
- Ensures proper foreign key constraints
- Validates tenant isolation in schema
- Handles migration rollbacks
- Seeds test data
- Manages database indexes
- Optimizes queries
- Validates migration idempotence

**When to Use**:
- Creating new tables
- Modifying existing schema
- Adding foreign keys
- Creating indexes
- Seeding data
- Migration troubleshooting

**Tools Available**:
- Bash (for artisan commands)
- Read/Write (for migration files)
- Grep/Glob (for finding migrations)

**Usage Example**:
```
User: "Create a migration for site analytics table"
→ Invoke database-migration-expert agent
→ Agent creates migration with proper structure, foreign keys, indexes
```

**Key Files**:
- `database/migrations/` (38 migrations)
- `database/seeders/`
- `database/factories/`

**Migration Pattern**:
```php
public function up(): void
{
    Schema::create('table_name', function (Blueprint $table) {
        $table->id();
        $table->foreignId('tenant_id')->constrained()->onDelete('cascade');
        $table->string('name');
        $table->timestamps();

        // Indexes for performance
        $table->index(['tenant_id', 'created_at']);
    });
}
```

---

### 10. incident-responder

**Purpose**: Responds to production incidents and system failures

**Capabilities**:
- Analyzes health check failures
- Diagnoses service outages
- Reviews logs (Laravel, Nginx, system)
- Checks observability dashboards
- Validates circuit breaker states
- Performs self-healing validation
- Generates incident reports
- Suggests remediation steps

**When to Use**:
- Production incidents
- Service degradation
- Monitoring alerts
- Performance issues
- Post-mortem analysis

**Tools Available**:
- Bash (for checking services, logs)
- Read (for analyzing logs)
- Grep (for searching logs)

**Usage Example**:
```
User: "The application is down, investigate"
→ Invoke incident-responder agent
→ Agent checks health endpoints, services, logs, reports findings
```

**Key Files**:
- `storage/logs/laravel.log`
- `/var/log/nginx/error.log`
- `docs/operations/self-healing.md`
- `deploy/RUNBOOK.md`

**Health Checks**:
```bash
# Application
curl http://landsraad.arewel.com/health

# Observability
curl http://mentat.arewel.com:9090/-/healthy  # Prometheus
curl http://mentat.arewel.com:3100/ready      # Loki
curl http://mentat.arewel.com:3000/api/health # Grafana

# System services
systemctl status nginx postgresql redis grafana-server prometheus
```

---

## Agent Coordination

### Multi-Agent Workflows

Some tasks benefit from multiple agents working together:

**Full Production Deployment**:
1. `security-auditor` - Pre-deployment security audit
2. `test-automation-specialist` - Run full test suite
3. `deployment-orchestrator` - Execute deployment
4. `observability-configurator` - Validate monitoring
5. `incident-responder` - Post-deployment health check

**New Feature Development**:
1. `laravel-architect` - Design and implement feature
2. `multi-tenancy-validator` - Validate isolation
3. `database-migration-expert` - Handle schema changes
4. `test-automation-specialist` - Create and run tests
5. `security-auditor` - Security review

**Incident Response**:
1. `incident-responder` - Initial investigation
2. `observability-configurator` - Check monitoring
3. `test-automation-specialist` - Validate system
4. `deployment-orchestrator` - Rollback if needed

---

## Agent Best Practices

### When to Use Agents

- **Complex multi-step tasks** - Deployment, testing, auditing
- **Domain expertise required** - Laravel patterns, multi-tenancy, observability
- **Repetitive workflows** - Site provisioning, testing, security scans
- **Cross-system coordination** - Deployment across multiple servers

### When NOT to Use Agents

- **Simple file edits** - Use Edit tool directly
- **Reading single files** - Use Read tool
- **Quick queries** - Use Grep/Glob tools
- **Trivial commands** - Use Bash tool

### Agent Communication

Agents should:
- Report progress clearly
- Document decisions made
- Provide actionable recommendations
- Include relevant file paths and line numbers
- Generate summary reports when complete

---

## Custom Agent Invocation

To invoke a custom agent:

```
User: "Use the [agent-name] agent to [task description]"
```

Examples:
- "Use the deployment-orchestrator agent to deploy CHOM to production"
- "Use the multi-tenancy-validator agent to audit the new backup feature"
- "Use the observability-configurator agent to add monitoring for the new VPS"

---

## Extending Agents

To add new agents:

1. Define agent purpose and capabilities
2. Specify when to use the agent
3. List available tools
4. Document key files and patterns
5. Provide usage examples
6. Add to this document

---

**Last Updated**: 2025-01-10
**Version**: 1.0.0
