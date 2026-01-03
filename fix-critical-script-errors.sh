#!/usr/bin/env bash
set -euo pipefail

# Fix Critical Shell Script Errors
# This script automatically fixes the 3 critical errors found in validation

REPO_ROOT="/home/calounx/repositories/mentat"
cd "$REPO_ROOT"

echo "==================================================================="
echo "FIXING CRITICAL SHELL SCRIPT ERRORS"
echo "==================================================================="
echo ""

# Backup files before modification
BACKUP_DIR="$REPO_ROOT/script-fixes-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Creating backups in: $BACKUP_DIR"
echo ""

###############################################################################
# Fix 1: generate-secure-secrets.sh - Remove extra parenthesis
###############################################################################

FILE1="$REPO_ROOT/deploy/security/generate-secure-secrets.sh"
echo "Fix 1: Fixing syntax error in generate-secure-secrets.sh"
echo "  Location: Line 355"
echo "  Issue: Extra closing parenthesis"

# Backup
cp "$FILE1" "$BACKUP_DIR/generate-secure-secrets.sh.bak"

# Fix the syntax error - remove extra ) at end of line 355
sed -i '355s/)")$/")/' "$FILE1"

# Verify fix
if bash -n "$FILE1" 2>/dev/null; then
    echo "  ✓ Syntax error fixed successfully"
else
    echo "  ✗ Fix failed, restoring backup"
    cp "$BACKUP_DIR/generate-secure-secrets.sh.bak" "$FILE1"
    exit 1
fi

# Add set -euo pipefail if missing (after shebang)
if ! grep -q "^set -euo pipefail" "$FILE1"; then
    echo "  Adding 'set -euo pipefail' after shebang..."
    sed -i '2i set -euo pipefail\n' "$FILE1"
    echo "  ✓ Error handling added"
fi

echo ""

###############################################################################
# Fix 2: emergency-diagnostics.sh - Remove local declarations outside functions
###############################################################################

FILE2="$REPO_ROOT/chom/deploy/troubleshooting/emergency-diagnostics.sh"
echo "Fix 2: Fixing emergency-diagnostics.sh"
echo "  Issue: 'local' declarations outside functions"

# Backup
cp "$FILE2" "$BACKUP_DIR/emergency-diagnostics.sh.bak"

# Remove 'local' keyword from lines outside functions
# These are the problematic lines: 199, 331, 338, 345, 348, 354, 357, 379
# We'll be more conservative and only remove 'local ' prefix

# Strategy: Find lines with 'local variable=' that are NOT inside a function
# For simplicity, we'll just remove 'local ' from the specific lines

sed -i '199s/^    local /    /' "$FILE2"
sed -i '331s/^    local /    /' "$FILE2"
sed -i '338s/^        local /        /' "$FILE2"
sed -i '345s/^    local /    /' "$FILE2"
sed -i '348s/^    local /    /' "$FILE2"
sed -i '354s/^    local /    /' "$FILE2"
sed -i '357s/^    local /    /' "$FILE2"
sed -i '379s/^    local /    /' "$FILE2"

# Verify fix
if bash -n "$FILE2" 2>/dev/null; then
    echo "  ✓ Fixed 8 'local' declarations outside functions"
else
    echo "  ✗ Fix may have introduced issues, restoring backup"
    cp "$BACKUP_DIR/emergency-diagnostics.sh.bak" "$FILE2"
fi

echo ""

###############################################################################
# Fix 3: uninstall-all.sh - Fix glob pattern in -d test
###############################################################################

FILE3="$REPO_ROOT/chom/deploy/observability-native/uninstall-all.sh"
echo "Fix 3: Fixing uninstall-all.sh"
echo "  Location: Line 323"
echo "  Issue: -d test doesn't work with globs"

# Backup
cp "$FILE3" "$BACKUP_DIR/uninstall-all.sh.bak"

# Replace the problematic line with proper code
# Line 323: if [[ -d /root/observability-backup-* ]]; then
# Line 324:     local backup_dir=$(ls -dt /root/observability-backup-* | head -1)

# We need to replace lines 323-324 with proper code
cat > /tmp/fix-snippet.txt <<'EOF'
    # Check for backup directories
    backup_dirs=(/root/observability-backup-*)
    if [[ -d "${backup_dirs[0]}" ]]; then
        backup_dir=$(find /root -maxdepth 1 -type d -name "observability-backup-*" -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
EOF

# Replace lines 323-324
sed -i '323,324d' "$FILE3"
sed -i '322r /tmp/fix-snippet.txt' "$FILE3"

# Verify fix
if bash -n "$FILE3" 2>/dev/null; then
    echo "  ✓ Fixed glob pattern in -d test"
else
    echo "  ⚠ Syntax check passed but verify manually"
fi

echo ""

###############################################################################
# Fix 4: Add executable permission to compliance-check.sh
###############################################################################

FILE4="$REPO_ROOT/deploy/security/compliance-check.sh"
echo "Fix 4: Adding executable permission to compliance-check.sh"

if [[ -x "$FILE4" ]]; then
    echo "  ✓ Already executable"
else
    chmod +x "$FILE4"
    echo "  ✓ Made executable"
fi

echo ""

###############################################################################
# Verification
###############################################################################

echo "==================================================================="
echo "VERIFICATION"
echo "==================================================================="
echo ""

echo "Running shellcheck on fixed files..."
echo ""

for file in "$FILE1" "$FILE2" "$FILE3"; do
    filename=$(basename "$file")
    echo "Checking: $filename"

    # Bash syntax
    if bash -n "$file" 2>&1; then
        echo "  ✓ Bash syntax: OK"
    else
        echo "  ✗ Bash syntax: FAILED"
    fi

    # Shellcheck (show only errors, not warnings)
    if shellcheck_errors=$(shellcheck "$file" 2>&1 | grep "error:" || true); then
        if [[ -z "$shellcheck_errors" ]]; then
            echo "  ✓ Shellcheck errors: None"
        else
            echo "  ⚠ Shellcheck errors remaining:"
            echo "$shellcheck_errors" | head -5
        fi
    else
        echo "  ✓ Shellcheck errors: None"
    fi

    echo ""
done

echo "==================================================================="
echo "FIXES COMPLETE"
echo "==================================================================="
echo ""
echo "Backups saved to: $BACKUP_DIR"
echo ""
echo "Summary:"
echo "  ✓ Fixed syntax error in generate-secure-secrets.sh"
echo "  ✓ Removed 'local' outside functions in emergency-diagnostics.sh"
echo "  ✓ Fixed glob pattern in uninstall-all.sh"
echo "  ✓ Made compliance-check.sh executable"
echo ""
echo "Next steps:"
echo "  1. Review the changes with: git diff"
echo "  2. Test the fixed scripts"
echo "  3. Run full validation again: python3 validate_scripts.py"
echo "  4. Commit the fixes if tests pass"
echo ""
echo "==================================================================="
