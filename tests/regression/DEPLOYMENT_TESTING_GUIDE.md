# Deployment Workflows Testing Guide

## Overview

This guide covers comprehensive testing of all deployment scripts and workflows for production readiness. The test suite validates 67 individual test cases across 12 test suites.

## Test Environment Setup

### Prerequisites

1. **Docker Container**: `landsraad_tst` running at IP `10.10.100.20`
2. **SSH Access**: Configured SSH access to test container
3. **CHOM Installation**: Laravel application installed at `/opt/chom`
4. **Required Services**: Nginx, PHP-FPM, MySQL/MariaDB, Redis

### Container Setup

```bash
# Start test container (if not running)
docker start landsraad_tst

# Verify SSH access
ssh root@10.10.100.20 "echo 'SSH OK'"

# Install CHOM in container (if needed)
ssh root@10.10.100.20 "cd /opt && git clone https://github.com/your-repo/chom.git"
```

## Running the Test Suite

### Basic Execution

```bash
cd /home/calounx/repositories/mentat
./tests/regression/deployment-workflows-test.sh
```

### Advanced Options

```bash
# Run with verbose output
./tests/regression/deployment-workflows-test.sh --verbose

# Stop on first failure
./tests/regression/deployment-workflows-test.sh --stop-on-failure

# Use custom container
./tests/regression/deployment-workflows-test.sh --container my_test_container --ip 10.10.100.30

# Generate JSON report
./tests/regression/deployment-workflows-test.sh --output json

# Generate JUnit XML report (for CI/CD)
./tests/regression/deployment-workflows-test.sh --output junit
```

## Test Suites

### Suite 1: Pre-deployment Checks (8 tests)

Validates the pre-deployment check script functionality:

- **predeployment_01**: All checks pass
- **predeployment_02**: Detect missing .env file
- **predeployment_03**: Disk space verification
- **predeployment_04**: PHP version check
- **predeployment_05**: Database connectivity
- **predeployment_06**: Redis connectivity
- **predeployment_07**: Storage permissions
- **predeployment_08**: Exit code validation

**Target**: All checks should complete in < 15 seconds

### Suite 2: Basic Health Checks (8 tests)

Tests the basic health check script:

- **health_01**: Basic execution
- **health_02**: HTTP endpoint checks
- **health_03**: Database health
- **health_04**: Redis health
- **health_05**: Cache functionality
- **health_06**: Storage write capability
- **health_07**: Response time measurement
- **health_08**: Exit code validation

**Target**: Health checks should complete in < 30 seconds

### Suite 3: Enhanced Health Checks (7 tests)

Validates enhanced health monitoring:

- **health_enhanced_01**: All enhanced checks
- **health_enhanced_02**: JSON output format
- **health_enhanced_03**: Prometheus metrics format
- **health_enhanced_04**: CPU usage monitoring
- **health_enhanced_05**: Memory usage monitoring
- **health_enhanced_06**: Service status checks (Nginx, PHP-FPM, MySQL, Redis)
- **health_enhanced_07**: SSL certificate validation

**Features**:
- Multiple output formats (text, JSON, Prometheus)
- System resource monitoring
- Service health validation
- SSL certificate expiry checking

### Suite 4: Production Deployment Workflow (8 tests)

Tests the main production deployment script:

- **production_01**: Script validation (syntax check)
- **production_02**: Backup creation
- **production_03**: Maintenance mode enable/disable
- **production_04**: Composer install
- **production_05**: Cache optimization
- **production_06**: Queue worker restart
- **production_07**: Rollback mechanism
- **production_08**: Deployment logging

**Target**: Full deployment should complete in < 5 minutes

**Validates**:
- Zero-downtime deployment
- Automatic backup before deployment
- Maintenance mode handling
- Dependency installation
- Cache optimization
- Queue worker management
- Rollback capability
- Comprehensive logging

### Suite 5: Blue-Green Deployment (5 tests)

Tests blue-green deployment strategy:

- **bluegreen_01**: Directory structure creation
- **bluegreen_02**: Atomic symlink switching
- **bluegreen_03**: Pre-switch health checks
- **bluegreen_04**: Rollback capability
- **bluegreen_05**: Old release cleanup

**Target**: Atomic switch should complete in < 1 second

**Validates**:
- Separate blue and green environments
- Atomic traffic switching
- Health validation before switch
- Instant rollback capability
- Disk space management

### Suite 6: Canary Deployment (4 tests)

Tests canary deployment with gradual rollout:

- **canary_01**: Traffic splitting configuration
- **canary_02**: Metrics collection capability
- **canary_03**: Gradual rollout stages (10%, 25%, 50%, 75%, 100%)
- **canary_04**: Automatic rollback on threshold breach

**Validates**:
- Traffic splitting via Nginx upstream
- Prometheus metrics integration
- Gradual traffic shift
- Automatic rollback on errors

### Suite 7: Rollback Functionality (6 tests)

Tests rollback script functionality:

- **rollback_01**: Script syntax validation
- **rollback_02**: Commit identification
- **rollback_03**: Migration counting
- **rollback_04**: Pre-rollback backup
- **rollback_05**: Cache clearing
- **rollback_06**: Dependency restoration

**Target**: Rollback should complete in < 3 minutes

**Validates**:
- Git-based code rollback
- Migration rollback
- Backup creation
- Dependency restoration
- Cache management

### Suite 8: Backup and Restore (3 tests)

Tests backup functionality:

- **backup_01**: Backup file creation
- **backup_02**: Retention policy (keep last 7 days)
- **backup_03**: Backup file verification

**Validates**:
- Database backup creation
- Backup file integrity
- Automatic cleanup of old backups

### Suite 9: Error Handling & Edge Cases (6 tests)

Tests error scenarios and edge cases:

- **error_01**: Network failure handling
- **error_02**: Disk full detection
- **error_03**: Composer timeout handling
- **error_04**: NPM build failure handling
- **error_05**: Migration failure handling
- **error_06**: Graceful error messages

**Validates**:
- Timeout handling
- Resource constraint detection
- Dependency installation failures
- Build failures
- Migration errors
- Error reporting

### Suite 10: Performance & Timing (3 tests)

Measures performance against SLA targets:

- **performance_01**: Pre-deployment check timing (< 15s)
- **performance_02**: Health check timing (< 30s)
- **performance_03**: Cache optimization timing

**SLA Targets**:
- Pre-deployment checks: < 15 seconds
- Health checks: < 30 seconds
- Full deployment: < 5 minutes
- Rollback: < 3 minutes
- Blue-green switch: < 1 second

### Suite 11: VPS Setup Scripts (3 tests)

Validates VPS setup automation:

- **vps_01**: Script syntax validation
- **vps_02**: Dependency checking
- **vps_03**: Service configuration

**Scripts Tested**:
- `setup-vpsmanager-vps.sh`
- `setup-observability-vps.sh`

### Suite 12: CI/CD Pipeline (6 tests)

Tests GitHub Actions workflow:

- **cicd_01**: YAML syntax validation
- **cicd_02**: Build stage configuration
- **cicd_03**: Security scanning stage
- **cicd_04**: Deployment stage
- **cicd_05**: Smoke tests stage
- **cicd_06**: Rollback on failure

**Validates**:
- Workflow syntax
- Multi-stage pipeline
- Security scanning integration
- Automated deployment
- Post-deployment testing
- Automatic rollback

## Expected Results

### Success Criteria

All 67 tests should pass for production readiness:

```
Total Tests:    67
Passed:         67 (100%)
Failed:         0
Skipped:        0

Production readiness: VERIFIED
```

### Performance Benchmarks

| Operation | Target | Acceptable |
|-----------|--------|------------|
| Pre-deployment checks | < 15s | < 20s |
| Health checks | < 30s | < 45s |
| Full deployment | < 5min | < 7min |
| Rollback | < 3min | < 5min |
| Blue-green switch | < 1s | < 2s |
| Cache optimization | < 30s | < 60s |

### Common Issues

#### Issue: SSH Connection Failed

```bash
# Solution: Check container status and SSH service
docker ps | grep landsraad_tst
ssh root@10.10.100.20 "systemctl status sshd"
```

#### Issue: CHOM Not Installed

```bash
# Solution: Install CHOM in container
ssh root@10.10.100.20 << 'EOF'
cd /opt
git clone https://github.com/your-repo/chom.git
cd chom
composer install
cp .env.example .env
php artisan key:generate
EOF
```

#### Issue: Missing Dependencies

```bash
# Solution: Install required services
ssh root@10.10.100.20 << 'EOF'
apt-get update
apt-get install -y nginx php8.2-fpm mysql-server redis-server
EOF
```

#### Issue: Test Timeouts

```bash
# Solution: Increase timeout or check service status
ssh root@10.10.100.20 "systemctl status nginx php8.2-fpm mysql redis"
```

## Test Reports

### Text Output (Default)

Human-readable output with color-coded results:

```
=========================================
TEST SUITE 1: Pre-deployment Checks (8 tests)
=========================================
[TEST] predeployment_01: All pre-deployment checks pass
✓ PASSED: predeployment_01
  Duration: 12s
...
```

### JSON Output

Machine-readable JSON format:

```bash
./tests/regression/deployment-workflows-test.sh --output json
```

Output file: `/tmp/deployment-test-report-TIMESTAMP.json`

```json
{
  "timestamp": "2026-01-02T15:30:00Z",
  "summary": {
    "total": 67,
    "passed": 67,
    "failed": 0,
    "skipped": 0,
    "duration": 450
  },
  "tests": {
    "predeployment_01": {
      "status": "PASS",
      "duration": 12,
      "message": "All checks passed"
    }
  }
}
```

### JUnit XML Output

CI/CD compatible XML format:

```bash
./tests/regression/deployment-workflows-test.sh --output junit
```

Output file: `/tmp/deployment-test-report-TIMESTAMP.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuites tests="67" failures="0" skipped="0" time="450">
  <testsuite name="DeploymentWorkflows" tests="67" failures="0" skipped="0">
    <testcase name="predeployment_01" time="12"/>
    ...
  </testsuite>
</testsuites>
```

## Integration with CI/CD

### GitHub Actions Integration

Add to `.github/workflows/test-deployments.yml`:

```yaml
name: Deployment Workflow Tests

on:
  pull_request:
    paths:
      - 'chom/scripts/**'
      - '.github/workflows/**'
  push:
    branches:
      - main

jobs:
  test-deployment-workflows:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up test environment
        run: |
          docker run -d --name landsraad_tst \
            --network custom_network \
            -p 10.10.100.20:22:22 \
            debian:13

      - name: Run deployment tests
        run: |
          ./tests/regression/deployment-workflows-test.sh \
            --container landsraad_tst \
            --output junit

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: deployment-test-results
          path: /tmp/deployment-test-report-*.xml
```

## Manual Testing Scenarios

### Scenario 1: Full Production Deployment

```bash
# In landsraad_tst container
cd /opt/chom

# Run pre-deployment checks
./scripts/pre-deployment-check.sh

# Run deployment
./scripts/deploy-production.sh

# Verify health
./scripts/health-check.sh
```

### Scenario 2: Blue-Green Deployment

```bash
# Deploy to GREEN environment
VERSION=$(date +%Y%m%d_%H%M%S)
ARTIFACT_PATH=/tmp/chom-${VERSION}.tar.gz

# Create artifact
tar -czf $ARTIFACT_PATH -C /opt/chom .

# Run blue-green deployment
APP_PATH=/var/www/chom \
RELEASES_PATH=/var/www/releases \
VERSION=$VERSION \
ARTIFACT_PATH=$ARTIFACT_PATH \
./scripts/deploy-blue-green.sh
```

### Scenario 3: Canary Deployment

```bash
# Deploy canary version
VERSION=$(date +%Y%m%d_%H%M%S)
CANARY_STAGES="10,25,50,75,100"
CANARY_INTERVAL=60

./scripts/deploy-canary.sh
```

### Scenario 4: Rollback

```bash
# Rollback last deployment
./scripts/rollback.sh --steps 1

# Rollback to specific commit
./scripts/rollback.sh --commit abc123def

# Rollback without migrations
./scripts/rollback.sh --skip-migrations
```

## Troubleshooting

### Debug Mode

Enable verbose output for detailed debugging:

```bash
VERBOSE=true ./tests/regression/deployment-workflows-test.sh --verbose
```

### Individual Test Execution

Run a specific test function:

```bash
# Source the test script
source ./tests/regression/deployment-workflows-test.sh

# Run specific test
test_predeployment_all_checks_pass
```

### Container Shell Access

Access container for manual testing:

```bash
# SSH into container
ssh root@10.10.100.20

# Or use docker exec
docker exec -it landsraad_tst bash
```

### Log Files

Check deployment logs:

```bash
# On container
ssh root@10.10.100.20 "tail -f /opt/chom/storage/logs/deployment_*.log"

# Health check logs
ssh root@10.10.100.20 "tail -f /var/log/chom/health_*.log"
```

## Maintenance

### Updating Tests

When adding new deployment features:

1. Add test function to test suite
2. Add to appropriate test suite section in `main()`
3. Update test count in documentation
4. Run full test suite to verify

### Test Data Cleanup

Clean up test artifacts:

```bash
# On container
ssh root@10.10.100.20 << 'EOF'
rm -f /tmp/test_*
rm -f /opt/chom/storage/app/backups/test_*
rm -rf /var/www/releases/test_*
EOF
```

## Performance Baselines

### Reference Timings (Debian 13, 4 CPU, 8GB RAM)

| Test Suite | Tests | Avg Time | Max Time |
|------------|-------|----------|----------|
| Pre-deployment Checks | 8 | 45s | 60s |
| Basic Health Checks | 8 | 60s | 90s |
| Enhanced Health Checks | 7 | 80s | 120s |
| Production Deployment | 8 | 30s | 45s |
| Blue-Green Deployment | 5 | 25s | 40s |
| Canary Deployment | 4 | 15s | 25s |
| Rollback Functionality | 6 | 20s | 35s |
| Backup and Restore | 3 | 10s | 20s |
| Error Handling | 6 | 20s | 30s |
| Performance & Timing | 3 | 60s | 90s |
| VPS Setup Scripts | 3 | 5s | 10s |
| CI/CD Pipeline | 6 | 5s | 10s |
| **TOTAL** | **67** | **375s** | **575s** |

## Success Indicators

### All Tests Pass

```
=========================================
  TEST EXECUTION SUMMARY
=========================================
Total Tests:    67
Passed:         67 (100%)
Failed:         0
Skipped:        0
Total Duration: 425s

ALL TESTS PASSED!

Production readiness: VERIFIED
```

### Critical Tests Must Pass

Even if some tests fail, these are critical for production:

1. **predeployment_01**: All pre-deployment checks pass
2. **health_01**: Basic health check execution
3. **production_03**: Maintenance mode
4. **production_07**: Rollback mechanism
5. **bluegreen_02**: Atomic symlink switch
6. **rollback_01**: Script validation
7. **backup_01**: Backup creation

If any critical test fails, **DO NOT DEPLOY TO PRODUCTION**.

## Next Steps

After successful test execution:

1. Review performance benchmarks against SLA targets
2. Address any warnings or degraded performance
3. Document any test failures and resolutions
4. Update deployment runbooks with findings
5. Schedule production deployment window
6. Prepare rollback plan based on test results

## Contact & Support

For issues or questions:

- **Repository**: https://github.com/your-repo/mentat
- **Documentation**: `/docs/deployment/`
- **Issues**: https://github.com/your-repo/mentat/issues
