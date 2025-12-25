# Observability Stack Testing Framework

Comprehensive testing suite for the observability stack module system. This framework ensures code quality, security, and reliability through multiple testing layers.

## Table of Contents

- [Overview](#overview)
- [Test Suite Structure](#test-suite-structure)
- [Prerequisites](#prerequisites)
- [Running Tests](#running-tests)
- [Writing Tests](#writing-tests)
- [CI/CD Integration](#cicd-integration)
- [Test Coverage](#test-coverage)
- [Troubleshooting](#troubleshooting)

## Overview

The testing framework follows the test pyramid approach:

```
        /\
       /  \  E2E Tests (Manual/Smoke)
      /----\
     / Inte \  Integration Tests (Module Workflows)
    /  gra  \
   /  tion   \
  /------------\
 /   Unit Tests \  Unit Tests (Functions)
/________________\
```

### Testing Philosophy

- **Many unit tests**: Fast, isolated tests of individual functions
- **Fewer integration tests**: Test complete workflows and module interactions
- **Minimal E2E tests**: Manual validation of critical user journeys
- **Security-first**: Dedicated security testing for all components
- **Fast feedback**: Optimized for quick execution and parallel runs

## Test Suite Structure

```
tests/
├── README.md                    # This file
├── helpers.bash                 # Shared test utilities
├── test-common.bats            # Unit tests for common.sh
├── test-integration.bats       # Integration tests for workflows
├── test-security.bats          # Security and permission tests
└── test-shellcheck.sh          # ShellCheck integration
```

### Test Files

#### `helpers.bash`
Shared utilities for all tests:
- Environment setup/teardown
- Mock functions (systemctl, curl, wget, etc.)
- Config generation helpers
- Assertion helpers
- Validation utilities

#### `test-common.bats`
Unit tests for `scripts/lib/common.sh`:
- YAML parsing functions
- Version comparison
- Path utilities
- File operations
- Network utilities
- Template rendering
- Logging functions

Coverage: **~70 test cases**

#### `test-integration.bats`
Integration tests for complete workflows:
- Module installation/uninstallation
- Configuration generation
- Service management
- Auto-detection
- Error recovery
- Multi-host configuration

Coverage: **~40 test cases**

#### `test-security.bats`
Security-focused tests:
- File permissions
- Credential handling
- Input validation
- Command injection prevention
- Download security
- Service isolation
- Log security

Coverage: **~50 test cases**

#### `test-shellcheck.sh`
Static analysis with ShellCheck:
- Code quality checks
- Common mistake detection
- Best practice enforcement
- Configurable severity levels

## Prerequisites

### Required Tools

1. **Bats** (Bash Automated Testing System)
```bash
# Ubuntu/Debian
sudo apt-get install bats

# macOS
brew install bats-core

# From source
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

2. **ShellCheck**
```bash
# Ubuntu/Debian
sudo apt-get install shellcheck

# macOS
brew install shellcheck

# Other systems
# See: https://github.com/koalaman/shellcheck#installing
```

3. **Optional: Bats Support Libraries**
```bash
# bats-support
git clone https://github.com/bats-core/bats-support.git
sudo mkdir -p /usr/local/lib/bats
sudo cp -r bats-support /usr/local/lib/bats/

# bats-assert
git clone https://github.com/bats-core/bats-assert.git
sudo cp -r bats-assert /usr/local/lib/bats/
```

### System Requirements

- Bash 4.0+
- Linux or macOS
- Root access for permission tests (optional)
- systemd for service tests (optional)

## Running Tests

### Run All Tests

```bash
# From observability-stack directory
cd observability-stack

# Run all bats tests
bats tests/*.bats

# Run with verbose output
bats -t tests/*.bats
```

### Run Specific Test Suites

```bash
# Unit tests only
bats tests/test-common.bats

# Integration tests only
bats tests/test-integration.bats

# Security tests only
bats tests/test-security.bats

# ShellCheck only
./tests/test-shellcheck.sh
```

### Run Specific Tests

```bash
# Run single test by name
bats tests/test-common.bats --filter "yaml_get"

# Run tests matching pattern
bats tests/test-security.bats --filter "security: validates"
```

### Run with Different Options

```bash
# Verbose output
bats -t tests/test-common.bats

# Pretty formatter
bats --formatter pretty tests/*.bats

# TAP output
bats --formatter tap tests/*.bats

# JUnit XML output (for CI)
bats --formatter junit tests/*.bats > test-results.xml
```

### ShellCheck Options

```bash
# Default run (warning severity)
./tests/test-shellcheck.sh

# Error severity only
./tests/test-shellcheck.sh --severity error

# Custom exclusions
./tests/test-shellcheck.sh --exclude SC2034,SC2086,SC2155

# Check specific files
./tests/test-shellcheck.sh scripts/module-manager.sh
```

## Writing Tests

### Test Structure (Bats)

```bash
#!/usr/bin/env bats

# Load helpers
load helpers

# Setup runs before each test
setup() {
    setup_test_environment
    source "${BATS_TEST_DIRNAME}/../scripts/lib/common.sh"
}

# Teardown runs after each test
teardown() {
    cleanup_test_environment
}

# Test case
@test "descriptive test name" {
    # Arrange
    local input="test value"

    # Act
    result=$(some_function "$input")

    # Assert
    [[ "$result" == "expected value" ]]
}
```

### Using Test Helpers

```bash
@test "example using helpers" {
    # Create test module
    create_test_module "my_exporter"

    # Create test host config
    create_test_host_config "test-host" "192.168.1.100"

    # Create mock service
    mock_service "prometheus" "active"

    # Assertions
    assert_file_exists "${TEST_TEMP_DIR}/config/hosts/test-host.yaml"
    assert_file_contains "${TEST_TEMP_DIR}/config/hosts/test-host.yaml" "192.168.1.100"
}
```

### Common Patterns

#### Testing Functions

```bash
@test "function returns expected value" {
    run my_function "input"

    [[ $status -eq 0 ]]
    [[ "$output" == "expected output" ]]
}
```

#### Testing File Operations

```bash
@test "creates file with correct content" {
    local file="${TEST_TEMP_DIR}/test.txt"

    echo "content" > "$file"

    assert_file_exists "$file"
    assert_file_contains "$file" "content"
}
```

#### Testing Error Handling

```bash
@test "handles error gracefully" {
    run failing_function

    [[ $status -ne 0 ]]
    [[ "$output" == *"error"* ]]
}
```

#### Skipping Tests Conditionally

```bash
@test "requires root" {
    skip_if_not_root

    # Test that requires root access
}

@test "requires systemd" {
    skip_if_no_systemd

    # Test that requires systemd
}
```

### Best Practices

1. **Descriptive Names**: Use clear, descriptive test names
   ```bash
   @test "yaml_get: retrieves simple key-value pair"  # Good
   @test "test1"                                       # Bad
   ```

2. **Arrange-Act-Assert**: Structure tests clearly
   ```bash
   @test "example" {
       # Arrange - setup test data
       local input="test"

       # Act - call function under test
       result=$(my_function "$input")

       # Assert - verify results
       [[ "$result" == "expected" ]]
   }
   ```

3. **Isolation**: Each test should be independent
   - Use `setup()` and `teardown()`
   - Don't rely on test execution order
   - Clean up after yourself

4. **One Assertion Per Test** (preferred)
   - Focus on one behavior per test
   - Makes failures easier to debug

5. **Test Edge Cases**
   - Empty input
   - Invalid input
   - Missing files
   - Permission errors

## CI/CD Integration

### GitHub Actions

The test suite runs automatically on GitHub Actions for:
- Push to main/master/develop branches
- Pull requests
- Manual workflow dispatch

See `.github/workflows/tests.yml` for configuration.

### Test Jobs

1. **ShellCheck**: Static analysis of shell scripts
2. **Unit Tests**: Tests for common.sh functions
3. **Integration Tests**: Module workflow tests
4. **Security Tests**: Security and permission validation
5. **YAML Validation**: Validates YAML syntax
6. **Syntax Check**: Bash syntax validation

### Local CI Simulation

```bash
# Run what CI runs
bats tests/*.bats && ./tests/test-shellcheck.sh

# Run with same formatters
bats --formatter junit tests/*.bats > test-results.xml
```

### Adding to Pre-commit Hook

```bash
# .git/hooks/pre-commit
#!/bin/bash
echo "Running tests..."
bats tests/*.bats || exit 1
./tests/test-shellcheck.sh || exit 1
echo "All tests passed!"
```

## Test Coverage

### Current Coverage

| Area | Test Suite | Test Cases | Coverage |
|------|-----------|------------|----------|
| Common Library | test-common.bats | ~70 | High |
| Module Workflows | test-integration.bats | ~40 | Medium |
| Security | test-security.bats | ~50 | High |
| Code Quality | test-shellcheck.sh | All scripts | High |

### Coverage Areas

#### Covered
- ✅ YAML parsing functions
- ✅ Version comparison
- ✅ File permissions
- ✅ Input validation
- ✅ Template rendering
- ✅ Configuration generation
- ✅ Module lifecycle
- ✅ Security measures
- ✅ Shell script quality

#### Partial Coverage
- ⚠️ Service management (requires systemd)
- ⚠️ Network operations (requires network)
- ⚠️ Auto-detection (requires services)

#### Not Covered (Manual Testing Required)
- ❌ End-to-end workflows
- ❌ Multi-host deployments
- ❌ Production environment
- ❌ Performance testing

### Improving Coverage

To add new tests:

1. Identify untested code
2. Write test in appropriate suite
3. Run test locally
4. Verify in CI
5. Update this documentation

## Troubleshooting

### Common Issues

#### Issue: "bats: command not found"
```bash
# Solution: Install bats
sudo apt-get install bats
# or
brew install bats-core
```

#### Issue: Tests fail with "Permission denied"
```bash
# Solution: Tests requiring root should skip gracefully
# Check if test uses skip_if_not_root

# Run with sudo if needed (not recommended)
sudo bats tests/test-security.bats
```

#### Issue: "shellcheck: command not found"
```bash
# Solution: Install shellcheck
sudo apt-get install shellcheck
# or
brew install shellcheck
```

#### Issue: Tests fail in CI but pass locally
```bash
# Check environment differences
# CI runs in Ubuntu container
# May need to mock systemd or network operations
```

#### Issue: Test isolation problems
```bash
# Ensure cleanup is working
teardown() {
    cleanup_test_environment  # This should run after each test
}

# Check for leftover files
ls -la /tmp/bats-test-*
```

### Debugging Tests

#### Verbose Output
```bash
# Show all commands
bats -t tests/test-common.bats

# Add debug logging in test
@test "debug example" {
    echo "DEBUG: value=$value" >&3
}
```

#### Run Single Test
```bash
# Faster debugging
bats tests/test-common.bats --filter "specific test name"
```

#### Check Test Environment
```bash
@test "debug environment" {
    echo "TEST_TEMP_DIR=$TEST_TEMP_DIR" >&3
    echo "PWD=$PWD" >&3
    echo "User: $(whoami)" >&3
}
```

### Getting Help

- **Bats Documentation**: https://bats-core.readthedocs.io/
- **ShellCheck Wiki**: https://www.shellcheck.net/wiki/
- **Report Issues**: Create issue in repository

## Maintenance

### Updating Tests

When modifying code:
1. Update corresponding tests
2. Run affected test suite
3. Run full test suite
4. Update documentation if needed

### Adding New Test Suites

1. Create `tests/test-<name>.bats`
2. Add to CI workflow (`.github/workflows/tests.yml`)
3. Document in this README
4. Run and verify

### Regular Tasks

- Review and update test coverage quarterly
- Update dependencies (bats, shellcheck)
- Review skipped tests
- Remove obsolete tests
- Improve test performance

## Quick Reference

### Run Commands
```bash
# All tests
bats tests/*.bats

# Specific suite
bats tests/test-common.bats

# With verbose output
bats -t tests/*.bats

# ShellCheck
./tests/test-shellcheck.sh

# Single test
bats tests/test-common.bats --filter "yaml_get"
```

### Common Helpers
```bash
setup_test_environment          # Setup test environment
cleanup_test_environment        # Cleanup test environment
create_test_module              # Create mock module
create_test_host_config         # Create mock host config
mock_service                    # Mock systemd service
assert_file_exists              # Assert file exists
assert_file_contains            # Assert file contains text
skip_if_not_root               # Skip test if not root
```

### Exit Codes
- `0` - All tests passed
- `1` - One or more tests failed
- `127` - Command not found (missing dependency)

## Contributing

When contributing tests:

1. Follow existing patterns
2. Use descriptive test names
3. Add comments for complex logic
4. Test both success and failure cases
5. Update documentation
6. Verify CI passes

---

**Last Updated**: 2025-12-25
**Test Framework Version**: 1.0.0
**Bats Version**: 1.11.0+
**ShellCheck Version**: 0.9.0+
