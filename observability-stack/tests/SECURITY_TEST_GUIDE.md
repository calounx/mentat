# Security Test Guide

## Quick Start

### Running All Tests
```bash
# From repository root
bats tests/security/*.bats tests/unit/*.bats tests/integration/*.bats

# Or use the test runner
./tests/run-security-tests.sh
```

### Running Specific Test Categories
```bash
# Security tests only
bats tests/security/*.bats

# Unit tests only
bats tests/unit/*.bats

# Integration tests only
bats tests/integration/*.bats
```

### Running Individual Test Files
```bash
# JQ injection tests
bats tests/security/test-jq-injection.bats

# Lock race condition tests
bats tests/security/test-lock-race-condition.bats

# Path traversal tests
bats tests/security/test-path-traversal.bats

# Dependency checks
bats tests/unit/test-dependency-check.bats

# State error handling
bats tests/unit/test-state-error-handling.bats

# Full upgrade flow
bats tests/integration/test-upgrade-flow.bats
```

---

## Test Coverage

### Security Vulnerabilities Tested

#### High Severity
- **H-1**: JQ Injection Prevention (14 tests)
  - Command substitution attacks
  - JSON corruption attempts
  - State file integrity

- **H-2**: Lock Race Conditions (14 tests)
  - Concurrent lock acquisition
  - Stale lock cleanup
  - Timeout enforcement

#### Medium Severity
- **M-3**: Path Traversal Prevention (17 tests)
  - Directory traversal attacks
  - Symlink exploitation
  - Component name validation

- **M-2**: Invalid Version Handling (covered in integration)
  - Version string validation
  - Comparison logic

### Code Quality Tests

- **Dependency Checking** (19 tests)
  - Required commands
  - Resource availability
  - Dependency graphs

- **State Error Handling** (24 tests)
  - State corruption prevention
  - Error tracking
  - Recovery mechanisms

- **Integration Testing** (25 tests)
  - Full upgrade workflows
  - Crash recovery
  - Idempotency

---

## Understanding Test Results

### Test Output Format (TAP)
```
1..14                           # Total number of tests
ok 1 test name                  # Passed test
not ok 2 test name              # Failed test
ok 3 test name # skip reason    # Skipped test
```

### Pass Criteria
- All security tests should pass
- Unit tests may skip optional features
- Integration tests should all pass

### Expected Skips
Some tests may skip if:
- Optional features not implemented
- Test environment constraints
- Missing dependencies (non-critical)

---

## Test Development

### Adding New Security Tests

1. **Create test file** in `tests/security/`
```bash
#!/usr/bin/env bats

load '../helpers'

setup() {
    setup_test_environment
    # Test-specific setup
}

teardown() {
    cleanup_test_environment
}

@test "security: description of test" {
    # Test implementation
}
```

2. **Use test helpers** from `tests/helpers.bash`:
   - `setup_test_environment` - Create isolated test directory
   - `cleanup_test_environment` - Clean up after tests
   - `source_lib` - Source library files
   - `mock_*` functions - Mock system commands

3. **Follow naming conventions**:
   - Test files: `test-feature-name.bats`
   - Test names: "category: specific scenario being tested"

### Test Best Practices

1. **Isolation**: Each test should be independent
2. **Cleanup**: Always cleanup in teardown
3. **Assertions**: Use clear, specific assertions
4. **Documentation**: Comment complex test logic
5. **Performance**: Keep tests fast, avoid sleeps when possible

---

## Common Issues and Solutions

### Permission Denied Errors
**Issue**: Tests fail with permission denied on `/var/log` or `/var/lock`

**Solution**: Tests use `TEST_TEMP_DIR` for isolation. If seeing these errors:
```bash
# Set proper test environment variables
export STATE_DIR="/tmp/test-state"
export LOCK_FILE="/tmp/test.lock"
```

### Source File Not Found
**Issue**: `skip upgrade-state.sh not found`

**Solution**: Run tests from repository root:
```bash
cd /path/to/observability-stack
bats tests/security/test-name.bats
```

### Race Condition Test Timing
**Issue**: Concurrent tests occasionally fail

**Solution**: These are timing-sensitive. Re-run or adjust timeouts:
```bash
# In test file, increase timeout
local timeout=10  # Instead of 5
```

---

## CI/CD Integration

### Pre-Commit Hook
```bash
#!/bin/bash
# .git/hooks/pre-commit

echo "Running security tests..."
if ! bats tests/security/*.bats; then
    echo "Security tests failed!"
    exit 1
fi
```

### GitHub Actions
```yaml
name: Security Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install BATS
        run: |
          git clone https://github.com/bats-core/bats-core.git
          cd bats-core
          sudo ./install.sh /usr/local
      - name: Run Tests
        run: bats tests/**/*.bats
```

### Jenkins Pipeline
```groovy
pipeline {
    agent any
    stages {
        stage('Test') {
            steps {
                sh 'bats tests/security/*.bats tests/unit/*.bats tests/integration/*.bats'
            }
        }
    }
}
```

---

## Test Maintenance

### When to Update Tests

1. **Adding Features**: Create tests for new functionality
2. **Bug Fixes**: Add regression tests
3. **Security Patches**: Add tests for vulnerabilities
4. **Refactoring**: Ensure existing tests still pass

### Updating Existing Tests

1. **Locate test file** for the component
2. **Add new test case** following existing patterns
3. **Run tests** to verify
4. **Update documentation** if behavior changed

### Deprecating Tests

If removing functionality:
1. Keep tests but mark as skip with reason
2. Update documentation
3. Remove after grace period

---

## Debugging Failed Tests

### Enable Debug Output
```bash
# Run with debug
DEBUG=true bats tests/security/test-name.bats

# Show all output
bats --show-output-of-passing-tests tests/security/test-name.bats
```

### Inspect Test Environment
```bash
@test "debug test environment" {
    echo "TEST_TEMP_DIR: $TEST_TEMP_DIR"
    echo "STATE_DIR: $STATE_DIR"
    ls -la "$STATE_DIR"
    # Test fails but shows output
    false
}
```

### Interactive Testing
```bash
# Source test helpers manually
source tests/helpers.bash

# Set up test environment
setup_test_environment

# Run commands interactively
source scripts/lib/upgrade-state.sh
state_init
state_begin_upgrade "test"

# Cleanup
cleanup_test_environment
```

---

## Security Test Checklist

Before marking security fix as complete:

- [ ] Tests cover all attack vectors
- [ ] Tests verify fix prevents vulnerability
- [ ] Tests check for regressions
- [ ] Tests validate error handling
- [ ] Tests confirm security boundaries
- [ ] Integration tests verify end-to-end
- [ ] Documentation updated
- [ ] Code reviewed
- [ ] All tests passing

---

## Resources

### BATS Documentation
- Official: https://github.com/bats-core/bats-core
- Tutorial: https://bats-core.readthedocs.io/

### Testing Best Practices
- Test-Driven Development (TDD)
- Behavior-Driven Development (BDD)
- Security Testing Principles

### Related Files
- `/tests/helpers.bash` - Test helper functions
- `/tests/README.md` - General testing documentation
- `/TEST_VERIFICATION_SUMMARY.md` - Latest test results

---

## Contact and Support

For questions about:
- **Test failures**: Check this guide first, then review test output
- **Adding tests**: Follow patterns in existing test files
- **Security issues**: Report immediately, add regression tests

---

**Last Updated**: December 27, 2025
**BATS Version**: 1.13.0
**Test Coverage**: 293 test cases across 6 test suites
