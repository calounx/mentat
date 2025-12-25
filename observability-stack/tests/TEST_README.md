# Observability Stack Test Suite

Comprehensive testing infrastructure for the observability stack modular monitoring system.

## Table of Contents

- [Overview](#overview)
- [Test Architecture](#test-architecture)
- [Getting Started](#getting-started)
- [Running Tests](#running-tests)
- [Writing Tests](#writing-tests)
- [CI/CD Integration](#cicd-integration)
- [Coverage Goals](#coverage-goals)
- [Troubleshooting](#troubleshooting)

## Overview

This test suite provides comprehensive coverage of the observability stack, including:

- **Unit Tests**: Test individual functions in isolation
- **Integration Tests**: Test complete workflows and module lifecycle
- **Security Tests**: Validate security controls and prevent vulnerabilities
- **Error Handling Tests**: Ensure graceful failure and recovery

### Test Statistics

- **Total Test Files**: 8+
- **Test Categories**: 4
- **Coverage Target**: 80%+
- **Framework**: BATS (Bash Automated Testing System)

## Test Architecture

### Directory Structure

```
tests/
├── setup.sh                  # Test environment setup
├── run-all-tests.sh         # Main test runner
├── unit/                    # Unit tests
│   ├── test_common.bats
│   ├── test_module_loader.bats
│   └── test_config_generator.bats
├── integration/             # Integration tests
│   ├── test_module_install.bats
│   └── test_config_generation.bats
├── security/                # Security tests
│   └── test_security.bats
├── errors/                  # Error handling tests
│   └── test_error_handling.bats
├── fixtures/                # Test data and fixtures
│   ├── sample_module.yaml
│   └── sample_host_config.yaml
└── TEST_README.md          # This file
```

### Test Layers

```
┌─────────────────────────────────────┐
│      Error Handling Tests          │  ← Resilience & Recovery
├─────────────────────────────────────┤
│       Security Tests                │  ← Security Controls
├─────────────────────────────────────┤
│     Integration Tests               │  ← End-to-End Workflows
├─────────────────────────────────────┤
│        Unit Tests                   │  ← Function-Level Testing
└─────────────────────────────────────┘
```

## Getting Started

### Prerequisites

1. **BATS Framework** (required)
   ```bash
   # Install via NPM
   sudo npm install -g bats

   # OR install from source
   git clone https://github.com/bats-core/bats-core.git
   cd bats-core
   sudo ./install.sh /usr/local
   ```

2. **Shellcheck** (required)
   ```bash
   sudo apt-get install shellcheck  # Debian/Ubuntu
   brew install shellcheck           # macOS
   ```

3. **Promtool** (optional, for integration tests)
   ```bash
   sudo apt-get install prometheus
   ```

4. **YQ** (optional, for YAML validation)
   ```bash
   sudo snap install yq
   ```

### Initial Setup

```bash
cd /home/calounx/repositories/mentat/observability-stack/tests
./setup.sh
```

This will:
- Check for required dependencies
- Create test directories
- Set up test environment variables
- Verify test structure

## Running Tests

### Run All Tests

```bash
./run-all-tests.sh
```

### Run Specific Test Suites

```bash
# Unit tests only
./run-all-tests.sh --unit-only

# Integration tests only
./run-all-tests.sh --integration-only

# Security tests only
./run-all-tests.sh --security-only

# Error handling tests only
./run-all-tests.sh --errors-only
```

### Run Specific Test Files

```bash
# Run single test file
bats unit/test_common.bats

# Run all tests in a directory
bats unit/

# Run with verbose output
bats --verbose-run unit/test_common.bats
```

### Advanced Options

```bash
# Stop on first failure
./run-all-tests.sh --fail-fast

# Verbose output
./run-all-tests.sh --verbose

# Combined options
./run-all-tests.sh --unit-only --verbose --fail-fast
```

### Running Individual Tests

```bash
# Run specific test by name (requires BATS with filter support)
bats --filter "yaml_get extracts simple" unit/test_common.bats
```

## Writing Tests

### Test Structure

BATS tests follow this structure:

```bash
#!/usr/bin/env bats

setup() {
    # Runs before each test
    # Load libraries, create temp dirs, etc.
}

teardown() {
    # Runs after each test
    # Cleanup temp files, restore state
}

@test "descriptive test name" {
    # Arrange: Set up test data
    input="test value"

    # Act: Execute the function under test
    result=$(function_under_test "$input")

    # Assert: Verify the result
    [[ "$result" == "expected value" ]]
}
```

### Unit Test Example

```bash
@test "yaml_get extracts simple key-value pairs" {
    # Create test YAML file
    cat > "$TEST_TMP/test.yaml" << 'EOF'
name: test_module
version: 1.0.0
EOF

    # Test extraction
    result=$(yaml_get "$TEST_TMP/test.yaml" "name")
    [[ "$result" == "test_module" ]]

    result=$(yaml_get "$TEST_TMP/test.yaml" "version")
    [[ "$result" == "1.0.0" ]]
}
```

### Integration Test Example

```bash
@test "install simple test module with mock binary" {
    # Create test module
    mkdir -p "$TEST_TMP/modules/_core/mock_exporter"

    cat > "$TEST_TMP/modules/_core/mock_exporter/module.yaml" << 'EOF'
module:
  name: mock_exporter
  version: 1.0.0
exporter:
  port: 19999
EOF

    # Create install script
    cat > "$TEST_TMP/modules/_core/mock_exporter/install.sh" << 'EOF'
#!/bin/bash
echo "installed" > /tmp/mock_exporter_status
exit 0
EOF

    chmod +x "$TEST_TMP/modules/_core/mock_exporter/install.sh"

    # Run installation
    MODULES_CORE_DIR="$TEST_TMP/modules/_core"
    install_module "mock_exporter"

    # Verify
    [[ -f /tmp/mock_exporter_status ]]

    # Cleanup
    rm -f /tmp/mock_exporter_status
}
```

### Security Test Example

```bash
@test "detection command validator blocks shell metacharacters" {
    # Test various injection attempts
    run validate_and_execute_detection_command "systemctl; rm -rf /"
    [[ $status -ne 0 ]]

    run validate_and_execute_detection_command "systemctl | malicious"
    [[ $status -ne 0 ]]

    run validate_and_execute_detection_command "systemctl && evil"
    [[ $status -ne 0 ]]
}
```

### Best Practices

1. **Test Naming**: Use descriptive names that explain what is being tested
2. **Isolation**: Each test should be independent
3. **Arrange-Act-Assert**: Follow the AAA pattern
4. **Error Cases**: Test both success and failure scenarios
5. **Use Skip for Conditional Tests**

### Assertions and Checks

```bash
# Exit status
[[ $? -eq 0 ]]           # Success
[[ $status -ne 0 ]]      # Failure (with 'run')

# String comparison
[[ "$result" == "expected" ]]
[[ "$result" != "unexpected" ]]
[[ -z "$empty_var" ]]     # Empty string
[[ -n "$non_empty" ]]     # Non-empty string

# Pattern matching
[[ "$result" == *"substring"* ]]
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]

# File tests
[[ -f "$file" ]]         # File exists
[[ -d "$dir" ]]          # Directory exists
[[ -x "$script" ]]       # File is executable
[[ -r "$file" ]]         # File is readable
```

## CI/CD Integration

### GitHub Actions Workflow

The test suite automatically runs on:
- Push to main/master/develop branches
- Pull requests
- Manual workflow dispatch

### Workflow Jobs

1. **Lint**: Shellcheck validation
2. **Unit Tests**: Fast, isolated function tests
3. **Integration Tests**: Module installation and config generation
4. **Security Tests**: Security control validation
5. **Error Handling Tests**: Error recovery and resilience
6. **Module Validation**: YAML syntax and structure
7. **Coverage Report**: Test coverage summary

## Coverage Goals

### Target Coverage by Component

| Component | Target | Description |
|-----------|--------|-------------|
| common.sh | 90%+ | Core utility functions |
| module-loader.sh | 85%+ | Module discovery and loading |
| config-generator.sh | 85%+ | Configuration generation |
| Module manifests | 100% | All modules validated |
| Security controls | 95%+ | Security mechanisms |

## Troubleshooting

### Common Issues

#### BATS Not Found

```bash
# Install BATS
sudo npm install -g bats

# OR from source
git clone https://github.com/bats-core/bats-core.git /tmp/bats
cd /tmp/bats
sudo ./install.sh /usr/local
```

#### Tests Fail Due to Permissions

```bash
# Some integration tests require root
sudo bats tests/integration/
```

#### Tests Leave Temporary Files

```bash
# Clean up test temp directory
rm -rf /tmp/observability-stack-tests
```

## Resources

- [BATS Documentation](https://github.com/bats-core/bats-core)
- [Bash Test Patterns](https://bats-core.readthedocs.io/)
- [Shellcheck Wiki](https://github.com/koalaman/shellcheck/wiki)
- [Testing Best Practices](https://google.github.io/styleguide/shellguide.html)
