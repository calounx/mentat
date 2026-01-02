# Deployment Test Suite

Comprehensive test suite for validating deployment pipeline scripts and workflows.

## Overview

This test suite provides comprehensive testing for the deployment pipeline including:

- **Integration Tests**: End-to-end testing of deployment workflows
- **Smoke Tests**: Quick validation of critical paths
- **Load Tests**: Performance testing under deployment scenarios
- **Chaos Tests**: Failure scenario and recovery testing

## Table of Contents

- [Quick Start](#quick-start)
- [Test Structure](#test-structure)
- [Running Tests](#running-tests)
- [Test Categories](#test-categories)
- [CI/CD Integration](#cicd-integration)
- [Performance Benchmarks](#performance-benchmarks)
- [Troubleshooting](#troubleshooting)

## Quick Start

### Prerequisites

- PHP 8.2+
- Composer
- Node.js 20+
- MySQL or SQLite
- Redis (optional, but recommended)
- Git

### Running All Tests

```bash
# Run all deployment tests
./tests/Deployment/run-deployment-tests.sh --all

# Run smoke tests only (fastest)
./tests/Deployment/run-deployment-tests.sh --smoke-only

# Run integration tests
./tests/Deployment/run-deployment-tests.sh --integration-only
```

### Running Specific Test Suites

```bash
# Smoke tests
vendor/bin/phpunit --filter 'Tests\\Deployment\\Smoke'

# Integration tests
vendor/bin/phpunit --filter 'Tests\\Deployment\\Integration'

# Load tests
vendor/bin/phpunit --filter 'Tests\\Deployment\\Load'

# Chaos tests
vendor/bin/phpunit --filter 'Tests\\Deployment\\Chaos'
```

## Test Structure

```
tests/Deployment/
├── README.md                          # This file
├── run-deployment-tests.sh            # Test runner script
├── Helpers/
│   ├── DeploymentTestCase.php         # Base test case
│   └── MockEnvironment.php            # Environment mocking utilities
├── Integration/
│   ├── PreDeploymentCheckTest.php     # Pre-deployment validation tests
│   ├── HealthCheckTest.php            # Health check script tests
│   ├── DeploymentWorkflowTest.php     # Full deployment workflow tests
│   └── RollbackWorkflowTest.php       # Rollback workflow tests
├── Smoke/
│   ├── CriticalPathTest.php           # Critical functionality tests
│   └── EndpointAvailabilityTest.php   # HTTP endpoint tests
├── Load/
│   └── DeploymentPerformanceTest.php  # Performance tests
└── Chaos/
    └── FailureScenarioTest.php        # Failure handling tests
```

## Running Tests

### Test Runner Script

The automated test runner provides a convenient way to execute test suites:

```bash
./tests/Deployment/run-deployment-tests.sh [OPTIONS]
```

**Options:**

- `--smoke-only`: Run only smoke tests (fast, critical paths)
- `--integration-only`: Run only integration tests
- `--load`: Include load/performance tests
- `--chaos`: Include chaos/failure tests
- `--all`: Run all test suites
- `--parallel`: Run tests in parallel (experimental)
- `--coverage`: Generate code coverage report
- `--verbose`, `-v`: Verbose output
- `--help`, `-h`: Show help message

**Examples:**

```bash
# Quick smoke tests before deployment
./tests/Deployment/run-deployment-tests.sh --smoke-only

# Full test suite with coverage
./tests/Deployment/run-deployment-tests.sh --all --coverage

# Integration tests with verbose output
./tests/Deployment/run-deployment-tests.sh --integration-only -v

# Load and chaos tests
./tests/Deployment/run-deployment-tests.sh --load --chaos
```

### PHPUnit Direct Execution

You can also run tests directly with PHPUnit:

```bash
# Run specific test class
vendor/bin/phpunit tests/Deployment/Integration/PreDeploymentCheckTest.php

# Run with specific group
vendor/bin/phpunit --group smoke
vendor/bin/phpunit --group integration
vendor/bin/phpunit --group load
vendor/bin/phpunit --group chaos

# Run specific test method
vendor/bin/phpunit --filter test_pre_deployment_checks_pass_with_valid_environment

# Generate coverage report
vendor/bin/phpunit --coverage-html storage/coverage tests/Deployment/
```

## Test Categories

### 1. Integration Tests

**Purpose**: Validate complete deployment workflows end-to-end.

**Location**: `tests/Deployment/Integration/`

**Coverage**:
- Pre-deployment checks (system requirements, dependencies, connectivity)
- Health checks (database, Redis, cache, endpoints)
- Full deployment workflow (backup, migration, cache optimization)
- Rollback procedures (code, database, dependencies)

**Run Time**: 5-10 minutes

**When to Run**:
- Before production deployments
- After major infrastructure changes
- As part of CI/CD pipeline

**Example**:
```bash
./tests/Deployment/run-deployment-tests.sh --integration-only
```

### 2. Smoke Tests

**Purpose**: Quick validation of critical functionality after deployment.

**Location**: `tests/Deployment/Smoke/`

**Coverage**:
- Database connectivity
- Redis connectivity
- HTTP endpoint availability
- Cache functionality
- Session handling
- Storage permissions
- Configuration validation

**Run Time**: 30 seconds - 2 minutes

**When to Run**:
- Immediately after deployment
- As first step in test pipeline
- For quick health checks

**Example**:
```bash
./tests/Deployment/run-deployment-tests.sh --smoke-only
```

### 3. Load Tests

**Purpose**: Validate performance under expected load conditions.

**Location**: `tests/Deployment/Load/`

**Coverage**:
- Database connection pool performance
- Cache operation performance
- Queue job dispatch performance
- Session operation performance
- File system operation performance
- Memory usage during operations
- Response time under load

**Run Time**: 5-15 minutes

**When to Run**:
- Before production deployments
- After performance optimizations
- During capacity planning

**Example**:
```bash
./tests/Deployment/run-deployment-tests.sh --load
```

### 4. Chaos Tests

**Purpose**: Test system resilience and failure handling.

**Location**: `tests/Deployment/Chaos/`

**Coverage**:
- Low disk space scenarios
- Database connection failures
- Redis connection failures
- Migration failures and rollback
- Permission denied scenarios
- Concurrent deployment attempts
- Corrupted cache handling
- Timeout scenarios

**Run Time**: 10-20 minutes

**When to Run**:
- Before critical deployments
- During disaster recovery planning
- Periodically (monthly recommended)

**Example**:
```bash
./tests/Deployment/run-deployment-tests.sh --chaos
```

## CI/CD Integration

### GitHub Actions

The deployment test suite integrates with GitHub Actions. The workflow file is located at:

`.github/workflows/deployment-tests.yml`

**Automatic Triggers**:
- Push to `main`, `develop`, or `release/**` branches
- Pull requests to `main` or `develop`
- Manual workflow dispatch

**Manual Execution**:

1. Go to Actions tab in GitHub
2. Select "Deployment Tests" workflow
3. Click "Run workflow"
4. Select test suite (smoke, integration, all, load, chaos)
5. Click "Run workflow"

**Available Jobs**:
- `smoke-tests`: Fast critical path validation
- `integration-tests`: Full deployment workflow validation
- `load-tests`: Performance validation
- `chaos-tests`: Failure scenario validation
- `test-summary`: Aggregated results

### GitLab CI/CD

For GitLab CI/CD, create `.gitlab-ci.yml`:

```yaml
deployment-tests:
  stage: test
  image: php:8.2
  services:
    - mysql:8.0
    - redis:7-alpine
  script:
    - ./tests/Deployment/run-deployment-tests.sh --all
  artifacts:
    paths:
      - storage/test-reports/
    expire_in: 7 days
```

### Jenkins

For Jenkins, create a pipeline job:

```groovy
pipeline {
    agent any

    stages {
        stage('Deployment Tests') {
            steps {
                sh './tests/Deployment/run-deployment-tests.sh --all --coverage'
            }
        }
    }

    post {
        always {
            junit 'storage/test-reports/**/*-junit.xml'
            publishHTML([
                reportDir: 'storage/test-reports',
                reportFiles: '*/summary.txt',
                reportName: 'Deployment Test Report'
            ])
        }
    }
}
```

## Performance Benchmarks

### Smoke Tests SLA

| Test | Target | Acceptable | Failure Threshold |
|------|--------|------------|-------------------|
| Database Connectivity | < 100ms | < 500ms | > 1000ms |
| Redis Connectivity | < 50ms | < 200ms | > 500ms |
| Cache Operations | < 10ms | < 50ms | > 100ms |
| Homepage Response | < 500ms | < 2000ms | > 5000ms |
| Health Endpoint | < 200ms | < 1000ms | > 2000ms |

### Load Tests SLA

| Test | Target | Acceptable | Failure Threshold |
|------|--------|------------|-------------------|
| DB Connection Pool (20 connections) | < 2s | < 5s | > 10s |
| Cache Operations (1000 ops) | < 5ms avg | < 10ms avg | > 20ms avg |
| Queue Dispatch (100 jobs) | < 2ms avg | < 5ms avg | > 10ms avg |
| Session Operations (500 ops) | < 1ms avg | < 2ms avg | > 5ms avg |
| File Operations (50 files) | < 10ms avg | < 20ms avg | > 50ms avg |

### Integration Tests SLA

| Test | Target | Acceptable | Failure Threshold |
|------|--------|------------|-------------------|
| Pre-deployment Checks | < 15s | < 30s | > 60s |
| Health Checks | < 10s | < 15s | > 30s |
| Full Deployment | < 5min | < 10min | > 15min |
| Rollback | < 3min | < 5min | > 10min |

## Test Reports

Test reports are generated in `storage/test-reports/deployment_<timestamp>/`:

```
storage/test-reports/deployment_20260102_120000/
├── summary.txt              # Overall test summary
├── smoke.log                # Smoke test detailed log
├── smoke-junit.xml          # JUnit format results
├── integration.log          # Integration test log
├── integration-junit.xml    # JUnit format results
├── load.log                 # Load test log
├── load-junit.xml           # JUnit format results
├── chaos.log                # Chaos test log
├── chaos-junit.xml          # JUnit format results
└── coverage-*/              # Code coverage reports (if --coverage used)
```

### Reading Test Reports

**Summary Report** (`summary.txt`):
- Overall pass/fail status
- Test counts (total, passed, failed, skipped)
- Execution duration
- Configuration used

**Detailed Logs** (`*.log`):
- Individual test results
- Assertions and failures
- Performance metrics
- Error messages and stack traces

**JUnit XML** (`*-junit.xml`):
- Machine-readable test results
- Compatible with CI/CD tools
- Test timing information

## Troubleshooting

### Common Issues

#### Tests Fail Due to Missing Dependencies

**Solution**:
```bash
# Install all dependencies
composer install
npm install

# Verify installations
php --version  # Should be 8.2+
composer --version
node --version  # Should be 20+
npm --version
```

#### Database Connection Errors

**Solution**:
```bash
# Check database configuration in .env
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=testing
DB_USERNAME=root
DB_PASSWORD=password

# Test connection
php artisan db:show
```

#### Redis Connection Errors

**Solution**:
```bash
# Check Redis configuration in .env
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_PASSWORD=

# Test connection
redis-cli ping  # Should return PONG

# Or skip Redis tests
vendor/bin/phpunit --exclude-group redis
```

#### Permission Denied Errors

**Solution**:
```bash
# Fix storage permissions
chmod -R 775 storage bootstrap/cache
chown -R www-data:www-data storage bootstrap/cache

# Create missing directories
mkdir -p storage/app/backups
mkdir -p storage/logs
mkdir -p storage/framework/{cache,sessions,views}
```

#### Script Execution Errors

**Solution**:
```bash
# Make scripts executable
chmod +x chom/scripts/*.sh
chmod +x tests/Deployment/run-deployment-tests.sh

# Check for Windows line endings (if applicable)
dos2unix chom/scripts/*.sh
dos2unix tests/Deployment/run-deployment-tests.sh
```

#### Tests Timeout

**Solution**:
```bash
# Increase PHPUnit timeout
export PHPUNIT_TIMEOUT=600

# Or increase specific test timeout
vendor/bin/phpunit --process-isolation --timeout=600
```

### Debug Mode

Run tests in verbose mode for detailed output:

```bash
# Using test runner
./tests/Deployment/run-deployment-tests.sh --verbose

# Using PHPUnit directly
vendor/bin/phpunit --verbose --debug tests/Deployment/
```

### Skipping Tests

Skip specific test groups:

```bash
# Skip slow tests
vendor/bin/phpunit --exclude-group slow

# Skip specific categories
vendor/bin/phpunit --exclude-group load,chaos

# Run only fast tests
vendor/bin/phpunit --group fast
```

## Best Practices

### Before Deployment

1. **Run smoke tests first**:
   ```bash
   ./tests/Deployment/run-deployment-tests.sh --smoke-only
   ```

2. **Run full integration tests**:
   ```bash
   ./tests/Deployment/run-deployment-tests.sh --integration-only
   ```

3. **Review test reports**:
   ```bash
   cat storage/test-reports/*/summary.txt
   ```

### After Deployment

1. **Run smoke tests immediately**:
   ```bash
   ./tests/Deployment/run-deployment-tests.sh --smoke-only
   ```

2. **Monitor for 5-10 minutes**

3. **Run health checks**:
   ```bash
   ./chom/scripts/health-check.sh
   ```

### Periodic Testing

1. **Weekly**: Run full test suite
2. **Monthly**: Run load and chaos tests
3. **Quarterly**: Review and update performance benchmarks

## Contributing

When adding new deployment functionality:

1. Write integration tests for the workflow
2. Add smoke tests for critical paths
3. Add chaos tests for failure scenarios
4. Update this documentation
5. Run full test suite before submitting PR

## Support

For issues or questions:

1. Check [Troubleshooting](#troubleshooting) section
2. Review test logs in `storage/test-reports/`
3. Check CI/CD workflow runs
4. Consult main project documentation

## License

This test suite is part of the CHOM application and follows the same license.
