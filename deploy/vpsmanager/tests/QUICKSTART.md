# VPSManager Tests - Quick Start Guide

Quick reference for running VPSManager tests.

## TL;DR - Run All Tests

```bash
# Run unit tests (no root required)
./deploy/vpsmanager/tests/run-all-tests.sh unit

# Run integration tests (requires root)
sudo ./deploy/vpsmanager/tests/run-all-tests.sh integration

# Run all tests (requires root for integration tests)
sudo ./deploy/vpsmanager/tests/run-all-tests.sh
```

## Individual Test Suites

### Unit Tests (No Root Required)

```bash
# Test validation functions
./deploy/vpsmanager/tests/unit/test-validation.sh

# Test user functions
./deploy/vpsmanager/tests/unit/test-users.sh
```

### Integration Tests (Root Required)

```bash
# Test site isolation (per-site user security)
sudo ./deploy/vpsmanager/tests/integration/test-site-isolation.sh
```

## What Each Test Does

### Site Isolation Test (Integration)
**Purpose:** Verify per-site user isolation prevents cross-site access

**Tests:**
1. Creates two test sites (test-site-a.local, test-site-b.local)
2. Verifies each has unique system user (www-site-{domain})
3. Verifies Site A cannot read Site B files (permission denied)
4. Verifies Site A cannot access Site B database
5. Verifies PHP-FPM uses open_basedir to restrict file access
6. Verifies each site has dedicated /tmp and sessions directories
7. Verifies PHP-FPM processes run as correct site users

**Duration:** ~30 seconds

### Validation Test (Unit)
**Purpose:** Test input validation functions

**Tests:** Domain validation, site type validation, PHP version validation, string sanitization

**Duration:** <5 seconds

### User Test (Unit)
**Purpose:** Test username generation functions

**Tests:** Domain to username conversion, length limits, character validation, uniqueness

**Duration:** <5 seconds

## Prerequisites

### For Unit Tests
- VPSManager installed at `/opt/vpsmanager`
- Bash 4.0+

### For Integration Tests
- All unit test prerequisites
- Root privileges
- nginx, PHP 8.2+, MariaDB installed and running
- jq installed

### Install Missing Prerequisites

```bash
# Install jq
sudo apt-get install -y jq

# Install and start services
sudo apt-get install -y nginx php8.2-fpm mariadb-server
sudo systemctl start nginx php8.2-fpm mariadb
```

## Interpreting Results

### Success Output
```
✓ ALL TESTS PASSED
Site isolation is working correctly!
```
Exit code: 0

### Failure Output
```
✗ SOME TESTS FAILED
Site isolation has issues that need to be addressed.
```
Exit code: 1

### Color Codes
- Green ✓ - Test passed
- Red ✗ - Test failed
- Yellow ⚠ - Warning (may not be critical)
- Cyan ℹ - Informational

## Troubleshooting

### "VPSManager not found"
```bash
sudo ./deploy/vpsmanager/install.sh
```

### "Must be run as root"
```bash
sudo ./deploy/vpsmanager/tests/integration/test-site-isolation.sh
```

### "MariaDB is not running"
```bash
sudo systemctl start mariadb
sudo systemctl status mariadb
```

### "Test sites not cleaned up"
```bash
sudo /opt/vpsmanager/bin/vpsmanager site:delete test-site-a.local --force
sudo /opt/vpsmanager/bin/vpsmanager site:delete test-site-b.local --force
```

## CI/CD Integration

### GitHub Actions
```yaml
- name: Run VPSManager Tests
  run: |
    sudo ./deploy/vpsmanager/install.sh
    sudo ./deploy/vpsmanager/tests/run-all-tests.sh
```

### GitLab CI
```yaml
test:
  script:
    - sudo ./deploy/vpsmanager/install.sh
    - sudo ./deploy/vpsmanager/tests/run-all-tests.sh
```

## Adding New Tests

1. Create test file in appropriate directory:
   - Unit tests: `tests/unit/test-{name}.sh`
   - Integration tests: `tests/integration/test-{name}.sh`

2. Make executable:
   ```bash
   chmod +x tests/unit/test-{name}.sh
   ```

3. Follow the existing test structure (see templates in existing tests)

4. Test your test:
   ```bash
   ./tests/unit/test-{name}.sh
   ```

## More Information

See `README.md` in the tests directory for comprehensive documentation.

## Support

For issues or questions about tests:
1. Check the main README.md in the tests directory
2. Review existing test code for examples
3. Check VPSManager logs: `/opt/vpsmanager/var/log/vpsmanager.log`
