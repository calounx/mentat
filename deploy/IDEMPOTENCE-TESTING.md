# Idempotence Testing and Implementation Guide

## Overview

This document describes the idempotence implementation across all deployment scripts in the CHOM project. Idempotent scripts can be run multiple times safely without creating duplicate resources, causing errors, or producing different results.

## Table of Contents

1. [What is Idempotence?](#what-is-idempotence)
2. [Why Idempotence Matters](#why-idempotence-matters)
3. [Idempotent Patterns Library](#idempotent-patterns-library)
4. [Testing Framework](#testing-framework)
5. [Pre-flight Checks](#pre-flight-checks)
6. [Updated Scripts](#updated-scripts)
7. [Common Patterns](#common-patterns)
8. [Testing Procedures](#testing-procedures)
9. [Troubleshooting](#troubleshooting)

## What is Idempotence?

Idempotence is a property where an operation can be applied multiple times without changing the result beyond the initial application. In deployment contexts:

- Running a script once: Creates user, installs package, configures service
- Running a script twice: No errors, no duplicates, same final state
- Running a script N times: Identical result every time

## Why Idempotence Matters

### Benefits

1. **Crash Recovery**: Scripts can be re-run after failures without manual cleanup
2. **Configuration Drift**: Re-running scripts brings systems back to desired state
3. **Partial Execution**: Scripts can safely resume from any point
4. **Testing**: Scripts can be tested multiple times without system resets
5. **CI/CD**: Automated deployments can retry safely on transient failures
6. **Disaster Recovery**: Systems can be rebuilt to exact specifications

### Risks Without Idempotence

- Duplicate users, files, database entries
- Configuration file corruption from appending
- Service failures from repeated operations
- Port conflicts from multiple instances
- Resource exhaustion from accumulating artifacts

## Idempotent Patterns Library

### Location

```bash
/home/calounx/repositories/mentat/deploy/utils/idempotence.sh
```

### Usage

```bash
# Source the library in your deployment script
source "${SCRIPT_DIR}/../utils/idempotence.sh"
```

### Key Functions

#### User Management

```bash
# Create user only if doesn't exist
ensure_user_exists "username" "/home/username" "/bin/bash"

# Create system user only if doesn't exist
ensure_system_user_exists "observability"

# Add user to group (idempotent)
ensure_user_in_group "username" "www-data"
```

#### Package Management

```bash
# Check if package is installed
if is_package_installed "nginx"; then
    echo "nginx is installed"
fi

# Install single package
ensure_package_installed "nginx"

# Install multiple packages
ensure_packages_installed curl wget git vim
```

#### Service Management

```bash
# Enable service (only if not enabled)
ensure_service_enabled "nginx"

# Start service (only if not running)
ensure_service_started "nginx"

# Enable and start service
ensure_service_running "nginx"

# Restart service (always safe)
restart_service "nginx"

# Reload service configuration
reload_service "nginx"

# Reload systemd daemon (always safe)
reload_systemd_daemon
```

#### File and Directory Management

```bash
# Create directory with ownership and permissions
ensure_directory_exists "/opt/app" "user:group" "755"

# Create file if doesn't exist
ensure_file_exists "/etc/config" "user:group" "644"

# Create symbolic link (updates if target changed)
ensure_symlink_exists "/opt/app/current" "/opt/app/releases/123"

# Backup file before modification
backup_file "/etc/important.conf"
```

#### Configuration Management

```bash
# Add line to file (only if not present)
ensure_line_in_file "/etc/hosts" "127.0.0.1 localhost"

# Set configuration value (create or update)
ensure_config_value "/etc/app.conf" "port" "8080" "="

# Uncomment configuration line
ensure_line_uncommented "/etc/ssh/sshd_config" "PermitRootLogin"

# Comment configuration line
ensure_line_commented "/etc/ssh/sshd_config" "PasswordAuthentication yes"
```

#### Database Operations

```bash
# Create PostgreSQL user (only if doesn't exist)
ensure_postgres_user_exists "appuser" "password123"

# Create PostgreSQL database (only if doesn't exist)
ensure_postgres_database_exists "appdb" "appuser"
```

#### APT Repository Management

```bash
# Add APT repository key
ensure_apt_key_exists "https://example.com/key.gpg" "/etc/apt/keyrings/example.gpg"

# Add APT repository source
ensure_apt_source_exists "deb https://repo.example.com stable main" "/etc/apt/sources.list.d/example.list"
```

#### System Configuration

```bash
# Set sysctl parameter
ensure_sysctl_value "net.ipv4.ip_forward" "1" "/etc/sysctl.d/99-custom.conf"
```

## Testing Framework

### Location

```bash
/home/calounx/repositories/mentat/deploy/tests/test-idempotence.sh
```

### Basic Usage

```bash
# Test a single script
./test-idempotence.sh --script /path/to/script.sh

# Test with custom iterations
./test-idempotence.sh --script /path/to/script.sh --iterations 3

# Test all deployment scripts
./test-idempotence.sh

# Clean up after testing
./test-idempotence.sh --cleanup
```

### How It Works

1. **Baseline Snapshot**: Captures system state before first run
2. **First Iteration**: Runs script, captures post-run state
3. **Second Iteration**: Runs script again, captures state
4. **Comparison**: Compares iterations to ensure identical results
5. **Reporting**: Shows pass/fail for each script

### What Gets Tested

- User accounts and groups
- Installed packages
- Systemd services (running and enabled)
- File system structure
- Firewall rules
- Network ports
- Sysctl parameters
- Cron jobs

### Example Output

```
========================================
Testing Idempotence: prepare-mentat.sh
========================================
[STEP] Creating system snapshot: baseline
[SUCCESS] Snapshot created: baseline
=== Iteration 1/2 ===
[STEP] Creating system snapshot: pre-iteration-1
[SUCCESS] Script executed successfully
[SUCCESS] Snapshot created: post-iteration-1
=== Iteration 2/2 ===
[SUCCESS] Script executed successfully
[SUCCESS] No changes detected (idempotent)

[SUCCESS] Script is idempotent: Multiple runs produce identical results
```

## Pre-flight Checks

### Location

```bash
/home/calounx/repositories/mentat/deploy/scripts/preflight-check.sh
```

### Usage

```bash
# Check local system
./preflight-check.sh

# Check for specific server deployment
./preflight-check.sh --server mentat
./preflight-check.sh --server landsraad

# Skip network checks
./preflight-check.sh --skip-network

# Non-strict mode (warnings don't fail)
./preflight-check.sh --no-strict
```

### Checks Performed

1. **Operating System**
   - Linux kernel
   - Debian-based distribution
   - Minimum Debian version (11+)
   - Architecture (x86_64)

2. **System Resources**
   - Memory (minimum 2GB)
   - Disk space (minimum 20GB)
   - CPU cores (recommended 2+)
   - System load

3. **Privileges**
   - Not running as root (recommended)
   - Sudo access available

4. **Network**
   - Internet connectivity
   - DNS resolution
   - Package repository access
   - GitHub access

5. **Server Connectivity** (when applicable)
   - DNS resolution for target servers
   - Host reachability
   - SSH port accessibility

6. **Required Packages**
   - curl
   - wget
   - git
   - sudo
   - systemctl

7. **Port Availability**
   - Checks ports needed for deployment
   - Varies by server type (mentat vs landsraad)

8. **Filesystem Permissions**
   - Write access to /opt
   - Write access to /etc
   - Write access to /var

9. **Systemd**
   - Systemd is running
   - systemctl command available
   - Can query services

10. **Security**
    - UFW firewall availability
    - SSH configuration
    - Automatic security updates

11. **Environment**
    - Required environment variables
    - PATH configuration

12. **Time Configuration**
    - NTP synchronization
    - Timezone configuration

### Example Usage in Deployment

```bash
#!/usr/bin/env bash
# deployment-script.sh

# Run preflight checks before deployment
if ! ./preflight-check.sh --server mentat; then
    echo "Pre-flight checks failed. Aborting deployment."
    exit 1
fi

# Continue with deployment
./prepare-mentat.sh
./deploy-observability.sh
```

## Updated Scripts

All deployment scripts have been updated with idempotent patterns:

### Core Deployment Scripts

- `prepare-mentat.sh` - Mentat server preparation
- `prepare-landsraad.sh` - Landsraad server preparation
- `deploy-application.sh` - Application deployment
- `deploy-observability.sh` - Observability stack deployment
- `setup-firewall.sh` - Firewall configuration
- `setup-ssl.sh` - SSL certificate setup

### Security Scripts

- `deploy/security/master-security-setup.sh`
- `deploy/security/setup-fail2ban.sh`
- `deploy/security/configure-firewall.sh`
- `deploy/security/harden-application.sh`
- All other security/* scripts

### Validation Scripts

- `chom/deploy/validation/pre-deployment-check.sh`
- `chom/deploy/validation/post-deployment-check.sh`
- All other validation/* scripts

## Common Patterns

### Before (Non-Idempotent)

```bash
# BAD: Creates duplicate users on second run
useradd -m stilgar

# BAD: Appends to file every run
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# BAD: Fails if service already enabled
systemctl enable nginx

# BAD: Downloads every time
wget https://example.com/file.tar.gz

# BAD: Overwrites without backup
cp config.yml /etc/app/config.yml
```

### After (Idempotent)

```bash
# GOOD: Check before creating
if ! id stilgar &>/dev/null; then
    useradd -m stilgar
fi

# GOOD: Use helper function
ensure_sysctl_value "net.ipv4.ip_forward" "1"

# GOOD: Only enable if not already enabled
ensure_service_enabled "nginx"

# GOOD: Download only if not present
ensure_file_downloaded "https://example.com/file.tar.gz" "/tmp/file.tar.gz"

# GOOD: Backup before overwriting
backup_file "/etc/app/config.yml"
cp config.yml /etc/app/config.yml
```

### Package Installation

```bash
# Before (non-idempotent)
apt-get install -y nginx php postgresql

# After (idempotent with helper)
ensure_packages_installed nginx php postgresql

# After (idempotent manual)
for pkg in nginx php postgresql; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        apt-get install -y "$pkg"
    fi
done
```

### Directory Creation

```bash
# Before
mkdir /opt/app
mkdir /opt/app/releases
mkdir /opt/app/shared

# After (always idempotent with -p)
mkdir -p /opt/app/{releases,shared}

# After (with helper)
ensure_directory_exists "/opt/app/releases" "user:group" "755"
```

### Service Management

```bash
# Before (fails on second run)
systemctl start nginx
systemctl enable nginx

# After (idempotent)
ensure_service_running "nginx"

# Alternative (always safe)
systemctl restart nginx  # restart is always safe
```

### File Modifications

```bash
# Before (appends every run)
echo "PermitRootLogin no" >> /etc/ssh/sshd_config

# After (idempotent)
if ! grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config
fi

# After (with helper)
ensure_line_in_file "/etc/ssh/sshd_config" "PermitRootLogin no"

# After (using sed for replacement)
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
```

## Testing Procedures

### 1. Local Testing (Safe)

Test on a local VM or development system:

```bash
# Run preflight checks
cd /home/calounx/repositories/mentat/deploy
./scripts/preflight-check.sh --server local

# Test a single script with idempotence framework
./tests/test-idempotence.sh --script ./scripts/prepare-mentat.sh --iterations 3

# Test all scripts
./tests/test-idempotence.sh --iterations 2
```

### 2. Manual Verification

Run script twice manually and verify:

```bash
# First run
./scripts/prepare-mentat.sh > run1.log 2>&1

# Second run
./scripts/prepare-mentat.sh > run2.log 2>&1

# Compare logs for errors
diff run1.log run2.log

# Check for duplicate resources
getent passwd | sort  # Check for duplicate users
dpkg -l | grep -E "nginx|php"  # Check packages
systemctl list-units --type=service  # Check services
```

### 3. Snapshot Comparison

Use system snapshots to verify idempotence:

```bash
# Before first run
dpkg -l > packages-before.txt
systemctl list-units > services-before.txt
getent passwd > users-before.txt

# Run script
./scripts/prepare-mentat.sh

# After first run
dpkg -l > packages-after1.txt
systemctl list-units > services-after1.txt
getent passwd > users-after1.txt

# Run script again
./scripts/prepare-mentat.sh

# After second run
dpkg -l > packages-after2.txt
systemctl list-units > services-after2.txt
getent passwd > users-after2.txt

# Compare
diff packages-after1.txt packages-after2.txt
diff services-after1.txt services-after2.txt
diff users-after1.txt users-after2.txt

# Should show no differences
```

### 4. Integration Testing

Test complete deployment workflow:

```bash
# Run preflight
./scripts/preflight-check.sh --server mentat

# First deployment
./scripts/prepare-mentat.sh
./scripts/deploy-observability.sh

# Verify services
systemctl status prometheus grafana-server loki

# Second deployment (should be idempotent)
./scripts/prepare-mentat.sh
./scripts/deploy-observability.sh

# Verify no duplicates or errors
journalctl -xe | grep -i error
```

### 5. Automated CI/CD Testing

Include in CI/CD pipeline:

```yaml
# .github/workflows/test-idempotence.yml
name: Idempotence Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Run preflight checks
        run: |
          cd deploy
          ./scripts/preflight-check.sh --skip-network

      - name: Test script idempotence
        run: |
          cd deploy
          ./tests/test-idempotence.sh --iterations 3
```

## Troubleshooting

### Common Issues

#### Issue: User Already Exists Error

**Problem:**
```
useradd: user 'stilgar' already exists
```

**Solution:**
```bash
# Use idempotent pattern
if ! id stilgar &>/dev/null; then
    useradd -m stilgar
fi

# Or use helper
ensure_user_exists "stilgar"
```

#### Issue: Package Reinstallation

**Problem:**
Script tries to reinstall packages every run (slow)

**Solution:**
```bash
# Check before installing
if ! dpkg -l | grep -q "^ii  nginx"; then
    apt-get install -y nginx
fi

# Or use helper
ensure_package_installed "nginx"
```

#### Issue: Service Already Enabled

**Problem:**
```
Failed to enable unit: Unit file nginx.service already enabled
```

**Solution:**
```bash
# Check before enabling
if ! systemctl is-enabled nginx &>/dev/null; then
    systemctl enable nginx
fi

# Or use helper
ensure_service_enabled "nginx"
```

#### Issue: Duplicate Configuration Lines

**Problem:**
Configuration file grows with duplicate entries on each run

**Solution:**
```bash
# Check before appending
if ! grep -qF "my_setting=value" /etc/config; then
    echo "my_setting=value" >> /etc/config
fi

# Or use helper
ensure_line_in_file "/etc/config" "my_setting=value"
```

#### Issue: File Download Every Run

**Problem:**
Large files re-downloaded on every run

**Solution:**
```bash
# Check before downloading
if [[ ! -f /tmp/file.tar.gz ]]; then
    wget https://example.com/file.tar.gz -O /tmp/file.tar.gz
fi

# Or use helper
ensure_file_downloaded "https://example.com/file.tar.gz" "/tmp/file.tar.gz"
```

### Debugging Idempotence Issues

#### Enable Verbose Logging

```bash
# Add to script
set -x  # Print each command before executing

# Run with verbose output
bash -x ./script.sh
```

#### Check System State

```bash
# Users
getent passwd | grep -E "stilgar|observability"

# Groups
getent group | grep -E "www-data|observability"

# Packages
dpkg -l | grep -E "nginx|php|postgresql"

# Services
systemctl list-units --type=service --all | grep -E "nginx|prometheus|grafana"

# Files
find /opt -type f
find /etc/observability -type f

# Ports
sudo netstat -tuln | grep -E "9090|3000|9093"
```

#### Use Dry Run Mode

Add dry-run capability to scripts:

```bash
DRY_RUN="${DRY_RUN:-false}"

run_command() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] $*"
    else
        "$@"
    fi
}

# Usage
run_command useradd -m stilgar
```

## Best Practices

### 1. Always Check Before Acting

```bash
# Good pattern
if [[ ! -f /etc/config ]]; then
    create_config
fi
```

### 2. Use Built-in Idempotent Tools

```bash
# mkdir -p is idempotent
mkdir -p /opt/app

# systemctl restart is idempotent
systemctl restart nginx

# ln -sf is idempotent
ln -sf /opt/app/current /opt/app/release-123
```

### 3. Backup Before Modification

```bash
# Always backup important files
if [[ -f /etc/important.conf ]]; then
    cp /etc/important.conf /etc/important.conf.backup.$(date +%s)
fi
```

### 4. Use Atomic Operations

```bash
# Atomic symlink update
ln -sf /new/target /tmp/link.tmp.$$
mv -Tf /tmp/link.tmp.$$ /current/link
```

### 5. Test Idempotence

```bash
# Test every script
./tests/test-idempotence.sh --script ./my-script.sh
```

### 6. Document Non-Idempotent Operations

```bash
# If operation cannot be made idempotent, document why
# NON-IDEMPOTENT: This generates a new secret key on each run
# Rationale: Required for security, users must manually preserve keys
openssl rand -base64 32 > /etc/app/secret.key
```

## Rollback Safety

All updated scripts include:

### Error Traps

```bash
# Cleanup on error
trap cleanup_on_error ERR EXIT

cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed, cleaning up..."
        # Restore backups, remove partial changes
    fi
}
```

### Backup Strategy

```bash
# Automatic backups
backup_file "/etc/important.conf"
# Creates: /etc/important.conf.backup.20240115_143022
```

### Rollback Functions

```bash
rollback() {
    log_warning "Rolling back changes..."
    # Restore from backups
    # Remove created resources
    # Stop services
}
```

## Validation

All scripts should pass:

1. **Preflight checks**: `./scripts/preflight-check.sh`
2. **Idempotence tests**: `./tests/test-idempotence.sh`
3. **Manual verification**: Run twice, verify no errors
4. **Service health**: All services still running
5. **No duplicates**: No duplicate users, files, config lines

## Continuous Improvement

### Monitoring Idempotence

1. Add idempotence tests to CI/CD
2. Run tests on representative systems
3. Review test failures promptly
4. Update patterns library with new patterns

### Contributing

When adding new deployment operations:

1. Use existing helper functions from `idempotence.sh`
2. Add new helper functions if needed
3. Test with `test-idempotence.sh`
4. Document any non-idempotent operations
5. Update this guide

## References

- [Idempotent Patterns Library](/home/calounx/repositories/mentat/deploy/utils/idempotence.sh)
- [Testing Framework](/home/calounx/repositories/mentat/deploy/tests/test-idempotence.sh)
- [Preflight Checks](/home/calounx/repositories/mentat/deploy/scripts/preflight-check.sh)
- [Deployment Scripts](/home/calounx/repositories/mentat/deploy/scripts/)

## Support

For issues or questions:

1. Check this guide
2. Review script source code
3. Run idempotence tests
4. Check error logs
5. Consult team documentation

---

**Last Updated**: 2026-01-03
**Version**: 1.0.0
**Maintainer**: CHOM DevOps Team
