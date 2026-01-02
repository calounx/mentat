# Deployment Testing Quick Reference

## Common Commands

### Run All Tests
```bash
./tests/Deployment/run-deployment-tests.sh --all
```

### Run Smoke Tests (Fastest)
```bash
./tests/Deployment/run-deployment-tests.sh --smoke-only
```

### Run Integration Tests
```bash
./tests/Deployment/run-deployment-tests.sh --integration-only
```

### Run Load Tests
```bash
./tests/Deployment/run-deployment-tests.sh --load
```

### Run Chaos Tests
```bash
./tests/Deployment/run-deployment-tests.sh --chaos
```

### Run with Coverage
```bash
./tests/Deployment/run-deployment-tests.sh --all --coverage
```

## PHPUnit Commands

### Run Specific Test File
```bash
vendor/bin/phpunit tests/Deployment/Integration/PreDeploymentCheckTest.php
```

### Run Specific Test Method
```bash
vendor/bin/phpunit --filter test_pre_deployment_checks_pass
```

### Run Tests by Group
```bash
vendor/bin/phpunit --group smoke
vendor/bin/phpunit --group integration
vendor/bin/phpunit --group load
vendor/bin/phpunit --group chaos
vendor/bin/phpunit --group fast
```

### Exclude Slow Tests
```bash
vendor/bin/phpunit --exclude-group slow
```

## Test Categories

### Smoke Tests
- **Purpose**: Quick validation of critical paths
- **Duration**: 30s - 2min
- **Location**: `tests/Deployment/Smoke/`
- **When**: After every deployment

### Integration Tests
- **Purpose**: End-to-end workflow validation
- **Duration**: 5-10min
- **Location**: `tests/Deployment/Integration/`
- **When**: Before production deployments

### Load Tests
- **Purpose**: Performance validation
- **Duration**: 5-15min
- **Location**: `tests/Deployment/Load/`
- **When**: Before major releases

### Chaos Tests
- **Purpose**: Failure scenario testing
- **Duration**: 10-20min
- **Location**: `tests/Deployment/Chaos/`
- **When**: Monthly or before critical deployments

## Pre-Deployment Checklist

- [ ] Run smoke tests
- [ ] Run integration tests
- [ ] Review test reports
- [ ] Verify backups are working
- [ ] Check disk space
- [ ] Verify database connectivity
- [ ] Verify Redis connectivity
- [ ] Check queue workers
- [ ] Review recent logs

## Post-Deployment Checklist

- [ ] Run smoke tests immediately
- [ ] Verify health endpoints
- [ ] Check application logs
- [ ] Monitor error rates
- [ ] Verify database migrations
- [ ] Check cache functionality
- [ ] Test critical user flows
- [ ] Monitor performance metrics

## Troubleshooting

### Tests Fail - Database Connection
```bash
# Check .env configuration
cat .env | grep DB_

# Test connection
php artisan db:show

# Run migrations
php artisan migrate --force
```

### Tests Fail - Redis Connection
```bash
# Check .env configuration
cat .env | grep REDIS_

# Test Redis
redis-cli ping

# Or skip Redis tests
vendor/bin/phpunit --exclude-group redis
```

### Tests Fail - Permissions
```bash
# Fix storage permissions
chmod -R 775 storage bootstrap/cache
chown -R www-data:www-data storage bootstrap/cache

# Create missing directories
mkdir -p storage/app/backups
mkdir -p storage/logs
```

### Tests Timeout
```bash
# Increase timeout
vendor/bin/phpunit --timeout=600

# Or use environment variable
export PHPUNIT_TIMEOUT=600
```

### Script Not Executable
```bash
# Make scripts executable
chmod +x chom/scripts/*.sh
chmod +x tests/Deployment/run-deployment-tests.sh
```

## Performance Targets

### Smoke Tests
- Database connectivity: < 100ms
- Redis connectivity: < 50ms
- Homepage response: < 500ms
- Health endpoint: < 200ms

### Integration Tests
- Pre-deployment checks: < 15s
- Health checks: < 10s
- Full deployment: < 5min
- Rollback: < 3min

### Load Tests
- DB operations: < 10ms avg
- Cache operations: < 5ms avg
- Queue dispatch: < 2ms avg
- Session operations: < 1ms avg

## Test Reports Location

```
storage/test-reports/deployment_<timestamp>/
├── summary.txt           # Overall results
├── smoke.log            # Smoke test log
├── integration.log      # Integration test log
├── load.log             # Load test log
├── chaos.log            # Chaos test log
└── coverage-*/          # Coverage reports
```

## CI/CD Integration

### GitHub Actions
- Workflow: `.github/workflows/deployment-tests.yml`
- Triggers: Push to main/develop, PRs, manual
- Jobs: smoke-tests, integration-tests, load-tests, chaos-tests

### Manual Trigger
1. Go to Actions tab
2. Select "Deployment Tests"
3. Click "Run workflow"
4. Choose test suite
5. Run

## Environment Variables

### Test Configuration
```bash
# PHPUnit timeout
export PHPUNIT_TIMEOUT=600

# Health check configuration
export HEALTH_CHECK_TIMEOUT=30
export HEALTH_CHECK_RETRIES=5
export HEALTH_CHECK_RETRY_DELAY=5

# Deployment configuration
export BACKUP_RETENTION_DAYS=7
export MAINTENANCE_RETRY_SECONDS=60
```

## Quick Test Scenarios

### Before Deployment
```bash
# Quick validation
./tests/Deployment/run-deployment-tests.sh --smoke-only

# Full validation
./tests/Deployment/run-deployment-tests.sh --integration-only
```

### After Deployment
```bash
# Immediate validation
./tests/Deployment/run-deployment-tests.sh --smoke-only

# Health check
./chom/scripts/health-check.sh
```

### Performance Testing
```bash
# Load tests
./tests/Deployment/run-deployment-tests.sh --load --verbose

# View results
cat storage/test-reports/*/summary.txt
```

### Failure Testing
```bash
# Chaos tests
./tests/Deployment/run-deployment-tests.sh --chaos

# Specific failure scenario
vendor/bin/phpunit --filter test_deployment_handles_database_connection_failure
```

## Helper Scripts

### View Latest Test Results
```bash
cat storage/test-reports/*/summary.txt | tail -20
```

### Clean Old Test Reports
```bash
find storage/test-reports -type d -mtime +7 -exec rm -rf {} +
```

### Count Test Files
```bash
find tests/Deployment -name "*Test.php" | wc -l
```

### List All Tests
```bash
vendor/bin/phpunit --list-tests tests/Deployment/
```

## Key Files

| File | Purpose |
|------|---------|
| `run-deployment-tests.sh` | Test runner script |
| `DeploymentTestCase.php` | Base test class |
| `MockEnvironment.php` | Environment mocking |
| `README.md` | Full documentation |
| `PERFORMANCE-BENCHMARKS.md` | Performance SLAs |
| `QUICK-REFERENCE.md` | This file |

## Support

- Full documentation: `tests/Deployment/README.md`
- Performance benchmarks: `tests/Deployment/PERFORMANCE-BENCHMARKS.md`
- Main project docs: Project root documentation

## Test Writing Guidelines

### Test Naming
```php
// Good
test_deployment_creates_backup()
test_health_check_validates_database()

// Bad
testDeployment()
test1()
```

### Test Structure (AAA Pattern)
```php
public function test_example(): void
{
    // Arrange - Set up test conditions
    $backupCount = $this->countBackups();

    // Act - Execute the action
    $result = $this->executeScript('deploy.sh');

    // Assert - Verify results
    $this->assertTrue($result['successful']);
}
```

### Groups and Tags
```php
/**
 * @group smoke
 * @group fast
 */
public function test_critical_path(): void
{
    // Test code
}
```

## Version Information

- PHP: 8.2+
- PHPUnit: 11.5+
- Laravel: 12.0+
- Node.js: 20+

## Last Updated

2026-01-02
