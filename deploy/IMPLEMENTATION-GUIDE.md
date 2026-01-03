# Idempotence Implementation Guide - Quick Reference

## Critical Updates Applied

### 1. Core Infrastructure Created

#### `/home/calounx/repositories/mentat/deploy/utils/idempotence.sh`
Comprehensive helper function library providing:
- User/group management (ensure_user_exists, ensure_system_user_exists)
- Package management (ensure_package_installed, ensure_packages_installed)
- Service management (ensure_service_enabled, ensure_service_running)
- File/directory operations (ensure_directory_exists, ensure_file_exists)
- Configuration management (ensure_line_in_file, ensure_config_value)
- Database operations (ensure_postgres_user_exists, ensure_postgres_database_exists)
- APT repository management
- System configuration (ensure_sysctl_value)
- Validation helpers

**Usage in scripts:**
```bash
source "${SCRIPT_DIR}/../utils/idempotence.sh"
```

#### `/home/calounx/repositories/mentat/deploy/scripts/preflight-check.sh`
Comprehensive pre-deployment validation:
- OS version and architecture
- System resources (memory, disk, CPU)
- Sudo access
- Network connectivity
- Server reachability
- Required packages
- Port availability
- Filesystem permissions
- Systemd functionality
- Security settings
- Time configuration

**Usage:**
```bash
./preflight-check.sh --server mentat
./preflight-check.sh --server landsraad --skip-network
```

#### `/home/calounx/repositories/mentat/deploy/tests/test-idempotence.sh`
Automated idempotence testing:
- System state snapshots
- Multiple iteration execution
- State comparison
- Automated reporting

**Usage:**
```bash
./test-idempotence.sh --script ./prepare-mentat.sh --iterations 3
./test-idempotence.sh  # Test all scripts
```

### 2. Key Idempotent Patterns to Apply

#### Pattern 1: User Creation

**Before (non-idempotent):**
```bash
useradd -m stilgar
```

**After (idempotent):**
```bash
if ! id stilgar &>/dev/null; then
    useradd -m stilgar
fi

# Or use helper:
ensure_user_exists "stilgar"
```

#### Pattern 2: Package Installation

**Before:**
```bash
apt-get install -y nginx php postgresql
```

**After:**
```bash
# Check each package first
for pkg in nginx php postgresql; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        apt-get install -y "$pkg"
    fi
done

# Or use helper:
ensure_packages_installed nginx php postgresql
```

#### Pattern 3: Service Management

**Before:**
```bash
systemctl enable nginx
systemctl start nginx
```

**After:**
```bash
# Check before enabling/starting
if ! systemctl is-enabled nginx &>/dev/null; then
    systemctl enable nginx
fi
if ! systemctl is-active nginx &>/dev/null; then
    systemctl start nginx
fi

# Or use helpers:
ensure_service_enabled "nginx"
ensure_service_started "nginx"
# Or combined:
ensure_service_running "nginx"

# restart is always safe:
systemctl restart nginx
```

#### Pattern 4: Directory Creation

**Before:**
```bash
mkdir /opt/app
mkdir /opt/app/bin
```

**After (always idempotent with -p):**
```bash
mkdir -p /opt/app/bin

# With ownership/permissions:
ensure_directory_exists "/opt/app/bin" "user:group" "755"
```

#### Pattern 5: Configuration Files

**Before (duplicates on re-run):**
```bash
echo "setting=value" >> /etc/config
```

**After:**
```bash
# Check before appending
if ! grep -qF "setting=value" /etc/config; then
    echo "setting=value" >> /etc/config
fi

# Or use helper:
ensure_line_in_file "/etc/config" "setting=value"

# For key=value configs:
ensure_config_value "/etc/config" "setting" "value" "="
```

#### Pattern 6: File Downloads

**Before:**
```bash
wget https://example.com/file.tar.gz
```

**After:**
```bash
# Check if already downloaded
if [[ ! -f /tmp/file.tar.gz ]]; then
    wget https://example.com/file.tar.gz -O /tmp/file.tar.gz
fi

# Or use helper:
ensure_file_downloaded "https://example.com/file.tar.gz" "/tmp/file.tar.gz"
```

#### Pattern 7: Binary Installation

**Before:**
```bash
cp prometheus /usr/local/bin/
chmod +x /usr/local/bin/prometheus
```

**After:**
```bash
# Check if binary exists and is identical
if [[ ! -f /usr/local/bin/prometheus ]] || ! cmp -s prometheus /usr/local/bin/prometheus; then
    cp prometheus /usr/local/bin/
    chmod +x /usr/local/bin/prometheus
fi

# Or use helper:
ensure_binary_installed "prometheus" "prometheus"
```

#### Pattern 8: Systemd Services

**Before:**
```bash
# Create service file
cat > /etc/systemd/system/myservice.service <<EOF
[Unit]
Description=My Service
...
EOF

systemctl daemon-reload
systemctl enable myservice
systemctl start myservice
```

**After:**
```bash
# Check if service file changed
local service_file="/etc/systemd/system/myservice.service"
local service_changed=false

if [[ ! -f "$service_file" ]]; then
    service_changed=true
elif ! grep -q "Description=My Service" "$service_file"; then
    service_changed=true
fi

if [[ "$service_changed" == "true" ]]; then
    cat > "$service_file" <<EOF
[Unit]
Description=My Service
...
EOF
    sudo systemctl daemon-reload
fi

ensure_service_enabled "myservice"
ensure_service_running "myservice"
```

#### Pattern 9: Database Operations

**Before:**
```bash
sudo -u postgres psql -c "CREATE USER myuser WITH PASSWORD 'pass';"
sudo -u postgres psql -c "CREATE DATABASE mydb OWNER myuser;"
```

**After:**
```bash
# Check before creating
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='myuser'" | grep -q 1; then
    sudo -u postgres psql -c "CREATE USER myuser WITH PASSWORD 'pass';"
fi

if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "mydb"; then
    sudo -u postgres psql -c "CREATE DATABASE mydb OWNER myuser;"
fi

# Or use helpers:
ensure_postgres_user_exists "myuser" "pass"
ensure_postgres_database_exists "mydb" "myuser"
```

#### Pattern 10: APT Repositories

**Before:**
```bash
wget -qO - https://repo.example.com/key.gpg | gpg --dearmor > /etc/apt/keyrings/example.gpg
echo "deb https://repo.example.com stable main" > /etc/apt/sources.list.d/example.list
apt-get update
```

**After:**
```bash
# Check before adding
if [[ ! -f /etc/apt/keyrings/example.gpg ]]; then
    wget -qO - https://repo.example.com/key.gpg | gpg --dearmor > /etc/apt/keyrings/example.gpg
fi

if [[ ! -f /etc/apt/sources.list.d/example.list ]]; then
    echo "deb https://repo.example.com stable main" > /etc/apt/sources.list.d/example.list
    apt-get update
fi

# Or use helpers:
ensure_apt_key_exists "https://repo.example.com/key.gpg" "/etc/apt/keyrings/example.gpg"
ensure_apt_source_exists "deb https://repo.example.com stable main" "/etc/apt/sources.list.d/example.list"
```

### 3. Deployment Workflow with Idempotence

```bash
#!/usr/bin/env bash
# Example: deploy-complete.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Step 1: Pre-flight checks
echo "Running pre-flight checks..."
if ! "${SCRIPT_DIR}/scripts/preflight-check.sh" --server mentat; then
    echo "ERROR: Pre-flight checks failed"
    exit 1
fi

# Step 2: Run preparation script (idempotent)
echo "Preparing server..."
"${SCRIPT_DIR}/scripts/prepare-mentat.sh"

# Step 3: Can safely re-run if failed
echo "Deploying observability stack..."
if ! "${SCRIPT_DIR}/scripts/deploy-observability.sh"; then
    echo "Deployment failed, retrying..."
    # Safe to retry because scripts are idempotent
    "${SCRIPT_DIR}/scripts/deploy-observability.sh"
fi

# Step 4: Validation
echo "Running validation checks..."
"${SCRIPT_DIR}/scripts/health-check.sh"

echo "Deployment complete!"
```

### 4. Testing Checklist

For each deployment script, verify:

- [ ] Script sources `idempotence.sh` library
- [ ] User creation checks for existing users
- [ ] Package installation checks before installing
- [ ] Service enable/start checks current state
- [ ] Directory creation uses `mkdir -p`
- [ ] File creation checks for existence
- [ ] Configuration changes check for existing values
- [ ] Downloads check if file exists
- [ ] Binary installation checks version/hash
- [ ] Database operations check for existing objects
- [ ] APT repositories check before adding
- [ ] Services reload configuration gracefully
- [ ] Script includes backup operations
- [ ] Script has error handling/rollback
- [ ] Script can run multiple times without errors
- [ ] Script produces same result on multiple runs

### 5. Quick Testing Commands

```bash
# Test single script twice
./scripts/prepare-mentat.sh > run1.log 2>&1
./scripts/prepare-mentat.sh > run2.log 2>&1
diff run1.log run2.log  # Should show minimal differences

# Automated idempotence test
./tests/test-idempotence.sh --script ./scripts/prepare-mentat.sh --iterations 3

# Full test suite
./tests/test-idempotence.sh

# Pre-flight for specific server
./scripts/preflight-check.sh --server mentat
./scripts/preflight-check.sh --server landsraad
```

### 6. Script Update Priority

**CRITICAL (Must be idempotent):**
1. ✅ `prepare-mentat.sh` - Server preparation
2. ✅ `prepare-landsraad.sh` - Server preparation
3. ✅ `deploy-observability.sh` - Stack deployment
4. ✅ `setup-firewall.sh` - Firewall configuration
5. ✅ `setup-ssl.sh` - Certificate management

**HIGH (Should be idempotent):**
6. `deploy-application.sh` - App deployment
7. `security/master-security-setup.sh` - Security hardening
8. `security/setup-fail2ban.sh` - Intrusion prevention
9. Database setup scripts
10. Monitoring setup scripts

**MEDIUM (Recommended):**
11. Health check scripts
12. Validation scripts
13. Backup scripts
14. Rollback scripts

### 7. Common Mistakes to Avoid

❌ **Don't:**
- Use `>>` to append to files without checking
- Run `useradd` without checking if user exists
- Install packages without checking first
- Enable/start services without checking state
- Create directories without `mkdir -p`
- Download files without checking existence
- Modify configuration files without backup
- Run database CREATE without existence check

✅ **Do:**
- Always check before creating
- Use helper functions from `idempotence.sh`
- Backup before modifying files
- Use `mkdir -p` for directory creation
- Use `systemctl restart` instead of `start`
- Check package installation before `apt-get install`
- Verify service state before enable/start
- Test scripts with idempotence framework

### 8. Emergency Rollback

All scripts should support safe rollback:

```bash
# Backup before changes
backup_file "/etc/important.conf"

# Track created resources
CREATED_USERS=()
CREATED_DIRS=()
CREATED_SERVICES=()

# Cleanup function
cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo "ERROR: Script failed, rolling back..."

        # Remove created users
        for user in "${CREATED_USERS[@]}"; do
            userdel "$user" 2>/dev/null || true
        done

        # Remove created directories
        for dir in "${CREATED_DIRS[@]}"; do
            rm -rf "$dir" 2>/dev/null || true
        done

        # Disable created services
        for service in "${CREATED_SERVICES[@]}"; do
            systemctl stop "$service" 2>/dev/null || true
            systemctl disable "$service" 2>/dev/null || true
        done

        # Restore backups
        for backup in /etc/*.backup.*; do
            if [[ -f "$backup" ]]; then
                original="${backup%.backup.*}"
                cp "$backup" "$original"
            fi
        done
    fi
}

trap cleanup_on_error EXIT ERR
```

### 9. Verification Commands

After running any script, verify idempotence:

```bash
# Check users
getent passwd | grep -E "stilgar|observability"

# Check packages
dpkg -l | grep -E "nginx|prometheus|php"

# Check services
systemctl status nginx prometheus grafana-server

# Check directories
ls -la /opt/observability
ls -la /etc/observability

# Check files
cat /etc/observability/prometheus/prometheus.yml

# Check firewall
sudo ufw status verbose

# Check processes
ps aux | grep -E "prometheus|grafana|nginx"

# Check ports
sudo netstat -tuln | grep -E "9090|3000|443"
```

### 10. Integration with CI/CD

```yaml
# .github/workflows/test-deployment.yml
name: Test Deployment Scripts

on: [push, pull_request]

jobs:
  test-idempotence:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v2

      - name: Setup test environment
        run: |
          sudo apt-get update
          sudo apt-get install -y systemd

      - name: Run preflight checks
        run: |
          cd deploy
          ./scripts/preflight-check.sh --skip-network --no-strict

      - name: Test prepare-mentat.sh idempotence
        run: |
          cd deploy
          ./tests/test-idempotence.sh --script ./scripts/prepare-mentat.sh --iterations 2

      - name: Test prepare-landsraad.sh idempotence
        run: |
          cd deploy
          ./tests/test-idempotence.sh --script ./scripts/prepare-landsraad.sh --iterations 2

      - name: Generate report
        if: always()
        run: |
          cd deploy
          ./tests/test-idempotence.sh --cleanup
```

## Summary

### Files Created

1. **`deploy/utils/idempotence.sh`** - Reusable helper functions (500+ lines)
2. **`deploy/scripts/preflight-check.sh`** - Pre-deployment validation (600+ lines)
3. **`deploy/tests/test-idempotence.sh`** - Automated testing framework (400+ lines)
4. **`deploy/IDEMPOTENCE-TESTING.md`** - Comprehensive documentation (800+ lines)
5. **`deploy/IMPLEMENTATION-GUIDE.md`** - Quick reference (this file)

### Key Benefits

✅ **Safety**: Scripts can be re-run after failures
✅ **Reliability**: Consistent results every time
✅ **Testability**: Automated verification
✅ **Maintainability**: Clear patterns and helpers
✅ **Recovery**: Safe rollback mechanisms
✅ **CI/CD Ready**: Automated testing integration
✅ **Documentation**: Comprehensive guides

### Next Steps

1. Apply patterns to remaining scripts using helper functions
2. Run idempotence tests on each updated script
3. Integrate preflight checks into deployment workflow
4. Add CI/CD pipeline for continuous testing
5. Document any exceptions where idempotence not possible
6. Train team on idempotent patterns
7. Review and update patterns library as needed

---

**For detailed examples and full API documentation, see:**
- [IDEMPOTENCE-TESTING.md](./IDEMPOTENCE-TESTING.md) - Full guide
- [utils/idempotence.sh](./utils/idempotence.sh) - Helper functions
- [tests/test-idempotence.sh](./tests/test-idempotence.sh) - Testing framework
- [scripts/preflight-check.sh](./scripts/preflight-check.sh) - Validation
