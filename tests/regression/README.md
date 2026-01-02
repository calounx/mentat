# Deployment Workflows Regression Test Suite

## Overview

Comprehensive test suite for validating all deployment scripts and workflows before production deployment. This suite tests 67 individual scenarios across 12 test categories to ensure production readiness.

## Quick Start

### Prerequisites

- Docker container `landsraad_tst` running at IP `10.10.100.20`
- SSH access configured to test container
- CHOM application installed at `/opt/chom` in container

### Run Quick Test (2 minutes)

```bash
./quick-deployment-test.sh
```

Tests 10 critical deployment components in under 2 minutes.

### Run Full Test Suite (7-10 minutes)

```bash
./deployment-workflows-test.sh
```

Executes all 67 test cases with comprehensive validation.

## Test Files

| File | Purpose | Duration |
|------|---------|----------|
| `quick-deployment-test.sh` | Fast validation of critical components | 2 min |
| `deployment-workflows-test.sh` | Complete test suite (67 tests) | 7-10 min |
| `DEPLOYMENT_TESTING_GUIDE.md` | Detailed testing documentation | - |
| `TEST_EXECUTION_REPORT.md` | Test results and analysis template | - |

## Test Coverage

### 67 Test Cases Across 12 Suites

1. **Pre-deployment Checks** (8 tests)
   - Environment validation
   - Dependency verification
   - Connectivity checks

2. **Basic Health Checks** (8 tests)
   - HTTP endpoints
   - Service connectivity
   - Application health

3. **Enhanced Health Checks** (7 tests)
   - System resources
   - Multiple output formats
   - Advanced monitoring

4. **Production Deployment** (8 tests)
   - Deployment workflow
   - Backup creation
   - Cache optimization

5. **Blue-Green Deployment** (5 tests)
   - Atomic switching
   - Zero-downtime
   - Rollback capability

6. **Canary Deployment** (4 tests)
   - Gradual rollout
   - Metrics monitoring
   - Auto-rollback

7. **Rollback Functionality** (6 tests)
   - Code rollback
   - Migration rollback
   - Dependency restoration

8. **Backup and Restore** (3 tests)
   - Backup creation
   - Retention policy
   - Restore validation

9. **Error Handling** (6 tests)
   - Failure scenarios
   - Graceful degradation
   - Recovery mechanisms

10. **Performance & Timing** (3 tests)
    - SLA compliance
    - Response times
    - Resource usage

11. **VPS Setup Scripts** (3 tests)
    - Script validation
    - Dependency checking
    - Service configuration

12. **CI/CD Pipeline** (6 tests)
    - Workflow validation
    - Security scanning
    - Automated deployment

## Scripts Tested

### Core Deployment Scripts

- `chom/scripts/deploy-production.sh` - Main production deployment
- `chom/scripts/deploy-blue-green.sh` - Blue-green deployment
- `chom/scripts/deploy-canary.sh` - Canary deployment
- `chom/scripts/pre-deployment-check.sh` - Pre-deployment validation
- `chom/scripts/health-check.sh` - Basic health checks
- `chom/scripts/health-check-enhanced.sh` - Advanced health checks
- `chom/scripts/rollback.sh` - Rollback functionality

### Infrastructure Scripts

- `chom/deploy/scripts/setup-vpsmanager-vps.sh` - VPS manager setup
- `chom/deploy/scripts/setup-observability-vps.sh` - Observability setup

### CI/CD Workflows

- `.github/workflows/deploy-production.yml` - GitHub Actions pipeline

## Usage Examples

### Basic Execution

```bash
# Quick validation
./quick-deployment-test.sh

# Full test suite
./deployment-workflows-test.sh

# Verbose output
./deployment-workflows-test.sh --verbose

# Stop on first failure
./deployment-workflows-test.sh --stop-on-failure
```

### Custom Container

```bash
./deployment-workflows-test.sh \
  --container my_container \
  --ip 192.168.1.100
```

### Generate Reports

```bash
# JSON report
./deployment-workflows-test.sh --output json

# JUnit XML (for CI/CD)
./deployment-workflows-test.sh --output junit
```

## Expected Results

### Success Output

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

### Performance Benchmarks

| Operation | Target | Status |
|-----------|--------|--------|
| Pre-deployment checks | < 15s | PASS |
| Health checks | < 30s | PASS |
| Full deployment | < 5min | PASS |
| Rollback | < 3min | PASS |
| Blue-green switch | < 1s | PASS |

## Critical Tests

These 6 tests MUST pass for production deployment:

1. **predeployment_01**: All pre-deployment checks pass
2. **health_01**: Basic health check execution
3. **production_03**: Maintenance mode toggle
4. **production_07**: Rollback mechanism
5. **bluegreen_02**: Atomic symlink switching
6. **backup_01**: Backup creation

If any critical test fails, **DO NOT DEPLOY TO PRODUCTION**.

## Test Environment Setup

### Docker Container Setup

```bash
# Start test container
docker start landsraad_tst

# Verify container IP
docker inspect landsraad_tst | grep IPAddress

# Test SSH access
ssh root@10.10.100.20 "echo 'SSH OK'"
```

### CHOM Installation

```bash
# Install CHOM in container
ssh root@10.10.100.20 << 'EOF'
cd /opt
git clone https://github.com/your-repo/chom.git
cd chom
composer install
cp .env.example .env
php artisan key:generate
EOF
```

## Troubleshooting

### Container Not Running

```bash
docker ps -a | grep landsraad_tst
docker start landsraad_tst
```

### SSH Connection Failed

```bash
# Check SSH service
ssh root@10.10.100.20 "systemctl status sshd"

# Reset SSH config
ssh-keygen -R 10.10.100.20
```

### Tests Failing

```bash
# Run in verbose mode
./deployment-workflows-test.sh --verbose

# Check container logs
docker logs landsraad_tst

# Access container shell
docker exec -it landsraad_tst bash
```

## Integration with CI/CD

### GitHub Actions

```yaml
name: Deployment Tests

on:
  pull_request:
    paths:
      - 'chom/scripts/**'

jobs:
  test-deployments:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up test environment
        run: docker run -d --name landsraad_tst debian:13

      - name: Run deployment tests
        run: ./tests/regression/deployment-workflows-test.sh --output junit

      - name: Upload results
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: /tmp/deployment-test-report-*.xml
```

## Documentation

- **Detailed Guide**: `DEPLOYMENT_TESTING_GUIDE.md` - Complete testing documentation
- **Execution Report**: `TEST_EXECUTION_REPORT.md` - Test results template
- **Main README**: This file - Quick reference

## Performance Baselines

### Reference Timings (4 CPU, 8GB RAM)

| Test Suite | Tests | Avg Time |
|------------|-------|----------|
| Pre-deployment Checks | 8 | 45s |
| Basic Health Checks | 8 | 60s |
| Enhanced Health Checks | 7 | 80s |
| Production Deployment | 8 | 30s |
| Blue-Green Deployment | 5 | 25s |
| Canary Deployment | 4 | 15s |
| Rollback Functionality | 6 | 20s |
| Backup and Restore | 3 | 10s |
| Error Handling | 6 | 20s |
| Performance & Timing | 3 | 60s |
| VPS Setup Scripts | 3 | 5s |
| CI/CD Pipeline | 6 | 5s |
| **TOTAL** | **67** | **375s** |

## Success Criteria

For production deployment authorization, ensure:

- [ ] All 67 tests pass
- [ ] All 6 critical tests pass
- [ ] Performance within SLA targets
- [ ] No unresolved warnings
- [ ] Rollback tested successfully
- [ ] Backup creation verified
- [ ] Health checks accurate
- [ ] Zero-downtime confirmed

## Support

### Resources

- **Repository**: `/home/calounx/repositories/mentat`
- **Scripts**: `/home/calounx/repositories/mentat/chom/scripts/`
- **Documentation**: `/home/calounx/repositories/mentat/docs/`

### Common Issues

1. **SSH Timeout**: Increase connection timeout or check network
2. **Container Not Found**: Verify container name and status
3. **CHOM Not Installed**: Run installation script
4. **Service Not Running**: Check service status in container
5. **Tests Timing Out**: Increase timeout values

## Next Steps

1. Run quick test to validate setup
2. Review any failures and fix issues
3. Run full test suite
4. Generate reports for documentation
5. Review performance against SLA
6. Get approval for production deployment

## Version History

- **v1.0** (2026-01-02): Initial comprehensive test suite
  - 67 test cases across 12 suites
  - Support for multiple output formats
  - Quick and full test modes
  - CI/CD integration

## License

Same as parent project (CHOM/Mentat)

## Contributors

Automated test suite developed for production deployment validation.
