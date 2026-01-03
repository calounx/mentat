# CRITICAL SCRIPT FIXES - LINE-BY-LINE GUIDE

This document provides exact fixes for the 3 critical errors found in shell script validation.

---

## ERROR 1: deploy/security/generate-secure-secrets.sh

### File Location
`/home/calounx/repositories/mentat/deploy/security/generate-secure-secrets.sh`

### Issue Summary
- **Line 355**: Syntax error - extra closing parenthesis
- **Missing**: `set -euo pipefail` directive

### Current Code (Lines 343-356)
```bash
# Generate encryption key
generate_encryption_key() {
    log_info "Generating encryption key (64 hex characters)..."

    # 64 hex chars = 32 bytes = 256 bits (AES-256 compatible)
    local encryption_key=$(generate_random_secret 64 hex)

    if [[ ${#encryption_key} -lt $MIN_KEY_LENGTH ]]; then
        log_error "Generated encryption key is too short (${#encryption_key} < $MIN_KEY_LENGTH)"
        exit 1
    fi

    echo "$encryption_key"
    log_success "Encryption key generated (${#encryption_key} characters, 256-bit)")  # ← EXTRA ) HERE
}
```

### Fixed Code (Lines 343-356)
```bash
# Generate encryption key
generate_encryption_key() {
    log_info "Generating encryption key (64 hex characters)..."

    # 64 hex chars = 32 bytes = 256 bits (AES-256 compatible)
    local encryption_key=$(generate_random_secret 64 hex)

    if [[ ${#encryption_key} -lt $MIN_KEY_LENGTH ]]; then
        log_error "Generated encryption key is too short (${#encryption_key} < $MIN_KEY_LENGTH)"
        exit 1
    fi

    echo "$encryption_key"
    log_success "Encryption key generated (${#encryption_key} characters, 256-bit)"  # ← FIXED
}
```

### Also Add After Shebang (Line 2)
```bash
#!/usr/bin/env bash
set -euo pipefail  # ← ADD THIS LINE

```

### Manual Fix Commands
```bash
# Fix the syntax error
sed -i '355s/)")$/")/' deploy/security/generate-secure-secrets.sh

# Add set -euo pipefail after shebang
sed -i '2i set -euo pipefail\n' deploy/security/generate-secure-secrets.sh

# Verify the fix
bash -n deploy/security/generate-secure-secrets.sh
```

### Verification
```bash
# Should show no errors
bash -n deploy/security/generate-secure-secrets.sh

# Should show fewer shellcheck warnings
shellcheck deploy/security/generate-secure-secrets.sh
```

---

## ERROR 2: chom/deploy/troubleshooting/emergency-diagnostics.sh

### File Location
`/home/calounx/repositories/mentat/chom/deploy/troubleshooting/emergency-diagnostics.sh`

### Issue Summary
**8 instances** of `local` keyword used outside functions

### Problematic Lines

#### Line 199
```bash
# CURRENT (WRONG):
    local php_log=$(ssh "$DEPLOY_USER@$APP_SERVER" "php -i 2>/dev/null | grep 'error_log' | grep -oP '/[^ ]+' | head -1" || echo "")

# FIXED:
    php_log=$(ssh "$DEPLOY_USER@$APP_SERVER" "php -i 2>/dev/null | grep 'error_log' | grep -oP '/[^ ]+' | head -1" || echo "")
```

#### Line 331
```bash
# CURRENT (WRONG):
    local db_log=$(ssh "$DB_USER@$DB_SERVER" "mysql -e 'SHOW VARIABLES LIKE \"log_error\"' 2>/dev/null | grep log_error | awk '{print \$2}'" || echo "")

# FIXED:
    db_log=$(ssh "$DB_USER@$DB_SERVER" "mysql -e 'SHOW VARIABLES LIKE \"log_error\"' 2>/dev/null | grep log_error | awk '{print \$2}'" || echo "")
```

#### Line 338
```bash
# CURRENT (WRONG):
        local db_error_log=$(ssh "$DB_USER@$DB_SERVER" "sudo tail -500 $db_log" 2>/dev/null || echo "")

# FIXED:
        db_error_log=$(ssh "$DB_USER@$DB_SERVER" "sudo tail -500 $db_log" 2>/dev/null || echo "")
```

#### Line 345
```bash
# CURRENT (WRONG):
    local db_slowquery_log=$(ssh "$DB_USER@$DB_SERVER" "mysql -e 'SHOW VARIABLES LIKE \"slow_query_log_file\"' 2>/dev/null | grep slow_query | awk '{print \$2}'" || echo "")

# FIXED:
    db_slowquery_log=$(ssh "$DB_USER@$DB_SERVER" "mysql -e 'SHOW VARIABLES LIKE \"slow_query_log_file\"' 2>/dev/null | grep slow_query | awk '{print \$2}'" || echo "")
```

#### Line 348
```bash
# CURRENT (WRONG):
    local db_general_log=$(ssh "$DB_USER@$DB_SERVER" "mysql -e 'SHOW VARIABLES LIKE \"general_log_file\"' 2>/dev/null | grep general_log | awk '{print \$2}'" || echo "")

# FIXED:
    db_general_log=$(ssh "$DB_USER@$DB_SERVER" "mysql -e 'SHOW VARIABLES LIKE \"general_log_file\"' 2>/dev/null | grep general_log | awk '{print \$2}'" || echo "")
```

#### Line 354
```bash
# CURRENT (WRONG):
    local mysql_process=$(ssh "$DB_USER@$DB_SERVER" "pgrep -a mysql" || echo "Not running")

# FIXED:
    mysql_process=$(ssh "$DB_USER@$DB_SERVER" "pgrep -a mysql" || echo "Not running")
```

#### Line 357
```bash
# CURRENT (WRONG):
    local mysql_status=$(ssh "$DB_USER@$DB_SERVER" "systemctl status mysql 2>&1" || echo "Status unavailable")

# FIXED:
    mysql_status=$(ssh "$DB_USER@$DB_SERVER" "systemctl status mysql 2>&1" || echo "Status unavailable")
```

#### Line 379
```bash
# CURRENT (WRONG):
    local disk_usage=$(ssh "$DEPLOY_USER@$APP_SERVER" "df -h" 2>/dev/null || echo "Unavailable")

# FIXED:
    disk_usage=$(ssh "$DEPLOY_USER@$APP_SERVER" "df -h" 2>/dev/null || echo "Unavailable")
```

### Manual Fix Commands
```bash
# Fix all 8 lines at once
sed -i '199s/^    local /    /' chom/deploy/troubleshooting/emergency-diagnostics.sh
sed -i '331s/^    local /    /' chom/deploy/troubleshooting/emergency-diagnostics.sh
sed -i '338s/^        local /        /' chom/deploy/troubleshooting/emergency-diagnostics.sh
sed -i '345s/^    local /    /' chom/deploy/troubleshooting/emergency-diagnostics.sh
sed -i '348s/^    local /    /' chom/deploy/troubleshooting/emergency-diagnostics.sh
sed -i '354s/^    local /    /' chom/deploy/troubleshooting/emergency-diagnostics.sh
sed -i '357s/^    local /    /' chom/deploy/troubleshooting/emergency-diagnostics.sh
sed -i '379s/^    local /    /' chom/deploy/troubleshooting/emergency-diagnostics.sh

# Verify the fix
bash -n chom/deploy/troubleshooting/emergency-diagnostics.sh
```

### Alternative Fix: Wrap in Function
If you want to keep using `local`, wrap the code in a function:

```bash
capture_diagnostics() {
    local php_log=$(...)
    local db_log=$(...)
    # ... rest of code
}

# Then call it
capture_diagnostics
```

---

## ERROR 3: chom/deploy/observability-native/uninstall-all.sh

### File Location
`/home/calounx/repositories/mentat/chom/deploy/observability-native/uninstall-all.sh`

### Issue Summary
- **Line 323**: `-d` test doesn't work with glob patterns
- **Line 324**: Using `ls` instead of `find` for file operations

### Current Code (Lines 320-328)
```bash
    echo "  - Node Exporter"
    echo ""

    if [[ -d /root/observability-backup-* ]]; then
        local backup_dir=$(ls -dt /root/observability-backup-* | head -1)
        echo -e "${BOLD}Configuration Backup:${NC}"
        echo "  $backup_dir"
        echo ""
    fi
```

### Fixed Code (Lines 320-330)
```bash
    echo "  - Node Exporter"
    echo ""

    # Check for backup directories (fixed glob handling)
    backup_dirs=(/root/observability-backup-*)
    if [[ -d "${backup_dirs[0]}" ]]; then
        # Use find instead of ls for robustness
        backup_dir=$(find /root -maxdepth 1 -type d -name "observability-backup-*" -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
        echo -e "${BOLD}Configuration Backup:${NC}"
        echo "  $backup_dir"
        echo ""
    fi
```

### Manual Fix Commands
```bash
# Delete the old problematic lines
sed -i '323,324d' chom/deploy/observability-native/uninstall-all.sh

# Create the replacement text
cat > /tmp/fix-snippet.txt <<'EOF'
    # Check for backup directories (fixed glob handling)
    backup_dirs=(/root/observability-backup-*)
    if [[ -d "${backup_dirs[0]}" ]]; then
        # Use find instead of ls for robustness
        backup_dir=$(find /root -maxdepth 1 -type d -name "observability-backup-*" -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
EOF

# Insert the new lines after line 322
sed -i '322r /tmp/fix-snippet.txt' chom/deploy/observability-native/uninstall-all.sh

# Verify the fix
bash -n chom/deploy/observability-native/uninstall-all.sh
```

### Alternative Fix: Simple Version
If you want a simpler fix:

```bash
    echo "  - Node Exporter"
    echo ""

    # Find most recent backup directory
    for dir in /root/observability-backup-*; do
        if [[ -d "$dir" ]]; then
            backup_dir="$dir"
            echo -e "${BOLD}Configuration Backup:${NC}"
            echo "  $backup_dir"
            echo ""
            break  # Use first (most recent with proper sorting)
        fi
    done
```

---

## BONUS FIX: Add Executable Permission

### File Location
`/home/calounx/repositories/mentat/deploy/security/compliance-check.sh`

### Command
```bash
chmod +x deploy/security/compliance-check.sh
```

---

## AUTOMATED FIX SCRIPT

All of these fixes can be applied automatically using:

```bash
/home/calounx/repositories/mentat/fix-critical-script-errors.sh
```

This script:
1. Creates backups in `script-fixes-backup-[timestamp]/`
2. Applies all fixes
3. Verifies each fix with `bash -n` and `shellcheck`
4. Reports success/failure for each fix

---

## VERIFICATION AFTER FIXES

### 1. Check Syntax
```bash
# Should show no errors for all three files
bash -n deploy/security/generate-secure-secrets.sh
bash -n chom/deploy/troubleshooting/emergency-diagnostics.sh
bash -n chom/deploy/observability-native/uninstall-all.sh
```

### 2. Run ShellCheck
```bash
# Should show no errors (warnings are OK)
shellcheck deploy/security/generate-secure-secrets.sh | grep error
shellcheck chom/deploy/troubleshooting/emergency-diagnostics.sh | grep error
shellcheck chom/deploy/observability-native/uninstall-all.sh | grep error
```

### 3. Run Full Validation
```bash
# Re-run the full validation
python3 validate_scripts.py

# Should show:
# - 0 errors (down from 3)
# - Same or fewer warnings
```

### 4. Test Scripts
```bash
# Test generate-secure-secrets.sh
./deploy/security/generate-secure-secrets.sh --help

# Test emergency-diagnostics.sh
# (requires proper environment variables)
# DRY_RUN=1 ./chom/deploy/troubleshooting/emergency-diagnostics.sh

# Test uninstall-all.sh
# (Don't actually run unless you want to uninstall!)
# bash -n chom/deploy/observability-native/uninstall-all.sh
```

---

## ESTIMATED TIME

- **Reading this guide**: 10 minutes
- **Running automated fix**: 2 minutes
- **Manual verification**: 5 minutes
- **Testing**: 15 minutes

**Total**: ~30 minutes

---

## ROLLBACK PROCEDURE

If anything goes wrong, backups are created in:

```
/home/calounx/repositories/mentat/script-fixes-backup-[timestamp]/
```

To rollback:

```bash
# Find the backup directory
ls -ltr /home/calounx/repositories/mentat/script-fixes-backup-*

# Restore from backup
BACKUP_DIR="script-fixes-backup-20260103-181500"  # Use actual timestamp
cp "$BACKUP_DIR/generate-secure-secrets.sh.bak" deploy/security/generate-secure-secrets.sh
cp "$BACKUP_DIR/emergency-diagnostics.sh.bak" chom/deploy/troubleshooting/emergency-diagnostics.sh
cp "$BACKUP_DIR/uninstall-all.sh.bak" chom/deploy/observability-native/uninstall-all.sh
```

Or use git:

```bash
# Discard changes
git checkout deploy/security/generate-secure-secrets.sh
git checkout chom/deploy/troubleshooting/emergency-diagnostics.sh
git checkout chom/deploy/observability-native/uninstall-all.sh
```

---

## NEXT STEPS AFTER FIXING

1. **Commit the fixes**:
   ```bash
   git add deploy/security/generate-secure-secrets.sh
   git add chom/deploy/troubleshooting/emergency-diagnostics.sh
   git add chom/deploy/observability-native/uninstall-all.sh
   git add deploy/security/compliance-check.sh
   git commit -m "fix: Critical shell script errors found in validation

   - Fix syntax error in generate-secure-secrets.sh (line 355)
   - Add set -euo pipefail to generate-secure-secrets.sh
   - Remove 'local' outside functions in emergency-diagnostics.sh
   - Fix glob pattern in -d test in uninstall-all.sh
   - Add executable permission to compliance-check.sh"
   ```

2. **Address high-priority warnings** (see SCRIPT_VALIDATION_EXECUTIVE_SUMMARY.md)

3. **Set up pre-commit hooks** to prevent future issues

4. **Update documentation** with script standards
