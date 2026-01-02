# CHOM API Testing Guide

Comprehensive guide for testing the CHOM API using the Python/pytest test suite.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Test Environment Setup](#test-environment-setup)
3. [Running Tests](#running-tests)
4. [Test Categories](#test-categories)
5. [Load Testing](#load-testing)
6. [Interpreting Results](#interpreting-results)
7. [CI/CD Integration](#cicd-integration)
8. [Troubleshooting](#troubleshooting)

## Quick Start

### Prerequisites

- Python 3.8+ installed
- CHOM API running (locally or in Docker)
- Git repository cloned

### 5-Minute Setup

```bash
# 1. Install dependencies
pip install -r requirements-test.txt

# 2. Configure environment
cp .env.testing .env.test
# Edit .env.test if needed

# 3. Run tests
./run_tests.sh

# 4. View results
open reports/test_report.html
```

## Test Environment Setup

### Option 1: Local Development

1. **Start CHOM API locally**
   ```bash
   cd chom
   php artisan serve --port=8000
   ```

2. **Configure test environment**
   ```bash
   cp .env.testing .env.test
   nano .env.test
   ```

   Update `API_BASE_URL`:
   ```
   API_BASE_URL=http://localhost:8000/api/v1
   ```

3. **Install Python dependencies**
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements-test.txt
   ```

### Option 2: Docker Test Environment

1. **Start test environment**
   ```bash
   docker-compose -f docker-compose.test.yml up -d
   ```

2. **Wait for services to be healthy**
   ```bash
   docker-compose -f docker-compose.test.yml ps
   ```

3. **Run tests in container**
   ```bash
   docker-compose -f docker-compose.test.yml exec test-runner ./run_tests.sh
   ```

4. **View logs**
   ```bash
   docker-compose -f docker-compose.test.yml logs -f test-api
   ```

### Option 3: Using landsraad_tst Container

If you have the existing Docker setup:

```bash
# Update .env.test
API_BASE_URL=http://landsraad_tst:80/api/v1

# Or if accessing from host
API_BASE_URL=http://localhost:8000/api/v1

# Run tests
./run_tests.sh
```

## Running Tests

### Basic Execution

```bash
# Run all tests
./run_tests.sh

# Run specific category
./run_tests.sh auth
./run_tests.sh sites
./run_tests.sh backups
./run_tests.sh team

# Run with options
./run_tests.sh --verbose
./run_tests.sh --coverage
./run_tests.sh --parallel
```

### Advanced Usage

```bash
# Run specific test file
pytest tests/api/test_auth.py -v

# Run specific test class
pytest tests/api/test_auth.py::TestLogin -v

# Run specific test function
pytest tests/api/test_auth.py::TestLogin::test_login_success -v

# Run tests matching pattern
pytest tests/api/ -k "login" -v

# Run tests with marker
pytest tests/api/ -m "performance" -v

# Stop on first failure
pytest tests/api/ -x

# Show local variables on failure
pytest tests/api/ -l

# Run last failed tests
pytest tests/api/ --lf

# Parallel execution
pytest tests/api/ -n auto
```

### Selective Testing

```bash
# Critical path tests only
./run_tests.sh --critical

# Performance tests only
./run_tests.sh --performance

# Security tests only
./run_tests.sh --security

# Skip slow tests
pytest tests/api/ -m "not slow"
```

## Test Categories

### 1. Authentication Tests (test_auth.py)

**Coverage:**
- User registration
- Login/logout
- Token management
- Token refresh
- Password validation
- Rate limiting

**Example:**
```bash
./run_tests.sh auth
```

**Key Tests:**
- `test_register_success` - Valid registration
- `test_login_success` - Valid login
- `test_login_invalid_credentials` - Invalid credentials
- `test_logout_success` - Logout flow
- `test_refresh_token` - Token refresh

### 2. Site Management Tests (test_sites.py)

**Coverage:**
- List sites with pagination/filtering
- Create sites (WordPress, HTML, Laravel)
- Get site details
- Update site settings
- Delete sites
- Site actions (enable/disable/SSL)
- Site metrics

**Example:**
```bash
./run_tests.sh sites
```

**Key Tests:**
- `test_create_wordpress_site` - Create WP site
- `test_list_sites_pagination` - Pagination
- `test_update_site_php_version` - Update settings
- `test_delete_site` - Delete operation
- `test_issue_ssl_certificate` - SSL issuance

### 3. Backup Management Tests (test_backups.py)

**Coverage:**
- List backups
- Create backups (full/database/files)
- Get backup details
- Delete backups
- Download backups
- Restore from backups

**Example:**
```bash
./run_tests.sh backups
```

**Key Tests:**
- `test_create_full_backup` - Full backup
- `test_create_database_backup` - DB backup
- `test_download_backup` - Download flow
- `test_restore_backup` - Restore flow

### 4. Team Management Tests (test_team.py)

**Coverage:**
- List team members
- Invite members
- Update member roles
- Remove members
- Transfer ownership
- Organization settings

**Example:**
```bash
./run_tests.sh team
```

**Key Tests:**
- `test_list_team_members` - Member listing
- `test_invite_team_member` - Invitation
- `test_update_member_role` - Role updates
- `test_transfer_ownership` - Ownership transfer

### 5. Health Check Tests (test_health.py)

**Coverage:**
- Basic health check
- Detailed health check
- Security health check
- Performance under load

**Example:**
```bash
pytest tests/api/test_health.py -v
```

### 6. Schema Validation Tests (test_schema_validation.py)

**Coverage:**
- JSON schema validation
- Response structure validation
- Pagination schema
- Error response format

**Example:**
```bash
pytest tests/api/test_schema_validation.py -v
```

## Load Testing

### Starting Load Test

**Option 1: Web UI (Interactive)**
```bash
./run_load_test.sh
```
- Opens web UI at http://localhost:8089
- Configure users, spawn rate, duration
- View real-time graphs and statistics

**Option 2: Headless (Automated)**
```bash
# Default: 10 users for 60 seconds
./run_load_test.sh --headless

# Custom configuration
./run_load_test.sh --headless --users 50 --duration 300

# Target different environment
./run_load_test.sh --headless --host http://staging.chom.com
```

### Load Test Scenarios

The load test simulates realistic API usage:

**User Distribution:**
- 90% CHOMAPIUser (normal users)
- 10% HealthCheckUser (monitoring)

**Task Distribution (CHOMAPIUser):**
- 5 weight: List sites (very common)
- 3 weight: Get current user
- 3 weight: Get site details
- 2 weight: Create site
- 2 weight: List backups
- 1 weight: Get site metrics
- 1 weight: List team members
- 1 weight: Get organization

### Interpreting Load Test Results

**Key Metrics:**

1. **Response Time**
   - **Average:** Should be < 200ms
   - **p95:** Should be < 500ms
   - **p99:** Should be < 1000ms

2. **Throughput**
   - **Requests/sec:** Target > 100 req/s
   - **Concurrent Users:** Support 50+ users

3. **Failure Rate**
   - **Target:** < 1%
   - **Acceptable:** < 5%

**Example Good Results:**
```
Total Requests: 12,000
Failures: 8 (0.07%)
Average Response Time: 145ms
p95: 320ms
p99: 580ms
Requests/sec: 200
```

**Example Problem Indicators:**
```
Total Requests: 5,000
Failures: 250 (5%)        # Too high
Average Response Time: 450ms  # Too slow
p95: 1200ms              # Way too slow
p99: 2500ms              # Unacceptable
```

## Interpreting Results

### HTML Test Report

After running tests, open `reports/test_report.html`:

**Sections:**
- **Summary:** Pass/fail counts, duration
- **Results:** Detailed test results
- **Error Details:** Stack traces for failures
- **Environment:** Test configuration

**What to Look For:**
- Green checkmarks: Tests passed
- Red X marks: Tests failed
- Yellow warnings: Tests skipped
- Duration: Overall test time

### Coverage Report

If run with `--coverage`, open `htmlcov/index.html`:

**Metrics:**
- **Line Coverage:** % of lines executed
- **Branch Coverage:** % of code branches taken
- **Missing Lines:** Highlighted in red

**Target Coverage:**
- 80%+ overall coverage
- 90%+ for critical endpoints

### Console Output

```bash
============================= test session starts ==============================
platform linux -- Python 3.11.0, pytest-7.4.3
collected 156 items

tests/api/test_auth.py::TestRegistration::test_register_success PASSED  [ 1%]
tests/api/test_auth.py::TestLogin::test_login_success PASSED          [ 2%]
...
tests/api/test_sites.py::TestCreateSite::test_create_wordpress_site PASSED

============================== 156 passed in 45.23s ============================
```

**Understanding Output:**
- `PASSED`: Test succeeded
- `FAILED`: Test failed (see traceback)
- `SKIPPED`: Test was skipped
- `xfail`: Expected failure
- `[  1%]`: Progress percentage

### Performance Tracking

Performance tests track slow endpoints:

```
Slow API calls (>500ms):
  /sites [POST]: 623.45ms
  /backups/{id}/download: 1234.56ms
```

**Action Items:**
- Investigate slow endpoints
- Optimize database queries
- Add caching where appropriate
- Consider async operations

## CI/CD Integration

### GitHub Actions

Create `.github/workflows/api-tests.yml`:

```yaml
name: API Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      mysql:
        image: mysql:8.0
        env:
          MYSQL_DATABASE: chom_test
          MYSQL_ROOT_PASSWORD: root
        options: >-
          --health-cmd "mysqladmin ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 3306:3306

      redis:
        image: redis:7-alpine
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 6379:6379

    steps:
      - uses: actions/checkout@v3

      - name: Set up PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: '8.2'
          extensions: mbstring, xml, ctype, json, mysql, pdo, redis

      - name: Install Laravel dependencies
        run: |
          cd chom
          composer install --no-progress --prefer-dist

      - name: Prepare Laravel
        run: |
          cd chom
          cp .env.testing .env
          php artisan key:generate
          php artisan migrate --force

      - name: Start Laravel server
        run: |
          cd chom
          php artisan serve --port=8000 &
          sleep 5

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Install test dependencies
        run: pip install -r requirements-test.txt

      - name: Run tests
        run: ./run_tests.sh --coverage --parallel

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage.xml

      - name: Upload test report
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: test-report
          path: reports/
```

### GitLab CI

Create `.gitlab-ci.yml`:

```yaml
stages:
  - test
  - report

variables:
  MYSQL_DATABASE: chom_test
  MYSQL_ROOT_PASSWORD: root
  API_BASE_URL: http://localhost:8000/api/v1

test:api:
  stage: test
  image: python:3.11
  services:
    - mysql:8.0
    - redis:7-alpine
  before_script:
    - apt-get update && apt-get install -y php php-cli php-mysql php-redis
    - cd chom && composer install
    - cp .env.testing .env
    - php artisan key:generate
    - php artisan migrate --force
    - php artisan serve --port=8000 &
    - sleep 10
    - cd ..
    - pip install -r requirements-test.txt
  script:
    - ./run_tests.sh --coverage --parallel
  artifacts:
    reports:
      junit: reports/junit.xml
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml
    paths:
      - reports/
      - htmlcov/
    when: always
  coverage: '/TOTAL.*\s+(\d+%)$/'
```

## Troubleshooting

### Common Issues

#### 1. Cannot Connect to API

**Problem:**
```
ConnectionError: Failed to connect to http://localhost:8000/api/v1
```

**Solution:**
```bash
# Check if API is running
curl http://localhost:8000/api/v1/health

# Check API logs
tail -f chom/storage/logs/laravel.log

# Verify API_BASE_URL in .env.test
cat .env.test | grep API_BASE_URL

# Try starting API manually
cd chom && php artisan serve
```

#### 2. Authentication Failures

**Problem:**
```
FAILED test_login_success - AssertionError: Expected 200, got 401
```

**Solution:**
```bash
# Check Laravel config
cd chom && php artisan config:clear

# Verify Sanctum is configured
cd chom && php artisan route:list | grep api

# Test registration manually
curl -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","email":"test@test.com","password":"Test123!@#","password_confirmation":"Test123!@#","organization_name":"Test Org"}'
```

#### 3. Import Errors

**Problem:**
```
ImportError: No module named 'pytest'
```

**Solution:**
```bash
# Activate virtual environment
source venv/bin/activate

# Reinstall dependencies
pip install -r requirements-test.txt --force-reinstall

# Verify installation
pip list | grep pytest
```

#### 4. Database Errors

**Problem:**
```
SQLSTATE[HY000]: General error: 1 no such table: users
```

**Solution:**
```bash
# Run migrations
cd chom && php artisan migrate:fresh --force

# Seed database
cd chom && php artisan db:seed --force

# Check database connection
cd chom && php artisan tinker
>>> DB::connection()->getPdo();
```

#### 5. Slow Tests

**Problem:**
Tests taking too long to complete.

**Solution:**
```bash
# Run in parallel
./run_tests.sh --parallel

# Set timeout
pytest tests/api/ --timeout=30

# Skip slow tests
pytest tests/api/ -m "not slow"

# Identify slow tests
pytest tests/api/ --durations=10
```

### Debug Mode

```bash
# Run with Python debugger
pytest tests/api/test_auth.py --pdb

# Very verbose output
pytest tests/api/ -vv

# Show print statements
pytest tests/api/ -s

# Show local variables on failure
pytest tests/api/ -l --tb=long
```

### Getting Help

1. Check test output in `reports/test_report.html`
2. Review API logs: `chom/storage/logs/laravel.log`
3. Run individual test to isolate issue
4. Check GitHub Issues for known problems
5. Ask in team chat with error details

## Best Practices

### Before Committing

```bash
# Run all tests
./run_tests.sh

# Run with coverage
./run_tests.sh --coverage

# Check coverage threshold
pytest tests/api/ --cov-fail-under=80
```

### Before Deployment

```bash
# Run critical path tests
./run_tests.sh --critical

# Run performance tests
./run_tests.sh --performance

# Run load test
./run_load_test.sh --headless --users 50 --duration 300

# Verify no failures
./run_tests.sh && echo "✓ Ready to deploy"
```

### Regular Maintenance

```bash
# Update dependencies monthly
pip install -r requirements-test.txt --upgrade

# Review slow tests
pytest tests/api/ --durations=20

# Check coverage
./run_tests.sh --coverage && open htmlcov/index.html
```

## Summary

This testing suite provides comprehensive coverage of the CHOM API with:

- **200+ tests** across all endpoints
- **Automated execution** with simple commands
- **Detailed reporting** in HTML and console
- **Load testing** capabilities
- **CI/CD integration** ready
- **Easy troubleshooting** with debug tools

**Quick Reference:**
```bash
# Run all tests
./run_tests.sh

# Run with coverage
./run_tests.sh --coverage

# Run load test
./run_load_test.sh --headless

# View results
open reports/test_report.html
```

Happy testing!
