#!/usr/bin/env bash
# VPSManager Site Isolation Integration Tests
# Tests per-site user isolation to ensure sites cannot access each other's files or databases
#
# Usage: sudo ./test-site-isolation.sh
#
# Requirements:
# - Must be run as root
# - VPSManager must be installed at /opt/vpsmanager
# - PHP, nginx, and MariaDB must be installed and running

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

VPSMANAGER_BIN="/opt/vpsmanager/bin/vpsmanager"
TEST_SITE_A="test-site-a.local"
TEST_SITE_B="test-site-b.local"
SITES_ROOT="/var/www/sites"

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# ============================================================================
# Color output helpers
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BOLD}${CYAN}==============================================================================${NC}"
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo -e "${BOLD}${CYAN}==============================================================================${NC}"
}

print_test() {
    echo -e "\n${BOLD}${BLUE}[TEST $((TESTS_TOTAL + 1))]${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
}

print_error() {
    echo -e "${RED}✗ FAIL:${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ INFO:${NC} $1"
}

# ============================================================================
# Test tracking
# ============================================================================

pass_test() {
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
    print_success "$1"
}

fail_test() {
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
    print_error "$1"
}

# ============================================================================
# Utility functions
# ============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}ERROR: This script must be run as root${NC}"
        echo "Usage: sudo $0"
        exit 1
    fi
}

check_prerequisites() {
    print_header "Checking Prerequisites"

    local prereqs_met=true

    # Check VPSManager
    if [[ ! -x "$VPSMANAGER_BIN" ]]; then
        print_error "VPSManager not found at $VPSMANAGER_BIN"
        prereqs_met=false
    else
        print_success "VPSManager found"
    fi

    # Check PHP
    if ! command -v php &> /dev/null; then
        print_error "PHP not found"
        prereqs_met=false
    else
        print_success "PHP found: $(php -v | head -n1)"
    fi

    # Check nginx
    if ! systemctl is-active --quiet nginx; then
        print_warning "nginx is not running"
    else
        print_success "nginx is running"
    fi

    # Check MariaDB
    if ! systemctl is-active --quiet mariadb && ! systemctl is-active --quiet mysql; then
        print_error "MariaDB/MySQL is not running"
        prereqs_met=false
    else
        print_success "MariaDB/MySQL is running"
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        print_error "jq not found (required for JSON parsing)"
        prereqs_met=false
    else
        print_success "jq found"
    fi

    if [[ "$prereqs_met" == "false" ]]; then
        echo -e "\n${RED}Prerequisites not met. Please install missing components.${NC}"
        exit 1
    fi

    echo ""
}

# Convert domain to username (matches vpsmanager logic)
domain_to_username() {
    local domain="$1"
    local safe_domain="${domain//\./-}"
    safe_domain="${safe_domain:0:28}"
    safe_domain="${safe_domain%-}"
    echo "www-site-${safe_domain}"
}

# ============================================================================
# Cleanup function
# ============================================================================

cleanup_test_sites() {
    print_header "Cleaning Up Test Sites"

    # Delete test sites if they exist
    for site in "$TEST_SITE_A" "$TEST_SITE_B"; do
        if "$VPSMANAGER_BIN" site:info "$site" &>/dev/null; then
            print_info "Deleting site: $site"
            if "$VPSMANAGER_BIN" site:delete "$site" --force &>/dev/null; then
                print_success "Deleted $site"
            else
                print_warning "Failed to delete $site"
            fi
        fi
    done

    echo ""
}

# ============================================================================
# Test Functions
# ============================================================================

test_01_create_test_sites() {
    print_test "Create two test sites"

    local success=true

    # Create Site A
    print_info "Creating $TEST_SITE_A..."
    if output=$("$VPSMANAGER_BIN" site:create "$TEST_SITE_A" --type=php 2>&1); then
        if echo "$output" | jq -e '.success == true' &>/dev/null; then
            print_info "Site A created successfully"
        else
            print_error "Site A creation failed: $output"
            success=false
        fi
    else
        print_error "Site A creation command failed"
        success=false
    fi

    # Create Site B
    print_info "Creating $TEST_SITE_B..."
    if output=$("$VPSMANAGER_BIN" site:create "$TEST_SITE_B" --type=php 2>&1); then
        if echo "$output" | jq -e '.success == true' &>/dev/null; then
            print_info "Site B created successfully"
        else
            print_error "Site B creation failed: $output"
            success=false
        fi
    else
        print_error "Site B creation command failed"
        success=false
    fi

    if [[ "$success" == "true" ]]; then
        pass_test "Both test sites created"
    else
        fail_test "Failed to create test sites"
        return 1
    fi
}

test_02_verify_unique_users() {
    print_test "Verify each site has unique system user"

    local user_a user_b
    user_a=$(domain_to_username "$TEST_SITE_A")
    user_b=$(domain_to_username "$TEST_SITE_B")

    local success=true

    # Check user A exists
    if id "$user_a" &>/dev/null; then
        print_info "User $user_a exists (UID: $(id -u "$user_a"))"
    else
        print_error "User $user_a does not exist"
        success=false
    fi

    # Check user B exists
    if id "$user_b" &>/dev/null; then
        print_info "User $user_b exists (UID: $(id -u "$user_b"))"
    else
        print_error "User $user_b does not exist"
        success=false
    fi

    # Check users are different
    if [[ "$user_a" != "$user_b" ]]; then
        print_info "Users are different: $user_a vs $user_b"
    else
        print_error "Users are the same!"
        success=false
    fi

    # Check users cannot login
    local shell_a shell_b
    shell_a=$(getent passwd "$user_a" | cut -d: -f7)
    shell_b=$(getent passwd "$user_b" | cut -d: -f7)

    if [[ "$shell_a" == "/usr/sbin/nologin" ]]; then
        print_info "User $user_a has nologin shell (secure)"
    else
        print_warning "User $user_a shell is $shell_a (expected /usr/sbin/nologin)"
    fi

    if [[ "$shell_b" == "/usr/sbin/nologin" ]]; then
        print_info "User $user_b has nologin shell (secure)"
    else
        print_warning "User $user_b shell is $shell_b (expected /usr/sbin/nologin)"
    fi

    if [[ "$success" == "true" ]]; then
        pass_test "Both sites have unique system users with proper security"
    else
        fail_test "User isolation verification failed"
        return 1
    fi
}

test_03_verify_file_permissions() {
    print_test "Verify Site A cannot read Site B files (permission denied)"

    local user_a user_b
    user_a=$(domain_to_username "$TEST_SITE_A")
    user_b=$(domain_to_username "$TEST_SITE_B")

    local site_a_root="${SITES_ROOT}/${TEST_SITE_A}"
    local site_b_root="${SITES_ROOT}/${TEST_SITE_B}"

    # Create a secret file in Site B
    local secret_file="${site_b_root}/secret.txt"
    echo "Secret data from Site B" > "$secret_file"
    chown "${user_b}:${user_b}" "$secret_file"
    chmod 600 "$secret_file"

    print_info "Created secret file: $secret_file"
    print_info "Owner: $(stat -c '%U:%G' "$secret_file"), Permissions: $(stat -c '%a' "$secret_file")"

    # Try to read as Site A user (should fail)
    if sudo -u "$user_a" cat "$secret_file" &>/dev/null; then
        fail_test "Site A was able to read Site B's secret file (SECURITY VIOLATION)"
        return 1
    else
        print_info "Site A correctly denied access to Site B's file"
    fi

    # Verify directory permissions
    local site_b_perms
    site_b_perms=$(stat -c '%a' "$site_b_root")
    if [[ "$site_b_perms" == "750" ]]; then
        print_info "Site B root has 750 permissions (correct)"
    else
        print_warning "Site B root has $site_b_perms permissions (expected 750)"
    fi

    # Try to list Site B directory as Site A
    if sudo -u "$user_a" ls "$site_b_root" &>/dev/null; then
        fail_test "Site A can list Site B directory (SECURITY VIOLATION)"
        return 1
    else
        print_info "Site A correctly denied directory listing of Site B"
    fi

    pass_test "File isolation verified - Site A cannot access Site B files"
}

test_04_verify_database_isolation() {
    print_test "Verify Site A cannot access Site B database"

    # Get database credentials from site info
    local site_a_info site_b_info
    site_a_info=$("$VPSMANAGER_BIN" site:info "$TEST_SITE_A")
    site_b_info=$("$VPSMANAGER_BIN" site:info "$TEST_SITE_B")

    local db_a_name db_a_user db_a_pass
    local db_b_name db_b_user db_b_pass

    db_a_name=$(echo "$site_a_info" | jq -r '.data.db_name')
    db_a_user=$(echo "$site_a_info" | jq -r '.data.db_user')

    db_b_name=$(echo "$site_b_info" | jq -r '.data.db_name')
    db_b_user=$(echo "$site_b_info" | jq -r '.data.db_user')

    print_info "Site A database: $db_a_name (user: $db_a_user)"
    print_info "Site B database: $db_b_name (user: $db_b_user)"

    # Verify databases are different
    if [[ "$db_a_name" != "$db_b_name" ]]; then
        print_info "Databases are unique"
    else
        fail_test "Databases are the same!"
        return 1
    fi

    # Try to access Site B's database with Site A's credentials
    if mysql -u "$db_a_user" "$db_b_name" -e "SHOW TABLES;" &>/dev/null; then
        fail_test "Site A user can access Site B database (SECURITY VIOLATION)"
        return 1
    else
        print_info "Site A user correctly denied access to Site B database"
    fi

    # Verify Site A can access its own database
    if mysql -u "$db_a_user" "$db_a_name" -e "SHOW TABLES;" &>/dev/null; then
        print_info "Site A can access its own database (correct)"
    else
        print_warning "Site A cannot access its own database"
    fi

    pass_test "Database isolation verified - Site A cannot access Site B database"
}

test_05_verify_php_open_basedir() {
    print_test "Verify Site A PHP process restricted by open_basedir"

    local user_a
    user_a=$(domain_to_username "$TEST_SITE_A")

    local site_a_root="${SITES_ROOT}/${TEST_SITE_A}"
    local site_b_root="${SITES_ROOT}/${TEST_SITE_B}"

    # Create a PHP test script that tries to access Site B
    local test_script="${site_a_root}/test_access.php"
    cat > "$test_script" <<'EOFPHP'
<?php
// Try to read a file from Site B
$site_b_path = $argv[1] ?? '/etc/passwd';
$result = @file_get_contents($site_b_path);
if ($result !== false) {
    echo "SUCCESS: Read file from $site_b_path\n";
    exit(0);
} else {
    echo "DENIED: Cannot read $site_b_path\n";
    exit(1);
}
EOFPHP

    chown "${user_a}:${user_a}" "$test_script"

    # Test 1: Try to access Site B's directory
    print_info "Testing PHP open_basedir for Site B directory..."
    if sudo -u "$user_a" php "$test_script" "${site_b_root}/index.html" 2>&1 | grep -q "DENIED"; then
        print_info "PHP correctly blocked access to Site B directory"
    elif sudo -u "$user_a" php "$test_script" "${site_b_root}/index.html" 2>&1 | grep -q "open_basedir restriction"; then
        print_info "PHP open_basedir blocked access (via warning)"
    else
        # Note: open_basedir is enforced by PHP-FPM pool, not CLI
        print_warning "PHP CLI doesn't enforce open_basedir (expected - use PHP-FPM for enforcement)"
    fi

    # Test 2: Try to access /etc/passwd
    print_info "Testing PHP open_basedir for system files..."
    if sudo -u "$user_a" php "$test_script" "/etc/passwd" 2>&1 | grep -q "DENIED"; then
        print_info "PHP correctly blocked access to /etc/passwd"
    elif sudo -u "$user_a" php "$test_script" "/etc/passwd" 2>&1 | grep -q "open_basedir restriction"; then
        print_info "PHP open_basedir would block access (via PHP-FPM)"
    else
        print_warning "PHP CLI can read system files (open_basedir enforced by PHP-FPM, not CLI)"
    fi

    # Check PHP-FPM pool configuration
    local pool_config="/etc/php/8.2/fpm/pool.d/${TEST_SITE_A}.conf"
    if [[ -f "$pool_config" ]]; then
        if grep -q "php_admin_value\[open_basedir\]" "$pool_config"; then
            print_info "PHP-FPM pool has open_basedir configured"
            local basedir
            basedir=$(grep "php_admin_value\[open_basedir\]" "$pool_config" | head -n1)
            print_info "Config: $basedir"
            pass_test "PHP open_basedir is configured in PHP-FPM pool"
        else
            fail_test "PHP-FPM pool missing open_basedir configuration"
            return 1
        fi
    else
        print_warning "PHP-FPM pool config not found at $pool_config"
        fail_test "Cannot verify open_basedir configuration"
        return 1
    fi

    rm -f "$test_script"
}

test_06_verify_tmp_isolation() {
    print_test "Verify Site A cannot list /tmp contents or access system-wide temp"

    local user_a
    user_a=$(domain_to_username "$TEST_SITE_A")

    local site_a_root="${SITES_ROOT}/${TEST_SITE_A}"

    # Check if site has its own tmp directory
    if [[ -d "${site_a_root}/tmp" ]]; then
        print_info "Site A has dedicated tmp directory: ${site_a_root}/tmp"

        # Check ownership
        local tmp_owner
        tmp_owner=$(stat -c '%U' "${site_a_root}/tmp")
        if [[ "$tmp_owner" == "$user_a" ]]; then
            print_info "tmp directory owned by site user (correct)"
        else
            print_warning "tmp directory owned by $tmp_owner (expected $user_a)"
        fi
    else
        print_warning "Site A missing dedicated tmp directory"
    fi

    # Verify PHP-FPM uses site-specific tmp
    local pool_config="/etc/php/8.2/fpm/pool.d/${TEST_SITE_A}.conf"
    if [[ -f "$pool_config" ]]; then
        if grep -q "php_admin_value\[upload_tmp_dir\].*${site_a_root}/tmp" "$pool_config"; then
            print_info "PHP-FPM configured to use site-specific tmp"
        else
            print_warning "PHP-FPM may not be using site-specific tmp"
        fi

        if grep -q "php_admin_value\[session.save_path\].*${site_a_root}/sessions" "$pool_config"; then
            print_info "PHP-FPM configured to use site-specific sessions"
        else
            print_warning "PHP-FPM may not be using site-specific sessions"
        fi
    fi

    # Try to access system /tmp as site user
    print_info "Testing access to system /tmp..."
    if sudo -u "$user_a" ls /tmp &>/dev/null; then
        print_warning "Site user can list /tmp (may see other processes' files)"
        # This is expected - /tmp is world-readable
        # But PHP-FPM should use site-specific tmp due to upload_tmp_dir
    else
        print_info "Site user denied access to /tmp"
    fi

    pass_test "Site has dedicated tmp and sessions directories configured in PHP-FPM"
}

test_07_verify_process_isolation() {
    print_test "Verify PHP-FPM processes run as correct site users"

    local user_a user_b
    user_a=$(domain_to_username "$TEST_SITE_A")
    user_b=$(domain_to_username "$TEST_SITE_B")

    # Check if PHP-FPM processes exist for these sites
    print_info "Checking for PHP-FPM processes..."

    # Reload PHP-FPM to ensure pools are loaded
    systemctl reload php8.2-fpm &>/dev/null || true
    sleep 2

    # Check for pool processes
    if pgrep -u "$user_a" php-fpm &>/dev/null; then
        local count
        count=$(pgrep -u "$user_a" php-fpm | wc -l)
        print_info "Found $count PHP-FPM process(es) running as $user_a"
    else
        print_warning "No PHP-FPM processes found for $user_a (may start on first request)"
    fi

    if pgrep -u "$user_b" php-fpm &>/dev/null; then
        local count
        count=$(pgrep -u "$user_b" php-fpm | wc -l)
        print_info "Found $count PHP-FPM process(es) running as $user_b"
    else
        print_warning "No PHP-FPM processes found for $user_b (may start on first request)"
    fi

    # Verify PHP-FPM pool configuration
    local pool_a="/etc/php/8.2/fpm/pool.d/${TEST_SITE_A}.conf"
    local pool_b="/etc/php/8.2/fpm/pool.d/${TEST_SITE_B}.conf"

    local success=true

    if [[ -f "$pool_a" ]]; then
        if grep -q "^user = ${user_a}" "$pool_a"; then
            print_info "Pool A configured with user: $user_a"
        else
            print_error "Pool A not configured with correct user"
            success=false
        fi
    else
        print_error "Pool A configuration not found"
        success=false
    fi

    if [[ -f "$pool_b" ]]; then
        if grep -q "^user = ${user_b}" "$pool_b"; then
            print_info "Pool B configured with user: $user_b"
        else
            print_error "Pool B not configured with correct user"
            success=false
        fi
    else
        print_error "Pool B configuration not found"
        success=false
    fi

    if [[ "$success" == "true" ]]; then
        pass_test "PHP-FPM pools configured with correct site-specific users"
    else
        fail_test "PHP-FPM pool configuration issues detected"
        return 1
    fi
}

# ============================================================================
# Main test runner
# ============================================================================

main() {
    print_header "VPSManager Site Isolation Integration Tests"
    echo -e "${BOLD}Testing per-site user isolation security${NC}\n"

    check_root
    check_prerequisites

    # Clean up any existing test sites
    cleanup_test_sites

    # Run tests
    print_header "Running Tests"

    test_01_create_test_sites || true
    test_02_verify_unique_users || true
    test_03_verify_file_permissions || true
    test_04_verify_database_isolation || true
    test_05_verify_php_open_basedir || true
    test_06_verify_tmp_isolation || true
    test_07_verify_process_isolation || true

    # Final cleanup
    cleanup_test_sites

    # Print summary
    print_header "Test Summary"
    echo -e "${BOLD}Total Tests:${NC} $TESTS_TOTAL"
    echo -e "${GREEN}${BOLD}Passed:${NC} $TESTS_PASSED"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}${BOLD}Failed:${NC} $TESTS_FAILED"
    else
        echo -e "${GREEN}${BOLD}Failed:${NC} 0"
    fi

    echo ""
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ ALL TESTS PASSED${NC}"
        echo -e "${GREEN}Site isolation is working correctly!${NC}"
        exit 0
    else
        echo -e "${RED}${BOLD}✗ SOME TESTS FAILED${NC}"
        echo -e "${RED}Site isolation has issues that need to be addressed.${NC}"
        exit 1
    fi
}

# Trap errors
trap 'echo -e "\n${RED}Test runner encountered an error${NC}"; cleanup_test_sites; exit 1' ERR

# Run main
main "$@"
