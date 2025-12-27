# Quick Test Reference Card
**Observability Stack - Test Execution Guide**

---

## Quick Start (30 seconds)

```bash
cd /home/calounx/repositories/mentat/observability-stack/tests

# Setup (first time only)
./setup.sh

# Run all tests
./run-all-tests.sh

# Or use quick shortcuts
./quick-test.sh check    # Quick health check
```

---

## Test Execution Methods

### Method 1: Using run-all-tests.sh (Recommended)

```bash
# Run everything
./run-all-tests.sh

# Run specific suites
./run-all-tests.sh --unit-only
./run-all-tests.sh --integration-only
./run-all-tests.sh --security-only
./run-all-tests.sh --errors-only

# Options
./run-all-tests.sh --verbose        # Detailed output
./run-all-tests.sh --fail-fast      # Stop on first failure
```

### Method 2: Using quick-test.sh (Convenient Shortcuts)

```bash
./quick-test.sh all           # Run all tests
./quick-test.sh unit          # Unit tests only
./quick-test.sh integration   # Integration tests only
./quick-test.sh security      # Security tests only
./quick-test.sh errors        # Error handling tests only

./quick-test.sh common        # Just common.sh tests
./quick-test.sh loader        # Just module-loader.sh tests
./quick-test.sh generator     # Just config-generator.sh tests

./quick-test.sh fast          # Fast tests (unit + security)
./quick-test.sh slow          # Slow tests (integration)
./quick-test.sh check         # Quick health check

./quick-test.sh setup         # Setup test environment
./quick-test.sh clean         # Clean test artifacts
```

### Method 3: Direct BATS Execution

```bash
# Single test file
bats unit/test_common.bats
bats security/test_security.bats

# Directory (all tests in folder)
bats unit/
bats integration/

# All tests
bats unit/ integration/ security/ errors/

# Verbose output
bats --verbose-run unit/test_common.bats

# Pretty formatter
bats --formatter pretty unit/

# Stop on first failure
bats --fail-fast unit/
```

### Method 4: Without BATS (Limited)

```bash
# Static analysis (no BATS needed)
./test-shellcheck.sh

# Pre-commit checks (partial BATS)
./pre-commit-tests.sh

# Manual verification (if created)
./manual-verification.sh    # NOT YET AVAILABLE
```

---

## Test Categories

### Unit Tests (Fast, ~10-20 seconds)
```bash
bats unit/test_common.bats              # 45 tests - common.sh utilities
bats unit/test_module_loader.bats       # 43 tests - module operations
bats unit/test_config_generator.bats    # 20 tests - config generation
```

### Integration Tests (Medium, ~30-60 seconds)
```bash
bats integration/test_module_install.bats      # 21 tests - module lifecycle
bats integration/test_config_generation.bats   # 23 tests - end-to-end config
```

### Security Tests (Medium, ~15-30 seconds)
```bash
bats security/test_security.bats       # 34 tests - attack prevention
```

### Error Handling Tests (Medium, ~20-40 seconds)
```bash
bats errors/test_error_handling.bats   # 39 tests - resilience
```

---

## Common Patterns

### Run Specific Test by Name
```bash
# Filter by test name pattern
bats unit/test_common.bats --filter "yaml_get"
bats security/test_security.bats --filter "injection"
```

### Debug Single Test
```bash
# Run with maximum verbosity
bats --verbose-run --trace unit/test_common.bats

# Or add debug output in test
@test "my test" {
    echo "DEBUG: value=$value" >&3
    # ... test code ...
}
```

### Run Tests in CI Mode
```bash
# TAP format (for CI)
bats --formatter tap unit/

# JUnit XML (for CI reporting)
bats --formatter junit unit/ > test-results.xml
```

---

## Test Results Interpretation

### Success Output
```
✓ test name passed
✓ another test passed

3 tests, 0 failures
```

### Failure Output
```
✗ test name failed
  (in test file unit/test_common.bats, line 42)
    `[[ "$result" == "expected" ]]' failed

  Expected: expected
  Got: actual

1 test, 1 failure
```

### Skipped Tests
```
- test name skipped (Test requires root privileges)

1 test, 0 failures, 1 skipped
```

---

## Troubleshooting

### Problem: "bats: command not found"

**Solution:**
```bash
# Install BATS
sudo apt-get install bats        # Ubuntu/Debian
brew install bats-core           # macOS

# Or run setup script
./setup.sh
```

### Problem: "Permission denied" errors

**Solution:**
```bash
# Some tests require root (integration tests)
sudo bats integration/

# Or skip root-only tests (they auto-skip anyway)
bats integration/  # Will skip tests requiring root
```

### Problem: Tests fail in CI but pass locally

**Solution:**
```bash
# Check environment differences
# CI runs in Ubuntu container with systemd

# Verify test isolation
./run-all-tests.sh --verbose

# Check for race conditions
./run-all-tests.sh --fail-fast
```

### Problem: Slow test execution

**Solution:**
```bash
# Run only fast tests
./quick-test.sh fast

# Or just unit tests
./quick-test.sh unit

# Skip integration tests (slower)
./run-all-tests.sh --unit-only --security-only
```

---

## Pre-Commit Testing

### Install Pre-Commit Hook
```bash
# Link pre-commit script
ln -s ../../tests/pre-commit-tests.sh .git/hooks/pre-commit

# Now tests run automatically before commits
git commit -m "message"  # Runs tests first

# Bypass if needed (not recommended)
git commit --no-verify -m "message"
```

### Manual Pre-Commit Check
```bash
./pre-commit-tests.sh

# Checks:
# - Shell syntax
# - ShellCheck linting
# - YAML validation
# - Unit tests (if lib files changed)
# - Common mistakes
```

---

## CI/CD Testing

### GitHub Actions Workflow

Tests run automatically on:
- Push to main/master/develop branches
- Pull requests to main branches
- Manual workflow dispatch

**Jobs:**
1. Lint (ShellCheck)
2. Unit Tests
3. Integration Tests
4. Security Tests
5. Error Handling Tests
6. Module Validation
7. Coverage Report
8. Test Summary

### View CI Results
```bash
# Push triggers CI
git push origin feature-branch

# View results at:
# https://github.com/your-repo/actions
```

---

## Test Coverage Commands

### Count Total Tests
```bash
cd /home/calounx/repositories/mentat/observability-stack/tests
find . -name "*.bats" -exec grep -h "^@test" {} \; | wc -l
# Output: 324
```

### Count Tests by File
```bash
for file in unit/*.bats integration/*.bats security/*.bats errors/*.bats; do
    echo "$file: $(grep -c "^@test" "$file") tests"
done
```

### List All Test Names
```bash
grep -h "^@test" unit/*.bats | head -20
```

---

## Performance Benchmarking

### Time Test Execution
```bash
# Time unit tests
time bats unit/

# Time all tests
time ./run-all-tests.sh

# Expected times:
# - Unit tests: ~10-20 seconds
# - Integration: ~30-60 seconds
# - Security: ~15-30 seconds
# - Errors: ~20-40 seconds
# - Total: ~2-3 minutes
```

---

## Advanced Usage

### Watch Mode (Requires entr)
```bash
# Install entr
sudo apt-get install entr

# Run tests on file changes
./quick-test.sh watch

# Or manually
find ../scripts ../modules -name "*.sh" | \
    entr -c ./run-all-tests.sh --unit-only
```

### Parallel Test Execution
```bash
# BATS doesn't support parallel by default
# But you can run suites in parallel manually

# Terminal 1
bats unit/ &

# Terminal 2
bats integration/ &

# Terminal 3
bats security/ &

# Wait for all
wait
```

### Custom Test Output
```bash
# Silent mode (only show failures)
bats unit/ 2>&1 | grep -E "(✗|not ok)"

# Count only
bats unit/ 2>&1 | tail -1

# Summary only
./run-all-tests.sh | grep -A 10 "Test Summary"
```

---

## Test Writing Quick Reference

### Basic Test Structure
```bash
@test "descriptive test name" {
    # Arrange
    input="test value"

    # Act
    result=$(function_under_test "$input")

    # Assert
    [[ "$result" == "expected value" ]]
}
```

### Common Assertions
```bash
# String equality
[[ "$result" == "expected" ]]

# Regex match
[[ "$result" =~ pattern ]]

# Numeric comparison
[[ $number -eq 42 ]]
[[ $number -gt 10 ]]
[[ $number -lt 100 ]]

# File existence
[[ -f "path/to/file" ]]
[[ -d "path/to/dir" ]]

# Exit code
run command
[[ $status -eq 0 ]]

# Output contains
[[ "$output" == *"substring"* ]]
```

### Setup and Teardown
```bash
setup() {
    # Runs before each test
    TEST_TMP="$BATS_TEST_TMPDIR/my_tests_$$"
    mkdir -p "$TEST_TMP"
}

teardown() {
    # Runs after each test
    rm -rf "$TEST_TMP"
}
```

---

## Environment Variables

```bash
# Test temp directory (set by run-all-tests.sh)
TEST_TMP_DIR=/tmp/observability-stack-tests

# Stack root
OBSERVABILITY_STACK_ROOT=/home/calounx/repositories/mentat/observability-stack

# Fixtures directory
TEST_FIXTURES_DIR=/home/calounx/repositories/mentat/observability-stack/tests/fixtures
```

---

## File Locations

```
tests/
├── run-all-tests.sh              # Main test runner
├── quick-test.sh                 # Quick shortcuts
├── setup.sh                      # Environment setup
├── pre-commit-tests.sh           # Pre-commit hooks
├── test-shellcheck.sh            # Static analysis
├── unit/                         # Unit tests
│   ├── test_common.bats
│   ├── test_module_loader.bats
│   └── test_config_generator.bats
├── integration/                  # Integration tests
│   ├── test_module_install.bats
│   └── test_config_generation.bats
├── security/                     # Security tests
│   └── test_security.bats
├── errors/                       # Error handling tests
│   └── test_error_handling.bats
├── fixtures/                     # Test data (hyphen-naming convention)
│   ├── sample-config.yaml        # Global config example
│   ├── sample-module.yaml        # Simple module manifest
│   ├── sample-module-full.yaml   # Complete module manifest
│   └── sample-host-config.yaml   # Host configuration example
└── README.md                     # Full documentation
```

---

## Quick Commands Cheat Sheet

```bash
# Setup (first time)
./setup.sh

# Run all tests
./run-all-tests.sh

# Quick health check
./quick-test.sh check

# Just unit tests (fast)
./quick-test.sh unit

# Just security tests
./quick-test.sh security

# Static analysis only
./test-shellcheck.sh

# Pre-commit checks
./pre-commit-tests.sh

# Clean artifacts
./quick-test.sh clean

# Help
./run-all-tests.sh --help
./quick-test.sh help
```

---

## Exit Codes

- `0` - All tests passed ✅
- `1` - One or more tests failed ❌
- `127` - Command not found (missing dependency) ⚠️

---

## Support & Documentation

- **Full Documentation:** `/home/calounx/repositories/mentat/observability-stack/tests/README.md`
- **Coverage Report:** `/home/calounx/repositories/mentat/observability-stack/tests/TEST_COVERAGE_VERIFICATION_REPORT.md`
- **Missing Tests:** `/home/calounx/repositories/mentat/observability-stack/tests/MISSING_TESTS_ACTION_PLAN.md`
- **BATS Documentation:** https://bats-core.readthedocs.io/
- **ShellCheck Wiki:** https://www.shellcheck.net/wiki/

---

**Last Updated:** 2025-12-27
**Test Count:** 324 tests
**Coverage:** ~85% core libraries, ~50% overall
