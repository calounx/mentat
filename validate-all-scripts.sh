#!/usr/bin/env bash
set -euo pipefail

# Comprehensive Shell Script Validation
# This script validates all deployment shell scripts for syntax, best practices, and common issues

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_FILE="${SCRIPT_DIR}/script-validation-report.txt"
JSON_REPORT="${SCRIPT_DIR}/script-validation-report.json"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
total_scripts=0
scripts_with_errors=0
scripts_with_warnings=0
scripts_passed=0
scripts_no_exec=0

# Arrays to store results
declare -a error_scripts=()
declare -a warning_scripts=()
declare -a passed_scripts=()
declare -a no_exec_scripts=()

echo "==================================================================="
echo "COMPREHENSIVE SHELL SCRIPT VALIDATION"
echo "==================================================================="
echo ""
echo "Starting validation at: $(date)"
echo ""

# Initialize report file
cat > "$REPORT_FILE" <<EOF
=================================================================
COMPREHENSIVE SHELL SCRIPT VALIDATION REPORT
=================================================================
Generated: $(date)
Working Directory: $SCRIPT_DIR

EOF

# Find all deployment shell scripts
mapfile -t scripts < <(find deploy chom/deploy -name "*.sh" -type f 2>/dev/null | sort)

total_scripts=${#scripts[@]}

echo "Found $total_scripts shell scripts to validate"
echo ""

# Validation functions
check_shebang() {
    local file="$1"
    local first_line
    first_line=$(head -n1 "$file")

    if [[ ! "$first_line" =~ ^#! ]]; then
        echo "MISSING_SHEBANG"
        return 1
    elif [[ "$first_line" =~ ^#!/usr/bin/env\ bash$ ]] || [[ "$first_line" =~ ^#!/bin/bash$ ]]; then
        echo "OK"
        return 0
    else
        echo "INVALID_SHEBANG:$first_line"
        return 1
    fi
}

check_set_flags() {
    local file="$1"
    if grep -q "^set -[a-z]*e[a-z]*u[a-z]*o[a-z]*pipefail" "$file" || \
       grep -q "^set -[a-z]*e.*pipefail.*-u" "$file" || \
       grep -q "^set -euo pipefail" "$file"; then
        echo "OK"
        return 0
    else
        echo "MISSING"
        return 1
    fi
}

check_executable() {
    local file="$1"
    if [[ -x "$file" ]]; then
        echo "OK"
        return 0
    else
        echo "NOT_EXECUTABLE"
        return 1
    fi
}

# Main validation loop
for script in "${scripts[@]}"; do
    echo -e "${BLUE}Validating:${NC} $script"

    issues_found=false
    severity="PASS"

    # Check executable permission
    exec_status=$(check_executable "$script")
    if [[ "$exec_status" != "OK" ]]; then
        no_exec_scripts+=("$script")
        ((scripts_no_exec++))
    fi

    # Check shebang
    shebang_status=$(check_shebang "$script" || true)

    # Check set flags
    set_flags_status=$(check_set_flags "$script" || true)

    # Run bash syntax check
    bash_syntax=""
    if bash -n "$script" 2>&1 | grep -q "error"; then
        bash_syntax="SYNTAX_ERROR"
        severity="ERROR"
        issues_found=true
    else
        bash_syntax="OK"
    fi

    # Run shellcheck
    shellcheck_output=""
    shellcheck_severity=""
    if shellcheck_result=$(shellcheck -f gcc "$script" 2>&1); then
        shellcheck_severity="CLEAN"
    else
        shellcheck_output="$shellcheck_result"

        # Determine severity
        if echo "$shellcheck_output" | grep -q "error:"; then
            shellcheck_severity="ERROR"
            severity="ERROR"
            issues_found=true
        elif echo "$shellcheck_output" | grep -q "warning:"; then
            shellcheck_severity="WARNING"
            if [[ "$severity" != "ERROR" ]]; then
                severity="WARNING"
            fi
            issues_found=true
        fi
    fi

    # Categorize script
    if [[ "$severity" == "ERROR" ]]; then
        error_scripts+=("$script")
        ((scripts_with_errors++))
        echo -e "${RED}  ✗ ERRORS FOUND${NC}"
    elif [[ "$severity" == "WARNING" ]]; then
        warning_scripts+=("$script")
        ((scripts_with_warnings++))
        echo -e "${YELLOW}  ⚠ WARNINGS FOUND${NC}"
    else
        passed_scripts+=("$script")
        ((scripts_passed++))
        echo -e "${GREEN}  ✓ PASSED${NC}"
    fi

    # Write to report
    cat >> "$REPORT_FILE" <<EOF

-------------------------------------------------------------------
Script: $script
-------------------------------------------------------------------
Status: $severity
Executable: $exec_status
Shebang: $shebang_status
Set Flags: $set_flags_status
Bash Syntax: $bash_syntax

EOF

    # Add shellcheck output if present
    if [[ -n "$shellcheck_output" ]]; then
        cat >> "$REPORT_FILE" <<EOF
Shellcheck Output:
$shellcheck_output

EOF
    fi

    echo ""
done

# Generate summary
cat >> "$REPORT_FILE" <<EOF

=================================================================
VALIDATION SUMMARY
=================================================================
Total Scripts Checked: $total_scripts
Scripts Passed: $scripts_passed
Scripts with Warnings: $scripts_with_warnings
Scripts with Errors: $scripts_with_errors
Scripts without Execute Permission: $scripts_no_exec

EOF

# List scripts by category
if [[ ${#error_scripts[@]} -gt 0 ]]; then
    cat >> "$REPORT_FILE" <<EOF

SCRIPTS WITH ERRORS (${#error_scripts[@]}):
EOF
    for script in "${error_scripts[@]}"; do
        echo "  - $script" >> "$REPORT_FILE"
    done
fi

if [[ ${#warning_scripts[@]} -gt 0 ]]; then
    cat >> "$REPORT_FILE" <<EOF

SCRIPTS WITH WARNINGS (${#warning_scripts[@]}):
EOF
    for script in "${warning_scripts[@]}"; do
        echo "  - $script" >> "$REPORT_FILE"
    done
fi

if [[ ${#passed_scripts[@]} -gt 0 ]]; then
    cat >> "$REPORT_FILE" <<EOF

SCRIPTS PASSED (${#passed_scripts[@]}):
EOF
    for script in "${passed_scripts[@]}"; do
        echo "  - $script" >> "$REPORT_FILE"
    done
fi

if [[ ${#no_exec_scripts[@]} -gt 0 ]]; then
    cat >> "$REPORT_FILE" <<EOF

SCRIPTS WITHOUT EXECUTE PERMISSION (${#no_exec_scripts[@]}):
EOF
    for script in "${no_exec_scripts[@]}"; do
        echo "  - $script" >> "$REPORT_FILE"
    done
fi

# Print summary to console
echo "==================================================================="
echo "VALIDATION SUMMARY"
echo "==================================================================="
echo ""
echo -e "Total Scripts Checked: ${BLUE}$total_scripts${NC}"
echo -e "Scripts Passed: ${GREEN}$scripts_passed${NC}"
echo -e "Scripts with Warnings: ${YELLOW}$scripts_with_warnings${NC}"
echo -e "Scripts with Errors: ${RED}$scripts_with_errors${NC}"
echo -e "Scripts without Execute Permission: ${YELLOW}$scripts_no_exec${NC}"
echo ""

if [[ ${#error_scripts[@]} -gt 0 ]]; then
    echo -e "${RED}SCRIPTS WITH ERRORS:${NC}"
    for script in "${error_scripts[@]}"; do
        echo "  - $script"
    done
    echo ""
fi

if [[ ${#warning_scripts[@]} -gt 0 ]]; then
    echo -e "${YELLOW}SCRIPTS WITH WARNINGS:${NC}"
    for script in "${warning_scripts[@]}"; do
        echo "  - $script"
    done
    echo ""
fi

if [[ ${#no_exec_scripts[@]} -gt 0 ]]; then
    echo -e "${YELLOW}SCRIPTS WITHOUT EXECUTE PERMISSION:${NC}"
    for script in "${no_exec_scripts[@]}"; do
        echo "  - $script"
    done
    echo ""
fi

echo "Detailed report saved to: $REPORT_FILE"
echo ""
echo "Validation completed at: $(date)"
echo "==================================================================="

# Exit with error if any scripts have errors
if [[ $scripts_with_errors -gt 0 ]]; then
    exit 1
fi

exit 0
