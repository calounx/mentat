# VPSManager Test Suite

Comprehensive test suite for VPSManager, covering integration tests and unit tests.

## Directory Structure

```
tests/
├── README.md                           # This file
├── integration/                        # Integration tests (require full environment)
│   └── test-site-isolation.sh         # Per-site user isolation tests
└── unit/                               # Unit tests (test individual functions)
    └── (future unit tests)
```

## Integration Tests

Integration tests require a fully configured VPSManager environment with:
- VPSManager installed at `/opt/vpsmanager`
- nginx, PHP 8.2+, and MariaDB installed and running
- Root privileges to create sites and users

### Site Isolation Tests

Tests per-site system user isolation to ensure sites cannot access each other's files or databases.

**Location:** `integration/test-site-isolation.sh`

**What it tests:**
1. **Site Creation** - Creates two test sites (test-site-a.local, test-site-b.local)
2. **Unique System Users** - Verifies each site has its own `www-site-{domain}` user
3. **File Isolation** - Verifies Site A cannot read Site B's files (permission denied)
4. **Database Isolation** - Verifies Site A cannot access Site B's database
5. **PHP Restrictions** - Verifies PHP-FPM uses `open_basedir` to restrict file access
6. **Temp Directory Isolation** - Verifies each site has its own `/tmp` and sessions directory
7. **Process Isolation** - Verifies PHP-FPM processes run as the correct site user

**Usage:**

```bash
# Run all isolation tests
sudo ./deploy/vpsmanager/tests/integration/test-site-isolation.sh
```

**Expected output:**

```
==============================================================================
VPSManager Site Isolation Integration Tests
==============================================================================
Testing per-site user isolation security

==============================================================================
Checking Prerequisites
==============================================================================
✓ PASS: VPSManager found
✓ PASS: PHP found: PHP 8.2.x (cli)
✓ PASS: nginx is running
✓ PASS: MariaDB/MySQL is running
✓ PASS: jq found

==============================================================================
Running Tests
==============================================================================

[TEST 1] Create two test sites
ℹ INFO: Creating test-site-a.local...
✓ PASS: Both test sites created

[TEST 2] Verify each site has unique system user
ℹ INFO: User www-site-test-site-a-local exists (UID: 999)
ℹ INFO: User www-site-test-site-b-local exists (UID: 998)
✓ PASS: Both sites have unique system users with proper security

[TEST 3] Verify Site A cannot read Site B files (permission denied)
ℹ INFO: Created secret file: /var/www/sites/test-site-b.local/secret.txt
ℹ INFO: Site A correctly denied access to Site B's file
✓ PASS: File isolation verified - Site A cannot access Site B files

[TEST 4] Verify Site A cannot access Site B database
ℹ INFO: Site A database: site_test_site_a_local (user: site_test_site_a_local)
ℹ INFO: Site B database: site_test_site_b_local (user: site_test_site_b_local)
✓ PASS: Database isolation verified - Site A cannot access Site B database

[TEST 5] Verify Site A PHP process restricted by open_basedir
ℹ INFO: PHP-FPM pool has open_basedir configured
✓ PASS: PHP open_basedir is configured in PHP-FPM pool

[TEST 6] Verify Site A cannot list /tmp contents or access system-wide temp
ℹ INFO: Site A has dedicated tmp directory: /var/www/sites/test-site-a.local/tmp
✓ PASS: Site has dedicated tmp and sessions directories configured in PHP-FPM

[TEST 7] Verify PHP-FPM processes run as correct site users
ℹ INFO: Pool A configured with user: www-site-test-site-a-local
✓ PASS: PHP-FPM pools configured with correct site-specific users

==============================================================================
Test Summary
==============================================================================
Total Tests: 7
Passed: 7
Failed: 0

✓ ALL TESTS PASSED
Site isolation is working correctly!
```

## Unit Tests

Unit tests test individual functions in isolation without requiring a full environment.

### Users Management Tests

Tests user management functions for multi-tenancy security isolation.

**Location:** `unit/test-users.sh`

**What it tests:**
1. **domain_to_username()** - Converts domains to safe Linux usernames
   - Basic domain conversion (example.com -> www-site-example-com)
   - Subdomain handling (blog.example.com -> www-site-blog-example-com)
   - Multiple dots (api.v2.example.com -> www-site-api-v2-example-com)
   - Long domain truncation (ensures <= 32 char total length)
   - Trailing hyphen removal after truncation
   - Special TLDs (example.co.uk -> www-site-example-co-uk)
   - Numeric domains (123.example.com -> www-site-123-example-com)
   - Domains with hyphens preserved
   - Correct "www-site-" prefix added
   - Consistency (same input = same output)

2. **get_site_username()** - Wrapper function verification

3. **Linux Username Compatibility**
   - Valid characters only (alphanumeric, hyphens, underscores)
   - Starts with letter/digit
   - Maximum 32 characters total
   - No dots in usernames

4. **Security Verification**
   - Different domains generate unique usernames
   - No information leakage through usernames

5. **Edge Cases**
   - Empty string handling
   - Single character domains
   - Maximum length domains
   - Real-world domain patterns

**Usage:**

```bash
# Run user management unit tests (no root required)
./deploy/vpsmanager/tests/unit/test-users.sh
```

**Expected output:**

```
==============================================================================
VPSManager Users.sh Unit Tests
==============================================================================
Testing user management functions

✓ PASS: Found users.sh
==============================================================================
Running Tests
==============================================================================

[TEST 1] domain_to_username() converts basic domain correctly
✓ PASS: Basic domain converted correctly

[TEST 2] domain_to_username() converts subdomain correctly
✓ PASS: Subdomain converted correctly
...
[TEST 19] Documentation example works as described
✓ PASS: Documentation example verified

==============================================================================
Test Summary
==============================================================================
Total Tests: 19
Passed: 19
Failed: 0

✓ ALL TESTS PASSED
User management functions are working correctly!
```

**Future unit tests planned:**
- Domain name validation
- Database name sanitization
- JSON response formatting
- Configuration parsing
- Site creation validation

## Writing New Tests

### Integration Test Guidelines

1. **Use descriptive test names** - `test_XX_description_of_what_is_tested`
2. **Print clear output** - Use the color helper functions
3. **Clean up after yourself** - Remove test sites/users created
4. **Be idempotent** - Tests should be runnable multiple times
5. **Test security boundaries** - Focus on isolation and permission checks

### Test Structure

```bash
test_XX_description() {
    print_test "Description of what this tests"

    # Setup test data
    local test_var="value"

    # Perform test
    if some_condition; then
        print_info "Detailed info about success"
    else
        print_error "What went wrong"
    fi

    # Assert results
    if [[ "$success" == "true" ]]; then
        pass_test "Test passed message"
    else
        fail_test "Test failed message"
        return 1
    fi
}
```

### Color Helpers

Available color functions:
- `print_header "Title"` - Large cyan header
- `print_test "Description"` - Test number and description
- `print_success "Message"` - Green checkmark
- `print_error "Message"` - Red X
- `print_warning "Message"` - Yellow warning
- `print_info "Message"` - Cyan info

### Test Tracking

Use these functions to track results:
- `pass_test "Message"` - Increment passed count, print success
- `fail_test "Message"` - Increment failed count, print error

## Continuous Integration

These tests can be integrated into CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v2
    - name: Install dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y nginx php-fpm mariadb-server jq
    - name: Install VPSManager
      run: sudo ./deploy/vpsmanager/install.sh
    - name: Run site isolation tests
      run: sudo ./deploy/vpsmanager/tests/integration/test-site-isolation.sh
```

## Troubleshooting

### Tests fail with "VPSManager not found"

Make sure VPSManager is installed:
```bash
sudo ./deploy/vpsmanager/install.sh
```

### Tests fail with "Must be run as root"

All integration tests require root privileges:
```bash
sudo ./deploy/vpsmanager/tests/integration/test-site-isolation.sh
```

### Tests fail with "MariaDB is not running"

Start MariaDB:
```bash
sudo systemctl start mariadb
```

### Tests hang or timeout

Check service status:
```bash
sudo systemctl status nginx php8.2-fpm mariadb
```

### Test sites not cleaned up

Manually clean up test sites:
```bash
sudo /opt/vpsmanager/bin/vpsmanager site:delete test-site-a.local --force
sudo /opt/vpsmanager/bin/vpsmanager site:delete test-site-b.local --force
```

## Contributing

When adding new tests:

1. Follow the existing test structure and naming conventions
2. Add documentation to this README
3. Ensure tests clean up after themselves
4. Test both success and failure cases
5. Use descriptive assertions and error messages

## Security Testing

These tests are specifically designed to verify security isolation between sites:

- **File-level isolation** - Each site's files owned by unique user with 750 permissions
- **Database isolation** - Each site has unique database user with limited privileges
- **Process isolation** - PHP-FPM processes run as site-specific users
- **Filesystem restrictions** - `open_basedir` limits file access
- **Temp isolation** - Each site has dedicated `/tmp` and sessions directories

These tests help ensure that even if one site is compromised, the attacker cannot access other sites on the same server.

## License

Same as VPSManager - see main project LICENSE file.
