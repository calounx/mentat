# Testing Quick Start Guide

Get started with the observability stack testing framework in 5 minutes.

## Prerequisites Check

```bash
# Check if you have required tools
command -v bats && echo "✓ Bats installed" || echo "✗ Bats missing"
command -v shellcheck && echo "✓ ShellCheck installed" || echo "✗ ShellCheck missing"
```

## Installation (if needed)

### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y bats shellcheck
```

### macOS
```bash
brew install bats-core shellcheck
```

### Using Make
```bash
make install-deps
```

## Running Tests

### Quick Test (Recommended for Development)
```bash
# Run unit tests + shellcheck (fast)
make test
# or
./tests/run-tests.sh quick
```

### All Tests
```bash
# Run complete test suite
make test-all
# or
./tests/run-tests.sh all
```

### Specific Test Suite
```bash
# Unit tests
make test-unit
bats tests/test-common.bats

# Integration tests
make test-integration
bats tests/test-integration.bats

# Security tests
make test-security
bats tests/test-security.bats

# ShellCheck
make test-shellcheck
./tests/test-shellcheck.sh
```

## Expected Output

### Successful Test Run
```
==========================================
Observability Stack Test Runner
==========================================

[INFO] Checking prerequisites...
[PASS] Prerequisites OK

==========================================
Running: Unit Tests
==========================================

✓ yaml_get: retrieves simple key-value pair
✓ yaml_get: handles quoted values
✓ version_compare: equal versions return 0
...
[PASS] Unit tests passed

==========================================
Test Summary
==========================================

Passed:  2
Failed:  0

[PASS] All test suites passed!
```

### Failed Test Run
```
✗ test-name
  (in test file tests/test-common.bats, line 42)
  assertion failed

1 test failed
[FAIL] Unit tests failed
```

## Common Commands

```bash
# Quick reference
make help                 # Show all available commands
make test                # Run quick tests
make test-all            # Run all tests
make test-coverage       # Show coverage report
make clean               # Clean up artifacts
make pre-commit          # Run pre-commit checks
```

## Running Individual Tests

```bash
# Run single test by name
bats tests/test-common.bats --filter "yaml_get"

# Run with verbose output
bats -t tests/test-common.bats

# Run with TAP output
bats --formatter tap tests/test-common.bats
```

## Troubleshooting

### Problem: Bats not found
```bash
# Solution
make install-deps
# or manually install as shown above
```

### Problem: Tests fail with permission errors
```bash
# Some tests require root, they should skip gracefully
# If needed, run with sudo:
sudo bats tests/test-security.bats
```

### Problem: Tests pass locally but fail in CI
- Check for system dependencies (systemd, network)
- Tests should skip if dependencies missing
- Review test isolation

## Writing Your First Test

```bash
# 1. Open test file
vim tests/test-common.bats

# 2. Add test
@test "my new test" {
    # Arrange
    local input="test"

    # Act
    result=$(my_function "$input")

    # Assert
    [[ "$result" == "expected" ]]
}

# 3. Run test
bats tests/test-common.bats --filter "my new test"
```

## Pre-commit Hooks

```bash
# Setup automatic testing before commits
make setup-hooks

# Now tests run automatically on git commit
git commit -m "my changes"
# Tests run automatically...
```

## CI/CD

Tests run automatically on:
- Push to main/master/develop
- Pull requests
- Manual workflow dispatch

View results in GitHub Actions tab.

## Next Steps

1. Run `make test` to verify everything works
2. Read [tests/README.md](README.md) for detailed documentation
3. Explore test files to understand patterns
4. Write tests for new features
5. Keep test coverage high

## Help

- Full documentation: [tests/README.md](README.md)
- Bats docs: https://bats-core.readthedocs.io/
- ShellCheck wiki: https://www.shellcheck.net/wiki/
- Report issues: GitHub Issues

## Summary

```bash
# The essentials
make install-deps        # Install tools
make test               # Run tests
make test-all           # Run all tests
make help               # See all commands
```

That's it! You're ready to test. Happy testing!
