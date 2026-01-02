# CHOM API Testing Suite

Comprehensive API testing suite for the CHOM SaaS platform using Python, pytest, and Locust.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Test Organization](#test-organization)
- [Running Tests](#running-tests)
- [Load Testing](#load-testing)
- [Configuration](#configuration)
- [CI/CD Integration](#cicd-integration)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

This test suite provides comprehensive coverage of the CHOM API, including:

- **Authentication & Authorization** - Registration, login, token management, 2FA
- **Site Management** - CRUD operations, site actions, metrics
- **Backup Management** - Backup creation, restoration, downloads
- **Team Management** - Invitations, roles, permissions
- **Health Checks** - System health monitoring
- **Performance Testing** - Response time validation
- **Load Testing** - Concurrent user simulation
- **Schema Validation** - API contract validation

## Features

- **200+ test cases** covering all API endpoints
- **Automatic cleanup** of test data
- **Parallel execution** for faster test runs
- **HTML reports** with detailed test results
- **Coverage reports** showing test coverage
- **Load testing** with Locust
- **Schema validation** using JSON Schema
- **Performance tracking** with thresholds
- **Security testing** for isolation and authorization

## Installation

### Prerequisites

- Python 3.8 or higher
- pip (Python package manager)
- Access to CHOM API (running locally or on test server)

### Install Dependencies

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install test dependencies
pip install -r requirements-test.txt
```

### Configure Environment

Copy the example environment file and customize:

```bash
cp .env.testing .env.test
nano .env.test  # Edit configuration
```

Key configuration options:

```bash
# API Configuration
API_BASE_URL=http://localhost:8000/api/v1

# Test User Credentials
TEST_USER_EMAIL=test@chom.local
TEST_USER_PASSWORD=Test123!@#Password

# Test Options
CLEANUP_AFTER_TESTS=true
TEST_PARALLEL_WORKERS=4
```

## Quick Start

### Run All Tests

```bash
./run_tests.sh
```

### Run Specific Test Categories

```bash
# Authentication tests only
./run_tests.sh auth

# Site management tests
./run_tests.sh sites

# Performance tests
./run_tests.sh --performance

# Security tests
./run_tests.sh --security
```

### Run with Coverage

```bash
./run_tests.sh --coverage
```

### Run in Parallel

```bash
./run_tests.sh --parallel
```

## Test Organization

### Directory Structure

```
tests/api/
├── conftest.py              # Shared fixtures and configuration
├── test_auth.py             # Authentication tests
├── test_sites.py            # Site management tests
├── test_backups.py          # Backup management tests
├── test_team.py             # Team management tests
├── test_health.py           # Health check tests
├── test_schema_validation.py # Schema validation tests
├── load/
│   └── locustfile.py        # Load testing scenarios
└── README.md                # This file
```

### Test Markers

Tests are organized using pytest markers:

- `@pytest.mark.auth` - Authentication tests
- `@pytest.mark.sites` - Site management tests
- `@pytest.mark.backups` - Backup tests
- `@pytest.mark.team` - Team management tests
- `@pytest.mark.health` - Health check tests
- `@pytest.mark.performance` - Performance tests
- `@pytest.mark.security` - Security tests
- `@pytest.mark.critical` - Critical path tests
- `@pytest.mark.slow` - Slow running tests

## Running Tests

### Basic Test Execution

```bash
# Run all tests
pytest tests/api/

# Run with verbose output
pytest tests/api/ -v

# Run specific test file
pytest tests/api/test_auth.py

# Run specific test function
pytest tests/api/test_auth.py::TestLogin::test_login_success

# Run tests matching pattern
pytest tests/api/ -k "login"
```

### Using Test Runner Script

```bash
# Run all tests with HTML report
./run_tests.sh

# Run verbose with coverage
./run_tests.sh -v -c

# Run specific marker
./run_tests.sh -m auth

# Run parallel with coverage
./run_tests.sh -p -c
```

### Advanced Options

```bash
# Stop on first failure
pytest tests/api/ -x

# Show local variables on failure
pytest tests/api/ -l

# Run last failed tests
pytest tests/api/ --lf

# Run tests modified since last commit
pytest tests/api/ --picked

# Set timeout for slow tests
pytest tests/api/ --timeout=30
```

## Load Testing

### Start Locust Web UI

```bash
./run_load_test.sh
```

Then open http://localhost:8089 and configure:
- Number of users
- Spawn rate
- Host (if different from default)

### Headless Load Test

```bash
# Run with defaults (10 users, 60 seconds)
./run_load_test.sh --headless

# Custom configuration
./run_load_test.sh --headless --users 50 --duration 300

# Different host
./run_load_test.sh --headless --host http://staging.chom.com
```

### Load Test Scenarios

The load test simulates realistic user behavior:

1. **CHOMAPIUser** (90% of traffic)
   - Register and login
   - List sites (high frequency)
   - Create sites (moderate)
   - View site details
   - Check metrics
   - List backups
   - View team members

2. **HealthCheckUser** (10% of traffic)
   - Periodic health checks
   - Simulates monitoring systems

### Interpreting Load Test Results

Key metrics to monitor:

- **Response Time (p50, p95, p99)** - Should stay below thresholds
- **Requests/sec** - Throughput capacity
- **Failure Rate** - Should be < 1%
- **Concurrent Users** - Maximum supported users

Example good results:
```
Total Requests: 10,000
Failures: 12 (0.12%)
Average Response Time: 145ms
p95 Response Time: 320ms
p99 Response Time: 580ms
Requests/sec: 166.7
```

## Configuration

### Environment Variables

All configuration is done via `.env.test` file:

```bash
# API Settings
API_BASE_URL=http://localhost:8000/api/v1
API_TIMEOUT=30

# Test Data
TEST_USER_EMAIL=test@chom.local
TEST_USER_PASSWORD=Test123!@#Password
TEST_ORG_NAME=Test Organization

# Execution
TEST_PARALLEL_WORKERS=4
CLEANUP_AFTER_TESTS=true

# Performance Thresholds (ms)
PERF_THRESHOLD_P95=500
PERF_THRESHOLD_P99=1000

# Rate Limits
RATE_LIMIT_AUTH_MAX=5
RATE_LIMIT_API_MAX=100
```

### pytest Configuration

Customize `pytest.ini`:

```ini
[pytest]
testpaths = tests/api
addopts = -v --tb=short --color=yes
markers =
    auth: Authentication tests
    sites: Site management tests
    performance: Performance tests
```

## CI/CD Integration

### GitHub Actions

```yaml
name: API Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install -r requirements-test.txt

      - name: Start API server
        run: |
          docker-compose up -d
          sleep 10

      - name: Run tests
        run: |
          ./run_tests.sh --coverage --parallel

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          file: ./htmlcov/index.html

      - name: Upload test report
        uses: actions/upload-artifact@v3
        with:
          name: test-report
          path: reports/test_report.html
```

### GitLab CI

```yaml
test:
  stage: test
  image: python:3.11
  services:
    - name: chom-api:latest
      alias: api
  variables:
    API_BASE_URL: http://api:8000/api/v1
  script:
    - pip install -r requirements-test.txt
    - ./run_tests.sh --coverage
  artifacts:
    reports:
      junit: reports/junit.xml
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml
    paths:
      - reports/
      - htmlcov/
```

## Best Practices

### Writing Tests

1. **Use descriptive test names**
   ```python
   def test_login_fails_with_invalid_password(self):
       """Test that login returns 401 with wrong password."""
   ```

2. **Use fixtures for setup**
   ```python
   @pytest.fixture
   def authenticated_user(make_request):
       # Setup code
       yield user_data
       # Cleanup code
   ```

3. **Assert expected behavior**
   ```python
   response.assert_status(200).assert_success()
   response.assert_has_field("user", "token")
   ```

4. **Clean up test data**
   ```python
   try:
       # Test code
   finally:
       # Cleanup
   ```

### Performance Testing

1. **Set realistic thresholds**
   ```python
   assert response.duration_ms < 500, "Too slow"
   ```

2. **Track slow endpoints**
   ```python
   track_performance("/api/endpoint", response.duration_ms)
   ```

3. **Test under load**
   - Use load testing to find bottlenecks
   - Monitor resource usage

### Security Testing

1. **Test authorization**
   ```python
   # Try to access other user's data
   response = make_request("GET", f"/sites/{other_user_site}", auth_token=user1_token)
   assert response.status_code in [403, 404]
   ```

2. **Test rate limiting**
   ```python
   for i in range(100):
       response = make_request("POST", "/auth/login", ...)
       if i > 60:
           assert response.status_code == 429
   ```

3. **Validate input**
   - Test boundary conditions
   - Test malformed input
   - Test SQL injection attempts

## Troubleshooting

### Common Issues

#### Tests Failing to Connect to API

```bash
# Check if API is running
curl http://localhost:8000/api/v1/health

# Check environment configuration
cat .env.test

# Verify API_BASE_URL is correct
echo $API_BASE_URL
```

#### Authentication Failures

```bash
# Check test user credentials
# Ensure TEST_USER_EMAIL and TEST_USER_PASSWORD are correct

# Verify registration is working
pytest tests/api/test_auth.py::TestRegistration::test_register_success -v
```

#### Cleanup Not Working

```bash
# Set cleanup to true
echo "CLEANUP_AFTER_TESTS=true" >> .env.test

# Manual cleanup if needed
# Delete test users/sites manually via API or database
```

#### Slow Tests

```bash
# Run with timeout
pytest tests/api/ --timeout=30

# Run in parallel
./run_tests.sh --parallel

# Skip slow tests
pytest tests/api/ -m "not slow"
```

#### Import Errors

```bash
# Ensure virtual environment is activated
source venv/bin/activate

# Reinstall dependencies
pip install -r requirements-test.txt --force-reinstall
```

### Debug Mode

```bash
# Run with Python debugger
pytest tests/api/test_auth.py --pdb

# Print statements
pytest tests/api/ -s

# Very verbose output
pytest tests/api/ -vv
```

### Getting Help

- Check test output in `reports/test_report.html`
- Review logs for error details
- Run individual tests to isolate issues
- Use `--lf` to rerun only failed tests

## Reports

### HTML Test Report

After running tests, view the HTML report:

```bash
open reports/test_report.html  # macOS
xdg-open reports/test_report.html  # Linux
start reports/test_report.html  # Windows
```

### Coverage Report

If run with `--coverage`:

```bash
open htmlcov/index.html
```

### Load Test Report

After load testing:

```bash
open reports/load/load_test_report.html
```

## Contributing

When adding new tests:

1. Follow existing test structure
2. Add appropriate markers
3. Include docstrings
4. Clean up test data
5. Update this README if needed

## License

Part of the CHOM SaaS platform.
