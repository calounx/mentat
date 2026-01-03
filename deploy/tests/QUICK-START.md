# Deployment Logic Testing - Quick Start Guide

## Installation

### 1. Install BATS

**Debian/Ubuntu:**
```bash
sudo apt-get update
sudo apt-get install -y bats
```

**macOS:**
```bash
brew install bats-core
```

**From source:**
```bash
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

### 2. Verify Installation

```bash
bats --version
# Should output: Bats 1.x.x
```

## Running Tests

### All Tests

```bash
cd /home/calounx/repositories/mentat/deploy/tests
./run-all-tests.sh
```

Expected output:
```
========================================
Deployment Logic Test Suite
========================================

Running: 01-argument-parsing
✓ PASSED

Running: 02-dependency-validation
✓ PASSED

...

========================================
Test Summary
========================================

Total tests:   80+
Passed:        80+
Failed:        0

All tests passed!
```

### Individual Test Suites

```bash
# Argument parsing
bats 01-argument-parsing.bats

# Dependency validation
bats 02-dependency-validation.bats

# Phase execution
bats 03-phase-execution.bats

# Error handling
bats 04-error-handling.bats

# File paths
bats 05-file-paths.bats

# User detection
bats 06-user-detection.bats

# SSH operations
bats 07-ssh-operations.bats
```

### Generate Report

```bash
./run-all-tests.sh --report
```

This creates: `DEPLOYMENT-LOGIC-TEST-REPORT.md`

## Test Options

```bash
# Verbose output
./run-all-tests.sh --verbose

# TAP format output
./run-all-tests.sh --tap

# Show help
./run-all-tests.sh --help
```

## What Gets Tested

### 1. Command-Line Arguments ✓
- All --skip-* flags
- --dry-run mode
- --interactive mode
- --help flag
- Invalid argument handling
- Flag combinations

### 2. Dependency Validation ✓
- Missing utils/ directory detection
- Missing scripts/ directory detection
- Missing individual utility files
- File permission checks
- Comprehensive error messages

### 3. Phase Execution Order ✓
- Correct phase sequence
- Phase skipping
- Multiple skip combinations
- Order preservation

### 4. Error Handling ✓
- Failure detection
- Rollback triggering
- Phase-specific rollback
- Error notifications
- Exit code preservation

### 5. File Paths ✓
- Absolute path resolution
- SCRIPT_DIR calculation
- Working directory independence
- Symlink handling

### 6. User Detection ✓
- DEPLOY_USER defaults
- CURRENT_USER from SUDO_USER
- Fallback to whoami
- Environment overrides

### 7. SSH Operations ✓
- Key generation
- Correct permissions (600/644)
- Key copying
- Connection testing
- Remote command execution

## Common Issues

### BATS not found
```bash
# Check if installed
which bats

# Install if missing
sudo apt-get install bats
```

### Permission denied
```bash
# Make scripts executable
chmod +x run-all-tests.sh
chmod +x generate-test-report.sh
```

### Tests fail
```bash
# Run with verbose output
./run-all-tests.sh --verbose

# Check specific test
bats -t 01-argument-parsing.bats
```

## Test Results

All tests passing = Deployment logic is correct!

```
Total tests:   80+
Passed:        80+
Failed:        0
Skipped:       2 (require root)
```

## Next Steps

After running tests:
1. Review `DEPLOYMENT-LOGIC-TEST-REPORT.md`
2. Check for any skipped tests
3. Run actual deployment with confidence!

## CI/CD Integration

Add to your pipeline:
```yaml
- name: Test Deployment Logic
  run: |
    cd deploy/tests
    ./run-all-tests.sh --tap
```

## Files Created

```
deploy/tests/
├── README.md                           # Full documentation
├── QUICK-START.md                      # This file
├── DEPLOYMENT-LOGIC-TEST-REPORT.md     # Test results
├── test-helper.bash                    # Test utilities
├── run-all-tests.sh                    # Test runner
├── generate-test-report.sh             # Report generator
├── 01-argument-parsing.bats            # Argument tests
├── 02-dependency-validation.bats       # Dependency tests
├── 03-phase-execution.bats             # Phase order tests
├── 04-error-handling.bats              # Error handling tests
├── 05-file-paths.bats                  # Path resolution tests
├── 06-user-detection.bats              # User detection tests
└── 07-ssh-operations.bats              # SSH operation tests
```

## Support

Questions? Check:
- `README.md` - Full documentation
- `DEPLOYMENT-LOGIC-TEST-REPORT.md` - Detailed results
- BATS docs: https://bats-core.readthedocs.io/

Happy testing!
